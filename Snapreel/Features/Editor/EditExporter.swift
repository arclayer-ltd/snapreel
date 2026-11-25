import AVFoundation
import CoreImage
import UIKit

/// What the saved file should be like. Chosen from the recording, so an edit is about as big as
/// the part of the recording it keeps: a 9-minute screen recording is a couple of hundred
/// megabytes, not a gigabyte that takes an hour to upload.
struct EditExportSettings: Equatable {
    /// Picture size in pixels; zero for a voice recording.
    var size: CGSize
    /// Bits a second of picture.
    var videoBitRate: Double
    static let audioBitRate = 128_000.0

    init(recipe: EditRecipe, picture: CGSize?, sourceBitRate: Double, frameRate: Double, quality: ExportQuality) {
        guard let picture else {
            size = .zero
            videoBitRate = 0
            return
        }
        size = recipe.renderSize(source: picture, quality: quality)
        let pixels = Double(size.width * size.height)
        // Above 30 frames a second each frame differs less from the last, so it costs half as much.
        let rate = min(60, max(24, frameRate))
        let effective = min(rate, 30) + max(0, rate - 30) * 0.5
        let usual = pixels * effective * 0.085
        guard sourceBitRate > 50_000 else {
            videoBitRate = usual
            return
        }
        // No point in spending much more than the recording itself did on the same picture.
        let cropped = recipe.outputPictureSize(source: picture)
        let share = min(1, pixels / max(1, Double(cropped.width * cropped.height)))
        let area = min(1, Double(cropped.width * cropped.height) / max(1, Double(picture.width * picture.height)))
        let played = recipe.segments.reduce(0) { $0 + $1.sourceLength }
        let speed = max(0.5, min(2, played / max(0.1, recipe.outputDuration)))
        let own = sourceBitRate * 1.3 * pow(share, 0.8) * pow(area, 0.7) * speed
        videoBitRate = max(min(usual, own), max(500_000, pixels * 30 * 0.015))
    }
}

/// Everything one save needs, gathered on the main actor and then used by one background job.
struct EditExportPlan {
    let id: UUID
    let recipe: EditRecipe
    let source: EditSource
    let build: EditBuild
    let settings: EditExportSettings
    /// Where finished pieces wait, so a save that is interrupted carries on where it was.
    let workFolder: URL
    let output: URL
    /// The overlays on screen during an output range, as pictures.
    let overlays: @MainActor (ClosedRange<Double>) -> [EditOverlayImage]
    /// Output times where an overlay appears or goes.
    let overlayTimes: [Double]

    /// The picture is drawn again (cropped, turned, blurred, with something over it, or HDR).
    var draws: Bool {
        !recipe.crop.isFullFrame || recipe.quarterTurns % 4 != 0 || recipe.flipped || !recipe.blurs.isEmpty
            || !overlayTimes.isEmpty || source.isHDR
    }

    /// Nothing changes but the end of the recording: the recording's own data is copied, which
    /// takes seconds and loses nothing.
    var copyRange: CMTimeRange? {
        guard source.hasVideo, !draws, recipe.voiceClips.isEmpty, source.audioTracks.count <= 1 else { return nil }
        let audio = recipe.audio
        guard source.audioTracks.isEmpty
                || (!audio.muted && audio.volume > 0.999 && !audio.fadeIn && !audio.fadeOut && !audio.reducesNoise) else { return nil }
        let played = recipe.playedSegments
        guard played.count == 1, let only = played.first, only.speed == 1, only.start < 0.001 else { return nil }
        let upright = source.uprightSize
        guard abs(settings.size.width - upright.width) < 2.5, abs(settings.size.height - upright.height) < 2.5 else { return nil }
        // Edits are always H.264, which everything plays.
        guard source.codec == kCMVideoCodecType_H264 else { return nil }
        return CMTimeRange(start: .zero, end: CMTime(seconds: min(only.end, source.duration), preferredTimescale: 600))
    }

    private static let noID = UUID(uuidString: "00000000-0000-0000-0000-000000000000") ?? UUID()

