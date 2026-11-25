import AVFoundation
import Combine
import SwiftUI
import UIKit

/// The playhead, on its own so that only what really follows it is redrawn while it moves (it
/// used to be part of the model, which redrew the whole editor thirty times a second).
@MainActor
final class EditorClock: ObservableObject {
    /// Output seconds.
    @Published var time: Double = 0 {
        didSet {
            let second = Int(max(0, time))
            if seconds.whole != second { seconds.whole = second }
        }
    }

    /// Whole seconds, for labels that only change once a second.
    let seconds = EditorSeconds()
}

@MainActor
final class EditorSeconds: ObservableObject {
    @Published fileprivate(set) var whole = 0
}

/// What is on the picture at the playhead; changes only when something appears or goes.
struct EditorMoment: Equatable {
    var overlays: Set<UUID> = []
    var caption: String?
}

@MainActor
final class EditorMomentStore: ObservableObject {
    @Published var value = EditorMoment()
}

/// Plays the edit. Two players take turns: a changed edit is made ready in the one behind, and
/// comes forward only when its picture is there, so the picture never goes black or jumps while
/// editing. Seeks run one at a time and always end on the latest place asked for.
@MainActor
final class EditorPlayback {
    private let players: [AVPlayer]
    private(set) var front = 0
    private var generation = 0
    private var seekGeneration = 0
    private var goal: (time: Double, tolerance: Double)?
    private(set) var isSeeking = false
    /// True while a changed edit is being made ready.
    private(set) var isShowing = false
    private var observers: [AnyCancellable] = []

    weak var stage: EditorStageView? {
        didSet { stage?.attach(players, front: front) }
    }

    /// The player in front stopped or started by itself (a call, headphones unplugged, the end).
    var onPlayingChanged: ((Bool) -> Void)?

    init() {
        players = [AVPlayer(), AVPlayer()]
        for (index, player) in players.enumerated() {
            player.actionAtItemEnd = .pause
            // Local files never need to buffer.
            player.automaticallyWaitsToMinimizeStalling = false
            player.publisher(for: \.timeControlStatus)
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, index == self.front else { return }
                        // What it does now, not what it did when this was sent: a pause and a play right
                        // after it arrive here late, and must not stop the video again.
                        // (The rate changes at once with play and pause; the status a moment later.)
                        self.onPlayingChanged?(self.players[index].rate != 0)
                    }
                }
                .store(in: &observers)
        }
    }

    var player: AVPlayer { players[front] }

    var isMuted = false {
        didSet { for player in players { player.isMuted = isMuted } }
    }

    /// Makes `item` ready behind and brings it forward at the time `place` gives. False when a
    /// newer change took its place or it can't play.
    @discardableResult
    func show(_ item: AVPlayerItem, hasPicture: Bool, place: @MainActor () -> Double) async -> Bool {
        generation += 1
        let mine = generation
        isShowing = true
        defer { if mine == generation { isShowing = false } }
        let back = 1 - front
        let next = players[back]
        next.pause()
        next.isMuted = isMuted
        next.replaceCurrentItem(with: item)
        await wait(4) { item.status != .unknown || mine != self.generation }
        guard mine == generation, item.status == .readyToPlay else { return false }
        var at = place()
        await seekExactly(next, to: at)
        guard mine == generation else { return false }
        if hasPicture, let stage, stage.window != nil {
            await wait(1) { stage.layers[back].isReadyForDisplay || mine != self.generation }
            guard mine == generation else { return false }
        }
        // The playhead may have moved on meanwhile.
        if abs(place() - at) > 0.02 {
            at = place()
            await seekExactly(next, to: at)
            guard mine == generation else { return false }
        }
        seekGeneration += 1
        isSeeking = false
        let last = player
        front = back
        stage?.bringForward(back)
        last.pause()
        // After the new picture is on screen, so the old one never shows as a gap.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.players[self.front] !== last, !self.isShowing else { return }
                last.replaceCurrentItem(with: nil)
            }
        }
        if goal != nil { performSeek() }
        return true
    }

    /// Moves to `time`. `tolerance` 0 is the exact frame; a wider one shows a near frame sooner,
    /// for fast scrubbing.
    func seek(to time: Double, tolerance: Double) {
        goal = (time, tolerance)
        guard !isSeeking else { return }
        performSeek()
    }

    private func performSeek() {
        guard let goal, player.currentItem != nil else { return }
        self.goal = nil
        isSeeking = true
        let mine = seekGeneration
        let tolerance = CMTime(seconds: max(0, goal.tolerance), preferredTimescale: 600)
        player.seek(to: CMTime(seconds: goal.time, preferredTimescale: 90_000), toleranceBefore: tolerance,
                    toleranceAfter: tolerance) { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, mine == self.seekGeneration else { return }
                    self.isSeeking = false
                    if self.goal != nil { self.performSeek() }
                }
            }
        }
    }

    /// Never waits for ever: a seek whose item is replaced meanwhile may not report back.
    private func seekExactly(_ player: AVPlayer, to time: Double) async {
        final class Flag { var isDone = false }
        let flag = Flag()
        player.seek(to: CMTime(seconds: time, preferredTimescale: 90_000), toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            DispatchQueue.main.async { flag.isDone = true }
        }
        let mine = generation
        await wait(3) { flag.isDone || mine != self.generation }
    }

    private func wait(_ timeout: Double, until done: () -> Bool) async {
        let started = CACurrentMediaTime()
        while !done(), CACurrentMediaTime() - started < timeout {
            try? await Task.sleep(nanoseconds: 5_000_000)
            if Task.isCancelled { return }
        }
    }

    func play() { player.play() }
    func pause() { players.forEach { $0.pause() } }

    func stop() {
        generation += 1
        seekGeneration += 1
        goal = nil
        isSeeking = false
        for player in players {
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
    }
}

