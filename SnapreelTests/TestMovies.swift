import AVFoundation
import XCTest
@testable import Snapreel

/// Movies like Snapreel's own recordings, made on the spot: H.264 at a chosen size and bit rate, frames
/// at uneven times, one AAC track per sound. Two seconds are encoded and then repeated without
/// re-encoding, so a two-gigabyte recording takes seconds to make.
enum TestMovie {
    enum Sound {
        /// A tone of this many hertz, for the whole movie or its first part.
        case tone(Double, seconds: Double? = nil)
        case silence(seconds: Double? = nil)
    }

    struct Spec {
        var seconds: Double = 6
        var width = 360
        var height = 780
        var bitRate = 800_000
        var sounds: [Sound] = [.tone(440)]
        var transform: CGAffineTransform = .identity
        var fileType: AVFileType = .mov
        /// Stops without closing the file, as when iOS ends the recorder: what is on disk is fragments.
        var isCutOff = false
        /// Frames at 1/60, 1/20 and 1/30 s, like a screen recording.
        var isUneven = true
    }

    struct Failed: Error { var reason: String }

    static func make(_ spec: Spec, at url: URL) async throws {
        try? FileManager.default.removeItem(at: url)
        let samples = try await encodedSeconds(spec)
        let writer = try AVAssetWriter(outputURL: url, fileType: spec.fileType)
        if spec.isCutOff { writer.movieFragmentInterval = CMTime(seconds: 1, preferredTimescale: 600) }
        guard let format = CMSampleBufferGetFormatDescription(samples[0]) else { throw Failed(reason: "no format") }
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: format)
        video.transform = spec.transform
        writer.add(video)
        var feeds: [Feed] = [Feed(input: video, next: pictures(samples, spec: spec))]
        for sound in spec.sounds {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: SoundSettings.aac(bitRate: 128_000))
            writer.add(input)
            feeds.append(Feed(input: input, next: pcm(sound, seconds: spec.seconds)))
        }
        guard writer.startWriting() else { throw writer.error ?? Failed(reason: "start") }
        writer.startSession(atSourceTime: .zero)
        let job = Job(writer: writer, feeds: feeds, finishes: !spec.isCutOff, url: url)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try job.run() })
            }
        }
    }

    // MARK: - Writing

    private struct Feed {
        let input: AVAssetWriterInput
        let next: () -> CMSampleBuffer?
    }

    private struct Job: @unchecked Sendable {
        let writer: AVAssetWriter
        let feeds: [Feed]
        let finishes: Bool
        let url: URL

        func run() throws {
            var open = Array(feeds.indices)
            var idle = 0
            while !open.isEmpty {
                guard writer.status == .writing else { throw writer.error ?? Failed(reason: "writer stopped") }
                var moved = false
                for index in open where feeds[index].input.isReadyForMoreMediaData {
                    moved = true
                    try autoreleasepool {
                        if let sample = feeds[index].next() {
                            guard feeds[index].input.append(sample) else { throw writer.error ?? Failed(reason: "append") }
                        } else {
                            // A cut-off recording's tracks are never closed.
                            if finishes { feeds[index].input.markAsFinished() }
                            open.removeAll { $0 == index }
                        }
                    }
                }
                if moved { idle = 0 } else {
                    idle += 1
                    if idle > 5_000 {
                        // With a track that has ended but stays open, the writer may wait for it.
                        if finishes { throw Failed(reason: "stalled") }
                        break
                    }
                    usleep(2_000)
                }
            }
            guard finishes else {
                // Let the last fragment reach the disk, take the file as it is at that moment, stop.
                Thread.sleep(forTimeInterval: 1)
                let kept = url.appendingPathExtension("kept")
                try FileManager.default.copyItem(at: url, to: kept)
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: url)
                try FileManager.default.moveItem(at: kept, to: url)
                return
            }
            let done = DispatchSemaphore(value: 0)
            writer.finishWriting { done.signal() }
            done.wait()
            guard writer.status == .completed else { throw writer.error ?? Failed(reason: "finish") }
        }
    }

    // MARK: - Pictures

    /// Two seconds of noise at 30 frames a second, encoded.
    private static func encodedSeconds(_ spec: Spec) async throws -> [CMSampleBuffer] {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gop-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let compression: [String: Any] = [
            AVVideoAverageBitRateKey: spec.bitRate,
            AVVideoMaxKeyFrameIntervalKey: 60,
            AVVideoAllowFrameReorderingKey: false,
            AVVideoExpectedSourceFrameRateKey: 30,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: spec.width, AVVideoHeightKey: spec.height,
            AVVideoCompressionPropertiesKey: compression,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey as String: spec.width, kCVPixelBufferHeightKey as String: spec.height,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? Failed(reason: "gop start") }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<60 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
            // Noise costs about 3 bits a pixel whatever the encoder is asked for, so only as much of the
            // picture is noise as the bit rate needs.
            let share = Double(spec.bitRate) / (Double(spec.width * spec.height) * 30 * 3.2)
            guard let buffer = noise(width: spec.width, height: spec.height, share: share, pool: adaptor.pixelBufferPool) else {
                throw Failed(reason: "no pixel buffer")
            }
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30))
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? Failed(reason: "gop") }

        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw Failed(reason: "gop track") }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        reader.startReading()
        var samples: [CMSampleBuffer] = []
        while let sample = output.copyNextSampleBuffer() {
            if CMSampleBufferGetNumSamples(sample) > 0 { samples.append(sample) }
        }
        guard !samples.isEmpty else { throw Failed(reason: "no samples") }
        return samples
    }

    /// A grey picture whose top `share` (0...1) is noise.
    static func noise(width: Int, height: Int, share: Double = 0.02, pool: CVPixelBufferPool? = nil) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        if let pool {
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        } else {
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        }
        guard let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        for plane in 0..<CVPixelBufferGetPlaneCount(buffer) {
            guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, plane) else { continue }
            let row = CVPixelBufferGetBytesPerRowOfPlane(buffer, plane)
            let rows = CVPixelBufferGetHeightOfPlane(buffer, plane)
            memset(base, 120, row * rows)
            let noisy = min(rows, max(2, Int(Double(rows) * share)))
            if plane == 0 { arc4random_buf(base, row * noisy) }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }

    private static func pictures(_ samples: [CMSampleBuffer], spec: Spec) -> () -> CMSampleBuffer? {
        var index = 0
        var time = 0.0
        // Six frames of these lengths add up to 0.2 s, the same as six at 30 a second.
        let uneven = [1.0 / 60, 1.0 / 20, 1.0 / 30, 1.0 / 60, 1.0 / 20, 1.0 / 30]
        return {
            guard time < spec.seconds - 0.001 else { return nil }
            let length = spec.isUneven ? uneven[index % uneven.count] : 1.0 / 30
            let sample = samples[index % samples.count]
            var timing = CMSampleTimingInfo(duration: CMTime(seconds: length, preferredTimescale: 600),
                                            presentationTimeStamp: CMTime(seconds: time, preferredTimescale: 600),
                                            decodeTimeStamp: .invalid)
            index += 1
            time += length
            var copy: CMSampleBuffer?
            CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: sample, sampleTimingEntryCount: 1,
                                                  sampleTimingArray: &timing, sampleBufferOut: &copy)
            return copy
        }
    }

    // MARK: - Sound

    private static func pcm(_ sound: Sound, seconds: Double) -> () -> CMSampleBuffer? {
        let pitch: Double, limit: Double
        switch sound {
        case .tone(let hertz, let length): pitch = hertz; limit = min(seconds, length ?? seconds)
        case .silence(let length): pitch = 0; limit = min(seconds, length ?? seconds)
        }
        // A tenth of a second holds a whole number of waves of any tone that is a multiple of 10 Hz,
        // so the same data is used for all of them.
        var frame = 0
        let count = 4_410
        let data = pcmBlock(frames: count, startingAt: 0, pitch: pitch)
        return {
            guard Double(frame) / 44_100 < limit, let data else { return nil }
            let buffer = pcmBuffer(data, frames: count, at: CMTime(value: CMTimeValue(frame), timescale: 44_100))
            frame += count
            return buffer
        }
    }

    static let pcmFormat: CMAudioFormatDescription = {
        var basic = AudioStreamBasicDescription(mSampleRate: 44_100, mFormatID: kAudioFormatLinearPCM,
                                                mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
                                                mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
                                                mChannelsPerFrame: 2, mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &basic, layoutSize: 0, layout: nil, magicCookieSize: 0,
                                       magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        return format!
    }()

    static func pcmBuffer(frames: Int, startingAt first: Int, pitch: Double, at time: CMTime? = nil) -> CMSampleBuffer? {
        guard let block = pcmBlock(frames: frames, startingAt: first, pitch: pitch) else { return nil }
        return pcmBuffer(block, frames: frames, at: time ?? CMTime(value: CMTimeValue(first), timescale: 44_100))
    }

    private static func pcmBlock(frames: Int, startingAt first: Int, pitch: Double) -> CMBlockBuffer? {
        var data = [Int16](repeating: 0, count: frames * 2)
        if pitch > 0 {
            for index in 0..<frames {
                let value = Int16(9_000 * sin(2 * .pi * pitch * Double(first + index) / 44_100))
                data[index * 2] = value
                data[index * 2 + 1] = value
            }
        }
        let length = data.count * 2
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: length, blockAllocator: nil,
                                           customBlockSource: nil, offsetToData: 0, dataLength: length,
                                           flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
        guard let block else { return nil }
        _ = data.withUnsafeBytes { bytes in
            CMBlockBufferReplaceDataBytes(with: bytes.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: length)
        }
        return block
    }

    private static func pcmBuffer(_ block: CMBlockBuffer, frames: Int, at time: CMTime) -> CMSampleBuffer? {
        var sample: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: block, formatDescription: pcmFormat, sampleCount: frames,
            presentationTimeStamp: time, packetDescriptions: nil, sampleBufferOut: &sample)
        return sample
    }
}

