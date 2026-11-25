import AVFoundation
import UIKit
import XCTest
@testable import Snapreel

/// Long and large recordings: how long Share takes to open, how long the file work takes next to build
/// 47's, and how much memory it uses. The numbers are the runner's, not a phone's; the ratios carry over.
final class LargeRecordingTests: MovieTestCase {
    /// Nine minutes at the owner's size and bit rate (their failing file is 8:50, 165.8 MB).
    private func nineMinutes(_ sounds: [TestMovie.Sound], cutOff: Bool = false) async throws -> URL {
        var spec = TestMovie.Spec()
        spec.seconds = 540
        spec.width = 886
        spec.height = 1918
        spec.bitRate = 2_400_000
        spec.sounds = sounds
        spec.isCutOff = cutOff
        return try await movie("nine-\(UUID().uuidString).mov", spec)
    }

    private func timed<T>(_ work: () async throws -> T) async throws -> (T, seconds: Double, peak: Double) {
        let peak = MemoryPeak()
        let started = Date()
        let value = try await work()
        return (value, Date().timeIntervalSince(started), peak.stop())
    }

    private func megabytes(_ url: URL) -> Double { Double(MediaInspector.fileSize(url)) / 1_000_000 }

    func testNineMinutesWithTwoSounds() async throws {
        let url = try await nineMinutes([.tone(440), .tone(880)])
        let old = folder.appendingPathComponent("old.mov")
        let (worked, oldSeconds, oldPeak) = try await timed { await LegacyAudioMixer.mix(url, into: old) }
        XCTAssertTrue(worked)
        try? FileManager.default.removeItem(at: old)

        let (plan, planSeconds, _) = try await timed { try await MoviePlan.make(for: url, isScreenRecording: true) }
        let new = folder.appendingPathComponent("new.mov")
        let (_, newSeconds, newPeak) = try await timed {
            try await MovieRewrite.run(url, to: new, plan: plan, fileType: .mov, indexFirst: false, control: MovieRewriteControl())
        }
        measure(String(format: "9 min, %.0f MB, both sounds heard: mix before %.1f s (+%.0f MB), now %.1f s (+%.0f MB), look %.2f s",
                       megabytes(url), oldSeconds, oldPeak, newSeconds, newPeak, planSeconds))
        XCTAssertLessThan(newPeak, 150)
        let facts = try await MovieFacts.read(new, countsFrames: false)
        XCTAssertEqual(facts.videoSeconds, 540, accuracy: 0.5)
        XCTAssertEqual(facts.audioSeconds[0], 540, accuracy: 0.5)
    }

    func testNineMinutesWithOneSilentSound() async throws {
        let url = try await nineMinutes([.silence(), .tone(880)])
        measure("step: made")
        let old = folder.appendingPathComponent("old.mov")
        let (_, oldSeconds, _) = try await timed { await LegacyAudioMixer.mix(url, into: old) }
        measure("step: mixed the old way")
        let (plan, planSeconds, _) = try await timed { try await MoviePlan.make(for: url, isScreenRecording: true) }
        measure("step: looked, \(plan.sound)")
        let new = folder.appendingPathComponent("new.mov")
        let (_, newSeconds, newPeak) = try await timed {
            try await MovieRewrite.run(url, to: new, plan: plan, fileType: .mov, indexFirst: false, control: MovieRewriteControl())
        }
        measure(String(format: "9 min, %.0f MB, phone sound silent: before %.1f s, now %.1f s (+%.0f MB), look %.2f s",
                       megabytes(url), oldSeconds, newSeconds, newPeak, planSeconds))
    }

    func testNineMinutesCutOff() async throws {
        let url = try await nineMinutes([.silence()], cutOff: true)
        XCTAssertEqual(MovieStructure.read(url)?.isFragmented, true)
        let (plan, planSeconds, _) = try await timed { try await MoviePlan.make(for: url, isScreenRecording: true) }
        let new = folder.appendingPathComponent("new.mp4")
        let (_, seconds, peak) = try await timed {
            try await MovieRewrite.run(url, to: new, plan: plan, fileType: .mp4, indexFirst: true, control: MovieRewriteControl())
        }
        measure(String(format: "9 min cut off (fragments), %.0f MB: repaired in %.1f s (+%.0f MB), look %.2f s, %.0f s kept",
                       megabytes(url), seconds, peak, planSeconds, plan.duration))
        let structure = try XCTUnwrap(MovieStructure.read(new))
        XCTAssertFalse(structure.isFragmented)
        XCTAssertTrue(structure.indexIsFirst)
    }

    /// 2 GB: longer than a phone's share extension could ever hold in memory.
    func testTwoGigabytes() async throws {
        var spec = TestMovie.Spec()
        spec.seconds = 600
        spec.width = 1080
        spec.height = 1920
        spec.bitRate = 28_000_000
        spec.sounds = [.tone(440), .tone(880)]
        guard DiskSpace.available > 8_000_000_000 || DiskSpace.available == 0 else { throw XCTSkip("no room on this runner") }
        let url = try await movie("two-gigabytes.mov", spec)
        XCTAssertGreaterThan(MediaInspector.fileSize(url), 1_000_000_000)
        let (plan, planSeconds, _) = try await timed { try await MoviePlan.make(for: url, isScreenRecording: true) }
        let new = folder.appendingPathComponent("new.mov")
        let (_, seconds, peak) = try await timed {
            try await MovieRewrite.run(url, to: new, plan: plan, fileType: .mov, indexFirst: false, control: MovieRewriteControl())
        }
        measure(String(format: "10 min, %.0f MB, two sounds: mixed in %.1f s (+%.0f MB), look %.2f s", megabytes(url), seconds, peak, planSeconds))
        XCTAssertLessThan(peak, 250)
        let structure = try XCTUnwrap(MovieStructure.read(new))
        XCTAssertTrue(structure.isComplete)
        try? FileManager.default.removeItem(at: new)

        let (_, linkSeconds, linkPeak) = try await timed { ShareFileLink.prepare(url, title: "Two gigabytes", root: folder) }
        measure(String(format: "link to the 2 GB recording: %.4f s (+%.0f MB)", linkSeconds, linkPeak))
        let (_, thumbSeconds, thumbPeak) = try await timed { try await MediaInspector.thumbnail(for: url, at: 0.5) }
        measure(String(format: "thumbnail of the 2 GB recording: %.2f s (+%.0f MB)", thumbSeconds, thumbPeak))
        XCTAssertLessThan(thumbPeak, 150)
    }