    /// The recording's turn for a picture that is stored unturned at another size.
    var fileTransform: CGAffineTransform {
        var turn = source.transform
        turn.tx = 0
        turn.ty = 0
        let sideways = source.orientation.turnsSides
        let stored = CGRect(x: 0, y: 0, width: sideways ? settings.size.height : settings.size.width,
                            height: sideways ? settings.size.width : settings.size.height)
        let turned = stored.applying(turn)
        turn.tx = -turned.minX
        turn.ty = -turned.minY
        return turn
    }

    /// Changes when anything about the picture changes, so pieces of another edit are never reused.
    var signature: String {
        var recipe = self.recipe
        recipe.updatedAt = .distantPast
        recipe.audio = EditAudio()
        recipe.voiceClips = []
        recipe.thumbnailTime = nil
        recipe.segments = recipe.segments.map { segment in
            var plain = segment
            plain.id = Self.noID
            return plain
        }
        let data = (try? JSONEncoder.snapreelStable.encode(recipe)) ?? Data()
        return "2|\(Int(settings.size.width))x\(Int(settings.size.height))|\(Int(settings.videoBitRate))|" + data.base64EncodedString()
    }
}

private extension JSONEncoder {
    static var snapreelStable: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

enum EditExportFailure: Error {
    case cancelled
    /// iOS took the encoder away (another app, a call, the background); try again when active.
    case interrupted
    case failed(Error?)
}

/// Makes the edited file. The picture is encoded in pieces of a few seconds that stay on disk, so
/// leaving Snapreel, a call or even the app closing costs a few seconds, never the whole save. It
/// keeps the recording's own frame times (screen recordings are uneven, and re-timing them to an
/// even rate makes scrolling judder), adds frames only where an overlay appears or goes, and
/// writes sound that is exactly as long as the picture.
///
/// All the work happens on one background queue; `cancel`, `suspend` and `resume` can be called
/// from anywhere.
final class EditExporter: @unchecked Sendable {
    static let pieceLength = 12.0
    /// A still picture is repeated at least this often, so a player can seek in it.
    private static let longestFrame = 1.0

    private let plan: EditExportPlan
    private let queue = DispatchQueue(label: "co.arclayer.snapreel.edit-export", qos: .userInitiated)
    private let state = NSCondition()
    private var isCancelled = false
    private var isSuspended = false
    /// Inside a piece of work that must stop before the app goes to the background.
    private var isWorking = false
    private var exportSession: AVAssetExportSession?
    private let report: (Double) -> Void

    init(plan: EditExportPlan, report: @escaping (Double) -> Void) {
        self.plan = plan
        self.report = report
    }

    // MARK: - Control

    func cancel() {
        state.lock()
        isCancelled = true
        exportSession?.cancelExport()
        state.broadcast()
        state.unlock()
    }

    /// Stops before the app goes to the background (drawing there isn't allowed). Waits for the
    /// frame being drawn, for half a second at most.
    func suspend() {
        state.lock()
        isSuspended = true
        let deadline = Date().addingTimeInterval(0.5)
        while isWorking, Date() < deadline {
            if !state.wait(until: deadline) { break }
        }
        state.unlock()
    }

    func resume() {
        state.lock()
        isSuspended = false
        state.broadcast()
        state.unlock()
    }

    private var shouldStop: Bool {
        state.lock()
        defer { state.unlock() }
        return isCancelled || isSuspended
    }

    private func checkStop() throws {
        state.lock()
        defer { state.unlock() }
        if isCancelled { throw EditExportFailure.cancelled }
        if isSuspended { throw EditExportFailure.interrupted }
    }

    /// Keeps the copy so `cancel` can stop it. True when it was cancelled already.
    private func hold(_ session: AVAssetExportSession?) -> Bool {
        state.lock()
        defer { state.unlock() }
        exportSession = session
        return isCancelled
    }

    /// Blocks while suspended. Throws when cancelled.
    private func waitUntilRunning() throws {
        state.lock()
        defer { state.unlock() }
        while isSuspended && !isCancelled { state.wait() }
        if isCancelled { throw EditExportFailure.cancelled }
    }

