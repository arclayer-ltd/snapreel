import AVFoundation
import Foundation

// MARK: - Voice-over

/// Records narration into the draft's folder while the video plays muted.
@MainActor
final class VoiceOverRecorder {
    private var recorder: AVAudioRecorder?
    private var fileName: String?

    func start(url: URL) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.prepareToRecord(), recorder.record() else {
            throw CocoaError(.fileWriteUnknown)
        }
        self.recorder = recorder
        self.fileName = url.lastPathComponent
    }

    /// Input level, 0...1.
    var level: Float {
        guard let recorder, recorder.isRecording else { return 0 }
        recorder.updateMeters()
        let decibels = recorder.averagePower(forChannel: 0)
        return max(0, min(1, (decibels + 50) / 50))
    }

    /// Stops and returns the take's file and length.
    func stop() -> (fileName: String, duration: Double)? {
        guard let recorder, let fileName else { return nil }
        let length = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        self.fileName = nil
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        return (fileName, length)
    }

    /// Stops and throws the take away (the editor closed mid-take).
    func cancel() {
        guard let recorder else { return }
        recorder.stop()
        _ = recorder.deleteRecording()
        self.recorder = nil
        fileName = nil
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }
}

// MARK: - Noise reduction

/// Cleans up a recording's sound on the device: a high-pass filter takes out rumble and hum, a
/// low-pass takes out hiss, and a gentle gate lowers the background between words. Writes a
/// mono AAC file on the recording's own clock, which the editor plays and saves instead of the
/// original sound. The original file is never touched.
enum NoiseReducer {
    enum Failure: Error { case noSound, unreadable }

    static let sampleRate = 44_100.0
    private static let window = 882 // 20 ms

    static func clean(source: URL, to destination: URL, progress: @escaping @MainActor (Double) -> Void) async throws {
        let asset = AVURLAsset(url: source)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { throw Failure.noSound }
        let duration = try await asset.load(.duration).seconds
        let job = NoiseJob(asset: asset, tracks: tracks, duration: duration, destination: destination)
        try await Task.detached(priority: .userInitiated) {
            try job.run { fraction in
                Task { @MainActor in progress(fraction) }
            }
        }.value
    }

    /// The asset and its tracks, handed to one background task that alone uses them.
    private struct NoiseJob: @unchecked Sendable {
        let asset: AVAsset
        let tracks: [AVAssetTrack]
        let duration: Double
        let destination: URL

        func run(report: (Double) -> Void) throws {
            let totalSamples = max(1, duration * NoiseReducer.sampleRate)

            // Pass 1: loudness of every 20 ms.
            var levels: [Float] = []
            var sum: Float = 0
            var count = 0
            try read { samples in
                for sample in samples {
                    sum += sample * sample
                    count += 1
                    if count == NoiseReducer.window {
                        levels.append((sum / Float(count)).squareRoot())
                        sum = 0
                        count = 0
                    }
                }
            }
            if count > 0 { levels.append((sum / Float(count)).squareRoot()) }
            guard !levels.isEmpty else { throw Failure.noSound }
            let sorted = levels.sorted()
            let floor = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.1))]
            let median = sorted[sorted.count / 2]
            let threshold = min(max(floor * 3, 0.0015), max(median * 0.6, 0.0015))
            report(0.3)

            // Pass 2: filter, gate and write.
            let partial = destination.deletingLastPathComponent().appendingPathComponent("partial-" + destination.lastPathComponent)
            try? FileManager.default.removeItem(at: partial)
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: NoiseReducer.sampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 96_000,
            ]
            let file = try AVAudioFile(forWriting: partial, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: NoiseReducer.sampleRate,
                                             channels: 1, interleaved: false) else { throw Failure.unreadable }
            var highPass = Biquad.highPass(frequency: 90, sampleRate: NoiseReducer.sampleRate)
            var lowPass = Biquad.lowPass(frequency: 9_000, sampleRate: NoiseReducer.sampleRate)
            let attack = Float(1 - exp(-1 / (0.005 * NoiseReducer.sampleRate)))
            let release = Float(1 - exp(-1 / (0.12 * NoiseReducer.sampleRate)))
            let quiet: Float = 0.22
            var gain: Float = 1
            var index = 0
            var written = 0.0
            var lastReport = 0.0
            try read { samples in
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
                      let channel = buffer.floatChannelData?[0] else { return }
                for (offset, sample) in samples.enumerated() {
                    let level = levels[min(levels.count - 1, index / NoiseReducer.window)]
                    // Below the threshold: quiet; up to twice it: eased in; above: untouched.
                    let target: Float
                    if level <= threshold {
                        target = quiet
                    } else if level >= threshold * 2 {
                        target = 1
                    } else {
                        target = quiet + (1 - quiet) * (level - threshold) / threshold
                    }
                    gain += (target - gain) * (target > gain ? attack : release)
                    channel[offset] = lowPass.process(highPass.process(sample)) * gain
                    index += 1
                }
                buffer.frameLength = AVAudioFrameCount(samples.count)
                try file.write(from: buffer)
                written += Double(samples.count)
                if written - lastReport > NoiseReducer.sampleRate * 5 {
                    lastReport = written
                    report(0.3 + 0.7 * min(1, written / totalSamples))
                }
            }
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: partial, to: destination)
            report(1)
        }

        /// Mono float samples of all the sound tracks mixed, in order.
        private func read(_ body: ([Float]) throws -> Void) throws {
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: NoiseReducer.sampleRate,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ])
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else { throw Failure.unreadable }
            reader.add(output)
            guard reader.startReading() else { throw reader.error ?? Failure.unreadable }
            while let buffer = output.copyNextSampleBuffer() {
                guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
                let length = CMBlockBufferGetDataLength(block)
                guard length >= 4 else { continue }
                var samples = [Float](repeating: 0, count: length / 4)
                let status = samples.withUnsafeMutableBytes { raw -> OSStatus in
                    guard let base = raw.baseAddress else { return -1 }
                    return CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: base)
                }
                guard status == noErr else { continue }
                try body(samples)
            }
            if reader.status == .failed { throw reader.error ?? Failure.unreadable }
        }
    }
}

/// A second-order filter (RBJ cookbook).
struct Biquad {
    private var b0: Float, b1: Float, b2: Float, a1: Float, a2: Float
    private var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0

    private init(b0: Double, b1: Double, b2: Double, a0: Double, a1: Double, a2: Double) {
        self.b0 = Float(b0 / a0)
        self.b1 = Float(b1 / a0)
        self.b2 = Float(b2 / a0)
        self.a1 = Float(a1 / a0)
        self.a2 = Float(a2 / a0)
    }

    static func highPass(frequency: Double, sampleRate: Double, q: Double = 0.707) -> Biquad {
        let w0 = 2 * Double.pi * frequency / sampleRate
        let alpha = sin(w0) / (2 * q)
        let c = cos(w0)
        return Biquad(b0: (1 + c) / 2, b1: -(1 + c), b2: (1 + c) / 2, a0: 1 + alpha, a1: -2 * c, a2: 1 - alpha)
    }

    static func lowPass(frequency: Double, sampleRate: Double, q: Double = 0.707) -> Biquad {
        let w0 = 2 * Double.pi * frequency / sampleRate
        let alpha = sin(w0) / (2 * q)
        let c = cos(w0)
        return Biquad(b0: (1 - c) / 2, b1: 1 - c, b2: (1 - c) / 2, a0: 1 + alpha, a1: -2 * c, a2: 1 - alpha)
    }

    mutating func process(_ x: Float) -> Float {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1
        x1 = x
        y2 = y1
        y1 = y
        return y
    }
}
