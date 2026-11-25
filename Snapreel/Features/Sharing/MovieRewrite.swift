import AVFoundation
import Foundation

// Writing a recording again without touching its picture: one sound track instead of two, one index
// instead of fragments, a proper MP4. Used after a screen recording is saved (`RecordingSaver`) and
// when one is shared or saved to Photos before that could be done (`ShareCopies`).

/// Why a recording's file was not written again.
enum MovieRewriteError: Error, Equatable {
    /// The person stopped it.
    case cancelled
    /// iOS stopped it: Snapreel went to the background and its time there ran out.
    case interrupted
    case noSpace
    /// The file can't be read as a movie.
    case unreadable
    case failed
}

/// Stops a rewrite from anywhere and carries its progress out. Safe from any thread.
final class MovieRewriteControl: @unchecked Sendable {
    private let lock = NSLock()
    private var stop: MovieRewriteError?
    private var lastReport = Date.distantPast
    private let report: @Sendable (Double) -> Void

    /// `report` gets 0...1, at most ten times a second, on any thread.
    init(report: @escaping @Sendable (Double) -> Void = { _ in }) {
        self.report = report
    }

    func cancel() { set(.cancelled) }
    func interrupt() { set(.interrupted) }

    /// Why it has to stop, if it does.
    var stopped: MovieRewriteError? {
        lock.lock()
        defer { lock.unlock() }
        return stop
    }

    func progress(_ value: Double) {
        lock.lock()
        let now = Date()
        let due = now.timeIntervalSince(lastReport) >= 0.1 || value >= 1
        if due { lastReport = now }
        lock.unlock()
        if due { report(min(1, max(0, value))) }
    }

    private func set(_ error: MovieRewriteError) {
        lock.lock()
        if stop == nil { stop = error }
        lock.unlock()
    }
}

/// What has to change in a recording's file before other apps get it, if anything.
struct MoviePlan: Equatable {
    enum Sound: Equatable {
        case none
        /// One track, copied as it is.
        case copy(CMPersistentTrackID)
        /// Several tracks with sound, mixed into one (the only step that decodes anything).
        case mix([CMPersistentTrackID])
    }

    enum Reason: String {
        /// Cut off while recording: many small indexes instead of one.
        case fragmented
        /// Phone sound and microphone on separate tracks. Most apps play only the first one.
        case twoSounds
        /// A turned picture without the shift back into view (builds up to 47).
        case pictureOffset
    }

    var reasons: Set<Reason> = []
    var sound: Sound = .none
    /// The picture's transform as it should be.
    var transform: CGAffineTransform = .identity
    var duration: Double = 0

    var needsRewrite: Bool { !reasons.isEmpty }

    /// Reads `url`. `isScreenRecording`: its sound tracks belong together and are mixed. Movies from
    /// elsewhere can carry alternative sound tracks that must not be.
    static func make(for url: URL, isScreenRecording: Bool) async throws -> MoviePlan {
        let asset = AVURLAsset(url: url)
        let videoTracks: [AVAssetTrack]
        let audioTracks: [AVAssetTrack]
        var plan = MoviePlan()
        do {
            videoTracks = try await asset.loadTracks(withMediaType: .video)
            audioTracks = try await asset.loadTracks(withMediaType: .audio)
            plan.duration = try await asset.load(.duration).seconds
        } catch {
            throw MovieRewriteError.unreadable
        }
        guard plan.duration.isFinite, plan.duration > 0, !videoTracks.isEmpty || !audioTracks.isEmpty else {
            throw MovieRewriteError.unreadable
        }
        if MovieStructure.read(url)?.isFragmented == true { plan.reasons.insert(.fragmented) }

        if let video = videoTracks.first {
            let size = try await video.load(.naturalSize)
            let transform = try await video.load(.preferredTransform)
            plan.transform = upright(transform, size: size)
            if isScreenRecording, plan.transform != transform { plan.reasons.insert(.pictureOffset) }
        }

        guard isScreenRecording, audioTracks.count > 1 else {
            plan.sound = audioTracks.first.map { .copy($0.trackID) } ?? .none
            return plan
        }
        plan.reasons.insert(.twoSounds)
        var heard: [CMPersistentTrackID] = []
        for track in audioTracks {
            if await carriesSound(track, of: asset) { heard.append(track.trackID) }
        }
        switch heard.count {
        case 0: plan.sound = .copy(audioTracks[0].trackID)
        case 1: plan.sound = .copy(heard[0])
        default: plan.sound = .mix(heard)
        }
        return plan
    }