    private func working<T>(_ body: () throws -> T) throws -> T {
        state.lock()
        if isCancelled {
            state.unlock()
            throw EditExportFailure.cancelled
        }
        if isSuspended {
            state.unlock()
            throw EditExportFailure.interrupted
        }
        isWorking = true
        state.unlock()
        defer {
            state.lock()
            isWorking = false
            state.broadcast()
            state.unlock()
        }
        return try body()
    }

    // MARK: - Run

    func run() async throws {
        if let range = plan.copyRange, try await copy(range) { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    try runOnQueue()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func runOnQueue() throws {
        var attempts = 0
        while true {
            do {
                try waitUntilRunning()
                let pieces = plan.build.videoTrackID == nil ? [] : try encodePieces()
                try join(pieces)
                return
            } catch EditExportFailure.cancelled {
                throw EditExportFailure.cancelled
            } catch {
                // Away from the app, or iOS took the encoder: carry on from the last whole piece.
                if shouldStop { continue }
                if Self.isOutOfSpace(error) { throw error }
                attempts += 1
                guard attempts < 4 else { throw EditExportFailure.failed(error) }
                Thread.sleep(forTimeInterval: 0.6 * Double(attempts))
            }
        }
    }

    private static func isOutOfSpace(_ error: Error) -> Bool {
        if case EditExportFailure.failed(let underlying?) = error { return DiskSpace.isOutOfSpace(underlying) }
        return DiskSpace.isOutOfSpace(error)
    }

    // MARK: - Copy

    /// False when the copy couldn't be made (the edit is then encoded as usual).
    private func copy(_ range: CMTimeRange) async throws -> Bool {
        guard let session = AVAssetExportSession(asset: plan.source.asset, presetName: AVAssetExportPresetPassthrough),
              session.supportedFileTypes.contains(.mp4) else { return false }
        try? FileManager.default.removeItem(at: plan.output)
        session.outputURL = plan.output
        session.outputFileType = .mp4
        session.timeRange = range
        session.shouldOptimizeForNetworkUse = true
        if hold(session) { throw EditExportFailure.cancelled }
        let ticker = Task { [report] in
            while !Task.isCancelled {
                report(Double(session.progress))
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { continuation.resume() }
        }
        ticker.cancel()
        if hold(nil) { throw EditExportFailure.cancelled }
        if session.status == .completed { return true }
        try? FileManager.default.removeItem(at: plan.output)
        if let error = session.error, DiskSpace.isOutOfSpace(error) { throw EditExportFailure.failed(error) }
        return false
    }

    // MARK: - Pieces

    private struct Piece {
        let index: Int
        let start: CMTime
        let end: CMTime
        let url: URL
    }

    private static let scale: CMTimeScale = 90_000

    private func allPieces() -> [Piece] {
        let total = plan.build.duration
        let length = CMTime(seconds: Self.pieceLength, preferredTimescale: Self.scale)
        var result: [Piece] = []
        var start = CMTime.zero
        while start < total {
            var end = start + length
            // No tiny last piece.
            if (total - end).seconds < 1 { end = total }
            result.append(Piece(index: result.count, start: start, end: end,
                                url: plan.workFolder.appendingPathComponent("piece-\(result.count).mov")))
            start = end
        }
        return result
    }

    /// Encodes the pieces that aren't on disk yet.
    private func encodePieces() throws -> [Piece] {
        let fm = FileManager.default
        try fm.createDirectory(at: plan.workFolder, withIntermediateDirectories: true)
        let stamp = plan.workFolder.appendingPathComponent("edit.txt")
        if (try? String(contentsOf: stamp, encoding: .utf8)) != plan.signature {
            for file in (try? fm.contentsOfDirectory(at: plan.workFolder, includingPropertiesForKeys: nil)) ?? [] {
                try? fm.removeItem(at: file)
            }
            try plan.signature.write(to: stamp, atomically: true, encoding: .utf8)
        }
        let pieces = allPieces()
        // Pieces are made in order, so the first one missing is where to carry on.
        let first = pieces.firstIndex { !fm.fileExists(atPath: $0.url.path) } ?? pieces.count
        guard first < pieces.count else { return pieces }
        try encode(pieces, from: first)
        return pieces
    }

    private func encode(_ pieces: [Piece], from first: Int) throws {
        guard let trackID = plan.build.videoTrackID,
              let track = plan.build.composition.track(withTrackID: trackID) else { throw EditExportFailure.failed(nil) }
        let total = plan.build.duration
        let reader = try AVAssetReader(asset: plan.build.composition)
        // A little before the piece, to have the frame that is on screen when it starts.
        let readStart = first == 0 ? CMTime.zero
            : CMTimeMaximum(.zero, pieces[first].start - CMTime(seconds: 3, preferredTimescale: Self.scale))
        reader.timeRange = CMTimeRange(start: readStart, end: total)
        let format = plan.source.isHDR ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
            : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: format,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw EditExportFailure.failed(nil) }
        reader.add(output)
        guard reader.startReading() else { throw EditExportFailure.failed(reader.error) }
        var writer: PieceWriter?
        defer {
            reader.cancelReading()
            writer?.abandon()
        }

        var pieceIndex = first
        let start = pieces[first].start
        var held: (buffer: CVPixelBuffer, time: CMTime)?
        var drew = false
        var events = plan.overlayTimes.filter { $0 > start.seconds + 0.001 }[...]
        var lastReport = Date.distantPast

        /// Writes the held frame at `time`, moving on to the next piece when it belongs there.
        func emit(_ buffer: CVPixelBuffer, at time: CMTime) throws {
            try checkStop()
            while time >= pieces[pieceIndex].end, pieceIndex + 1 < pieces.count {
                try writer?.finish()
                writer = nil
                pieceIndex += 1
            }
            if writer == nil {
                writer = try PieceWriter(piece: pieces[pieceIndex].url, start: pieces[pieceIndex].start,
                                         end: pieces[pieceIndex].end, plan: plan)
                let range = pieces[pieceIndex].start.seconds...pieces[pieceIndex].end.seconds
                writer?.overlays = overlays(in: range)
            }
            guard let writer else { return }
            try working { try writer.append(buffer, at: time) }
            if Date().timeIntervalSince(lastReport) > 0.2 {
                lastReport = Date()
                report(0.94 * min(1, time.seconds / max(0.1, total.seconds)))
            }
        }

        /// Everything to write between the held frame's own time and `next`: its repeats where an
        /// overlay changes, where a piece starts, and so it never stands longer than a second.
        func fill(until next: CMTime) throws {
            guard let held else { return }
            var cursor = CMTimeMaximum(held.time, start)
            if !drew {
                try emit(held.buffer, at: cursor)
                drew = true
            }
            while true {
                var following = cursor + CMTime(seconds: Self.longestFrame, preferredTimescale: Self.scale)
                if let event = events.first {
                    let time = CMTime(seconds: event, preferredTimescale: Self.scale)
                    if time <= cursor {
                        events = events.dropFirst()
                        continue
                    }
                    following = CMTimeMinimum(following, time)
                }
                let boundary = pieces[pieceIndex].end
                if pieceIndex + 1 < pieces.count, boundary > cursor { following = CMTimeMinimum(following, boundary) }
                // A repeat right before the next frame would only make the picture stutter.
                guard (next - following).seconds > 0.008 else { break }
                try emit(held.buffer, at: following)
                cursor = following
            }
        }

        while let sample = output.copyNextSampleBuffer() {
            try autoreleasepool {
                guard let buffer = CMSampleBufferGetImageBuffer(sample) else { return }
                let time = CMSampleBufferGetPresentationTimeStamp(sample)
                guard time.isNumeric else { return }
                if let current = held {
                    // A frame from before the piece, or one that starts where the last one did (a cut).
                    if time <= start || time <= current.time + CMTime(value: 1, timescale: 2_000) {
                        held = (buffer, CMTimeMaximum(time, current.time))
                        return
                    }
                    try fill(until: time)
                }
                // The very first frame stands from the start even when it is stamped a little later.
                held = (buffer, held == nil ? CMTimeMinimum(time, start) : time)
                drew = false
                try checkStop()
            }
        }
        if reader.status == .failed { throw EditExportFailure.failed(reader.error) }
        try checkStop()
        guard held != nil else { throw EditExportFailure.failed(nil) }
        try fill(until: total)
        // The last pieces, when the picture stands still to the end.
        try writer?.finish()
        writer = nil
        if pieceIndex + 1 < pieces.count { throw EditExportFailure.failed(nil) }
    }

    private func overlays(in range: ClosedRange<Double>) -> [EditOverlayImage] {
        guard !plan.overlayTimes.isEmpty else { return [] }
        // Made on the main thread (they are SwiftUI views) a few at a time, so a long video with
        // hundreds of captions never holds all of them in memory.
        let make = plan.overlays
        return DispatchQueue.main.sync { MainActor.assumeIsolated { make(range) } }
    }

    // MARK: - Join

    /// The pieces, one after another without encoding them again, with the sound.
    private func join(_ pieces: [Piece]) throws {
        try working {}
        try? FileManager.default.removeItem(at: plan.output)
        let writer = try AVAssetWriter(outputURL: plan.output, fileType: pieces.isEmpty ? .m4a : .mp4)
        writer.shouldOptimizeForNetworkUse = true
        let total = plan.build.duration

        var videoIn: AVAssetWriterInput?
        let feed = PieceFeed(pieces: pieces.map { ($0.url, $0.start, $0.end) })
        if !pieces.isEmpty {
            guard let format = try feed.firstFormat() else { throw EditExportFailure.failed(nil) }
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: format)
            input.expectsMediaDataInRealTime = false
            input.mediaTimeScale = Self.scale
            if !plan.draws { input.transform = plan.fileTransform }
            guard writer.canAdd(input) else { throw EditExportFailure.failed(nil) }
            writer.add(input)
            videoIn = input
        }
        var audioIn: AVAssetWriterInput?
        var sound: SoundFeed?
        if !plan.build.audioTrackIDs.isEmpty || !plan.build.voiceTrackIDs.isEmpty {
            sound = try SoundFeed(plan: plan)
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: SoundFeed.sampleRate,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: Int(EditExportSettings.audioBitRate),
            ])
            input.expectsMediaDataInRealTime = false
            guard writer.canAdd(input) else { throw EditExportFailure.failed(nil) }
            writer.add(input)
            audioIn = input
        }
        guard writer.startWriting() else { throw EditExportFailure.failed(writer.error) }
        writer.startSession(atSourceTime: .zero)
        var finished = false
        defer {
            if !finished { writer.cancelWriting() }
            sound?.stop()
        }

