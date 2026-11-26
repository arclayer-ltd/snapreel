import AVFoundation
import XCTest
@testable import Snapreel

/// The editor's state: what plays after each change, interruptions, drafts.
@MainActor
final class EditorModelTests: XCTestCase {
    private var model: EditorModel!

    override func tearDown() async throws {
        model?.teardown()
        model = nil
    }

    private func open() async throws -> (EditorModel, Library, UUID) {
        var spec = TestMedia.Spec()
        spec.name = "copy20"
        spec.duration = 20
        spec.audioDuration = 20
        let (url, _) = try await TestMedia.make(spec)
        let (library, id) = try await TestMedia.library(with: url)
        let model = EditorModel(videoID: id, library: library)
        self.model = model
        await model.load()
        XCTAssertFalse(model.loadFailed)
        let ready = await wait(5) { model.player.currentItem?.status == .readyToPlay }
        XCTAssertTrue(ready)
        return (model, library, id)
    }

    private func wait(_ timeout: Double, _ done: () -> Bool) async -> Bool {
        let started = Date()
        while Date().timeIntervalSince(started) < timeout {
            if done() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return done()
    }

    private func playsLength(_ model: EditorModel, _ seconds: Double) async -> Bool {
        await wait(5) { abs((model.player.currentItem?.duration.seconds ?? 0) - seconds) < 0.05 && !model.playback.isShowing }
    }

    func testChangesReachThePlayer() async throws {
        let (model, _, _) = try await open()
        XCTAssertFalse(model.isDirty)
        model.seek(to: 12, exact: true)
        model.apply { $0.remove(source: 2...6) }
        let cut = await playsLength(model, 16)
        XCTAssertTrue(cut)
        XCTAssertEqual(model.playhead, 8, accuracy: 0.01, "the playhead stays on its moment")
        let arrived = await wait(3) { abs(model.player.currentTime().seconds - 8) < 0.05 }
        XCTAssertTrue(arrived)
        model.undo()
        let back = await playsLength(model, 20)
        XCTAssertTrue(back)
        XCTAssertEqual(model.playhead, 12, accuracy: 0.01)
        model.redo()
        let again = await playsLength(model, 16)
        XCTAssertTrue(again)
    }

    /// Levels and picture changes never make a new item (that is what made the picture blink).
    func testLevelsAndPictureKeepTheItem() async throws {
        let (model, _, _) = try await open()
        let item = model.player.currentItem
        let mix = item?.audioMix
        model.apply { $0.audio.volume = 0.3 }
        XCTAssertTrue(model.player.currentItem === item)
        XCTAssertFalse(item?.audioMix === mix)
        model.apply { $0.crop.rect = CGRect(x: 0, y: 0.1, width: 1, height: 0.5) }
        XCTAssertTrue(model.player.currentItem === item)
        XCTAssertNotNil(item?.videoComposition)
        model.undo()
        XCTAssertNil(item?.videoComposition)
        XCTAssertTrue(model.player.currentItem === item)
    }

    /// A level changed while a cut is being made ready must be in what comes forward.
    func testLevelChangedDuringARebuildIsHeard() async throws {
        let (model, _, _) = try await open()
        model.apply { $0.remove(source: 2...6) }
        model.apply { $0.audio.muted = true }
        let cut = await playsLength(model, 16)
        XCTAssertTrue(cut)
        let mix = try XCTUnwrap(model.player.currentItem?.audioMix)
        var start: Float = -1, end: Float = -1
        var range = CMTimeRange()
        XCTAssertTrue(mix.inputParameters[0].getVolumeRamp(for: CMTime(seconds: 1, preferredTimescale: 600), startVolume: &start, endVolume: &end, timeRange: &range))
        XCTAssertEqual(start, 0, "muted")
    }

    func testManyQuickChangesEndOnTheLastOne() async throws {
        let (model, _, _) = try await open()
        for index in 0..<12 {
            model.apply { $0.remove(source: (Double(index) + 0.3)...(Double(index) + 0.5)) }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let done = await playsLength(model, 20 - 12 * 0.2)
        XCTAssertTrue(done, "\(model.player.currentItem?.duration.seconds ?? 0)")
    }

    func testInterruptionsPause() async throws {
        let (model, _, _) = try await open()
        func startPlaying() async {
            model.seek(to: 1, exact: true)
            model.play()
            let moving = await wait(4) { model.playhead > 1.2 }
            XCTAssertTrue(moving, "plays (at \(model.playhead), player \(model.player.currentTime().seconds) rate \(model.player.rate), "
                + "playing \(model.isPlaying), seeking \(model.playback.isSeeking), showing \(model.playback.isShowing))")
        }
        await startPlaying()
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil,
                                        userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        let call = await wait(1) { !model.isPlaying }
        XCTAssertTrue(call, "a call pauses")
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil,
                                        userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue])
        await startPlaying()
        NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: nil,
                                        userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])
        let unplugged = await wait(1) { !model.isPlaying }
        XCTAssertTrue(unplugged, "unplugging headphones pauses")
        await startPlaying()
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        let left = await wait(1) { !model.isPlaying }
        XCTAssertTrue(left, "leaving the app pauses")
        await startPlaying()
        model.player.pause()
        let system = await wait(2) { !model.isPlaying }
        XCTAssertTrue(system, "the button follows when the system stops the player")
    }

    func testPlaysToTheEndAndFromTheStartAgain() async throws {
        let (model, _, _) = try await open()
        model.seek(to: 19.2, exact: true)
        model.play()
        let ended = await wait(5) { !model.isPlaying }
        XCTAssertTrue(ended)
        XCTAssertEqual(model.playhead, 20, accuracy: 0.1)
        model.play()
        let started = await wait(4) { model.isPlaying && model.playhead > 0.2 && model.playhead < 5 }
        XCTAssertTrue(started)
        model.pause()
    }

    /// Dragging a section's handle shows the recording itself, then the edit again.
    func testTrimPreviewAndBack() async throws {
        let (model, _, _) = try await open()
        let id = model.recipe.segments[0].id
        model.beginTrim(.segment(id), edge: .end)
        for step in 1...20 {
            model.updateTrim(offset: -Double(step) * 0.4)
            try await Task.sleep(nanoseconds: 16_000_000)
        }
        let previewing = await wait(3) { abs(model.player.currentTime().seconds - 11.97) < 0.2 }
        XCTAssertTrue(previewing, "shows the frame under the handle (\(model.player.currentTime().seconds))")
        model.endTrim()
        let trimmed = await playsLength(model, 12)
        XCTAssertTrue(trimmed)
        XCTAssertEqual(model.playhead, 11.96, accuracy: 0.05, "the playhead goes to the edge that was set")
        XCTAssertTrue(model.canUndo)
        model.undo()
        let back = await playsLength(model, 20)
        XCTAssertTrue(back)
        XCTAssertFalse(model.canUndo, "the whole drag is one step")
    }

    func testDraftsSaveThemselvesAndGoWithTheEdits() async throws {
        let (model, library, id) = try await open()
        XCTAssertNil(library.draft(for: id))
        model.apply { $0.remove(source: 2...6) }
        let saved = await wait(3) { library.draft(for: id) != nil }
        XCTAssertTrue(saved)
        model.undo()
        let gone = await wait(3) { library.draft(for: id) == nil }
        XCTAssertTrue(gone, "back to the recording, nothing to keep")
        // Leaving the app right after a change keeps it, without the usual short wait.
        model.apply { $0.audio.volume = 0.5 }
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        XCTAssertNotNil(library.draft(for: id))
        model.setQuality(.hd720)
        XCTAssertEqual(model.recipe.quality, .hd720)
        model.undo()
        XCTAssertEqual(model.recipe.audio.volume, 1)
    }

    func testDiscardEditsCanBeUndoneWithItsVoiceOver() async throws {
        let (model, library, id) = try await open()
        let file = model.editFolder.appendingPathComponent("take.m4a")
        try Data([1, 2, 3]).write(to: file)
        model.apply { $0.voiceClips = [EditVoiceClip(fileName: "take.m4a", start: 1, duration: 2)] }
        model.discardEdits()
        XCTAssertNil(library.draft(for: id))
        XCTAssertFalse(model.isDirty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        model.undo()
        XCTAssertEqual(model.recipe.voiceClips.count, 1)
        model.discardDraft()
        model.teardown()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "left without the edits: its files go")
    }

    func testCaptionsAndOverlaysAppearAtTheirTime() async throws {
        let (model, library, id) = try await open()
        library.saveTranscript(Transcript(videoID: id, localeIdentifier: "en", segments: [
            TranscriptSegment(start: 2, duration: 3, text: "Hello there"),
            TranscriptSegment(start: 8, duration: 3, text: "Second"),
        ], createdAt: Date(), summary: nil))
        model.addCaptions()
        model.apply { $0.texts = [EditText(text: "Hi", start: 4, end: 6)] }
        model.seek(to: 3)
        XCTAssertEqual(model.moment.value.caption, "Hello there")
        XCTAssertTrue(model.moment.value.overlays.isEmpty)
        model.seek(to: 4.5)
        XCTAssertEqual(model.moment.value.overlays.count, 1)
        model.seek(to: 7)
        XCTAssertNil(model.moment.value.caption)
        model.apply { $0.remove(source: 0...2) }
        model.seek(to: 6.5)
        XCTAssertEqual(model.moment.value.caption, "Second")
    }

    func testOverlaysMoveInTimeAndOnePartOpensTrim() async throws {
        let (library, id) = TestMedia.placeholder(duration: 60)
        let model = EditorModel(videoID: id, library: library, isStatic: true)
        self.model = model
        model.apply { $0.stickers = [EditSticker(kind: .arrow, start: 10, end: 13)] }
        let arrow = model.recipe.stickers[0].id
        model.beginTrim(.sticker(arrow), edge: .whole)
        model.updateTrim(offset: 5)
        model.endTrim()
        XCTAssertEqual(model.recipe.stickers[0].start, 15, accuracy: 0.001)
        XCTAssertEqual(model.recipe.stickers[0].end, 18, accuracy: 0.001)
        model.beginTrim(.sticker(arrow), edge: .whole)
        model.updateTrim(offset: 100)
        model.endTrim()
        XCTAssertEqual(model.recipe.stickers[0].end, 60, accuracy: 0.001, "stays inside the video, length kept")
        XCTAssertEqual(model.recipe.stickers[0].start, 57, accuracy: 0.001)
        model.toggleSegment(atOutput: 30)
        XCTAssertNil(model.selection, "one part: nothing to pick")
        XCTAssertEqual(model.tool, .trim)
        model.toggleSegment(atOutput: 30)
        XCTAssertEqual(model.tool, .trim, "tapping again doesn't flip back")
    }

    func testDoneWithoutWordsAsksForThem() {
        let (library, id) = TestMedia.placeholder(duration: 60)
        let model = EditorModel(videoID: id, library: library, isStatic: true)
        self.model = model
        model.addText()
        model.commitTextEntry()
        XCTAssertNotNil(model.textEntry, "stays open")
        XCTAssertTrue(model.textEntryNeedsWords)
        model.commitTextEntry(leaving: true)
        XCTAssertNil(model.textEntry)
        XCTAssertTrue(model.recipe.texts.isEmpty)
    }

    func testMissingFileSaysSo() async throws {
        let (library, id) = TestMedia.placeholder(duration: 30)
        let model = EditorModel(videoID: id, library: library)
        self.model = model
        await model.load()
        XCTAssertTrue(model.loadFailed)
        XCTAssertFalse(model.isPreparing)
    }
}
