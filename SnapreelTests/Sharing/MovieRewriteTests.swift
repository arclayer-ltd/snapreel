import AVFoundation
import XCTest
@testable import Snapreel

/// Putting a recording's file in order without touching its picture.
final class MovieRewriteTests: SharingTestCase {
    // MARK: Layout

    func testOrdinaryRecordingNeedsNothing() async throws {
        let url = try await movie()
        let structure = try XCTUnwrap(MovieStructure.read(url))
        XCTAssertEqual(structure.brand, "qt  ")
        XCTAssertFalse(structure.isFragmented)
        XCTAssertTrue(structure.isComplete)
        let plan = try await MoviePlan.make(for: url, isScreenRecording: true)
        XCTAssertFalse(plan.needsRewrite, "\(plan.reasons)")
    }

    func testStructureOfSomethingElse() throws {
        let url = folder.appendingPathComponent("notes.txt")
        try Data(String(repeating: "not a movie ", count: 40).utf8).write(to: url)
        XCTAssertNil(MovieStructure.read(url))
        XCTAssertNil(MovieStructure.read(folder.appendingPathComponent("missing.mov")))
    }

    func testUnreadableFileSaysSo() async throws {
        let url = folder.appendingPathComponent("broken.mov")
        try Data(repeating: 7, count: 50_000).write(to: url)
        do {
            _ = try await MoviePlan.make(for: url, isScreenRecording: true)
            XCTFail("a broken file got a plan")
        } catch {
            XCTAssertEqual(error as? MovieRewriteError, .unreadable)
        }
    }

    // MARK: Sound

    func testTwoSoundsBecomeOneWithBothInIt() async throws {
        var spec = TestMovie.Spec()
        spec.sounds = [.tone(440, seconds: 2), .tone(880)]
        let url = try await movie("two.mov", spec)
        let plan = try await MoviePlan.make(for: url, isScreenRecording: true)
        XCTAssertEqual(plan.reasons, [.twoSounds])
        guard case .mix(let ids) = plan.sound else { return XCTFail("\(plan.sound)") }
        XCTAssertEqual(ids.count, 2)

        let before = try await MovieFacts.read(url)
        let target = folder.appendingPathComponent("one.mov")
        try await MovieRewrite.run(url, to: target, plan: plan, fileType: .mov, indexFirst: false, control: MovieRewriteControl())
        let after = try await MovieFacts.read(target)
        XCTAssertEqual(after.audioSeconds.count, 1)
        XCTAssertEqual(after.audioSeconds[0], 6, accuracy: 0.15)
        XCTAssertEqual(after.frames, before.frames)
        // Uneven frame times are kept exactly.
        for (old, new) in zip(before.frameTimes, after.frameTimes) { XCTAssertEqual(old, new, accuracy: 0.002) }
        let both = try await MovieFacts.loudness(target, from: 0.5, to: 1.5)
        let one = try await MovieFacts.loudness(target, from: 4, to: 5)
        XCTAssertGreaterThan(both, one * 1.5)
        XCTAssertGreaterThan(one, 0.1)
    }

    func testSilentTrackIsLeftOutWithoutEncoding() async throws {
        var spec = TestMovie.Spec()
        spec.sounds = [.silence(), .tone(880)]
        let url = try await movie("silent.mov", spec)
        let plan = try await MoviePlan.make(for: url, isScreenRecording: true)
        guard case .copy(let id) = plan.sound else { return XCTFail("\(plan.sound)") }
        XCTAssertEqual(id, 3, "the tone is the third track")
        let target = folder.appendingPathComponent("out.mov")
        try await MovieRewrite.run(url, to: target, plan: plan, fileType: .mov, indexFirst: false, control: MovieRewriteControl())
        let after = try await MovieFacts.read(target)
        XCTAssertEqual(after.audioSeconds.count, 1)
        XCTAssertEqual(after.audioSeconds[0], 6, accuracy: 0.15)
        let heard = try await MovieFacts.loudness(target, from: 2, to: 4)
        XCTAssertGreaterThan(heard, 0.1)
    }