        var videoDone = videoIn == nil
        var audioDone = audioIn == nil
        var idle = 0
        var lastReport = Date.distantPast
        while !(videoDone && audioDone) {
            try checkStop()
            if writer.status == .failed { throw EditExportFailure.failed(writer.error) }
            var moved = false
            if !videoDone, let videoIn, videoIn.isReadyForMoreMediaData {
                try autoreleasepool {
                    if let sample = try feed.next() {
                        guard videoIn.append(sample) else { throw EditExportFailure.failed(writer.error) }
                        if Date().timeIntervalSince(lastReport) > 0.2 {
                            lastReport = Date()
                            let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                            report(0.94 + 0.05 * min(1, time / max(0.1, total.seconds)))
                        }
                    } else {
                        videoIn.markAsFinished()
                        videoDone = true
                    }
                }
                moved = true
            }
            if !audioDone, let audioIn, let sound, audioIn.isReadyForMoreMediaData {
                try autoreleasepool {
                    if let sample = try sound.next() {
                        guard audioIn.append(sample) else { throw EditExportFailure.failed(writer.error) }
                        if videoIn == nil, Date().timeIntervalSince(lastReport) > 0.2 {
                            lastReport = Date()
                            report(min(0.99, CMSampleBufferGetPresentationTimeStamp(sample).seconds / max(0.1, total.seconds)))
                        }
                    } else {
                        audioIn.markAsFinished()
                        audioDone = true
                    }
                }
                moved = true
            }
            if moved {
                idle = 0
            } else {
                idle += 1
                if idle > 15_000 { throw EditExportFailure.failed(writer.error) }
                usleep(1_000)
            }
        }
        writer.endSession(atSourceTime: total)
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        finished = true
        guard writer.status == .completed else { throw EditExportFailure.failed(writer.error) }
        try? FileManager.default.removeItem(at: plan.workFolder)
    }
}

