import AVFoundation
import UIKit

/// Makes a share link's three files from a recording (docs/pro/API.md, "Storage layout"), cheapest first: the poster
/// (one frame), the preview (3 seconds), then the video.
///
/// The video is copied as it is when it is already web-sized (`WebPlan`), otherwise encoded in hardware in stretches
/// of a few seconds. Each stretch is added to `video.mp4` through `WebMovieFile` and noted in `prepare.json`, so
/// - what is done can be sent at once;
/// - preparing that is cut short (Snapreel left the screen, a call, the app closed) carries on at the last stretch;
/// - real progress is known.
final class WebPreparer {
    struct Job {
        var source: URL
        var folder: URL
        var maxLongSide: Int
        var isScreen: Bool
        var isAudio: Bool
        var title: String
        var duration: Double
        var hasPoster = false
        var hasPreview = false
    }

    /// `prepare.json`: where the web copy got to.
    private struct State: Codable {
        var copyID: String
        var sourceSize: Int64
        var sourceDate: Date
        var maxLongSide: Int
        var plan: WebPlan
        var reserve: Int64
        var isComplete = false
        var length: Int64 = 0
        var records = 0
        /// Video samples and audio packets written.
        var videoSamples = 0
        var audioPackets = 0
        /// The first video frame's time in the recording, and where the next stretch starts.
        var origin: CMTimeBox?
        var next: CMTimeBox?
        var videoEntry: Data?
        var audioEntry: Data?
        var audioRate: Int32 = 44_100
        var audioStart: Double = 0
        var audioTrim: Int64 = 0
        /// The sound was encoded to its own file first.
        var audioOffset: Double?
        /// Made with Apple's own exporter after this way failed.
        var usedFallback = false
    }

    private struct CMTimeBox: Codable {
        var value: Int64
        var timescale: Int32
        init(_ time: CMTime) { value = time.value; timescale = time.timescale }
        var time: CMTime { CMTime(value: value, timescale: timescale) }
    }

    private let job: Job
    private let update: (PrepareUpdate) -> Void
    private var stateURL: URL { job.folder.appendingPathComponent("prepare.json") }
    private var videoURL: URL { job.folder.appendingPathComponent("video.mp4") }
    private var tablesURL: URL { job.folder.appendingPathComponent("samples.bin") }
    private var soundURL: URL { job.folder.appendingPathComponent("sound.m4a") }

    /// Why the last web copy needed Apple's exporter (the tests expect it never to).
    static var lastFallback: String?

    /// One encoded stretch.
    private static let stretch = CMTime(value: 10, timescale: 1)

    /// `update` is called on the main thread, in order.
    init(job: Job, update: @escaping @MainActor (PrepareUpdate) -> Void) {
        self.job = job
        self.update = { item in
            DispatchQueue.main.async { MainActor.assumeIsolated { update(item) } }
        }
    }