    /// `transform` with the turned picture moved back to the origin.
    static func upright(_ transform: CGAffineTransform, size: CGSize) -> CGAffineTransform {
        let placed = CGRect(origin: .zero, size: size).applying(transform)
        guard abs(placed.minX) > 1 || abs(placed.minY) > 1 else { return transform }
        return transform.concatenating(CGAffineTransform(translationX: -placed.minX, y: -placed.minY))
    }

    /// Whether a track has anything to hear. Digital silence packs into AAC packets of a few bytes,
    /// so the packet sizes tell, without decoding. Only AAC is judged; anything else counts as sound.
    private static func carriesSound(_ track: AVAssetTrack, of asset: AVAsset) async -> Bool {
        guard let range = try? await track.load(.timeRange), range.duration.seconds > 0.1 else { return false }
        guard let formats = try? await track.load(.formatDescriptions), let format = formats.first,
              CMFormatDescriptionGetMediaSubType(format) == kAudioFormatMPEG4AAC,
              let reader = try? AVAssetReader(asset: asset) else { return true }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return true }
        reader.add(output)
        guard reader.startReading() else { return true }
        var loudPackets = 0
        while let sample = output.copyNextSampleBuffer() {
            for index in 0..<CMSampleBufferGetNumSamples(sample)
            where CMSampleBufferGetSampleSize(sample, at: index) > silentPacketBytes {
                loudPackets += 1
                // The encoder's first packets can be large even for silence.
                if loudPackets > 12 {
                    reader.cancelReading()
                    return true
                }
            }
        }
        // A read that failed midway proves nothing.
        return reader.status != .completed
    }

    private static let silentPacketBytes = 40
}

/// Writes a movie again with its picture copied sample by sample.
enum MovieRewrite {
    /// - Parameters:
    ///   - fileType: `.mov` for the library's own file, `.mp4` for a copy other apps get.
    ///   - indexFirst: puts the index before the pictures. The file is written twice for that, so
    ///     only for copies that may be streamed.
    static func run(_ source: URL, to destination: URL, plan: MoviePlan, fileType: AVFileType,
                    indexFirst: Bool, control: MovieRewriteControl) async throws {
        try? FileManager.default.removeItem(at: destination)
        do {
            try await write(source, to: destination, plan: plan, fileType: fileType, indexFirst: indexFirst,
                            control: control)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw MoviePump.explain(error, control: control)
        }
    }

    private static func write(_ source: URL, to destination: URL, plan: MoviePlan, fileType: AVFileType,
                              indexFirst: Bool, control: MovieRewriteControl) async throws {
        let asset = AVURLAsset(url: source)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: destination, fileType: fileType)
        writer.shouldOptimizeForNetworkUse = indexFirst
        if let created = try? await asset.load(.creationDate) { writer.metadata = [created] }
        var lanes: [MoviePump.Lane] = []

        if let video = videoTracks.first {
            let output = AVAssetReaderTrackOutput(track: video, outputSettings: nil)
            let formats = try await video.load(.formatDescriptions)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: formats.first)
            input.transform = plan.transform
            // Frames keep their exact (uneven) times.
            let scale = try await video.load(.naturalTimeScale)
            if scale > 0 { input.mediaTimeScale = scale }
            lanes.append(MoviePump.Lane(output: output, input: input))
        }
        switch plan.sound {
        case .none:
            break
        case .copy(let id):
            guard let track = audioTracks.first(where: { $0.trackID == id }) else { throw MovieRewriteError.unreadable }
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            let formats = try await track.load(.formatDescriptions)
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: formats.first)
            lanes.append(MoviePump.Lane(output: output, input: input))
        case .mix(let ids):
            let tracks = audioTracks.filter { ids.contains($0.trackID) }
            guard !tracks.isEmpty else { throw MovieRewriteError.unreadable }
            let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: SoundSettings.pcm)
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: SoundSettings.aac(bitRate: 160_000))
            lanes.append(MoviePump.Lane(output: output, input: input))
        }
        for lane in lanes { lane.output.alwaysCopiesSampleData = false }
        try await MoviePump.run(reader: reader, writer: writer, lanes: lanes, duration: plan.duration, control: control)
    }
}

