import Photos
import UIKit
import XCTest
@testable import Snapreel

/// Names, links and their clean-up, the item the share sheet hands over, and Photos' errors.
final class ShareFilesTests: MovieTestCase {
    private var root: URL { folder }

    private func recording(_ name: String = "source.mov", bytes: Int = 2_000) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data(repeating: 3, count: bytes).write(to: url)
        return url
    }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    // MARK: Names

    func testNames() {
        XCTAssertEqual(ShareFileLink.fileName(for: "Bug: map pins jump on zoom", pathExtension: "mp4"), "Bug map pins jump on zoom.mp4")
        XCTAssertEqual(ShareFileLink.fileName(for: "  ..  ", pathExtension: "mov"), "Snapreel recording.mov")
        XCTAssertEqual(ShareFileLink.fileName(for: "a/b\\c", pathExtension: "m4a"), "a b c.m4a")
        XCTAssertEqual(ShareFileLink.fileName(for: String(repeating: "x", count: 300), pathExtension: "mp4").count, 84)
    }

    /// A file name holds 255 bytes; Bangla letters are three each and family emoji 25.
    func testLongNamesInOtherScriptsFit() throws {
        for title in [String(repeating: "রেকর্ডিং", count: 30), String(repeating: "👨‍👩‍👧‍👦", count: 60)] {
            let name = ShareFileLink.fileName(for: title, pathExtension: "mp4")
            XCTAssertLessThan(name.utf8.count, 255)
            let link = ShareFileLink.prepare(try recording(), title: title, root: root)
            XCTAssertEqual(link.lastPathComponent, ShareFileLink.fileName(for: title, pathExtension: "mov"))
            ShareFileLink.released(link)
        }
    }

    // MARK: Links

    func testLinkTakesNoSpaceAndOutlivesTheRecording() throws {
        let source = try recording()
        let link = ShareFileLink.prepare(source, title: "Demo", root: root)
        XCTAssertEqual(link.lastPathComponent, "Demo.mov")
        let attributes = try FileManager.default.attributesOfItem(atPath: link.path)
        XCTAssertEqual(attributes[.referenceCount] as? Int, 2)
        try FileManager.default.removeItem(at: source)
        XCTAssertEqual(try Data(contentsOf: link).count, 2_000)
        ShareFileLink.released(link)
    }

    func testMissingSourceGivesItBackUnlinked() {
        let source = root.appendingPathComponent("missing.mov")
        XCTAssertEqual(ShareFileLink.prepare(source, title: "Demo", root: root), source)
        let left = try? FileManager.default.contentsOfDirectory(atPath: ShareFileLink.directory(root: root).path)
        XCTAssertEqual(left ?? [], [])
    }

    func testDiscardOnlyRemovesItsOwnFolder() throws {
        let source = try recording()
        let link = ShareFileLink.prepare(source, title: "Demo", root: root)
        ShareFileLink.discard(link, root: root)
        XCTAssertFalse(exists(link))
        XCTAssertTrue(exists(source))
        // The fallback hands over the recording itself: discarding that must not touch it.
        ShareFileLink.discard(source, root: root)
        XCTAssertTrue(exists(source))
    }

    // MARK: Clean-up

    func testStaleRules() {
        let hour: TimeInterval = 3_600
        func stale(_ age: TimeInterval, links: Int, inUse: Bool = false) -> Bool {
            ShareFileLink.isStale(age: age, linkCount: links, inUse: inUse, copyAge: hour)
        }
        // A slow transfer of a recording that is still in the library: untouched for a day.
        XCTAssertFalse(stale(2 * hour, links: 2))
        XCTAssertFalse(stale(23 * hour, links: 2))
        XCTAssertTrue(stale(25 * hour, links: 2))
        // Nothing else holds its space any more.
        XCTAssertFalse(stale(2 * hour, links: 1))
        XCTAssertTrue(stale(4 * hour, links: 1))
        // Never while the sheet is up.
        XCTAssertFalse(stale(100 * hour, links: 1, inUse: true))
    }

    func testCleanUp() throws {
        let hour: TimeInterval = 3_600
        let kept = try recording("kept.mov")
        let gone = try recording("gone.mov")
        let keptLink = ShareFileLink.prepare(kept, title: "Kept", root: root)
        let goneLink = ShareFileLink.prepare(gone, title: "Gone", root: root)
        let openLink = ShareFileLink.prepare(gone, title: "Open", root: root)
        ShareFileLink.released(keptLink)
        ShareFileLink.released(goneLink)
        try FileManager.default.removeItem(at: gone)

        ShareFileLink.cleanUp(olderThan: hour, root: root, now: Date().addingTimeInterval(2 * hour))
        XCTAssertTrue(exists(keptLink) && exists(goneLink), "a transfer of an hour or two must not lose its file")
        ShareFileLink.cleanUp(olderThan: hour, root: root, now: Date().addingTimeInterval(26 * hour))
        XCTAssertFalse(exists(keptLink))
        XCTAssertFalse(exists(goneLink))
        XCTAssertTrue(exists(openLink), "its sheet is still up")
        XCTAssertTrue(exists(kept))
        ShareFileLink.released(openLink)
        ShareFileLink.cleanUp(olderThan: hour, root: root, now: Date().addingTimeInterval(26 * hour))
        XCTAssertFalse(exists(openLink))
    }

    func testPreparedCopiesGoAfterAnHourAndTheirLinksStay() throws {
        let hour: TimeInterval = 3_600
        let copies = ShareCopies.folder(root: root)
        try FileManager.default.createDirectory(at: copies, withIntermediateDirectories: true)
        let copy = copies.appendingPathComponent("copy.mp4")
        let partial = copies.appendingPathComponent("x.partial.mp4")
        try Data(count: 10).write(to: copy)
        try Data(count: 10).write(to: partial)
        let link = ShareFileLink.prepare(copy, title: "Copy", root: root)
        ShareFileLink.released(link)
        ShareFilesInUse.add(partial.lastPathComponent)
        ShareFileLink.cleanUp(olderThan: hour, root: root, now: Date().addingTimeInterval(30))
        XCTAssertTrue(exists(copy))
        ShareFileLink.cleanUp(olderThan: hour, root: root, now: Date().addingTimeInterval(1.5 * hour))
        XCTAssertFalse(exists(copy))
        XCTAssertTrue(exists(link), "someone may still be reading it")
        XCTAssertTrue(exists(partial), "it is being written")
        ShareFilesInUse.remove(partial.lastPathComponent)
        ShareFileLink.cleanUp(olderThan: hour, root: root, now: Date().addingTimeInterval(1.5 * hour))
        XCTAssertFalse(exists(partial), "half-written by an app that was closed")
    }

    // MARK: Copies

    @MainActor
    func testOneCopyIsMadeOnceAndUsedAgain() async throws {
        let source = try await movie("recording.mov")
        let video = Video(title: "Demo", createdAt: Date(), kind: .screen, fileName: "recording.mov", duration: 6,
                          fileSize: MediaInspector.fileSize(source), pixelWidth: 360, pixelHeight: 780)
        let plan = try await MoviePlan.make(for: source, isScreenRecording: true)
        let first = ShareCopies.shared.job(for: video, source: source, kind: .complete(plan), root: root)
        let same = ShareCopies.shared.job(for: video, source: source, kind: .complete(plan), root: root)
        XCTAssertTrue(first === same)
        let url = try await first.value()
        XCTAssertEqual(first.outcome.url(waiting: 0), url)
        let made = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        let again = ShareCopies.shared.job(for: video, source: source, kind: .complete(plan), root: root)
        let secondURL = try await again.value()
        XCTAssertEqual(secondURL, url)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date, made)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: ShareCopies.folder(root: root).path).count, 1)
    }

    @MainActor
    func testCancelledCopyCanBeMadeAgain() async throws {
        let source = try await movie("recording.mov", TestMovie.Spec(seconds: 60))
        let video = Video(title: "Demo", createdAt: Date(), kind: .screen, fileName: "recording.mov", duration: 60,
                          fileSize: MediaInspector.fileSize(source), pixelWidth: 360, pixelHeight: 780)
        let plan = try await MoviePlan.make(for: source, isScreenRecording: true)
        let job = ShareCopies.shared.job(for: video, source: source, kind: .complete(plan), root: root)
        job.cancel()
        do {
            _ = try await job.value()
            XCTFail("it was not cancelled")
        } catch {
            XCTAssertEqual(error as? MovieRewriteError, .cancelled)
        }
        XCTAssertNil(job.outcome.url(waiting: 0))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: ShareCopies.folder(root: root).path), [])
        let url = try await ShareCopies.shared.job(for: video, source: source, kind: .complete(plan), root: root).value()
        XCTAssertTrue(exists(url))
    }

    func testCopyOfAnEarlierVersionIsNotUsed() throws {
        let id = UUID()
        let source = try recording(bytes: 2_000)
        let before = ShareCopies.key(for: id, source: source, tag: "full")
        XCTAssertEqual(before, ShareCopies.key(for: id, source: source, tag: "full"))
        XCTAssertNotEqual(before, ShareCopies.key(for: id, source: source, tag: "small"))
        try Data(repeating: 1, count: 2_500).write(to: source)
        XCTAssertNotEqual(before, ShareCopies.key(for: id, source: source, tag: "full"))
    }

    // MARK: The share sheet's item

    func testItemHandsOverTheMP4ToAppsAndTheOriginalToAirDrop() throws {
        let original = try recording("Demo.mov")
        let made = try recording("made.mp4")
        let outcome = ShareCopyOutcome()
        outcome.set(.success(made))
        let provider = ShareItemProvider(file: original, copy: outcome, title: "Demo", thumbnailURL: nil, isAudio: false, root: root)
        XCTAssertEqual(provider.resolve(for: .airDrop), original)
        XCTAssertEqual(provider.resolve(for: .saveToCameraRoll), original)
        XCTAssertEqual(provider.resolve(for: SmallerCopyActivity.type), original)
        XCTAssertEqual(provider.resolve(for: .message).lastPathComponent, "Demo.mp4")
        XCTAssertEqual(provider.resolve(for: UIActivity.ActivityType("net.whatsapp.WhatsApp.ShareExtension")).pathExtension, "mp4")
        XCTAssertEqual(provider.placeholderItem as? URL, original)
    }

    func testItemWaitsForTheMP4ButNotForever() throws {
        let original = try recording("Demo.mov")
        let made = try recording("made.mp4")
        let outcome = ShareCopyOutcome()
        let provider = ShareItemProvider(file: original, copy: outcome, title: "Demo", thumbnailURL: nil, isAudio: false, root: root)
        // On the main thread it never waits.
        XCTAssertEqual(provider.resolve(for: .mail), original)
        let done = expectation(description: "resolved")
        DispatchQueue.global().async {
            XCTAssertEqual(provider.resolve(for: .mail).pathExtension, "mp4")
            done.fulfill()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { outcome.set(.success(made)) }
        wait(for: [done], timeout: 5)

        let failed = ShareCopyOutcome()
        failed.set(.failure(MovieRewriteError.failed))
        let other = ShareItemProvider(file: original, copy: failed, title: "Demo", thumbnailURL: nil, isAudio: false, root: root)
        XCTAssertEqual(other.resolve(for: .mail), original)
        XCTAssertNil(ShareCopyOutcome().url(waiting: 0.1))
    }

    @MainActor
    func testSmallerCopyActivity() {
        let activity = SmallerCopyActivity(estimatedBytes: 34_000_000)
        XCTAssertEqual(activity.activityTitle, "Smaller copy, about 34 MB")
        XCTAssertTrue(activity.canPerform(withActivityItems: []))
        XCTAssertNotNil(activity.activityImage)
    }

    // MARK: Photos

    @MainActor
    func testPhotosErrorsSaySomethingUseful() {
        func stage(_ code: Int, domain: String = "PHPhotosErrorDomain", denied: Bool = false) -> PhotosSaveStage {
            PhotosLibraryWriter.stage(for: NSError(domain: domain, code: code), accessDenied: denied)
        }
        XCTAssertEqual(stage(3305), .failed(.outOfSpace))
        XCTAssertEqual(stage(NSFileWriteOutOfSpaceError, domain: NSCocoaErrorDomain), .failed(.outOfSpace))
        XCTAssertEqual(stage(3311), .denied)
        XCTAssertEqual(stage(3310), .denied)
        XCTAssertEqual(stage(-1, denied: true), .denied)
        for code in [3302, 3301, 3114, 3164, -1] {
            guard case .failed(.other(let text)) = stage(code) else { return XCTFail("\(code)") }
            XCTAssertGreaterThan(text.count, 30)
        }
    }
}