    /// Runs to the end, or throws `CancellationError`/`WebExport.Interrupted` (carry on later) or a `WebExport.Failure`.
    func run() async throws {
        guard FileManager.default.fileExists(atPath: job.source.path) else { throw WebExport.Failure.gone }
        try await writeSmallFiles()
        try Task.checkCancellation()
        if job.isAudio {
            try await prepareSound()
        } else {
            try await prepareVideo()
        }
        // The updates sent so far have been handled.
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { done.resume() }
        }
    }

    // MARK: - Poster and preview

    private func writeSmallFiles() async throws {
        let posterURL = job.folder.appendingPathComponent("poster.jpg")
        let previewURL = job.folder.appendingPathComponent("preview.mp4")
        var poster: UIImage?
        if !job.hasPoster {
            poster = try? await WebExport.writePoster(from: job.source, isAudio: job.isAudio, title: job.title,
                                                      duration: job.duration, to: posterURL)
            if poster == nil { WebExport.writeStandIn(.poster, to: posterURL, title: job.title) }
            update(.file(.poster, size: FileFacts.size(posterURL)))
        }
        try Task.checkCancellation()
        if !job.hasPreview {
            // A preview that can't be made never holds the video back.
            if !AppActivity.isInBackground {
                try? await WebExport.writePreview(from: job.source, isAudio: job.isAudio,
                                                  card: poster ?? UIImage(contentsOfFile: posterURL.path), to: previewURL)
            }
            if FileFacts.size(previewURL) == 0, let card = poster ?? UIImage(contentsOfFile: posterURL.path) {
                try? await StillClip.write(card, seconds: 3, width: 480, to: previewURL)
            }
            update(.file(.preview, size: FileFacts.size(previewURL)))
        }
    }

    // MARK: - Sound only

    private func prepareSound() async throws {
        let source = try sourceFacts()
        if let state = loadState(), state.isComplete, matches(state, source), FileFacts.size(videoURL) == state.length {
            update(.videoDone(copyID: state.copyID, size: state.length, headerEnd: 0))
            return
        }
        try await WebExport.exportAudio(AVURLAsset(url: job.source), to: videoURL)
        let size = FileFacts.size(videoURL)
        guard size > 0 else { throw WebExport.Failure.cannotExport(nil) }
        var state = State(copyID: UUID().uuidString, sourceSize: source.size, sourceDate: source.date,
                          maxLongSide: job.maxLongSide, plan: WebPlan(), reserve: 0)
        state.isComplete = true
        state.length = size
        save(state)
        update(.videoDone(copyID: state.copyID, size: size, headerEnd: 0))
    }

    // MARK: - Video

    private func prepareVideo() async throws {
        let source = try sourceFacts()
        let saved = loadState().flatMap { matches($0, source) ? $0 : nil }
        if let saved, saved.isComplete, FileFacts.size(videoURL) == saved.length {
            update(.videoDone(copyID: saved.copyID, size: saved.length, headerEnd: saved.reserve))
            return
        }
        let asset = AVURLAsset(url: job.source, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw WebExport.Failure.cannotRead
        }
        let facts = try await VideoFacts(asset: asset, track: track)
        if saved?.usedFallback == true {
            try await fallback(asset, source: source, facts: facts)
            return
        }
        let plan = saved?.plan ?? WebPlan.make(facts, maxLongSide: job.maxLongSide, isScreen: job.isScreen)
        try checkRoom(plan.estimatedBytes)
        do {
            try await build(asset, track, facts, plan: plan, source: source, saved: saved)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Task.isCancelled { throw CancellationError() }
            if WebExport.isInterruption(error) || AppActivity.wasRecentlyInBackground { throw WebExport.Interrupted() }
            if DiskSpace.isOutOfSpace(error) { throw WebExport.Failure.cannotExport("Your iPhone is too full to prepare the video.") }
            Self.lastFallback = "\(error)"
            // Something about this file doesn't suit the fast way: let Apple's exporter do the whole of it.
            try await fallback(asset, source: source, facts: facts)
        }
    }

    private func checkRoom(_ bytes: Int64) throws {
        let have = FileFacts.size(videoURL)
        guard DiskSpace.available + have > bytes + 80_000_000 else {
            throw WebExport.Failure.cannotExport("Your iPhone is too full to prepare the video. Free up about \(Format.bytes(bytes + 80_000_000)) and try again.")
        }
    }

    /// The streamable file, from compressed samples: the recording's own, or freshly encoded ones.
    private func build(_ asset: AVURLAsset, _ track: AVAssetTrack, _ facts: VideoFacts, plan: WebPlan,
                       source: (size: Int64, date: Date), saved: State?) async throws {
        var state = saved ?? State(copyID: UUID().uuidString, sourceSize: source.size, sourceDate: source.date,
                                   maxLongSide: job.maxLongSide, plan: plan,
                                   reserve: WebMovieFile.reserve(duration: facts.duration,
                                                                 frameRate: plan.copies ? max(30, facts.frameRate) : 30))
        let movie: WebMovieFile
        if let opened = try? WebMovieFile(url: videoURL, tablesURL: tablesURL, reserve: state.reserve,
                                          resume: state.records > 0 ? (state.records, state.length) : nil) {
            movie = opened
        } else {
            // The files don't match the notes: start over, under a new name so nothing sent before is kept.
            state = State(copyID: UUID().uuidString, sourceSize: source.size, sourceDate: source.date,
                          maxLongSide: job.maxLongSide, plan: plan, reserve: state.reserve)
            movie = try WebMovieFile(url: videoURL, tablesURL: tablesURL, reserve: state.reserve)
        }
        save(state)
        send(state, facts)
        for file in (try? FileManager.default.contentsOfDirectory(at: job.folder, includingPropertiesForKeys: nil)) ?? []
        where file.lastPathComponent.hasPrefix("stretch-") {
            try? FileManager.default.removeItem(at: file)
        }

        let sound = try await openSound(asset, facts, &state)
        try sound?.skip(state.audioPackets)
        // Encoding and file work block: they run on their own thread, and look at `isCancelled` as they go.
        let box = StateBox(state)
        let cancelled = CancelFlag()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        if plan.copies {
                            try self.copySamples(asset, track, facts, movie, sound, box, cancelled)
                        } else {
                            try self.encodeSamples(asset, track, facts, plan, movie, sound, box, cancelled)
                        }
                        try self.finish(movie, sound, facts, plan, box)
                        done.resume()
                    } catch {
                        done.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            cancelled.set()
        }
        try await check(box.value, facts)
        var finished = box.value
        finished.isComplete = true
        finished.length = movie.length
        save(finished)
        for file in [tablesURL, soundURL] { try? FileManager.default.removeItem(at: file) }
        update(.videoDone(copyID: finished.copyID, size: movie.length, headerEnd: finished.reserve))
    }

    private final class StateBox: @unchecked Sendable {
        var value: State
        init(_ value: State) { self.value = value }
    }

    final class CancelFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var flag = false
        func set() { lock.lock(); flag = true; lock.unlock() }
        var isSet: Bool { lock.lock(); defer { lock.unlock() }; return flag }
        func check() throws { if isSet { throw CancellationError() } }
    }

    private func send(_ state: State, _ facts: VideoFacts) {
        let done: Double
        if let origin = state.origin?.time, let next = state.next?.time, facts.duration > 0 {
            done = min(0.99, max(0, (next - origin).seconds / facts.duration))
        } else {
            done = 0
        }
        let estimate: Int64
        if done > 0.05 {
            estimate = max(state.length, Int64(Double(state.length - state.reserve) / done) + state.reserve)
        } else {
            estimate = max(state.length, state.plan.estimatedBytes + state.reserve)
        }
        update(.video(.init(copyID: state.copyID, fraction: done,
                            finalBytes: state.records > 0 ? state.length : 0,
                            headerEnd: state.reserve, estimatedBytes: estimate)))
    }

    private func commit(_ movie: WebMovieFile, _ sound: SoundReader?, _ box: StateBox, next: CMTime, facts: VideoFacts) throws {
        try movie.commit()
        box.value.length = movie.length
        box.value.records = movie.committedRecords
        box.value.audioPackets = sound?.packetsRead ?? 0
        box.value.next = CMTimeBox(next)
        save(box.value)
        send(box.value, facts)
    }

    /// Adds one stretch of video, with the sound that belongs beside it, in half-second turns.
    private func add(_ samples: [WebMovieFile.Sample], _ movie: WebMovieFile, _ sound: SoundReader?) throws {
        let step = Int64(WebMovieFile.videoTimescale) / 2
        var mark = samples.first?.dts ?? 0
        for sample in samples {
            if sample.dts >= mark {
                mark = sample.dts + step
                try sound?.write(until: Double(mark) / Double(WebMovieFile.videoTimescale), to: movie)
            }
            try movie.append(sample)
        }
    }

    private func ticks(_ time: CMTime, from origin: CMTime) -> Int64 {
        CMTimeConvertScale(time - origin, timescale: WebMovieFile.videoTimescale, method: .roundHalfAwayFromZero).value
    }

    // MARK: Copying

    /// The recording's own samples, repackaged.
    private func copySamples(_ asset: AVURLAsset, _ track: AVAssetTrack, _ facts: VideoFacts, _ movie: WebMovieFile,
                             _ sound: SoundReader?, _ box: StateBox, _ cancelled: CancelFlag) throws {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw WebExport.Failure.cannotRead }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? WebExport.Failure.cannotRead }
        var skip = box.value.videoSamples
        var batch: [WebMovieFile.Sample] = []
        var batchStart: CMTime?
        while true {
            try cancelled.check()
            let more: Bool = try autoreleasepool {
                guard let buffer = output.copyNextSampleBuffer() else { return false }
                for piece in try CompressedSample.split(buffer) {
                    if box.value.origin == nil { box.value.origin = CMTimeBox(piece.pts) }
                    if box.value.videoEntry == nil, let description = piece.description {
                        box.value.videoEntry = SampleEntry.video(description)
                        guard box.value.videoEntry != nil else { throw WebExport.Failure.cannotExport(nil) }
                    }
                    if skip > 0 { skip -= 1; continue }
                    let origin = box.value.origin!.time
                    if let start = batchStart, piece.isSync, (piece.dts - start).seconds >= 10 {
                        try add(batch, movie, sound)
                        box.value.videoSamples += batch.count
                        try commit(movie, sound, box, next: piece.pts, facts: facts)
                        batch.removeAll(keepingCapacity: true)
                        batchStart = piece.dts
                    }
                    if batchStart == nil { batchStart = piece.dts }
                    batch.append(.init(isVideo: true, isSync: piece.isSync, dts: ticks(piece.dts, from: origin),
                                       pts: ticks(piece.pts, from: origin), data: piece.data))
                }
                return true
            }
            if !more { break }
        }
        guard reader.status == .completed else { throw reader.error ?? WebExport.Failure.cannotRead }
        try add(batch, movie, sound)
        box.value.videoSamples += batch.count
    }

    // MARK: Encoding

    /// Decodes, scales and encodes in hardware, one stretch after another. Frame times are kept (above 30 a second,
    /// frames are dropped, never the last one before a pause).
    private func encodeSamples(_ asset: AVURLAsset, _ track: AVAssetTrack, _ facts: VideoFacts, _ plan: WebPlan,
                               _ movie: WebMovieFile, _ sound: SoundReader?, _ box: StateBox, _ cancelled: CancelFlag) throws {
        let reader = try AVAssetReader(asset: asset)
        let from = box.value.next?.time ?? .zero
        if from > .zero { reader.timeRange = CMTimeRange(start: from, duration: .positiveInfinity) }
        let output = try frameOutput(asset, track, facts, plan)
        guard reader.canAdd(output) else { throw WebExport.Failure.cannotRead }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? WebExport.Failure.cannotRead }
        defer { if reader.status == .reading { reader.cancelReading() } }

        var writer: StretchWriter?
        var stretchStart = CMTime.invalid
        var index = box.value.records

        func close(next: CMTime) throws {
            guard let open = writer else { return }
            writer = nil
            let url = try open.finish()
            defer { try? FileManager.default.removeItem(at: url) }
            let origin = box.value.origin!.time
            var samples: [WebMovieFile.Sample] = []
            try CompressedSample.read(url, type: .video) { piece in
                if let description = piece.description, let entry = SampleEntry.video(description) {
                    if let known = box.value.videoEntry {
                        // The encoder changed its settings between stretches: this way can't join them.
                        if known != entry { throw WebExport.Failure.cannotExport(nil) }
                    } else {
                        box.value.videoEntry = entry
                    }
                }
                let start = open.start
                samples.append(.init(isVideo: true, isSync: piece.isSync, dts: self.ticks(start + piece.dts, from: origin),
                                     pts: self.ticks(start + piece.pts, from: origin), data: piece.data))
            }
            guard !samples.isEmpty else { throw WebExport.Failure.cannotExport(nil) }
            try add(samples, movie, sound)
            box.value.videoSamples += samples.count
            try commit(movie, sound, box, next: next, facts: facts)
        }

        func encode(_ frame: CMSampleBuffer) throws {
            let time = CMSampleBufferGetPresentationTimeStamp(frame)
            if box.value.origin == nil { box.value.origin = CMTimeBox(time) }
            if writer != nil, time - stretchStart >= Self.stretch { try close(next: time) }
            if writer == nil {
                index += 1
                writer = try StretchWriter(url: job.folder.appendingPathComponent("stretch-\(index).mp4"), plan: plan, start: time)
                stretchStart = time
            }
            try writer?.append(frame, cancelled)
        }

        var pacer = FramePacer()
        var last = CMTime.invalid
        while true {
            try cancelled.check()
            let more: Bool = try autoreleasepool {
                guard let frame = output.copyNextSampleBuffer() else { return false }
                guard CMSampleBufferGetImageBuffer(frame) != nil else { return true }
                let time = CMSampleBufferGetPresentationTimeStamp(frame)
                // A frame from before the stretch (still showing when it starts) belongs to the one before.
                guard time.isNumeric, time >= from, !last.isValid || time > last else { return true }
                last = time
                for ready in pacer.offer(frame, at: time) { try encode(ready) }
                return true
            }
            if !more { break }
        }
        guard reader.status == .completed else { throw reader.error ?? WebExport.Failure.cannotRead }
        for ready in pacer.rest() { try encode(ready) }
        try close(next: (box.value.origin?.time ?? .zero) + CMTime(seconds: facts.duration, preferredTimescale: 600))
    }

    /// Frames as the decoder makes them (the writer scales them and the file says how to turn them), or through a
    /// composition when an HDR picture has to become a normal one.
    private func frameOutput(_ asset: AVAsset, _ track: AVAssetTrack, _ facts: VideoFacts, _ plan: WebPlan) throws -> AVAssetReaderOutput {
        let pixels: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        guard facts.isHDR else {
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: pixels)
            output.alwaysCopiesSampleData = false
            return output
        }
        let composition = AVMutableVideoComposition()
        composition.renderSize = CGSize(width: plan.width, height: plan.height)
        composition.frameDuration = CMTime(value: 1, timescale: 30)
        composition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: facts.duration + 1, preferredTimescale: 600))
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setTransform(WebExport.upright(facts.transform, size: CGSize(width: facts.encodedWidth, height: facts.encodedHeight),
                                             scale: Double(plan.width) / max(1, facts.shownWidth)), at: .zero)
        instruction.layerInstructions = [layer]
        composition.instructions = [instruction]
        let output = AVAssetReaderVideoCompositionOutput(videoTracks: [track], videoSettings: pixels)
        output.videoComposition = composition
        output.alwaysCopiesSampleData = false
        return output
    }

    // MARK: Sound

    /// The recording's sound as AAC packets: its own when they suit, otherwise encoded to a file first (a minute of
    /// sound takes a fraction of a second).
    private func openSound(_ asset: AVURLAsset, _ facts: VideoFacts, _ state: inout State) async throws -> SoundReader? {
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { return nil }
        let origin: Double
        if let known = state.origin?.time {
            origin = known.seconds
        } else {
            origin = facts.firstFrame
        }
        let reader: SoundReader?
        if tracks.count == 1, let own = try await SoundReader.suitable(tracks[0]) {
            reader = try SoundReader(asset: asset, track: own, offset: 0, origin: origin)
        } else {
            if state.audioOffset == nil || FileFacts.size(soundURL) == 0 {
                guard let offset = try await WebExport.encodeSound(asset, tracks: tracks, to: soundURL) else { return nil }
                state.audioOffset = offset
                save(state)
            }
            let encoded = AVURLAsset(url: soundURL)
            guard let track = try await encoded.loadTracks(withMediaType: .audio).first else { return nil }
            reader = try SoundReader(asset: encoded, track: track, offset: state.audioOffset ?? 0, origin: origin)
        }
        guard let reader, reader.entry != nil else { return nil }
        state.audioEntry = reader.entry
        state.audioRate = reader.rate
        state.audioStart = reader.start
        state.audioTrim = reader.trim
        save(state)
        return reader
    }

    // MARK: Finishing

    private func finish(_ movie: WebMovieFile, _ sound: SoundReader?, _ facts: VideoFacts, _ plan: WebPlan, _ box: StateBox) throws {
        try sound?.write(until: .infinity, to: movie)
        guard let entry = box.value.videoEntry, movie.records.contains(where: \.isVideo) else { throw WebExport.Failure.cannotExport(nil) }
        // The turn with its shift worked out again: recordings from the screen recorder carry a turn without one, which
        // browsers ignore but Apple's players follow, drawing the picture off the canvas.
        let size = plan.copies ? CGSize(width: facts.encodedWidth, height: facts.encodedHeight)
            : CGSize(width: plan.encodedWidth, height: plan.encodedHeight)
        let transform = facts.isHDR && !plan.copies ? .identity : WebExport.upright(facts.transform, size: size, scale: 1)
        let origin = box.value.origin?.time ?? .zero
        let end = ticks(CMTime(seconds: facts.end, preferredTimescale: 90_000), from: origin)
        let video = WebMovieFile.Track(timescale: WebMovieFile.videoTimescale, entry: entry,
                                       width: Double(plan.copies ? facts.encodedWidth : plan.encodedWidth),
                                       height: Double(plan.copies ? facts.encodedHeight : plan.encodedHeight),
                                       transform: transform, end: end)
        var audio: WebMovieFile.Track?
        if let soundEntry = box.value.audioEntry, movie.records.contains(where: { !$0.isVideo }) {
            audio = WebMovieFile.Track(timescale: box.value.audioRate, entry: soundEntry,
                                       start: box.value.audioStart, trim: box.value.audioTrim)
        }
        try movie.finish(video: video, audio: audio)
        box.value.length = movie.length
        box.value.records = movie.committedRecords
    }

    /// Opens the finished file the way a player would, so a bad one is never sent.
    private func check(_ state: State, _ facts: VideoFacts) async throws {
        let asset = AVURLAsset(url: videoURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let playable = try await asset.load(.isPlayable)
        let duration = try await asset.load(.duration).seconds
        guard playable, abs(duration - facts.shownDuration) < max(1, facts.shownDuration * 0.02),
              try await asset.loadTracks(withMediaType: .video).count == 1 else {
            throw WebExport.Failure.cannotExport(nil)
        }
        // A frame from near the end proves the index points at real pictures.
        guard !AppActivity.isInBackground else { return }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.maximumSize = CGSize(width: 64, height: 64)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 6, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 6, preferredTimescale: 600)
        _ = try await generator.image(at: CMTime(seconds: max(0, duration - 1), preferredTimescale: 600))
    }

    /// Apple's exporter, for anything the fast way can't do. Nothing can be sent before it is done, and it starts
    /// over when interrupted.
    private func fallback(_ asset: AVURLAsset, source: (size: Int64, date: Date), facts: VideoFacts) async throws {
        var state = State(copyID: UUID().uuidString, sourceSize: source.size, sourceDate: source.date,
                          maxLongSide: job.maxLongSide, plan: WebPlan.make(facts, maxLongSide: job.maxLongSide, isScreen: job.isScreen),
                          reserve: 0)
        state.usedFallback = true
        save(state)
        let estimate = state.plan.estimatedBytes
        let copyID = state.copyID
        let update = update
        do {
            try await WebExport.exportWhole(asset, to: videoURL, maxLongSide: job.maxLongSide, limit: estimate * 13 / 10) { fraction in
                update(.video(.init(copyID: copyID, fraction: fraction, finalBytes: 0, headerEnd: 0, estimatedBytes: estimate)))
            }
        } catch {
            if Task.isCancelled { throw CancellationError() }
            if WebExport.isInterruption(error) || AppActivity.wasRecentlyInBackground { throw WebExport.Interrupted() }
            throw error
        }
        let size = FileFacts.size(videoURL)
        guard size > 0 else { throw WebExport.Failure.cannotExport(nil) }
        state.isComplete = true
        state.length = size
        save(state)
        update(.videoDone(copyID: copyID, size: size, headerEnd: 0))
    }

    // MARK: State

    private func sourceFacts() throws -> (size: Int64, date: Date) {
        let size = FileFacts.size(job.source)
        guard size > 0 else { throw WebExport.Failure.cannotRead }
        return (size, FileFacts.modified(job.source) ?? .distantPast)
    }

    private func matches(_ state: State, _ source: (size: Int64, date: Date)) -> Bool {
        state.sourceSize == source.size && abs(state.sourceDate.timeIntervalSince(source.date)) < 1
            && state.maxLongSide == job.maxLongSide
    }

    private func loadState() -> State? {
        (try? Data(contentsOf: stateURL)).flatMap { try? JSONDecoder().decode(State.self, from: $0) }
    }

    private func save(_ state: State) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