// MARK: - One piece of picture

/// Encodes one piece. Until `finish` the file has another name, so a piece on disk is a whole one.
private final class PieceWriter {
    var overlays: [EditOverlayImage] = []
    private let url: URL
    private let partial: URL
    private let start: CMTime
    private let end: CMTime
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let pipeline: EditFramePipeline?
    private var last = CMTime.negativeInfinity
    private var isDone = false

    init(piece url: URL, start: CMTime, end: CMTime, plan: EditExportPlan) throws {
        self.url = url
        self.start = start
        self.end = end
        partial = url.deletingPathExtension().appendingPathExtension("partial.mov")
        try? FileManager.default.removeItem(at: partial)
        writer = try AVAssetWriter(outputURL: partial, fileType: .mov)
        let size = plan.settings.size
        // A picture that isn't drawn again is encoded the way it is stored and turned by the file,
        // like the recording itself.
        let sideways = !plan.draws && plan.source.orientation.turnsSides
        let width = sideways ? size.height : size.width
        let height = sideways ? size.width : size.height
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(width),
            AVVideoHeightKey: Int(height),
            AVVideoScalingModeKey: AVVideoScalingModeResize,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: Int(plan.settings.videoBitRate),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoH264EntropyModeKey: AVVideoH264EntropyModeCABAC,
                // No frames that depend on later ones: pieces join exactly at their edges.
                AVVideoAllowFrameReorderingKey: false,
                AVVideoMaxKeyFrameIntervalDurationKey: 2,
                AVVideoExpectedSourceFrameRateKey: plan.source.frameRate > 31 ? 60 : 30,
            ] as [String: Any],
        ])
        input.expectsMediaDataInRealTime = false
        input.mediaTimeScale = 90_000
        // Drawn frames come from the adaptor's pool; others are handed over as they were read, at
        // their own size (the encoder scales them).
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: plan.draws ? [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey as String: Int(width),
            kCVPixelBufferHeightKey as String: Int(height),
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ] : nil)
        pipeline = plan.draws ? EditFramePipeline(recipe: plan.recipe, source: plan.source, renderSize: size, showsBlur: true) : nil
        guard writer.canAdd(input) else { throw EditExportFailure.failed(nil) }
        writer.add(input)
        guard writer.startWriting() else { throw EditExportFailure.failed(writer.error) }
        writer.startSession(atSourceTime: start)
    }

    func append(_ buffer: CVPixelBuffer, at time: CMTime) throws {
        let time = CMTimeMaximum(time, start)
        guard time > last, time < end else { return }
        var waited = 0
        while !input.isReadyForMoreMediaData {
            if writer.status != .writing { throw EditExportFailure.failed(writer.error) }
            waited += 1
            if waited > 15_000 { throw EditExportFailure.failed(writer.error) }
            usleep(1_000)
        }
        var frame = buffer
        if let pipeline {
            guard let pool = adaptor.pixelBufferPool else { throw EditExportFailure.failed(writer.error) }
            var made: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made)
            guard let output = made else { throw EditExportFailure.failed(nil) }
            pipeline.render(buffer, at: time.seconds, overlays: overlays, into: output)
            frame = output
        }
        guard adaptor.append(frame, withPresentationTime: time) else { throw EditExportFailure.failed(writer.error) }
        last = time
    }

    func finish() throws {
        guard !isDone else { return }
        isDone = true
        input.markAsFinished()
        writer.endSession(atSourceTime: end)
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed, last.isNumeric else {
            try? FileManager.default.removeItem(at: partial)
            throw EditExportFailure.failed(writer.error)
        }
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: partial, to: url)
    }

    func abandon() {
        guard !isDone else { return }
        isDone = true
        if writer.status == .writing { writer.cancelWriting() }
        try? FileManager.default.removeItem(at: partial)
    }
}