    func testMP4CopyOfNineMinutes() async throws {
        let url = try await nineMinutes([.silence(seconds: 440)])
        let plan = try await MoviePlan.make(for: url, isScreenRecording: true)
        XCTAssertFalse(plan.needsRewrite, "the owner's file goes out as it is, at once")
        for first in [false, true] {
            let new = folder.appendingPathComponent("copy-\(first).mp4")
            let (_, seconds, peak) = try await timed {
                try await MovieRewrite.run(url, to: new, plan: plan, fileType: .mp4, indexFirst: first, control: MovieRewriteControl())
            }
            measure(String(format: "MP4 of 9 min, %.0f MB, index %@: %.1f s (+%.0f MB)", megabytes(url), first ? "first" : "last", seconds, peak))
            XCTAssertEqual(MovieStructure.read(new)?.indexIsFirst, first)
            XCTAssertLessThan(peak, 150)
        }
    }

    func testSmallerCopyOfAMinute() async throws {
        var spec = TestMovie.Spec()
        spec.seconds = 60
        spec.width = 886
        spec.height = 1918
        spec.bitRate = 2_400_000
        let url = try await movie("minute.mov", spec)
        let plan = SmallerCopyPlan(width: 540, height: 1168, videoBitRate: 450_000, estimatedBytes: 4_300_000)
        let new = folder.appendingPathComponent("small.mp4")
        let (_, seconds, peak) = try await timed {
            try await SmallerCopy.write(url, to: new, plan: plan, control: MovieRewriteControl())
        }
        measure(String(format: "smaller copy of 1 min: %.1f s (+%.0f MB), %.1f of %.1f MB, estimate %.1f MB",
                       seconds, peak, megabytes(new), megabytes(url), Double(plan.estimatedBytes) / 1_000_000))
    }

    // MARK: Tap to sheet

    /// The real flow with the real share sheet, over the app's own window.
    @MainActor
    func testTapToSheet() async throws {
        let root = folder.appendingPathComponent("library", isDirectory: true)
        let library = Library(storage: InMemoryStorage(mediaRoot: root))
        func add(_ url: URL, _ title: String) throws -> Video {
            let id = UUID()
            let name = "\(id.uuidString).\(url.pathExtension)"
            try FileManager.default.moveItem(at: url, to: library.media.videoURL(name))
            let video = Video(id: id, title: title, createdAt: Date(), kind: .screen, fileName: name, duration: 540,
                              fileSize: MediaInspector.fileSize(library.media.videoURL(name)), pixelWidth: 886, pixelHeight: 1918)
            library.add(video)
            return video
        }
        let one = try add(try await nineMinutes([.silence(seconds: 440)]), "One sound")
        let two = try add(try await nineMinutes([.tone(440), .tone(880)]), "Two sounds, not mixed yet")
        for video in [one, two] {
            let flow = ShareFlow()
            var ended = false
            let started = Date()
            var cardAt: Double?
            let peak = MemoryPeak()
            flow.start(video, library: library, onEnd: { ended = true })
            for _ in 0..<6_000 where flow.phase != .sheet && !ended {
                if cardAt == nil, flow.card != nil { cardAt = Date().timeIntervalSince(started) }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            let seconds = Date().timeIntervalSince(started)
            XCTAssertEqual(flow.phase, .sheet, "\(video.title) \(flow.toast?.text ?? "") state \(UIApplication.shared.applicationState.rawValue)")
            let sheet = ShareSheetPresenter.topViewController()
            XCTAssertTrue(sheet is UIActivityViewController, "\(String(describing: sheet))")
            measure(String(format: "tap to share sheet, %@ (%.0f MB): %.2f s, card after %@, +%.0f MB", video.title,
                           Double(video.fileSize) / 1_000_000, seconds, cardAt.map { String(format: "%.2f s", $0) } ?? "none needed", peak.stop()))
            // Closing the sheet ends the flow, so the next tap works.
            sheet?.dismiss(animated: true)
            for _ in 0..<500 where !ended { try await Task.sleep(nanoseconds: 10_000_000) }
            XCTAssertTrue(ended)
            XCTAssertFalse(flow.isBusy(with: video.id))
        }
        // Again, with everything prepared.
        let flow = ShareFlow()
        let started = Date()
        flow.start(two, library: library, onEnd: {})
        for _ in 0..<2_000 where flow.phase != .sheet { try await Task.sleep(nanoseconds: 10_000_000) }
        measure(String(format: "tap to share sheet, second time: %.2f s", Date().timeIntervalSince(started)))
        XCTAssertEqual(flow.phase, .sheet)
        ShareSheetPresenter.topViewController()?.dismiss(animated: false)
        try await Task.sleep(nanoseconds: 600_000_000)
    }
}
