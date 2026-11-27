import AVFoundation
import XCTest
@testable import Snapreel

/// What the share and save buttons say around them: tester round of 26 Nov 2026.
final class ShareSurfaceTests: SharingTestCase {
    @MainActor private func video(state: VideoState, bytes: Int64, width: Int = 886, saves: Int = 0) -> Video {
        var video = Video(id: UUID(), title: "Demo", createdAt: Date(timeIntervalSince1970: 1_790_000_000), kind: .imported,
                          fileName: "demo.mp4", duration: 480, fileSize: bytes, pixelWidth: width,
                          pixelHeight: width == 0 ? 0 : 1918, state: state)
        video.photosSaveCount = saves
        return video
    }

    /// An edit still being written said "Zero KB" and nothing about why its buttons were grey.
    @MainActor func testStillSavingSaysHowFarInsteadOfZeroBytes() {
        let saving = video(state: .saving(progress: 0.126), bytes: 0, width: 0)
        let line = LibraryActionsSheet.dateLine(saving)
        XCTAssertTrue(line.hasPrefix("Saving 12% · "), line)
        XCTAssertFalse(line.contains("KB"), line)
        XCTAssertNotNil(LibraryActionsSheet.waitNote(saving))
        // Not taken for a sound recording while it has no picture size yet.
        XCTAssertFalse(saving.kind == .audio)
    }

    @MainActor func testReadyRecordingShowsItsSizeAndNoNote() {
        let ready = video(state: .ready, bytes: 25_900_000)
        XCTAssertTrue(LibraryActionsSheet.dateLine(ready).hasSuffix(Format.bytes(25_900_000)))
        XCTAssertNil(LibraryActionsSheet.waitNote(ready))
        let empty = video(state: .ready, bytes: 0)
        XCTAssertEqual(LibraryActionsSheet.dateLine(empty), Format.dateTime(empty.createdAt))
    }

    @MainActor func testFailedRecordingSaysWhyItCantBeShared() {
        let failed = video(state: .failed(reason: "Stopped", outOfSpace: false), bytes: 0)
        XCTAssertTrue(LibraryActionsSheet.dateLine(failed).hasPrefix("Not saved · "))
        XCTAssertNotNil(LibraryActionsSheet.waitNote(failed))
    }

    /// Saving again is a question, not a silent second copy.
    @MainActor func testSavingAgainAsksFirst() {
        XCTAssertTrue(PhotosSaveStage.alreadySaved(2).asksQuestion)
    }

    /// iOS paused the review player behind a share sheet while the screen still said "Playing".
    @MainActor func testReviewPlayerFollowsAPauseItDidNotAskFor() async throws {
        let url = try await movie("review.mov", TestMovie.Spec(seconds: 6))
        let review = RecorderReviewPlayer(url: url, duration: 6)
        review.play()
        XCTAssertTrue(review.isPlaying)
        await until("plays") { review.player.timeControlStatus != .paused }

        review.player.pause() // as iOS does, without telling the screen
        await until("shows paused") { !review.isPlaying }

        // One tap plays again.
        review.toggle()
        XCTAssertTrue(review.isPlaying)
        XCTAssertEqual(review.player.rate, 1)
        review.stop()
    }

    @MainActor func testReviewPlayerTapAfterStopPlaysAndMovesOn() async throws {
        let url = try await movie("again.mov", TestMovie.Spec(seconds: 6))
        let review = RecorderReviewPlayer(url: url, duration: 6)
        review.play()
        review.stop() // the screen went away for a moment
        XCTAssertFalse(review.isPlaying)
        review.play()
        await until("time moves") { review.position > 0.3 }
        review.stop()
    }

    @MainActor private func until(_ what: String, seconds: Double = 10, _ condition: @MainActor () -> Bool) async {
        let end = Date().addingTimeInterval(seconds)
        while !condition() {
            if Date() > end { return XCTFail("timed out: \(what)") }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
