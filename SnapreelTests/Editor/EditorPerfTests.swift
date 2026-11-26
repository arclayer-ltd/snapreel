import AVFoundation
import SwiftUI
import UIKit
import XCTest
@testable import Snapreel

/// Opens the real editor on 1, 9 and 30 minute recordings and measures what a person waits for.
/// Nothing here fails on a slow machine; the numbers are printed ("PERF|…") and compared between
/// runs, because a CI Mac is not an iPhone X.
@MainActor
final class EditorPerfTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SNAPREEL_EDITOR_LONG"] == "1",
                          "Saves real files for minutes: run by the editor-tests job (ios.yml editor_tests)")
    }

    func testOneMinute() async throws { try await run(minutes: 1, audioShortBy: 0) }
    func testNineMinutes() async throws { try await run(minutes: 9, audioShortBy: 93) }
    func testThirtyMinutes() async throws { try await run(minutes: 30, audioShortBy: 93) }

    private var window: UIWindow?
    private static var isWarm = false

    private func show(_ model: EditorModel, library: Library) {
        let view = EditorView(model: model, onClose: {}, onOpen: { _ in })
            .environmentObject(library)
            .environmentObject(AppEnvironment.shared.settings)
            .environmentObject(AppEnvironment.shared.router)
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        self.window = window
    }

    /// The layer showing the player in front.
    private func playerLayer(_ model: EditorModel) -> AVPlayerLayer? {
        func find(_ layer: CALayer) -> AVPlayerLayer? {
            if let layer = layer as? AVPlayerLayer, layer.player === model.player { return layer }
            for child in layer.sublayers ?? [] {
                if let found = find(child) { return found }
            }
            return nil
        }
        guard let root = window?.layer else { return nil }
        return find(root)
    }

    private func wait(_ timeout: Double, until done: () -> Bool) async -> Bool {
        let started = Date()
        while Date().timeIntervalSince(started) < timeout {
            if done() { return true }
            try? await Task.sleep(nanoseconds: 4_000_000)
        }
        return done()
    }

    /// The picture on screen is the edit's, at the playhead.
    private func settled(_ model: EditorModel) -> Bool {
        guard let item = model.player.currentItem, item.status == .readyToPlay,
              playerLayer(model)?.isReadyForDisplay == true else { return false }
        return abs(model.player.currentTime().seconds - model.playhead) < 0.1
    }

    /// Seconds from a change until its result is on screen, and how long the picture was gone.
    private func latency(_ model: EditorModel, _ change: () -> Void) async -> (done: Double, black: Double) {
        let before = model.player.currentItem
        let composition = before?.videoComposition
        let mix = before?.audioMix
        let started = CACurrentMediaTime()
        change()
        let applied = CACurrentMediaTime() - started
        var black = 0.0
        var last = CACurrentMediaTime()
        _ = await wait(5) {
            let now = CACurrentMediaTime()
            if playerLayer(model)?.isReadyForDisplay != true { black += now - last }
            last = now
            let item = model.player.currentItem
            let changed = item !== before || item?.videoComposition !== composition || item?.audioMix !== mix
            return changed && settled(model)
        }
        return (max(applied, CACurrentMediaTime() - started), black)
    }

    private func run(minutes: Int, audioShortBy: Double) async throws {
        executionTimeAllowance = 5_000
        let name = "\(minutes)min"
        let url = try await TestMedia.long(minutes: minutes, audioShortBy: audioShortBy)
        let (library, id) = try await TestMedia.library(with: url)
        addTranscript(to: library, id: id, minutes: minutes)
        // The first video a freshly started simulator plays takes seconds longer: not counted.
        if !Self.isWarm {
            Self.isWarm = true
            let first = EditorModel(videoID: id, library: library)
            show(first, library: library)
            _ = await wait(30) { settled(first) }
            first.teardown()
            window?.isHidden = true
            window = nil
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        let start = memoryMB()
        let peak = MemoryPeak()

        // Open.
        let opened = CACurrentMediaTime()
        let model = EditorModel(videoID: id, library: library)
        show(model, library: library)
        _ = await wait(20) { settled(model) }
        perf(name, "open to first picture", (CACurrentMediaTime() - opened) * 1_000, "ms")
        _ = await wait(60) { filmstripDone(model) }
        perf(name, "open to full filmstrip", (CACurrentMediaTime() - opened) * 1_000, "ms")
        perf(name, "memory open", memoryMB() - start, "MB")
        perf(name, "untouched recording counts as changed", model.isDirty ? 1 : 0, "bool")

        // Scrubbing: 3 seconds at 60 a second.
        let length = model.duration
        let scrub = await busy {
            for step in 0..<180 {
                model.seek(to: length * 0.2 + Double(step) / 60 * 4)
                try? await Task.sleep(nanoseconds: 16_666_667)
            }
            model.seek(to: model.playhead, exact: true)
        }
        perf(name, "scrub main thread per tick", scrub.busy / 180 * 1_000, "ms")
        perf(name, "scrub longest stall", scrub.longest * 1_000, "ms")
        let arrived = CACurrentMediaTime()
        _ = await wait(5) { settled(model) }
        perf(name, "scrub end to exact frame", (CACurrentMediaTime() - arrived) * 1_000, "ms")

        // Changes.
        model.seek(to: 20, exact: true)
        _ = await wait(3) { settled(model) }
        let cut = await latency(model) { model.apply { $0.remove(source: 30...40) } }
        perf(name, "cut shows after", cut.done * 1_000, "ms")
        perf(name, "cut picture gone", cut.black * 1_000, "ms")
        let volume = await latency(model) { model.apply { $0.audio.volume = 0.6 } }
        perf(name, "volume applies after", volume.done * 1_000, "ms")
        perf(name, "volume picture gone", volume.black * 1_000, "ms")
        let crop = await latency(model) { model.apply { $0.crop.rect = CGRect(x: 0, y: 0.2, width: 1, height: 0.5) } }
        perf(name, "crop shows after", crop.done * 1_000, "ms")
        perf(name, "crop picture gone", crop.black * 1_000, "ms")
        model.undo()
        _ = await wait(3) { settled(model) }

        // Playback of a busy edit: captions and 60 cuts.
        model.apply { recipe in
            recipe.captions = EditCaptions()
            for index in 0..<60 {
                let at = 2 + Double(index) * (length - 10) / 60
                recipe.remove(source: at...(at + 0.25))
            }
        }
        _ = await wait(5) { settled(model) }
        let play = await busy {
            model.play()
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            model.pause()
        }
        perf(name, "busy edit playback main thread", play.busy / 4 * 100, "% of one core")
        perf(name, "busy edit playback longest stall", play.longest * 1_000, "ms")
        let busyScrub = await busy {
            for step in 0..<120 {
                model.seek(to: 10 + Double(step) / 60 * 4)
                try? await Task.sleep(nanoseconds: 16_666_667)
            }
        }
        perf(name, "busy edit scrub main thread per tick", busyScrub.busy / 120 * 1_000, "ms")

        // Memory over many changes: the first rounds fill caches, later ones must add nothing.
        var last = memoryMB()
        for part in 1...4 {
            for round in 0..<45 {
                model.apply { $0.audio.volume = round % 2 == 0 ? 0.5 : 0.9 }
                model.apply { $0.crop.rect = round % 2 == 0 ? CGRect(x: 0, y: 0, width: 1, height: 1) : CGRect(x: 0, y: 0.1, width: 1, height: 0.6) }
                let at = 5 + Double(round) * 0.7 + Double(part) * 0.15
                model.apply { $0.remove(source: at...(at + 0.12)) }
                model.seek(to: at)
                try? await Task.sleep(nanoseconds: 60_000_000)
            }
            _ = await wait(3) { settled(model) }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            let now = memoryMB()
            perf(name, "memory growth, edits \((part - 1) * 135 + 1) to \(part * 135)", now - last, "MB")
            last = now
        }
        perf(name, "memory peak in the editor", peak.stop() - start, "MB")
        model.teardown()
        window?.isHidden = true
        window = nil
        try? await Task.sleep(nanoseconds: 500_000_000)

        // Save.
        guard let source = library.video(id) else { return }
        var recipe = EditRecipe.original(sourceID: id, duration: source.duration)
        recipe.remove(source: 10...15)
        recipe.remove(source: 40...44)
        recipe.captions = EditCaptions()
        let exportPeak = MemoryPeak()
        let exportBase = memoryMB()
        let exportStart = CACurrentMediaTime()
        let (video, file) = try await TestMedia.export(recipe, library: library, timeout: 4_500)
        let seconds = CACurrentMediaTime() - exportStart
        perf(name, "export time", seconds, "s")
        perf(name, "export speed", video.duration / seconds, "x")
        perf(name, "export memory peak", exportPeak.stop() - exportBase, "MB")
        perf(name, "export file", Double(TestMedia.fileSize(file)) / 1_000_000, "MB")
        perf(name, "source file", Double(TestMedia.fileSize(url)) / 1_000_000, "MB")
        perf(name, "export bitrate", Double(TestMedia.fileSize(file)) * 8 / video.duration / 1_000_000, "Mbit/s")
        perf(name, "export length error", video.duration - recipe.outputDuration, "s")
        library.delete(video.id)
    }

    private func filmstripDone(_ model: EditorModel) -> Bool {
        model.filmstrip.hasOverview
    }

    private func addTranscript(to library: Library, id: UUID, minutes: Int) {
        let words = "This is how the checkout works now so watch the total change when the coupon goes away"
            .split(separator: " ").map(String.init)
        var segments: [TranscriptSegment] = []
        for index in 0..<(minutes * 10) {
            let start = Double(index) * 6 + 0.2
            let timed = words.enumerated().map { TranscriptWord(text: $1, start: start + Double($0) * 0.32, duration: 0.3) }
            segments.append(TranscriptSegment(start: start, duration: 5.4, text: words.joined(separator: " ") + ".", words: timed))
        }
        library.saveTranscript(Transcript(videoID: id, localeIdentifier: "en-GB", segments: segments, createdAt: Date(), summary: nil))
    }

    /// Time the main thread spent working while `body` ran, and its longest single stretch.
    private func busy(_ body: () async -> Void) async -> (busy: Double, longest: Double) {
        let meter = MainThreadMeter()
        meter.start()
        await body()
        return meter.stop()
    }
}

/// Adds up the time between the main run loop waking and going back to sleep.
final class MainThreadMeter {
    private var observer: CFRunLoopObserver?
    private var woke: Double?
    private var total = 0.0
    private var longest = 0.0

    func start() {
        let activities = CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue
        observer = CFRunLoopObserverCreateWithHandler(nil, activities, true, CFIndex.max) { [weak self] _, activity in
            guard let self else { return }
            let now = CACurrentMediaTime()
            if activity == .afterWaiting {
                self.woke = now
            } else if let woke = self.woke {
                self.total += now - woke
                self.longest = max(self.longest, now - woke)
                self.woke = nil
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    func stop() -> (busy: Double, longest: Double) {
        if let observer { CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes) }
        return (total, longest)
    }
}