// MARK: - What the recording is

/// Facts about the recording's picture that decide how it goes to the web.
struct VideoFacts {
    var encodedWidth: Int
    var encodedHeight: Int
    var transform: CGAffineTransform
    var shownWidth: Double
    var shownHeight: Double
    var isH264: Bool
    var isHDR: Bool
    /// One plain stretch: no edits or gaps inside the track.
    var isSimple: Bool
    var bitRate: Double
    var frameRate: Double
    var duration: Double
    /// The first frame's time and where the picture ends, in seconds.
    var firstFrame: Double
    var end: Double
    /// The longer of picture and sound, counted from the first frame.
    var shownDuration: Double

    init(asset: AVURLAsset, track: AVAssetTrack) async throws {
        let natural = try await track.load(.naturalSize)
        transform = try await track.load(.preferredTransform)
        let formats = try await track.load(.formatDescriptions)
        let range = try await track.load(.timeRange)
        let segments = try await track.load(.segments)
        bitRate = Double(try await track.load(.estimatedDataRate))
        frameRate = Double(try await track.load(.nominalFrameRate))
        let shown = CGRect(origin: .zero, size: natural).applying(transform).size
        shownWidth = Double(abs(shown.width))
        shownHeight = Double(abs(shown.height))
        let format = formats.first
        let pixels = format.map { CMVideoFormatDescriptionGetDimensions($0) }
        encodedWidth = Int(pixels?.width ?? Int32(natural.width))
        encodedHeight = Int(pixels?.height ?? Int32(natural.height))
        isH264 = formats.count == 1 && format.map { CMFormatDescriptionGetMediaSubType($0) == kCMVideoCodecType_H264 } ?? false
        let transfer = format.flatMap { CMFormatDescriptionGetExtension($0, extensionKey: kCMFormatDescriptionExtension_TransferFunction) } as? String
        isHDR = transfer == kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String
            || transfer == kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String
        let real = segments.filter { !$0.isEmpty }
        isSimple = real.count <= 1 && real.allSatisfy { segment in
            let map = segment.timeMapping
            return abs(map.source.duration.seconds - map.target.duration.seconds) < 0.05 && abs(map.source.start.seconds) < 0.2
        }
        // Square pixels only, so the size in the file is the size shown.
        if let format {
            let presented = CMVideoFormatDescriptionGetPresentationDimensions(format, usePixelAspectRatio: true, useCleanAperture: true)
            if abs(presented.width - CGFloat(encodedWidth)) > 2 || abs(presented.height - CGFloat(encodedHeight)) > 2 { isSimple = false }
        }
        firstFrame = max(0, range.start.seconds.isFinite ? range.start.seconds : 0)
        end = range.end.seconds.isFinite ? range.end.seconds : firstFrame
        duration = max(0, end - firstFrame)
        guard duration > 0, encodedWidth > 0, encodedHeight > 0 else { throw WebExport.Failure.cannotRead }
        if bitRate <= 0 { bitRate = Double(FileFacts.size(asset.url)) * 8 / duration }
        let total = try await asset.load(.duration).seconds
        shownDuration = max(duration, (total.isFinite ? total : end) - firstFrame)
    }