/// The two players' pictures, one over the other.
final class EditorStageView: UIView {
    let layers = [AVPlayerLayer(), AVPlayerLayer()]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        clipsToBounds = true
        for layer in layers {
            layer.videoGravity = .resizeAspect
            self.layer.addSublayer(layer)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func attach(_ players: [AVPlayer], front: Int) {
        for (layer, player) in zip(layers, players) where layer.player !== player { layer.player = player }
        bringForward(front)
    }

    func bringForward(_ index: Int) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layers[index].zPosition = 1
        layers[1 - index].zPosition = 0
        CATransaction.commit()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in layers { layer.frame = bounds }
        CATransaction.commit()
    }
}

struct EditorStageRepresentable: UIViewRepresentable {
    let playback: EditorPlayback

    func makeUIView(context: Context) -> EditorStageView {
        let view = EditorStageView()
        playback.stage = view
        return view
    }

    func updateUIView(_ view: EditorStageView, context: Context) {
        if playback.stage !== view { playback.stage = view }
    }
}

// MARK: - Filmstrip

/// Pictures for the timeline: a few across the whole recording at once, then exact ones for the
/// part on screen at the zoom it is at. Small pictures, at most a couple of hundred, whatever the
/// recording's length.
@MainActor
final class EditorFilmstrip {
    private struct Key: Hashable {
        let level: Int
        let index: Int
    }

    private var frames: [Key: CGImage] = [:]
    private var used: [Key: Int] = [:]
    private var counter = 0
    private var overview: [(time: Double, image: CGImage)] = []
    private var pending: [Key] = []
    private var worker: Task<Void, Never>?
    private var generator: AVAssetImageGenerator?
    private var duration = 0.0
    private var notifyTask: Task<Void, Never>?
    private let limit = 200
    /// While the video plays its decoder has the phone to itself.
    var isPaused = false {
        didSet { if !isPaused { work() } }
    }

    /// Something new to draw.
    var onUpdate: (() -> Void)?
    private(set) var hasOverview = false
    /// The same picture everywhere (debug screenshots).
    var still: CGImage? {
        didSet { onUpdate?() }
    }

    func start(_ source: EditSource) {
        duration = source.duration
        let generator = AVAssetImageGenerator(asset: source.asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 160)
        self.generator = generator
        let count = Int(min(32, max(6, duration / 2)))
        let step = duration / Double(max(1, count))
        worker = Task { [weak self] in
            for index in 0..<count {
                guard let self, !Task.isCancelled else { return }
                let time = (Double(index) + 0.5) * step
                if let image = await self.make(time, tolerance: step / 2) {
                    self.overview.append((time, image))
                    if index % 4 == 3 { self.notify() }
                }
            }
            guard let self, !Task.isCancelled else { return }
            self.hasOverview = true
            self.notify()
            self.worker = nil
            self.work()
        }
    }

    func stop() {
        worker?.cancel()
        worker = nil
        notifyTask?.cancel()
        pending = []
        generator?.cancelAllCGImageGeneration()
    }

    /// Memory warning: keep the overview only.
    func trim() {
        frames = [:]
        used = [:]
    }