extension CGImagePropertyOrientation {
    /// Width and height swap when it is applied.
    var turnsSides: Bool {
        switch self {
        case .left, .right, .leftMirrored, .rightMirrored: return true
        default: return false
        }
    }
}

// MARK: - Feeds

/// The encoded frames of the pieces, in order, on the edit's clock.
private final class PieceFeed {
    private let pieces: [(url: URL, start: CMTime, end: CMTime)]
    private var index = -1
    private var reader: AVAssetReader?
    private var output: AVAssetReaderTrackOutput?
    private var pending: CMSampleBuffer?
    private var queued: [CMSampleBuffer] = []

    init(pieces: [(url: URL, start: CMTime, end: CMTime)]) {
        self.pieces = pieces
    }

    func firstFormat() throws -> CMFormatDescription? {
        guard let first = pieces.first, let track = AVURLAsset(url: first.url).tracks(withMediaType: .video).first else { return nil }
        return track.formatDescriptions.first.map { $0 as! CMFormatDescription }
    }

    /// The next frame, with its time moved to where its piece starts and its length reaching to
    /// the next frame (the file would otherwise guess the last length of each piece).
    func next() throws -> CMSampleBuffer? {
        while true {
            if let sample = try raw() {
                if let ready = pending {
                    pending = sample
                    return try timed(ready, until: CMSampleBufferGetPresentationTimeStamp(sample))
                }
                pending = sample
                continue
            }
            guard let ready = pending else { return nil }
            pending = nil
            return try timed(ready, until: pieces[pieces.count - 1].end)
        }
    }