    /// A few seconds of sound in a long silence must never be taken for silence.
    func testShortSoundIsNotTakenForSilence() async throws {
        var spec = TestMovie.Spec()
        spec.seconds = 20
        spec.sounds = [.tone(440, seconds: 1), .silence()]
        let url = try await movie("short.mov", spec)
        let plan = try await MoviePlan.make(for: url, isScreenRecording: true)
        XCTAssertEqual(plan.sound, .copy(2))
    }

    func testTwoSilentTracksKeepOne() async throws {
        var spec = TestMovie.Spec()
        spec.sounds = [.silence(), .silence()]
        let url = try await movie("quiet.mov", spec)
        let plan = try await MoviePlan.make(for: url, isScreenRecording: true)
        XCTAssertEqual(plan.sound, .copy(2))
    }

    /// A movie from elsewhere can carry alternative sound tracks; they are none of our business.
    func testImportedMovieIsLeftAlone() async throws {
        var spec = TestMovie.Spec()
        spec.sounds = [.tone(440), .tone(880)]
        let url = try await movie("imported.mov", spec)
        let plan = try await MoviePlan.make(for: url, isScreenRecording: false)
        XCTAssertFalse(plan.needsRewrite)
    }

    /// The owner's recording: the sound ends 93 s before the picture. Nothing may wait for it or cut the picture.
    func testSoundShorterThanPicture() async throws {
        var spec = TestMovie.Spec()
        spec.seconds = 12
        spec.sounds = [.tone(440, seconds: 3)]
        let url = try await movie("shorter.mov", spec)
        let plan = try await MoviePlan.make(for: url, isScreenRecording: true)
        XCTAssertFalse(plan.needsRewrite)
        let target = folder.appendingPathComponent("shorter.mp4")
        try await MovieRewrite.run(url, to: target, plan: plan, fileType: .mp4, indexFirst: true, control: MovieRewriteControl())
        let after = try await MovieFacts.read(target)
        XCTAssertEqual(after.videoSeconds, 12, accuracy: 0.1)
        XCTAssertEqual(after.audioSeconds[0], 3, accuracy: 0.2)
    }

    func testNoSoundAtAll() async throws {
        var spec = TestMovie.Spec()
        spec.sounds = []
        let url = try await movie("mute.mov", spec)
        let plan = try await MoviePlan.make(for: url, isScreenRecording: true)
        XCTAssertEqual(plan.sound, .none)
        let target = folder.appendingPathComponent("mute.mp4")
        try await MovieRewrite.run(url, to: target, plan: plan, fileType: .mp4, indexFirst: true, control: MovieRewriteControl())
        let after = try await MovieFacts.read(target)
        XCTAssertEqual(after.audioSeconds, [])
        XCTAssertEqual(after.videoSeconds, 6, accuracy: 0.1)
    }

    // MARK: Container

    func testCopyForOtherAppsIsARealMP4() async throws {
        let url = try await movie()
        let plan = try await MoviePlan.make(for: url, isScreenRecording: true)
        let target = folder.appendingPathComponent("copy.mp4")
        try await MovieRewrite.run(url, to: target, plan: plan, fileType: .mp4, indexFirst: true, control: MovieRewriteControl())
        let structure = try XCTUnwrap(MovieStructure.read(target))
        XCTAssertTrue(["mp41", "mp42", "isom"].contains(structure.brand), structure.brand)
        XCTAssertTrue(structure.indexIsFirst)
        XCTAssertTrue(structure.isComplete)
        XCTAssertFalse(structure.isFragmented)
        let before = try await MovieFacts.read(url)
        let after = try await MovieFacts.read(target)
        XCTAssertEqual(after.frames, before.frames)
        XCTAssertEqual(after.seconds, before.seconds, accuracy: 0.1)
        XCTAssertEqual(after.codec, kCMVideoCodecType_H264)
        // Copied, not encoded again: about the same size.
        let ratio = Double(MediaInspector.fileSize(target)) / Double(MediaInspector.fileSize(url))
        XCTAssertEqual(ratio, 1, accuracy: 0.1)
    }

