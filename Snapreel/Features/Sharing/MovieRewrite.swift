import AVFoundation
import Foundation
import OSLog

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
struct MoviePlan: Equatable, Sendable {
    enum Sound: Equatable, Sendable {
        case none
        /// One track, copied as it is.
        case copy(CMPersistentTrackID)
        /// Several tracks with sound, mixed into one (the only step that decodes anything).
        case mix([CMPersistentTrackID])
    }

    enum Reason: String, Sendable {
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
    ///
    /// Takes a moment whatever the length; given up on after 30 seconds, so nothing ever waits on a file
    /// AVFoundation can't get through.
    static func make(for url: URL, isScreenRecording: Bool) async throws -> MoviePlan {
        try await Deadline.run(seconds: 30) { try await read(url, isScreenRecording: isScreenRecording) }
    }

    private static func read(_ url: URL, isScreenRecording: Bool) async throws -> MoviePlan {
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

/// Work that must not keep anyone waiting forever.
enum Deadline {
    private final class Once<Value: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Value, Error>?

        init(_ continuation: CheckedContinuation<Value, Error>) { self.continuation = continuation }

        func resume(_ result: Result<Value, Error>) {
            lock.lock()
            let waiting = continuation
            continuation = nil
            lock.unlock()
            waiting?.resume(with: result)
        }
    }

    /// The result of `work`, or `MovieRewriteError.failed` after `seconds` (the work may go on unseen).
    static func run<Value: Sendable>(seconds: Double, _ work: @escaping @Sendable () async throws -> Value) async throws -> Value {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Value, Error>) in
            let once = Once(continuation)
            Task.detached(priority: .userInitiated) {
                do {
                    once.resume(.success(try await work()))
                } catch {
                    once.resume(.failure(error))
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
                once.resume(.failure(MovieRewriteError.failed))
            }
        }
    }
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

/// Moves samples from a reader to a writer until both are done: each track on a thread of its own, one
/// sample at a time, so memory stays flat whatever the movie's length and no track can block another.
enum MoviePump {
    struct Lane {
        let output: AVAssetReaderOutput
        let input: AVAssetWriterInput
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
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            MoviePumpJob(reader: reader, writer: writer, lanes: lanes, duration: max(duration, 0.1), control: control) {
                continuation.resume(with: $0)
            }.start()
        }
    }

    /// What went wrong in AVFoundation's own words, for a phone's console and the tests' log.
    static func log(_ line: String) {
        logger.error("movie: \(line, privacy: .public)")
        #if DEBUG
        print("NOTE|movie|\(line)")
        #endif
    }

    private static let logger = Logger(subsystem: "co.arclayer.snapreel", category: "sharing")