/// What a finished movie holds.
struct MovieFacts {
    var seconds: Double
    var videoSeconds: Double
    var audioSeconds: [Double]
    var frames: Int
    var frameTimes: [Double]
    var transform: CGAffineTransform
    var size: CGSize
    var codec: FourCharCode?

    static func read(_ url: URL, countsFrames: Bool = true) async throws -> MovieFacts {
        let asset = AVURLAsset(url: url)
        var facts = MovieFacts(seconds: try await asset.load(.duration).seconds, videoSeconds: 0, audioSeconds: [], frames: 0,
                               frameTimes: [], transform: .identity, size: .zero, codec: nil)
        for track in try await asset.loadTracks(withMediaType: .audio) {
            facts.audioSeconds.append(try await track.load(.timeRange).duration.seconds)
        }
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { return facts }
        facts.videoSeconds = try await track.load(.timeRange).duration.seconds
        facts.transform = try await track.load(.preferredTransform)
        facts.size = try await track.load(.naturalSize)
        facts.codec = try await track.load(.formatDescriptions).first.map { CMFormatDescriptionGetMediaSubType($0) }
        guard countsFrames else { return facts }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        reader.add(output)
        reader.startReading()
        while let sample = output.copyNextSampleBuffer() {
            let count = CMSampleBufferGetNumSamples(sample)
            guard count > 0 else { continue }
            facts.frames += count
            facts.frameTimes.append(CMSampleBufferGetPresentationTimeStamp(sample).seconds)
        }
        return facts
    }