    func testCutOffRecordingBecomesWhole() async throws {
        var spec = TestMovie.Spec()
        spec.seconds = 12
        spec.isCutOff = true
        let url = try await movie("cut.mov", spec)
        let structure = try XCTUnwrap(MovieStructure.read(url))
        XCTAssertTrue(structure.isFragmented)
        let plan = try await MoviePlan.make(for: url, isScreenRecording: true)
        XCTAssertTrue(plan.reasons.contains(.fragmented))
        XCTAssertGreaterThan(plan.duration, 5)
        let target = folder.appendingPathComponent("whole.mov")
        try await MovieRewrite.run(url, to: target, plan: plan, fileType: .mov, indexFirst: false, control: MovieRewriteControl())
        let whole = try XCTUnwrap(MovieStructure.read(target))
        XCTAssertFalse(whole.isFragmented)
        XCTAssertTrue(whole.isComplete)
        let before = try await MovieFacts.read(url)
        let after = try await MovieFacts.read(target)
        XCTAssertEqual(after.seconds, plan.duration, accuracy: 0.5)
        XCTAssertEqual(after.videoSeconds, before.videoSeconds, accuracy: 0.5)
        XCTAssertEqual(after.frames, before.frames)
    }

    func testTurnedPictureComesBackIntoView() async throws {
        var spec = TestMovie.Spec()
        spec.transform = CGAffineTransform(rotationAngle: .pi / 2) // builds up to 47
        let url = try await movie("turned.mov", spec)
        let plan = try await MoviePlan.make(for: url, isScreenRecording: true)
        XCTAssertEqual(plan.reasons, [.pictureOffset])
        let target = folder.appendingPathComponent("upright.mp4")
        try await MovieRewrite.run(url, to: target, plan: plan, fileType: .mp4, indexFirst: true, control: MovieRewriteControl())
        let after = try await MovieFacts.read(target)
        let placed = CGRect(origin: .zero, size: after.size).applying(after.transform)
        XCTAssertEqual(placed.minX, 0, accuracy: 1)
        XCTAssertEqual(placed.minY, 0, accuracy: 1)
        XCTAssertEqual(placed.width, 780, accuracy: 1)
        let again = try await MoviePlan.make(for: target, isScreenRecording: true)
        XCTAssertFalse(again.needsRewrite)
    }