/// Sound settings shared by the mix and the smaller copy.
enum SoundSettings {
    static let pcm: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 44_100,
        AVNumberOfChannelsKey: 2,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ]

    static func aac(bitRate: Int) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: bitRate,
        ]
    }
}

/// Moves samples from a reader to a writer until both are done. A few samples at a time, so memory
/// stays flat whatever the movie's length.
enum MoviePump {
    struct Lane {
        let output: AVAssetReaderOutput
        let input: AVAssetWriterInput
    }

    /// Handed once to the loop, which is the only code that touches them afterwards.
    private struct Job: @unchecked Sendable {
        let reader: AVAssetReader
        let writer: AVAssetWriter
        let lanes: [Lane]
        let duration: Double
        let control: MovieRewriteControl
    }

    static func run(reader: AVAssetReader, writer: AVAssetWriter, lanes: [Lane], duration: Double,
                    control: MovieRewriteControl) async throws {
        guard !lanes.isEmpty else { throw MovieRewriteError.unreadable }
        for lane in lanes {
            lane.input.expectsMediaDataInRealTime = false
            guard reader.canAdd(lane.output), writer.canAdd(lane.input) else { throw MovieRewriteError.failed }
            reader.add(lane.output)
            writer.add(lane.input)
        }
        guard reader.startReading() else { throw reader.error ?? MovieRewriteError.unreadable }
        guard writer.startWriting() else {
            reader.cancelReading()
            throw writer.error ?? MovieRewriteError.failed
        }
        writer.startSession(atSourceTime: .zero)
        let job = Job(reader: reader, writer: writer, lanes: lanes, duration: max(duration, 0.1), control: control)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try loop(job)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func loop(_ job: Job) throws {
        var open = Array(job.lanes.indices)
        var idle = 0
        do {
            while !open.isEmpty {
                if let stop = job.control.stopped { throw stop }
                guard job.writer.status == .writing else { throw job.writer.error ?? MovieRewriteError.failed }
                var moved = false
                for index in open {
                    if try feed(job, index, moved: &moved) == false { open.removeAll { $0 == index } }
                }
                if moved {
                    idle = 0
                } else {
                    idle += 1
                    // Nothing has moved for about 20 seconds of running time.
                    if idle > 10_000 { throw MovieRewriteError.failed }
                    usleep(2_000)
                }
            }
            guard job.reader.status == .completed else { throw job.reader.error ?? MovieRewriteError.failed }
        } catch {
            job.reader.cancelReading()
            job.writer.cancelWriting()
            throw error
        }
        let finished = DispatchSemaphore(value: 0)
        job.writer.finishWriting { finished.signal() }
        finished.wait()
        guard job.writer.status == .completed else { throw job.writer.error ?? MovieRewriteError.failed }
        if let stop = job.control.stopped { throw stop }
        job.control.progress(1)
    }

    /// Moves up to 16 samples of one track, which keeps the tracks next to each other in the file.
    /// False when the track is done.
    private static func feed(_ job: Job, _ index: Int, moved: inout Bool) throws -> Bool {
        let lane = job.lanes[index]
        for _ in 0..<16 {
            guard lane.input.isReadyForMoreMediaData else { return true }
            moved = true
            let more = try autoreleasepool { () throws -> Bool in
                guard let sample = lane.output.copyNextSampleBuffer() else { return false }
                guard lane.input.append(sample) else { throw job.writer.error ?? MovieRewriteError.failed }
                if index == 0 {
                    let seconds = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                    if seconds.isFinite { job.control.progress(0.96 * seconds / job.duration) }
                }
                return true
            }
            if !more {
                lane.input.markAsFinished()
                return false
            }
        }
        return true
    }

    /// AVFoundation's error as one the app acts on.
    static func explain(_ error: Error, control: MovieRewriteControl) -> MovieRewriteError {
        if let stop = control.stopped { return stop }
        if let known = error as? MovieRewriteError { return known }
        if DiskSpace.isOutOfSpace(error) { return .noSpace }
        let ns = error as NSError
        if ns.domain == AVFoundationErrorDomain {
            switch ns.code {
            case AVError.operationInterrupted.rawValue, AVError.sessionWasInterrupted.rawValue,
                 AVError.mediaServicesWereReset.rawValue:
                return .interrupted
            case AVError.fileFormatNotRecognized.rawValue, AVError.invalidSourceMedia.rawValue:
                return .unreadable
            default:
                break
            }
        }
        return .failed
    }
}
