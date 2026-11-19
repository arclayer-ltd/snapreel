import AVFoundation
import SwiftUI

/// Number of bars in the live waveform.
private let waveformBarCount = 44

/// Voice-only recording with AVAudioRecorder (AAC in .m4a) and level metering for the waveform.
/// Keeps recording in the background (Snapreel has the audio background mode).
@MainActor
final class RecorderAudioEngine {
    private var recorder: AVAudioRecorder?

    var isRecording: Bool { recorder?.isRecording ?? false }

    func start(to url: URL) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        try? FileManager.default.removeItem(at: url)
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.prepareToRecord(), recorder.record() else {
            throw CocoaError(.fileWriteUnknown)
        }
        self.recorder = recorder
    }

    func pause() {
        recorder?.pause()
    }

    func resume() {
        recorder?.record()
    }

    /// Stops and closes the file; it is ready to save straight away.
    func stop() {
        recorder?.stop()
        recorder = nil
        deactivate()
    }

    /// Stops and deletes the file.
    func cancel() {
        recorder?.stop()
        recorder?.deleteRecording()
        recorder = nil
        deactivate()
    }

    /// Current loudness from 0 (silence) to 1.
    func level() -> CGFloat {
        guard let recorder, recorder.isRecording else { return 0 }
        recorder.updateMeters()
        let decibels = CGFloat(recorder.averagePower(forChannel: 0))
        let linear = max(0, min(1, (decibels + 50) / 50))
        return pow(linear, 1.4)
    }

    private func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// The waveform's recent levels. Separate from the recorder model so only the waveform
/// redraws when levels change.
@MainActor
final class RecorderAudioMeter: ObservableObject {
    @Published private(set) var levels: [CGFloat] = Array(repeating: 0, count: waveformBarCount)

    func push(_ level: CGFloat) {
        var next = levels
        next.removeFirst()
        next.append(level)
        levels = next
    }

    func reset() {
        levels = Array(repeating: 0, count: waveformBarCount)
    }

    func show(_ values: [CGFloat]) {
        let padded = Array(values.suffix(waveformBarCount))
        levels = Array(repeating: 0, count: waveformBarCount - padded.count) + padded
    }

    /// A speech-like pattern for screenshots.
    static var sampleLevels: [CGFloat] {
        (0..<waveformBarCount).map { index in
            let x = Double(index)
            let value = 0.18 + 0.42 * abs(sin(x * 0.55)) + 0.25 * abs(sin(x * 0.21 + 1.1))
            return CGFloat(min(0.95, value))
        }
    }
}

/// Bars that scroll from right to left as you speak. Newest on the right.
struct RecorderWaveformView: View {
    @ObservedObject var meter: RecorderAudioMeter
    var isActive: Bool