    /// For the tests.
    init(width: Int, height: Int, bitRate: Double, duration: Double, isH264: Bool = true, frameRate: Double = 30,
         isSimple: Bool = true, isHDR: Bool = false) {
        encodedWidth = width
        encodedHeight = height
        transform = .identity
        shownWidth = Double(width)
        shownHeight = Double(height)
        self.isH264 = isH264
        self.isHDR = isHDR
        self.isSimple = isSimple
        self.bitRate = bitRate
        self.frameRate = frameRate
        self.duration = duration
        firstFrame = 0
        end = duration
        shownDuration = duration
    }
}

/// How a recording goes to the web: copied as it is, or encoded to a size and bit rate.
struct WebPlan: Codable, Equatable {
    /// The recording's own samples are small enough.
    var copies = false
    /// The size as shown, upright.
    var width = 0
    var height = 0
    /// The size in the file (before the turn).
    var encodedWidth = 0
    var encodedHeight = 0
    var bitRate = 0
    var estimatedBytes: Int64 = 0

    /// Most a link may hold, with room to spare for the bit rate to drift.
    private static let byteLimit = Double(CloudConfig.maxFileBytes) * 0.9

    /// About 5 Mbit/s for a camera picture at 1080p and 2.6 at 720p. Screen recordings are mostly still with sharp
    /// edges: the same steps at about half, which keeps text readable (docs/pro/BACKEND.md, "Uploads", has samples).
    static func targetBitRate(pixels: Double, isScreen: Bool) -> Double {
        let full = isScreen ? 2_600_000.0 : 5_000_000.0
        let rate = full * pow(max(1, pixels) / (1_920 * 1_080), 0.8)
        return max(isScreen ? 500_000 : 800_000, min(isScreen ? 4_000_000 : 8_000_000, rate))
    }