    private func raw() throws -> CMSampleBuffer? {
        while true {
            if !queued.isEmpty { return queued.removeFirst() }
            if let output {
                if let sample = output.copyNextSampleBuffer() {
                    let count = CMSampleBufferGetNumSamples(sample)
                    guard count > 0, CMSampleBufferGetDataBuffer(sample) != nil else { continue }
                    if count == 1 { return try shifted(sample, by: pieces[index].start) }
                    for position in 0..<count {
                        var one: CMSampleBuffer?
                        CMSampleBufferCopySampleBufferForRange(allocator: nil, sampleBuffer: sample,
                                                               sampleRange: CFRange(location: position, length: 1),
                                                               sampleBufferOut: &one)
                        guard let one else { throw EditExportFailure.failed(nil) }
                        queued.append(try shifted(one, by: pieces[index].start))
                    }
                    continue
                }
                if reader?.status == .failed { throw EditExportFailure.failed(reader?.error) }
                reader = nil
                self.output = nil
            }
            index += 1
            guard index < pieces.count else { return nil }
            let asset = AVURLAsset(url: pieces[index].url)
            guard let track = asset.tracks(withMediaType: .video).first else { throw EditExportFailure.failed(nil) }
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else { throw EditExportFailure.failed(nil) }
            reader.add(output)
            guard reader.startReading() else { throw EditExportFailure.failed(reader.error) }
            self.reader = reader
            self.output = output
        }
    }

    private func shifted(_ sample: CMSampleBuffer, by offset: CMTime) throws -> CMSampleBuffer {
        try copy(sample, at: CMSampleBufferGetPresentationTimeStamp(sample) + offset, duration: CMSampleBufferGetDuration(sample))
    }

    private func timed(_ sample: CMSampleBuffer, until end: CMTime) throws -> CMSampleBuffer {
        let time = CMSampleBufferGetPresentationTimeStamp(sample)
        return try copy(sample, at: time, duration: CMTimeMaximum(end - time, CMTime(value: 1, timescale: 90_000)))
    }

    private func copy(_ sample: CMSampleBuffer, at time: CMTime, duration: CMTime) throws -> CMSampleBuffer {
        var timing = CMSampleTimingInfo(duration: duration, presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var result: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: sample, sampleTimingEntryCount: 1,
                                                           sampleTimingArray: &timing, sampleBufferOut: &result)
        guard status == noErr, let result else { throw EditExportFailure.failed(nil) }
        return result
    }
}

/// The edit's sound, mixed, without gaps and exactly as long as the edit. Silence fills what the
/// recording has no sound for, so every player keeps sound and picture together.
private final class SoundFeed {
    static let sampleRate = 44_100
    private let reader: AVAssetReader
    private let output: AVAssetReaderAudioMixOutput
    private let totalFrames: Int
    private var written = 0
    private var ended = false
    /// Samples read but not handed out yet (they start later than what is written).
    private var waiting: (frame: Int, sample: CMSampleBuffer)?
    private let format: CMAudioFormatDescription