    var body: some View {
        GeometryReader { proxy in
            let count = meter.levels.count
            let spacing: CGFloat = 4
            let barWidth = max(2, (proxy.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<count, id: \.self) { index in
                    Capsule()
                        .fill(barColor(index: index, count: count))
                        .frame(width: barWidth,
                               height: max(barWidth, proxy.size.height * meter.levels[index]))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .animation(.linear(duration: 0.1), value: meter.levels)
        }
        .accessibilityElement()
        .accessibilityLabel(isActive ? "Sound level" : "Waiting to record")
    }

    private func barColor(index: Int, count: Int) -> Color {
        guard isActive else { return Color.srStageText.opacity(0.18) }
        // Older bars fade a little so the newest sound stands out.
        let age = Double(count - index) / Double(count)
        return Color.srRed.opacity(1 - age * 0.45)
    }
}

// MARK: - Playback

/// How loud an audio recording is over time: one value (0...1) per 0.1 s, the recorder's meter
/// rate, read from the file once and kept. Playback draws the same moving bars as recording
/// from it (build 29's bars stood still on playback).
struct AudioEnvelope {
    /// Seconds per value, the same as the recorder's meter.
    static let step: Double = 0.1
    let levels: [CGFloat]

    /// The level at `time` seconds (0 before the start and after the end).
    func level(at time: Double) -> CGFloat {
        guard time >= 0 else { return 0 }
        let index = Int(time / Self.step)
        return index < levels.count ? levels[index] : 0
    }

    @MainActor private static var cache: [URL: AudioEnvelope] = [:]

    /// Reads `url`'s first audio track off the main thread. Nil when it has no sound to read.
    @MainActor
    static func load(_ url: URL) async -> AudioEnvelope? {
        #if DEBUG
        // The fixture files have no voice in them; screenshots get a speech-like envelope.
        if AppEnvironment.shared.debugScreenID != nil { return sample }
        #endif
        if let cached = cache[url] { return cached }
        let levels = await Task.detached(priority: .utility) { await AudioEnvelope.read(url) }.value
        guard let levels, !levels.isEmpty else { return nil }
        let envelope = AudioEnvelope(levels: levels)
        cache[url] = envelope
        return envelope
    }

    /// 16-bit PCM of the first channel, averaged over 0.1 s windows, with the recorder's
    /// mapping from decibels (-50 dB is silent, 0 dB full), so playback looks like recording.
    private static func read(_ url: URL) async -> [CGFloat]? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let reader = try? AVAssetReader(asset: asset) else { return nil }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }

        var levels: [CGFloat] = []
        var channels = 1
        var windowFrames = 0
        var sum: Double = 0
        var frames = 0
        while let buffer = output.copyNextSampleBuffer() {
            if windowFrames == 0,
               let format = CMSampleBufferGetFormatDescription(buffer),
               let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee {
                channels = max(1, Int(description.mChannelsPerFrame))
                windowFrames = max(1, Int(description.mSampleRate * step))
            }
            guard windowFrames > 0, let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            guard length >= 2 else { continue }
            var samples = [Int16](repeating: 0, count: length / 2)
            let status = samples.withUnsafeMutableBytes { raw -> OSStatus in
                guard let base = raw.baseAddress else { return -1 }
                return CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: raw.count, destination: base)
            }
            guard status == kCMBlockBufferNoErr else { continue }
            var index = 0
            while index < samples.count {
                let value = Double(samples[index]) / 32_768
                sum += value * value
                frames += 1
                if frames == windowFrames {
                    levels.append(meterLevel(meanSquare: sum / Double(frames)))
                    sum = 0
                    frames = 0
                }
                index += channels
            }
        }
        if frames > 0 { levels.append(meterLevel(meanSquare: sum / Double(frames))) }
        return levels.isEmpty ? nil : levels
    }

    /// The same curve as `RecorderAudio.level()`.
    private static func meterLevel(meanSquare: Double) -> CGFloat {
        let decibels = 10 * log10(max(meanSquare, 1e-10))
        let linear = max(0, min(1, (decibels + 50) / 50))
        return CGFloat(pow(linear, 1.4))
    }

    #if DEBUG
    /// Two minutes of speech-like loudness with short pauses, for screenshots.
    static let sample = AudioEnvelope(levels: (0..<1_200).map { index -> CGFloat in
        let x = Double(index)
        let phrase = abs(sin(x * 0.045))
        guard phrase > 0.18 else { return 0.04 }
        let syllables = 0.35 + 0.4 * abs(sin(x * 0.9)) + 0.2 * abs(sin(x * 0.37 + 1.3))
        return CGFloat(min(0.92, syllables * (0.55 + 0.45 * phrase)))
    })
    #endif
}

/// An audio recording playing back: the recorder's scrolling bars, drawn from the file's
/// loudness up to the playhead (newest on the right), so they move with the recorded voice and
/// hold still when it pauses. The panel follows Light and Dark like the rest of the stage.
struct AudioPlaybackBars: View {
    let url: URL
    /// Read for the exact time while playing, many times a second.
    let player: AVPlayer
    let isPlaying: Bool
    /// The playhead when not playing (after a seek, or in a screenshot).
    let time: Double

    @State private var envelope: AudioEnvelope?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.srStageRaised, Color.srStage], startPoint: .top, endPoint: .bottom)
            TimelineView(.animation(minimumInterval: AudioEnvelope.step / 2, paused: !isPlaying)) { _ in
                bars(at: isPlaying ? player.currentTime().seconds : time)
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.xl)
        }
        .task(id: url) { envelope = await AudioEnvelope.load(url) }
        .accessibilityHidden(true)
    }

    private func bars(at seconds: Double) -> some View {
        let now = seconds.isFinite ? max(0, seconds) : 0
        // Whole steps, like the recorder's meter: the bars move one place every 0.1 s.
        let newest = (now / AudioEnvelope.step).rounded(.down)
        let count = waveformBarCount
        return GeometryReader { proxy in
            let spacing: CGFloat = 4
            let barWidth = max(2, (proxy.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<count, id: \.self) { index in
                    let at = (newest - Double(count - 1 - index)) * AudioEnvelope.step
                    let level = envelope?.level(at: at) ?? 0
                    Capsule()
                        .fill(color(index: index, count: count))
                        .frame(width: barWidth, height: max(barWidth, proxy.size.height * level))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func color(index: Int, count: Int) -> Color {
        guard envelope != nil else { return Color.srStageText.opacity(0.18) }
        // As while recording: older bars fade a little so the sound at the playhead stands out.
        let age = Double(count - index) / Double(count)
        return Color.srRed.opacity(1 - age * 0.45)
    }
}
