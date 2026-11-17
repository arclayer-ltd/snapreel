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
        guard isActive else { return Color.white.opacity(0.18) }
        // Older bars fade a little so the newest sound stands out.
        let age = Double(count - index) / Double(count)
        return Color.srRed.opacity(1 - age * 0.45)
    }
}