    init(plan: EditExportPlan) throws {
        let composition = plan.build.composition
        let tracks = (plan.build.audioTrackIDs + plan.build.voiceTrackIDs).compactMap { composition.track(withTrackID: $0) }
        reader = try AVAssetReader(asset: composition)
        reader.timeRange = CMTimeRange(start: .zero, duration: plan.build.duration)
        output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Self.sampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        output.alwaysCopiesSampleData = false
        output.audioMix = EditCompositionBuilder.audioMix(recipe: plan.recipe, build: plan.build)
        output.audioTimePitchAlgorithm = .spectral
        guard reader.canAdd(output) else { throw EditExportFailure.failed(nil) }
        reader.add(output)
        guard reader.startReading() else { throw EditExportFailure.failed(reader.error) }
        totalFrames = Int((plan.build.duration.seconds * Double(Self.sampleRate)).rounded())
        var description = AudioStreamBasicDescription(mSampleRate: Float64(Self.sampleRate), mFormatID: kAudioFormatLinearPCM,
                                                      mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
                                                      mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
                                                      mChannelsPerFrame: 2, mBitsPerChannel: 16, mReserved: 0)
        var made: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &description, layoutSize: 0, layout: nil, magicCookieSize: 0,
                                       magicCookie: nil, extensions: nil, formatDescriptionOut: &made)
        guard let made else { throw EditExportFailure.failed(nil) }
        format = made
    }

    func stop() { reader.cancelReading() }

    func next() throws -> CMSampleBuffer? {
        while written < totalFrames {
            if waiting == nil, !ended {
                if let sample = output.copyNextSampleBuffer() {
                    let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                    let frame = time.isFinite ? Int((time * Double(Self.sampleRate)).rounded()) : written
                    waiting = (frame, sample)
                } else {
                    if reader.status == .failed { throw EditExportFailure.failed(reader.error) }
                    ended = true
                }
            }
            guard let next = waiting else {
                // Nothing more: silence to the end.
                return try silence(min(Self.sampleRate / 2, totalFrames - written))
            }
            // A step of a frame or two is rounding; more is a real gap.
            if next.frame > written + 2 {
                return try silence(min(Self.sampleRate / 2, min(next.frame, totalFrames) - written))
            }
            waiting = nil
            guard let data = bytes(of: next.sample) else { continue }
            var samples = data
            if next.frame < written - 2 {
                let skip = min(samples.count / 4, written - next.frame)
                samples = samples.dropFirst(skip * 4)
            }
            let count = min(samples.count / 4, totalFrames - written)
            guard count > 0 else { continue }
            return try buffer(Data(samples.prefix(count * 4)), frames: count)
        }
        return nil
    }

    private func bytes(of sample: CMSampleBuffer) -> Data? {
        guard let block = CMSampleBufferGetDataBuffer(sample) else { return nil }
        let length = CMBlockBufferGetDataLength(block)
        guard length >= 4 else { return nil }
        var data = Data(count: length)
        let status = data.withUnsafeMutableBytes { raw -> OSStatus in
            guard let base = raw.baseAddress else { return -1 }
            return CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: base)
        }
        return status == noErr ? data : nil
    }

    private func silence(_ frames: Int) throws -> CMSampleBuffer? {
        guard frames > 0 else { return nil }
        return try buffer(Data(count: frames * 4), frames: frames)
    }

    private func buffer(_ data: Data, frames: Int) throws -> CMSampleBuffer {
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: data.count, blockAllocator: nil,
                                           customBlockSource: nil, offsetToData: 0, dataLength: data.count,
                                           flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
        guard let block else { throw EditExportFailure.failed(nil) }
        data.withUnsafeBytes { raw in
            if let base = raw.baseAddress {
                _ = CMBlockBufferReplaceDataBytes(with: base, blockBuffer: block, offsetIntoDestination: 0, dataLength: data.count)
            }
        }
        var sample: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: frames,
            presentationTimeStamp: CMTime(value: CMTimeValue(written), timescale: CMTimeScale(Self.sampleRate)),
            packetDescriptions: nil, sampleBufferOut: &sample)
        guard let sample else { throw EditExportFailure.failed(nil) }
        written += frames
        return sample
    }
}