    static func make(_ facts: VideoFacts, maxLongSide: Int, isScreen: Bool) -> WebPlan {
        let long = max(facts.shownWidth, facts.shownHeight, 1)
        let scale = min(1, Double(maxLongSide) / long)
        func even(_ value: Double) -> Int { max(2, Int((value / 2).rounded()) * 2) }
        var plan = WebPlan()
        plan.width = even(facts.shownWidth * scale)
        plan.height = even(facts.shownHeight * scale)
        plan.encodedWidth = facts.isHDR ? plan.width : even(Double(facts.encodedWidth) * scale)
        plan.encodedHeight = facts.isHDR ? plan.height : even(Double(facts.encodedHeight) * scale)
        let target = targetBitRate(pixels: Double(plan.width * plan.height), isScreen: isScreen)
        // Two hours still have to fit in 2 GB.
        let most = max(300_000, byteLimit * 8 / max(1, facts.duration) - 160_000)
        plan.bitRate = Int(min(target, most))
        // Encoding again costs time and sharpness, so a recording a little over the target is sent as it is.
        let fits = long <= Double(maxLongSide) + 1
        plan.copies = facts.isH264 && facts.isSimple && !facts.isHDR && fits
            && facts.bitRate <= target * 1.25 && facts.bitRate <= most
        let rate = plan.copies ? facts.bitRate : Double(plan.bitRate) * (isScreen ? 0.85 : 1)
        plan.estimatedBytes = Int64((rate + 128_000) * facts.duration / 8)
        return plan
    }
}