    /// AVFoundation's error as one the app acts on.
    static func explain(_ error: Error, control: MovieRewriteControl) -> MovieRewriteError {
        if let stop = control.stopped { return stop }
        if let known = error as? MovieRewriteError { return known }
        log("\(error)")
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

/// One run of `MoviePump`. Ends exactly once: done, failed, stopped, or given up on because nothing has
/// moved for too long.
private final class MoviePumpJob: @unchecked Sendable {
    private let reader: AVAssetReader
    private let writer: AVAssetWriter
    private let lanes: [MoviePump.Lane]
    private let duration: Double
    private let control: MovieRewriteControl
    private let lock = NSLock()
    private var ending: ((Result<Void, Error>) -> Void)?
    private var problem: Error?
    private var openLanes: Int
    private var idleTicks = 0
    private var isFinishing = false
    private var watchdog: DispatchSourceTimer?

    /// Seconds of running time (time asleep in the background doesn't count) without a single sample.
    /// Generous: a cut-off recording's hundreds of small indexes are read before its first sample.
    private static let mostIdle = 120
    /// Closing the file can mean writing all of it once more.
    private static let mostIdleFinishing = 600

    init(reader: AVAssetReader, writer: AVAssetWriter, lanes: [MoviePump.Lane], duration: Double,
         control: MovieRewriteControl, ending: @escaping (Result<Void, Error>) -> Void) {
        self.reader = reader
        self.writer = writer
        self.lanes = lanes
        self.duration = duration
        self.control = control
        self.ending = ending
        openLanes = lanes.count
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        timer.schedule(deadline: .now() + 1, repeating: 1)
        // Keeps the job alive until it ends.
        timer.setEventHandler { self.tick() }
        watchdog = timer
        timer.resume()
        for index in lanes.indices {
            Thread.detachNewThread { [self] in
                Thread.current.qualityOfService = .userInitiated
                pump(index)
            }
        }
    }

    // MARK: - One track

    private func pump(_ index: Int) {
        let lane = lanes[index]
        do {
            while true {
                if let stop = control.stopped { throw stop }
                if let problem = currentProblem { throw problem }
                guard writer.status == .writing else { throw writer.error ?? MovieRewriteError.failed }
                guard lane.input.isReadyForMoreMediaData else {
                    usleep(1_000)
                    continue
                }
                let more = try autoreleasepool { () throws -> Bool in
                    guard let sample = lane.output.copyNextSampleBuffer() else { return false }
                    guard lane.input.append(sample) else { throw writer.error ?? MovieRewriteError.failed }
                    moved()
                    if index == 0 {
                        let seconds = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                        if seconds.isFinite { control.progress(0.96 * seconds / duration) }
                    }
                    return true
                }
                guard more else { break }
            }
            // Calling this, or finishing, on a writer that has just failed (a full disk) is a crash.
            guard writer.status == .writing else { throw writer.error ?? MovieRewriteError.failed }
            lane.input.markAsFinished()
        } catch {
            note(error)
        }
        laneEnded()
    }

    private func laneEnded() {
        lock.lock()
        openLanes -= 1
        let isLast = openLanes == 0
        let failure = problem
        if isLast { isFinishing = true }
        idleTicks = 0
        lock.unlock()
        guard isLast else { return }
        if let failure { return abort(failure) }
        guard reader.status == .completed else { return abort(reader.error ?? MovieRewriteError.failed) }
        guard writer.status == .writing else { return abort(writer.error ?? MovieRewriteError.failed) }
        writer.finishWriting { [self] in
            if writer.status != .completed {
                end(.failure(writer.error ?? MovieRewriteError.failed))
            } else if let stop = control.stopped {
                end(.failure(stop))
            } else {
                control.progress(1)
                end(.success(()))
            }
        }
    }

    private func abort(_ error: Error) {
        reader.cancelReading()
        if writer.status == .writing { writer.cancelWriting() }
        end(.failure(error))
    }

    // MARK: - State

    private var currentProblem: Error? {
        lock.lock()
        defer { lock.unlock() }
        return problem
    }

    private func note(_ error: Error) {
        lock.lock()
        if problem == nil { problem = error }
        lock.unlock()
    }

    private func moved() {
        lock.lock()
        idleTicks = 0
        lock.unlock()
    }

    private func tick() {
        lock.lock()
        idleTicks += 1
        let limit = isFinishing ? Self.mostIdleFinishing : Self.mostIdle
        let isStuck = idleTicks > limit
        lock.unlock()
        guard isStuck else { return }
        // A track's thread can be stuck inside AVFoundation; the work ends for everyone else anyway.
        note(MovieRewriteError.failed)
        MoviePump.log("nothing moved for \(limit) s, reader \(reader.status.rawValue), writer \(writer.status.rawValue)")
        reader.cancelReading()
        end(.failure(MovieRewriteError.failed))
    }

    private func end(_ result: Result<Void, Error>) {
        lock.lock()
        let ending = self.ending
        self.ending = nil
        let timer = watchdog
        watchdog = nil
        lock.unlock()
        timer?.cancel()
        ending?(result)
    }
}