    func testUprightTransformsAreLeftAlone() {
        let size = CGSize(width: 886, height: 1918)
        XCTAssertEqual(MoviePlan.upright(.identity, size: size), .identity)
        let camera = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1918, ty: 0)
        XCTAssertEqual(MoviePlan.upright(camera, size: size), camera)
        for angle in [CGFloat.pi / 2, -.pi / 2, .pi] {
            let placed = CGRect(origin: .zero, size: size)
                .applying(MoviePlan.upright(CGAffineTransform(rotationAngle: angle), size: size))
            XCTAssertEqual(placed.minX, 0, accuracy: 0.01)
            XCTAssertEqual(placed.minY, 0, accuracy: 0.01)
        }
    }

    // MARK: Stopping

    func testCancelLeavesNothingBehind() async throws {
        var spec = TestMovie.Spec()
        spec.seconds = 120
        let url = try await movie("long.mov", spec)
        let plan = try await MoviePlan.make(for: url, isScreenRecording: true)
        let target = folder.appendingPathComponent("stopped.mp4")
        let control = MovieRewriteControl()
        control.cancel()
        do {
            try await MovieRewrite.run(url, to: target, plan: plan, fileType: .mp4, indexFirst: false, control: control)
            XCTFail("it was not stopped")
        } catch {
            XCTAssertEqual(error as? MovieRewriteError, .cancelled)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testProgressRisesToOne() async throws {
        let url = try await movie("progress.mov", TestMovie.Spec(seconds: 30))
        let plan = try await MoviePlan.make(for: url, isScreenRecording: true)
        let seen = ProgressValues()
        let control = MovieRewriteControl { seen.add($0) }
        try await MovieRewrite.run(url, to: folder.appendingPathComponent("p.mp4"), plan: plan, fileType: .mp4,
                                   indexFirst: false, control: control)
        XCTAssertEqual(seen.all.last, 1)
        XCTAssertEqual(seen.all, seen.all.sorted())
    }

    func testFirstReasonToStopWins() {
        let control = MovieRewriteControl()
        XCTAssertNil(control.stopped)
        control.interrupt()
        control.cancel()
        XCTAssertEqual(control.stopped, .interrupted)
    }

    func testErrorsBecomeReasons() {
        let control = MovieRewriteControl()
        func explain(_ domain: String, _ code: Int) -> MovieRewriteError {
            MoviePump.explain(NSError(domain: domain, code: code), control: control)
        }
        XCTAssertEqual(explain(AVFoundationErrorDomain, AVError.diskFull.rawValue), .noSpace)
        XCTAssertEqual(explain(NSPOSIXErrorDomain, Int(ENOSPC)), .noSpace)
        XCTAssertEqual(explain(AVFoundationErrorDomain, AVError.operationInterrupted.rawValue), .interrupted)
        XCTAssertEqual(explain(AVFoundationErrorDomain, AVError.unknown.rawValue), .failed)
        control.cancel()
        XCTAssertEqual(explain(AVFoundationErrorDomain, AVError.unknown.rawValue), .cancelled)
    }

    // MARK: Smaller copy

    func testSmallerCopyPlans() throws {
        // The owner's 8:50 recording.
        let long = try XCTUnwrap(SmallerCopyPlan.make(width: 886, height: 1918, duration: 530, bytes: 165_791_499))
        XCTAssertEqual(min(long.width, long.height), 540)
        XCTAssertLessThan(long.estimatedBytes, 40_000_000)
        // A 3-minute one fits what Messenger and mail take.
        let medium = try XCTUnwrap(SmallerCopyPlan.make(width: 886, height: 1918, duration: 120, bytes: 60_000_000))
        XCTAssertLessThanOrEqual(medium.estimatedBytes, 25_000_000)
        XCTAssertEqual(min(medium.width, medium.height), 720)
        XCTAssertEqual(medium.width % 2, 0)
        XCTAssertEqual(medium.height % 2, 0)
        // Nothing to gain.
        XCTAssertNil(SmallerCopyPlan.make(width: 886, height: 1918, duration: 30, bytes: 9_000_000))
        XCTAssertNil(SmallerCopyPlan.make(width: 886, height: 1918, duration: 530, bytes: 40_000_000))
        XCTAssertNil(SmallerCopyPlan.make(width: 0, height: 0, duration: 530, bytes: 400_000_000))
    }

    func testSmallerCopyPlaysEverywhere() async throws {
        var spec = TestMovie.Spec()
        spec.seconds = 10
        spec.width = 886
        spec.height = 1918
        spec.bitRate = 12_000_000
        spec.sounds = [.tone(440), .tone(880)]
        spec.transform = CGAffineTransform(rotationAngle: .pi / 2)
        let url = try await movie("big.mov", spec)
        let plan = SmallerCopyPlan(width: 1170, height: 540, videoBitRate: 900_000, estimatedBytes: 1_300_000)
        let target = folder.appendingPathComponent("small.mp4")
        try await SmallerCopy.write(url, to: target, plan: plan, control: MovieRewriteControl())
        let facts = try await MovieFacts.read(target)
        XCTAssertEqual(facts.size, CGSize(width: 1170, height: 540))
        XCTAssertEqual(facts.codec, kCMVideoCodecType_H264)
        XCTAssertEqual(facts.videoSeconds, 10, accuracy: 0.2)
        XCTAssertEqual(facts.audioSeconds.count, 1)
        XCTAssertEqual(Double(facts.frames), 300, accuracy: 6)
        XCTAssertTrue(try XCTUnwrap(MovieStructure.read(target)).indexIsFirst)
        XCTAssertLessThan(MediaInspector.fileSize(target), MediaInspector.fileSize(url) / 3)
    }
}

final class ProgressValues: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []

    func add(_ value: Double) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    var all: [Double] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}