/// Keeps at most 30 frames a second without losing the last frame before a pause: a screen that changes twice
/// quickly and then stands still must end on the second picture.
struct FramePacer {
    private var lastKept = CMTime.invalid
    private var held: (frame: CMSampleBuffer, time: CMTime)?
    private static let shortest = CMTime(value: 29, timescale: 1_000)

    /// The frames to encode now that `frame` arrived.
    mutating func offer(_ frame: CMSampleBuffer, at time: CMTime) -> [CMSampleBuffer] {
        var ready: [CMSampleBuffer] = []
        if let waiting = held, time - waiting.time >= Self.shortest {
            ready.append(waiting.frame)
            lastKept = waiting.time
            held = nil
        }
        if !lastKept.isValid || time - lastKept >= Self.shortest {
            ready.append(frame)
            lastKept = time
            held = nil
        } else {
            held = (frame, time)
        }
        return ready
    }

    mutating func rest() -> [CMSampleBuffer] {
        defer { held = nil }
        return held.map { [$0.frame] } ?? []
    }
}

// MARK: - Reading and writing samples

/// One compressed sample out of a file.
struct CompressedSample {
    var dts: CMTime
    var pts: CMTime
    var duration: CMTime
    var isSync: Bool
    var data: Data
    var description: CMFormatDescription?

