import XCTest

/// Real touches on the real editor (`-screen edit.live`: a two-minute portrait recording), so the
/// gestures are checked on iOS 16 as well as on the newest iOS.
final class EditorUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-screen", "edit.live", "-uiTests"]
        app.launch()
        XCTAssertTrue(app.buttons["Close editor"].waitForExistence(timeout: 90), "the editor opens")
        XCTAssertTrue(wait(20) { self.app.buttons["Play"].isEnabled }, "the recording is ready")
    }

    override func tearDown() {
        shot("end")
        app.terminate()
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

    private func openTool(_ name: String) {
        let button = app.buttons[name]
        var tries = 0
        while !button.isHittable, tries < 6 {
            app.buttons["Trim"].firstMatch.exists ? app.scrollViews.containing(.button, identifier: name).firstMatch.swipeLeft(velocity: .slow)
                : app.swipeLeft(velocity: .slow)
            tries += 1
        }
        button.tap()
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
        XCTAssertTrue(app.buttons["Done"].isHittable, "Done isn't under the keyboard")
        app.buttons["Done"].firstMatch.tap()
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
        app.buttons["Done"].firstMatch.tap()
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
        app.buttons["Done"].tap()
        openTool("Blur")
        app.buttons["Add blur"].tap()
        XCTAssertTrue(app.buttons["Delete blur"].waitForExistence(timeout: 3))
        shot("blur")
        app.buttons["Done"].tap()
        openTool("Shapes")
        app.buttons["Add arrow"].tap()
        shot("arrow")
        app.buttons["Done"].tap()
        openTool("Sound")
        app.buttons["Fade in"].tap()
        app.sliders.firstMatch.adjust(toNormalizedSliderPosition: 0.4)
        shot("sound")
        app.buttons["Done"].tap()
        app.buttons["Play"].tap()
        XCTAssertTrue(wait(6) { self.time.now >= 2 }, "still plays with everything on")
        shot("playing")
    }

    func testTranscriptCutAndSpeed() {
        openTool("Transcript")
        let line = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Line number 3,'")).firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 5))
        line.tap()
        shot("transcript")
        app.buttons["Done"].tap()
        XCTAssertTrue(wait(4) { self.time.length <= 116 }, "the sentence is cut (\(time.length))")
        let cut = time.length
        openTool("Speed")
        app.buttons["2× speed"].tap()
        app.buttons["Done"].tap()
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
        app.buttons["Done"].tap()
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
        app.buttons["Done"].tap()
        let length = time.length
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Save a copy"].waitForExistence(timeout: 4))
        shot("save-sheet")
        app.buttons["720p"].tap()
        app.buttons["Save"].firstMatch.tap()
        if app.staticTexts["Saving your edit"].waitForExistence(timeout: 4) {
            shot("saving")
            app.buttons["Cancel"].tap()
            XCTAssertTrue(app.staticTexts["Saving stopped"].waitForExistence(timeout: 4))
            app.buttons["Back to the editor"].tap()
        }
        XCTAssertTrue(wait(4) { self.time.length == length }, "the edits are still there")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Save a copy"].waitForExistence(timeout: 4))
        app.buttons["Save"].firstMatch.tap()
        // Leave the app while it saves, and come back.
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        XCUIDevice.shared.press(.home)
        RunLoop.current.run(until: Date().addingTimeInterval(4))
        app.activate()
        XCTAssertTrue(app.staticTexts["Saved as a new recording"].waitForExistence(timeout: 180), "the save carries on and finishes")
        shot("saved")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["live.saved"].waitForExistence(timeout: 6))
        XCTAssertEqual(app.staticTexts["live.saved"].label, "1 saved")
        XCTAssertTrue(wait(6) { self.app.staticTexts["live.draft"].label == "No draft" }, "a saved edit leaves no draft")
    }
}