    /// The time step of the pictures for cells `seconds` of the recording wide.
    private static func level(for seconds: Double) -> Int {
        min(6, max(-2, Int(floor(log2(max(0.01, seconds))))))
    }

    private static func key(_ time: Double, level: Int) -> Key {
        Key(level: level, index: Int((time / pow(2, Double(level))).rounded()))
    }

    /// The best picture there is for source time `time` in a cell `seconds` wide.
    func image(at time: Double, cell seconds: Double) -> CGImage? {
        if let still { return still }
        let key = Self.key(time, level: Self.level(for: seconds))
        if let exact = frames[key] {
            counter += 1
            used[key] = counter
            return exact
        }
        guard !overview.isEmpty else { return nil }
        var low = 0, high = overview.count
        while low < high {
            let middle = (low + high) / 2
            if overview[middle].time < time { low = middle + 1 } else { high = middle }
        }
        if low == 0 { return overview[0].image }
        if low == overview.count { return overview[overview.count - 1].image }
        return time - overview[low - 1].time < overview[low].time - time ? overview[low - 1].image : overview[low].image
    }

    /// Asks for the exact pictures of the cells on screen (what was asked before and isn't on
    /// screen any more is dropped).
    func want(_ times: [Double], cell seconds: Double) {
        guard generator != nil, still == nil else { return }
        let level = Self.level(for: seconds)
        var seen = Set<Key>()
        var missing: [Key] = []
        for time in times {
            let key = Self.key(time, level: level)
            if frames[key] == nil, seen.insert(key).inserted { missing.append(key) }
        }
        pending = missing
        work()
    }

    private func work() {
        guard worker == nil, !isPaused, !pending.isEmpty else { return }
        worker = Task { [weak self] in
            while let self, !Task.isCancelled, !self.isPaused, !self.pending.isEmpty {
                let key = self.pending.removeFirst()
                let step = pow(2, Double(key.level))
                let time = min(max(0, Double(key.index) * step), max(0, self.duration - 0.05))
                if let image = await self.make(time, tolerance: step / 2) {
                    self.counter += 1
                    self.frames[key] = image
                    self.used[key] = self.counter
                    self.evict()
                    self.notify()
                }
            }
            self?.worker = nil
        }
    }

    private func make(_ time: Double, tolerance: Double) async -> CGImage? {
        guard let generator else { return nil }
        let slack = CMTime(seconds: tolerance, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = slack
        generator.requestedTimeToleranceAfter = slack
        return try? await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
    }

    private func evict() {
        guard frames.count > limit else { return }
        for (key, _) in used.sorted(by: { $0.value < $1.value }).prefix(frames.count - limit + 20) {
            frames[key] = nil
            used[key] = nil
        }
    }

    /// At most eight times a second.
    private func notify() {
        guard notifyTask == nil else { return }
        notifyTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard let self else { return }
            self.notifyTask = nil
            if !Task.isCancelled { self.onUpdate?() }
        }
    }
}

// MARK: - Sound levels

/// How loud a sound file is, ten times a second, for drawing it. Read away from the main thread.
enum EditorLevels {
    static let perSecond = 10.0

    static func load(_ url: URL) async -> [Float] {
        await Task.detached(priority: .utility) { () -> [Float] in
            let asset = AVURLAsset(url: url)
            guard let tracks = try? await asset.loadTracks(withMediaType: .audio), !tracks.isEmpty,
                  let reader = try? AVAssetReader(asset: asset) else { return [] }
            let rate = 8_000.0
            let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ])
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else { return [] }
            reader.add(output)
            guard reader.startReading() else { return [] }
            let window = Int(rate / perSecond)
            var levels: [Float] = []
            var sum = 0.0
            var count = 0
            while let sample = output.copyNextSampleBuffer() {
                guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
                let length = CMBlockBufferGetDataLength(block)
                var values = [Int16](repeating: 0, count: length / 2)
                values.withUnsafeMutableBytes { raw in
                    if let base = raw.baseAddress {
                        _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: base)
                    }
                }
                for value in values {
                    let level = Double(value) / 32_768
                    sum += level * level
                    count += 1
                    if count == window {
                        levels.append(scaled(sum / Double(count)))
                        sum = 0
                        count = 0
                    }
                }
            }
            if count > 0 { levels.append(scaled(sum / Double(count))) }
            return levels
        }.value
    }

    /// Loudness as a bar height, 0...1 (-50 dB to -6 dB).
    private static func scaled(_ power: Double) -> Float {
        guard power > 0 else { return 0 }
        return Float(min(1, max(0, (10 * log10(power) + 50) / 44)))
    }
}
