import XCTest

/// Real touches on the real editor (`-screen edit.live`: a two-minute portrait recording), so the
/// gestures are checked on iOS 16 as well as on the newest iOS.
final class EditorUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SNAPREEL_EDITOR_LONG"] == "1",
                          "Touches the live editor for minutes: run by the editor-tests job (ios.yml editor_tests)")
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-screen", "edit.live", "-uiTests"]
        app.launch()
        XCTAssertTrue(app.buttons["Close editor"].waitForExistence(timeout: 90), "the editor opens")
        XCTAssertTrue(wait(20) { self.app.buttons["Play"].isEnabled }, "the recording is ready")
    }

    override func tearDown() {
        if let app {
            shot("end")
            app.terminate()
        }
        super.tearDown()
    }

    // MARK: - Helpers

    private func wait(_ timeout: Double, _ done: () -> Bool) -> Bool {
        let started = Date()
        while Date().timeIntervalSince(started) < timeout {
            if done() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        }
        return done()
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "\(self.name.replacingOccurrences(of: "[-\\[\\] ]", with: "", options: .regularExpression))-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// "0:12 of 2:00" as seconds.
    private var time: (now: Int, length: Int) {
        let label = app.staticTexts["editor.time"].label
        let parts = label.components(separatedBy: " of ").map { part -> Int in
            let numbers = part.split(separator: ":").compactMap { Int($0) }
            return numbers.reduce(0) { $0 * 60 + $1 }
        }
        return parts.count == 2 ? (parts[0], parts[1]) : (-1, -1)
    }

    private var timeline: XCUIElement { app.otherElements["Timeline"].firstMatch }

    /// A point on the filmstrip; `x` from the playhead in the middle, in points.
    private func strip(_ x: CGFloat, dy: CGFloat = 0) -> XCUICoordinate {
        let frame = timeline.frame
        return app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: app.frame.midX + x, dy: frame.maxY + 6 + 26 + dy))
    }

    private func drag(_ from: XCUICoordinate, by x: CGFloat, dy: CGFloat = 0, velocity: XCUIGestureVelocity = .slow, hold: Double = 0.05) {
        from.press(forDuration: hold, thenDragTo: from.withOffset(CGVector(dx: x, dy: dy)), withVelocity: velocity, thenHoldForDuration: 0.1)
    }

    /// Whether it is on screen (a button scrolled out of a row has no place to tap).
    private func onScreen(_ element: XCUIElement) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame
        return !frame.isEmpty && app.frame.contains(CGPoint(x: frame.midX, y: frame.midY))
    }

    private func openTool(_ name: String) {
        let button = app.buttons[name].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 4), "\(name) is in the tool bar")
        let row = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.midX, dy: button.frame.midY))
        for _ in 0..<6 where !onScreen(button) {
            row.press(forDuration: 0.05, thenDragTo: row.withOffset(CGVector(dx: -220, dy: 0)), withVelocity: .default, thenHoldForDuration: 0.2)
        }
        button.tap()
    }

    private func openSaveSheet() {
        XCTAssertTrue(wait(12) {
            if self.app.staticTexts["Save a copy"].exists { return true }
            let save = self.app.buttons["Save"].firstMatch
            if save.exists, save.isHittable { save.tap() }
            return self.app.staticTexts["Save a copy"].waitForExistence(timeout: 2)
        }, "Save opens its sheet")
    }

    /// The one that can be tapped, of several with the same name.
    private func tapButton(_ name: String) {
        let all = app.buttons.matching(identifier: name).allElementsBoundByIndex
        (all.last { $0.isHittable } ?? app.buttons[name].firstMatch).tap()
    }

    // MARK: - Tests

    func testOpenPlayScrubAndZoom() {
        XCTAssertEqual(time.length, 120, accuracy: 1)
        app.buttons["Play"].tap()
        XCTAssertTrue(wait(6) { self.time.now >= 2 }, "plays")
        app.buttons["Pause"].tap()
        let paused = time.now
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        XCTAssertEqual(time.now, paused, accuracy: 1, "stays paused")

        // A slow drag moves the playhead by what the finger moved.
        drag(strip(80), by: -160)
        let dragged = time.now
        XCTAssertGreaterThan(dragged, paused + 5, "dragging the timeline scrubs")
        // A flick rolls on.
        strip(120).press(forDuration: 0.02, thenDragTo: strip(-140), withVelocity: .fast, thenHoldForDuration: 0)
        XCTAssertTrue(wait(4) { self.time.now > dragged + 22 }, "a flick keeps rolling (\(dragged) to \(time.now))")
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        shot("scrubbed")

        // Pinch out: the same drag now moves less.
        let before = time.now
        timelineArea.pinch(withScale: 2.5, velocity: 2)
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        XCTAssertEqual(time.now, before, accuracy: 2, "zooming keeps the moment")
        drag(strip(80), by: -160)
        XCTAssertLessThan(time.now - before, 9, "zoomed in, the same drag moves less (\(before) to \(time.now))")
        shot("zoomed")
    }

    private var timelineArea: XCUIElement { app.otherElements["editor.timeline"].firstMatch }

    func testSelectSplitDeleteUndoRedo() {
        drag(strip(60), by: -240)
        strip(20).tap()
        XCTAssertTrue(app.buttons["Split"].waitForExistence(timeout: 3), "tapping the clip selects it")
        shot("selected")
        app.buttons["Split"].tap()
        XCTAssertTrue(app.staticTexts["Part 2 of 2"].waitForExistence(timeout: 3) || app.staticTexts["Part 1 of 2"].exists, "split in two")
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.buttons["Delete part"].waitForExistence(timeout: 3))
        app.buttons["Delete part"].tap()
        XCTAssertTrue(wait(4) { self.time.length < 118 }, "the part is gone")
        let cut = time.length
        shot("deleted")
        app.buttons["Undo"].tap()
        XCTAssertTrue(wait(4) { self.time.length >= 119 }, "undo brings it back")
        app.buttons["Redo"].tap()
        XCTAssertTrue(wait(4) { self.time.length == cut }, "redo cuts it again")
    }

    func testTrimHandleAndCutHere() {
        openTool("Trim")
        // Let the panel finish opening (the timeline moves while it does) before touching the handle.
        XCTAssertTrue(app.descendants(matching: .any)["Start handle"].waitForExistence(timeout: 4))
        var frame = timeline.frame
        for _ in 0..<10 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            if timeline.frame == frame { break }
            frame = timeline.frame
        }
        // The start handle sits at the playhead when the video is at its start.
        drag(strip(-8), by: 90, hold: 0.1)
        XCTAssertTrue(wait(4) { self.time.length <= 116 }, "dragging the start handle trims (\(time.length))")
        shot("trimmed")
        let trimmed = time.length
        // The same handle drags back out.
        drag(strip(-8), by: -60, hold: 0.1)
        XCTAssertTrue(wait(4) { self.time.length > trimmed }, "and back (\(trimmed) to \(time.length))")
        // Held at the edge, the timeline rolls on under the handle.
        let start = time.length
        strip(-8).press(forDuration: 0.1, thenDragTo: strip(app.frame.width / 2 - 12), withVelocity: .slow, thenHoldForDuration: 1.5)
        XCTAssertTrue(wait(4) { self.time.length < start - 20 }, "holding at the edge keeps trimming (\(start) to \(time.length))")
        app.buttons["Undo"].tap()
        XCTAssertTrue(wait(4) { self.time.length == start }, "one undo for the whole drag")
        // Cut to the playhead.
        drag(strip(60), by: -180)
        let at = time.now
        app.buttons["End here"].tap()
        XCTAssertTrue(wait(4) { abs(self.time.length - at) <= 1 }, "End here cuts after the playhead (\(at), \(time.length))")
        drag(strip(-60), by: 60)
        let middle = time.now
        app.buttons["Start here"].tap()
        XCTAssertTrue(wait(4) { abs(self.time.length - (at - middle)) <= 1 }, "Start here cuts before it")
        XCTAssertEqual(time.now, 0)
    }

    func testTextMovePinchEditDelete() {
        openTool("Text")
        app.buttons["Add text"].firstMatch.tap()
        let field = app.textFields["Text"].exists ? app.textFields["Text"] : app.textViews["Text"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 6), "the keyboard comes by itself")
        app.typeText("Look here")
        shot("typing")
        XCTAssertTrue(app.buttons["Done"].firstMatch.isHittable, "Done isn't under the keyboard")
        tapButton("Done")
        XCTAssertTrue(app.buttons["Edit text"].waitForExistence(timeout: 4), "the new text is selected")
        let before = app.buttons["Edit text"].frame
        let start = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: app.frame.midX, dy: before.midY + 22))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 10, dy: 60)), withVelocity: .slow, thenHoldForDuration: 0.1)
        let after = app.buttons["Edit text"].frame
        XCTAssertEqual(after.midY - before.midY, 60, accuracy: 14, "the text follows the finger")
        shot("moved")
        // Pinch on the picture, away from the text.
        app.buttons["Video"].firstMatch.pinch(withScale: 1.8, velocity: 1.5)
        XCTAssertGreaterThan(app.buttons["Edit text"].frame.midX, after.midX + 4, "pinching anywhere makes it larger")
        shot("pinched")
        app.buttons["Edit text"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 6))
        tapButton("Done")
        XCTAssertTrue(app.buttons["Delete"].firstMatch.waitForExistence(timeout: 4))
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertFalse(app.buttons["Edit text"].waitForExistence(timeout: 1))
    }

    func testCropBlurShapesAndSound() {
        openTool("Crop")
        app.buttons["Crop 1:1"].tap()
        shot("crop")
        let box = app.otherElements["Crop box"].firstMatch
        XCTAssertTrue(box.waitForExistence(timeout: 3))
        drag(box.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)), by: 0, dy: 50)
        shot("crop-moved")
        tapButton("Done")
        openTool("Blur")
        app.buttons["Add blur"].tap()
        XCTAssertTrue(app.buttons["Delete blur"].waitForExistence(timeout: 3))
        shot("blur")
        tapButton("Done")
        openTool("Shapes")
        app.buttons["Add arrow"].tap()
        XCTAssertTrue(app.buttons["Delete"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["Save"].firstMatch.frame.maxX, app.frame.maxX - 16, accuracy: 4, "the page is as wide as the screen")
        shot("arrow")
        // Dragging it by its middle moves it as far as the finger (build 47 hung here on iOS 16).
        // The arrow on the picture (the timeline and the panel have things called Arrow too).
        let top = app.otherElements["Timeline"].firstMatch.frame.minY
        func arrowOnPicture() -> XCUIElement? {
            app.descendants(matching: .any).matching(identifier: "Arrow").allElementsBoundByIndex
                .first { $0.frame.midY < top && $0.frame.width > 10 && $0.frame.minY > 60 }
        }
        guard let arrow = arrowOnPicture() else {
            XCTFail("no arrow on the picture")
            return
        }
        let was = arrow.frame
        let middle = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: was.midX, dy: was.midY))
        middle.press(forDuration: 0.1, thenDragTo: middle.withOffset(CGVector(dx: 25, dy: 60)), withVelocity: .slow, thenHoldForDuration: 0.2)
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        let moved = arrowOnPicture()?.frame ?? .zero
        XCTAssertFalse(moved.isEmpty, "still there")
        XCTAssertEqual(moved.midY - was.midY, 60, accuracy: 14)
        XCTAssertEqual(moved.midX - was.midX, 25, accuracy: 14)
        shot("arrow-moved")
        // The white corner makes it larger.
        let corner = app.descendants(matching: .any)["Resize and turn"].firstMatch
        XCTAssertTrue(corner.waitForExistence(timeout: 3), "a corner to resize with")
        let size = moved.width
        let grab = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: corner.frame.midX, dy: corner.frame.midY))
        grab.press(forDuration: 0.1, thenDragTo: grab.withOffset(CGVector(dx: 40, dy: 40)), withVelocity: .slow, thenHoldForDuration: 0.2)
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCTAssertGreaterThan(arrowOnPicture()?.frame.width ?? 0, size + 10, "dragging the corner makes it larger")
        shot("arrow-larger")
        tapButton("Done")
        openTool("Sound")
        app.buttons["Fade in"].tap()
        app.sliders.firstMatch.adjust(toNormalizedSliderPosition: 0.4)
        shot("sound")
        tapButton("Done")
        app.buttons["Play"].tap()
        XCTAssertTrue(wait(6) { self.time.now >= 2 }, "still plays with everything on")
        shot("playing")
    }

    /// The microphone prompt, the countdown, a take and using it (a CI Mac may have no microphone:
    /// then the editor must say so and stay usable).
    func testVoiceOver() {
        openTool("Voice-over")
        if app.buttons["Allow microphone"].waitForExistence(timeout: 3) {
            app.buttons["Allow microphone"].tap()
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            for title in ["Allow", "OK"] where springboard.buttons[title].firstMatch.waitForExistence(timeout: 3) {
                springboard.buttons[title].firstMatch.tap()
                break
            }
        }
        let record = app.buttons["Record voice-over"]
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        record.tap()
        XCTAssertTrue(app.staticTexts["Get ready…"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Save"].firstMatch.isEnabled, "nothing else while it counts and records")
        shot("countdown")
        if app.buttons["Stop recording"].waitForExistence(timeout: 8) {
            RunLoop.current.run(until: Date().addingTimeInterval(3))
            shot("recording")
            app.buttons["Stop recording"].tap()
            XCTAssertTrue(app.buttons["Use take"].waitForExistence(timeout: 5))
            app.buttons["Use take"].tap()
            XCTAssertTrue(app.buttons["Record another"].waitForExistence(timeout: 5))
            print("NOTE|voice-over recorded")
        } else {
            print("NOTE|no microphone on this Mac")
            XCTAssertTrue(record.waitForExistence(timeout: 5), "the panel is back after the microphone failed")
        }
        shot("after")
        tapButton("Done")
        app.buttons["Play"].tap()
        XCTAssertTrue(wait(8) { self.time.now >= 2 }, "plays after a voice-over")
    }

    func testTranscriptCutAndSpeed() {
        openTool("Transcript")
        let line = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Line number 3,'")).firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 5))
        line.tap()
        shot("transcript")
        tapButton("Done")
        XCTAssertTrue(wait(4) { self.time.length <= 116 }, "the sentence is cut (\(time.length))")
        let cut = time.length
        openTool("Speed")
        app.buttons["2× speed"].tap()
        tapButton("Done")
        XCTAssertTrue(wait(4) { abs(self.time.length * 2 - cut) <= 2 }, "twice the speed, half the length")
    }

    func testClosingUntouchedAsksNothingAndDraftsComeBack() {
        app.buttons["Close editor"].tap()
        XCTAssertFalse(app.staticTexts["Leave the editor?"].waitForExistence(timeout: 1.5), "nothing changed, nothing to ask")
        XCTAssertTrue(app.buttons["Open again"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["live.draft"].label, "No draft")
        app.buttons["Open again"].tap()
        XCTAssertTrue(wait(20) { self.app.buttons["Play"].exists && self.app.buttons["Play"].isEnabled })
        XCTAssertFalse(app.staticTexts["Pick up where you left off?"].exists, "no draft, no question")

        drag(strip(60), by: -180)
        openTool("Trim")
        app.buttons["Start here"].tap()
        let length = time.length
        tapButton("Done")
        // Swipe the page down from its top bar.
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.1))
        top.press(forDuration: 0.05, thenDragTo: top.withOffset(CGVector(dx: 0, dy: 400)), withVelocity: .default, thenHoldForDuration: 0)
        XCTAssertTrue(app.staticTexts["Leave the editor?"].waitForExistence(timeout: 4), "a swipe down asks about the edits")
        app.buttons["Keep draft"].tap()
        XCTAssertTrue(app.buttons["Open again"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["live.draft"].label, "Draft kept")
        app.buttons["Open again"].tap()
        XCTAssertTrue(app.buttons["Continue editing"].waitForExistence(timeout: 8))
        app.buttons["Continue editing"].tap()
        XCTAssertTrue(wait(8) { self.time.length == length }, "the draft is back")
        shot("draft")
    }

    func testSaveCancelSaveAndLeaveMidway() {
        drag(strip(60), by: -120)
        openTool("Trim")
        app.buttons["Start here"].tap()
        tapButton("Done")
        let length = time.length
        openSaveSheet()
        shot("save-sheet")
        // Sizes that make the same file are one choice ("720p · Original"), and a 720p
        // recording has no choice at all.
        let small = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '720p'")).firstMatch
        if small.exists { small.tap() }
        tapButton("Save")
        if app.staticTexts["Saving your edit"].waitForExistence(timeout: 4) {
            shot("saving")
            app.buttons["Cancel"].tap()
            XCTAssertTrue(app.staticTexts["Saving stopped"].waitForExistence(timeout: 4))
            app.buttons["Back to the editor"].tap()
        }
        XCTAssertTrue(wait(4) { self.time.length == length }, "the edits are still there")
        openSaveSheet()
        tapButton("Save")
        XCTAssertTrue(app.staticTexts["Saving your edit"].waitForExistence(timeout: 6) || app.staticTexts["Saved as a new recording"].exists)
        // Leave the app while it saves, and come back.
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        XCUIDevice.shared.press(.home)
        RunLoop.current.run(until: Date().addingTimeInterval(4))
        app.activate()
        XCTAssertTrue(app.staticTexts["Saved as a new recording"].waitForExistence(timeout: 300), "the save carries on and finishes")
        shot("saved")
        tapButton("Done")
        XCTAssertTrue(app.staticTexts["live.saved"].waitForExistence(timeout: 6))
        XCTAssertEqual(app.staticTexts["live.saved"].label, "1 saved")
        XCTAssertTrue(wait(6) { self.app.staticTexts["live.draft"].label == "No draft" }, "a saved edit leaves no draft")
    }
}