    /// The loudest sample of the mixed sound between two times, 0...1.
    static func loudness(_ url: URL, from start: Double, to end: Double) async throws -> Double {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { return 0 }
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                       end: CMTime(seconds: end, preferredTimescale: 600))
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: SoundSettings.pcm)
        reader.add(output)
        reader.startReading()
        var peak = 0
        while let sample = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(sample) {
            let length = CMBlockBufferGetDataLength(block)
            var data = [Int16](repeating: 0, count: length / 2)
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: &data)
            for value in data { peak = max(peak, abs(Int(value))) }
        }
        return Double(peak) / 32_768
    }
}

/// The most memory the process used while it ran, over what it used at the start.
final class MemoryPeak: @unchecked Sendable {
    private let lock = NSLock()
    private var most: UInt64 = 0
    private var isRunning = true
    private let start: UInt64

    init() {
        start = Self.footprint()
        most = start
        Thread.detachNewThread { [weak self] in
            while let self, self.sample() { usleep(10_000) }
        }
    }

    /// Megabytes above the start.
    func stop() -> Double {
        lock.lock()
        defer { lock.unlock() }
        isRunning = false
        return Double(most - min(most, start)) / 1_000_000
    }

    private func sample() -> Bool {
        let now = Self.footprint()
        lock.lock()
        defer { lock.unlock() }
        most = max(most, now)
        return isRunning
    }

    static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? UInt64(info.phys_footprint) : 0
    }
}

/// A folder of its own for each test, gone afterwards.
class MovieTestCase: XCTestCase {
    private(set) var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func movie(_ name: String = "movie.mov", _ spec: TestMovie.Spec = TestMovie.Spec()) async throws -> URL {
        let url = folder.appendingPathComponent(name)
        try await TestMovie.make(spec, at: url)
        return url
    }

    /// A line CI collects (`scripts/ci-tests.sh`).
    func measure(_ text: String) {
        print("MEASURE \(text)")
    }
}