    /// The single samples inside a buffer (sound comes in packs).
    static func split(_ buffer: CMSampleBuffer) throws -> [CompressedSample] {
        let count = CMSampleBufferGetNumSamples(buffer)
        guard count > 0, let block = CMSampleBufferGetDataBuffer(buffer) else { return [] }
        let description = CMSampleBufferGetFormatDescription(buffer)
        let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[CFString: Any]]
        let all = try block.dataBytes()
        var offset = 0
        var samples: [CompressedSample] = []
        samples.reserveCapacity(count)
        for index in 0..<count {
            let size = CMSampleBufferGetSampleSize(buffer, at: index)
            guard size > 0, offset + size <= all.count else { throw WebExport.Failure.cannotRead }
            var timing = CMSampleTimingInfo()
            guard CMSampleBufferGetSampleTimingInfo(buffer, at: index, timingInfoOut: &timing) == noErr else { throw WebExport.Failure.cannotRead }
            let pts = timing.presentationTimeStamp
            let dts = timing.decodeTimeStamp.isNumeric ? timing.decodeTimeStamp : pts
            let attachment = attachments.flatMap { index < $0.count ? $0[index] : nil }
            let notSync = attachment?[kCMSampleAttachmentKey_NotSync] as? Bool ?? false
            samples.append(CompressedSample(dts: dts, pts: pts, duration: timing.duration, isSync: !notSync,
                                            data: all.subdata(in: (all.startIndex + offset)..<(all.startIndex + offset + size)),
                                            description: description))
            offset += size
        }
        return samples
    }

    /// Every sample of a short file's track, in file order.
    static func read(_ url: URL, type: AVMediaType, _ each: (CompressedSample) throws -> Void) throws {
        let asset = AVURLAsset(url: url)
        let reader = try AVAssetReader(asset: asset)
        guard let track = asset.loadedTracks(type).first else { throw WebExport.Failure.cannotRead }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw WebExport.Failure.cannotRead }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? WebExport.Failure.cannotRead }
        while let buffer = output.copyNextSampleBuffer() {
            for sample in try split(buffer) { try each(sample) }
        }
        guard reader.status == .completed else { throw reader.error ?? WebExport.Failure.cannotRead }
    }
}

extension AVAsset {
    /// The tracks, loaded while a worker thread waits. Never call it from the main thread.
    func loadedTracks(_ type: AVMediaType) -> [AVAssetTrack] {
        let done = DispatchSemaphore(value: 0)
        var found: [AVAssetTrack] = []
        loadTracks(withMediaType: type) { tracks, _ in
            found = tracks ?? []
            done.signal()
        }
        done.wait()
        return found
    }
}

/// Encodes one stretch of frames to its own little file.
private final class StretchWriter {
    let start: CMTime
    private let url: URL
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput

    init(url: URL, plan: WebPlan, start: CMTime) throws {
        self.url = url
        self.start = start
        try? FileManager.default.removeItem(at: url)
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let compression: [String: Any] = [
            AVVideoAverageBitRateKey: plan.bitRate,
            AVVideoExpectedSourceFrameRateKey: 30,
            AVVideoMaxKeyFrameIntervalKey: 120,
            AVVideoMaxKeyFrameIntervalDurationKey: 4,
            AVVideoAllowFrameReorderingKey: false,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            AVVideoH264EntropyModeKey: AVVideoH264EntropyModeCABAC,
        ]
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: plan.encodedWidth,
            AVVideoHeightKey: plan.encodedHeight,
            AVVideoScalingModeKey: AVVideoScalingModeResize,
            AVVideoCompressionPropertiesKey: compression,
        ])
        input.expectsMediaDataInRealTime = false
        input.mediaTimeScale = WebMovieFile.videoTimescale
        guard writer.canAdd(input) else { throw WebExport.Failure.cannotExport(nil) }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? WebExport.Failure.cannotExport(nil) }
        writer.startSession(atSourceTime: start)
    }

    func append(_ frame: CMSampleBuffer, _ cancelled: WebPreparer.CancelFlag) throws {
        while !input.isReadyForMoreMediaData {
            if cancelled.isSet { writer.cancelWriting(); throw CancellationError() }
            guard writer.status == .writing else { throw writer.error ?? WebExport.Failure.cannotExport(nil) }
            usleep(1_500)
        }
        guard input.append(frame) else { throw writer.error ?? WebExport.Failure.cannotExport(nil) }
    }

    func finish() throws -> URL {
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else { throw writer.error ?? WebExport.Failure.cannotExport(nil) }
        return url
    }
}

/// Hands out a track's AAC packets in order.
final class SoundReader {
    let entry: Data?
    let rate: Int32
    /// Where the first packet starts, in seconds from the first video frame.
    let start: Double
    /// The encoder's delay inside the first packets.
    let trim: Int64
    private(set) var packetsRead = 0

    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput
    private var queue: [CompressedSample] = []
    private var firstPTS = CMTime.invalid
    private var ended = false

    /// The track itself when its packets can go up as they are: AAC-LC, at most stereo, a sensible bit rate, no gaps.
    static func suitable(_ track: AVAssetTrack) async throws -> AVAssetTrack? {
        let formats = try await track.load(.formatDescriptions)
        guard formats.count == 1, let format = formats.first,
              CMFormatDescriptionGetMediaSubType(format) == kAudioFormatMPEG4AAC,
              let basic = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
              basic.mChannelsPerFrame <= 2, basic.mSampleRate >= 22_050, basic.mSampleRate <= 48_000 else { return nil }
        let bitRate = try await track.load(.estimatedDataRate)
        guard bitRate <= 200_000 else { return nil }
        let real = try await track.load(.segments).filter { !$0.isEmpty }
        guard real.count == 1 else { return nil }
        return track
    }

    init(asset: AVAsset, track: AVAssetTrack, offset: Double, origin: Double) throws {
        reader = try AVAssetReader(asset: asset)
        output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw WebExport.Failure.cannotRead }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? WebExport.Failure.cannotRead }
        var first: CMSampleBuffer?
        while let buffer = output.copyNextSampleBuffer() {
            if CMSampleBufferGetNumSamples(buffer) > 0 && CMSampleBufferGetDataBuffer(buffer) != nil {
                first = buffer
                break
            }
        }
        guard let first, let format = CMSampleBufferGetFormatDescription(first),
              let basic = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee else {
            entry = nil
            rate = 44_100
            start = 0
            trim = 0
            ended = true
            return
        }
        entry = SampleEntry.audio(format)
        rate = Int32(basic.mSampleRate)
        let trimmed = (CMGetAttachment(first, key: kCMSampleBufferAttachmentKey_TrimDurationAtStart, attachmentModeOut: nil))
            .map { CMTimeMakeFromDictionary(($0 as! CFDictionary)) } ?? .zero
        trim = trimmed.isNumeric ? CMTimeConvertScale(trimmed, timescale: rate, method: .roundHalfAwayFromZero).value : 0
        queue = try CompressedSample.split(first)
        firstPTS = queue.first?.pts ?? .zero
        // Packets are timed in the file's own media time. What counts is where they are heard: the first buffer is heard
        // from its output time on, once the encoder's delay is cut off, so its first packet starts that much earlier.
        // (Measured on iOS 16.4: media time 0, delay 0.048 s, heard from 0.)
        let heard = CMSampleBufferGetOutputPresentationTimeStamp(first)
        start = (heard.isNumeric ? heard.seconds : firstPTS.seconds) - (trimmed.isNumeric ? trimmed.seconds : 0) + offset - origin
    }

    private func fill() throws {
        while queue.isEmpty && !ended {
            guard let buffer = output.copyNextSampleBuffer() else {
                ended = true
                guard reader.status == .completed else { throw reader.error ?? WebExport.Failure.cannotRead }
                return
            }
            queue = try CompressedSample.split(buffer)
        }
    }

    /// Passes over packets written in an earlier run.
    func skip(_ count: Int) throws {
        while packetsRead < count {
            try fill()
            guard !queue.isEmpty else { return }
            queue.removeFirst()
            packetsRead += 1
        }
    }

    /// Writes the packets that start before `time` (seconds from the first video frame).
    func write(until time: Double, to movie: WebMovieFile) throws {
        while true {
            try fill()
            guard let packet = queue.first else { return }
            let since = packet.pts - firstPTS
            if start + since.seconds >= time { return }
            let tick = CMTimeConvertScale(since, timescale: rate, method: .roundHalfAwayFromZero).value
            try movie.append(.init(isVideo: false, isSync: true, dts: tick, pts: tick, data: packet.data))
            queue.removeFirst()
            packetsRead += 1
        }
    }
}

/// Whether Snapreel is off the screen, for work that can't ask the main thread.
enum AppActivity {
    private static let lock = NSLock()
    private static var background = false
    private static var leftAt = Date.distantPast
    private static var returnedAt = Date.distantPast
    private static var observing = false

    static var isInBackground: Bool {
        lock.lock()
        defer { lock.unlock() }
        return background
    }

    /// Off the screen now, or a moment ago (hardware encoders are taken away when an app leaves).
    static var wasRecentlyInBackground: Bool {
        lock.lock()
        defer { lock.unlock() }
        return background || Date().timeIntervalSince(returnedAt) < 5
    }

    @MainActor static func startObserving() {
        guard !observing else { return }
        observing = true
        lock.lock()
        background = UIApplication.shared.applicationState == .background
        lock.unlock()
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { _ in
            lock.lock()
            background = true
            leftAt = Date()
            lock.unlock()
        }
        center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil) { _ in
            lock.lock()
            background = false
            returnedAt = Date()
            lock.unlock()
        }
    }
}
