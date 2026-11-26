import AVFoundation
import XCTest
@testable import Snapreel

/// The faults found in the 25 Nov 2026 audit, each as a test that fails on the build 47 editor.
@MainActor
final class EditorFaultTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SNAPREEL_EDITOR_LONG"] == "1",
                          "Saves real files for minutes: run by the editor-tests job (ios.yml editor_tests)")
    }

    func testUntouchedRecordingIsNotDirty() {
        let recipe = EditRecipe.original(sourceID: UUID(), duration: 60)
        XCTAssertTrue(recipe.isUntouched, "a recording nobody touched counts as edited")
    }

    /// A 37-a-second screen recording must not be resampled to 37 even frames.
    func testUnevenFramesKeepTheirTimes() async throws {
        var spec = TestMedia.Spec()
        spec.name = "vfr10"
        let (url, times) = try await TestMedia.make(spec)
        let (library, id) = try await TestMedia.library(with: url)
        var recipe = EditRecipe.original(sourceID: id, duration: 10)
        recipe.remove(source: 4...6)
        let (_, file) = try await TestMedia.export(recipe, library: library)
        let frames = try await TestMedia.readFrames(file)
        var wrong = 0
        var worst = 0.0
        for frame in frames {
            guard let index = frame.index, index < times.count else {
                wrong += 1
                continue
            }
            // The source frame that belongs on screen at this output time.
            let sourceTime = recipe.sourceTime(forOutput: frame.time + 0.002)
            let expected = times.lastIndex { $0.seconds <= sourceTime + 0.001 } ?? 0
            if abs(index - expected) > 1 { wrong += 1 }
            worst = max(worst, abs(times[index].seconds - times[expected].seconds))
        }
        let gaps = zip(frames.dropFirst(), frames).map { $0.time - $1.time }
        let onGrid = gaps.filter { abs($0 * 60 - ($0 * 60).rounded()) < 0.1 }.count
        let share = Double(onGrid) / Double(max(1, gaps.count))
        perf("vfr", "frames in the saved file", Double(frames.count), "frames")
        perf("vfr", "frames showing the wrong moment", Double(wrong), "frames")
        perf("vfr", "worst frame time error", worst * 1_000, "ms")
        perf("vfr", "frame gaps on the recording's 60 Hz grid", share * 100, "%")
        XCTAssertEqual(wrong, 0)
        XCTAssertGreaterThan(share, 0.97, "frames fall between the recording's own frame times")
    }

    /// A blur must be there from its first moment even when the picture isn't moving (passwords).
    func testBlurStartsOnTimeOverAStillPicture() async throws {
        var spec = TestMedia.Spec()
        spec.name = "still10"
        spec.stillAt = 3
        spec.stillLength = 4
        let (url, _) = try await TestMedia.make(spec)
        let (library, id) = try await TestMedia.library(with: url)
        var recipe = EditRecipe.original(sourceID: id, duration: 10)
        recipe.blurs = [EditBlur(rect: CGRect(x: 0, y: 0, width: 0.2, height: 0.1), start: 4, end: 6)]
        let (_, file) = try await TestMedia.export(recipe, library: library)
        let early = try await cornerSharpness(file, at: 3.8)
        let covered = try await cornerSharpness(file, at: 4.2)
        let late = try await cornerSharpness(file, at: 6.3)
        perf("blur", "edge sharpness before", early, "0-1")
        perf("blur", "edge sharpness during", covered, "0-1")
        perf("blur", "edge sharpness after", late, "0-1")
        XCTAssertLessThan(covered, early * 0.5, "the blur isn't there when it should start")
        XCTAssertGreaterThan(late, early * 0.8, "the blur is still there after it should end")
    }

    /// How sharp the red corner square's right edge is (it ends at 10% of the width).
    private func cornerSharpness(_ file: URL, at seconds: Double) async throws -> Double {
        let image = try await TestMedia.image(file, at: seconds)
        return abs(TestMedia.color(image, x: 0.092, y: 0.02).1 - TestMedia.color(image, x: 0.108, y: 0.02).1)
    }

    /// Camera recordings are stored sideways or upside down and turned when shown.
    func testEveryOrientationStaysUpright() async throws {
        let w: CGFloat = 640, h: CGFloat = 360
        let turns: [(String, CGAffineTransform)] = [
            ("up", .identity),
            ("right", CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: h, ty: 0)),
            ("down", CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: w, ty: h)),
            ("left", CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: w)),
            // A turn without its move, as landscape screen recordings up to build 47 have.
            ("unplaced", CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 0, ty: 0)),
        ]
        for (name, transform) in turns {
            var spec = TestMedia.Spec()
            spec.name = "turn-\(name)"
            spec.duration = 2
            spec.audioDuration = 2
            spec.size = CGSize(width: w, height: h)
            spec.variableFrameRate = false
            spec.transform = transform
            let (url, _) = try await TestMedia.make(spec)
            let (library, id) = try await TestMedia.library(with: url)
            // (The unplaced one shows as the "right" one does.)
            let shown = name == "unplaced" ? TestMedia.folder.appendingPathComponent("turn-right.mov") : url
            let wanted = try await TestMedia.image(shown, at: 1.2)
            for drawn in [false, true] {
                var recipe = EditRecipe.original(sourceID: id, duration: 2)
                recipe.remove(source: 0...0.5)
                if drawn { recipe.blurs = [EditBlur(rect: CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1), start: 0, end: 1.5)] }
                let (video, file) = try await TestMedia.export(recipe, library: library)
                let got = try await TestMedia.image(file, at: 0.7)
                XCTAssertEqual(Double(got.width) / Double(got.height), Double(wanted.width) / Double(wanted.height), accuracy: 0.01)
                for (x, y) in [(0.02, 0.02), (0.98, 0.02), (0.02, 0.98), (0.98, 0.98)] {
                    let a = TestMedia.color(wanted, x: x, y: y), b = TestMedia.color(got, x: x, y: y)
                    XCTAssertEqual(b.0, a.0, accuracy: 0.25, "\(name) drawn \(drawn) red at \(x),\(y)")
                    XCTAssertEqual(b.2, a.2, accuracy: 0.25, "\(name) drawn \(drawn) blue at \(x),\(y)")
                }
                library.delete(video.id)
            }
        }
    }

    /// Sound that stops before the picture: cuts stay in sync and the file keeps its full length.
    func testSoundShorterThanPicture() async throws {
        var spec = TestMedia.Spec()
        spec.name = "short-sound"
        spec.duration = 12
        spec.audioDuration = 7.4
        let (url, _) = try await TestMedia.make(spec)
        let (library, id) = try await TestMedia.library(with: url)
        var recipe = EditRecipe.original(sourceID: id, duration: 12)
        recipe.remove(source: 2.5...4.5)
        let (video, file) = try await TestMedia.export(recipe, library: library)
        let sound = try await TestMedia.beeps(file)
        // Beeps at 0, 1, 2 then 5, 6, 7 of the recording: 0, 1, 2, 3, 4, 5 of the edit.
        print("BEEPS|\(sound.starts)|\(sound.length)|\(video.duration)")
        XCTAssertEqual(video.duration, 10, accuracy: 0.08)
        XCTAssertEqual(sound.starts.count, 6)
        for (index, start) in sound.starts.enumerated() { XCTAssertEqual(start, Double(index), accuracy: 0.06) }
        XCTAssertEqual(sound.length, video.duration, accuracy: 0.1, "the saved sound is shorter than the picture")
    }

    /// A cut out of a picture that stands still: the frame that was up stays up, and the next one
    /// comes exactly when it should.
    func testCutsInsideAStillPicture() async throws {
        var spec = TestMedia.Spec()
        spec.name = "still10"
        spec.stillAt = 3
        spec.stillLength = 4
        let (url, times) = try await TestMedia.make(spec)
        let (library, id) = try await TestMedia.library(with: url)
        var recipe = EditRecipe.original(sourceID: id, duration: 10)
        recipe.remove(source: 1...1.5)
        recipe.remove(source: 4...5)
        recipe.remove(source: 5.2...6)
        recipe.remove(source: 8...8.4)
        let (video, file) = try await TestMedia.export(recipe, library: library)
        XCTAssertEqual(video.duration, recipe.outputDuration, accuracy: 0.05)
        var worst = 0.0
        for frame in try await TestMedia.readFrames(file) {
            guard let index = frame.index, index < times.count else {
                XCTFail("a broken frame at \(frame.time)")
                continue
            }
            let wanted = [-0.001, 0.001].map { offset -> Int in
                let source = recipe.sourceTime(forOutput: max(0, frame.time + offset))
                return times.lastIndex { $0.seconds <= source + 0.0005 } ?? 0
            }
            if !wanted.contains(index) {
                print("NOTE|frame \(index) at \(frame.time), wanted \(wanted)")
                worst = max(worst, abs(times[index].seconds - times[wanted[0]].seconds))
            }
        }
        perf("still", "worst picture error", worst * 1_000, "ms")
        XCTAssertEqual(worst, 0)
    }

    /// Fifty small cuts must not push the sound away from the picture.
    func testManyCutsStayInSync() async throws {
        var spec = TestMedia.Spec()
        spec.name = "minute"
        spec.duration = 60
        spec.audioDuration = 60
        let (url, times) = try await TestMedia.make(spec)
        let (library, id) = try await TestMedia.library(with: url)
        var recipe = EditRecipe.original(sourceID: id, duration: 60)
        for index in 0..<50 {
            let at = Double(index) * 1.1
            recipe.remove(source: (at + 0.4137)...(at + 0.6371))
        }
        let (video, file) = try await TestMedia.export(recipe, library: library)
        let sound = try await TestMedia.beeps(file)
        var worstSound = 0.0
        for second in 0..<60 {
            let beep = Double(second)...(Double(second) + 0.05)
            guard let expected = recipe.outputTime(forSource: Double(second) + 0.0005),
                  recipe.keptFraction(ofSource: beep) > 0.99 else { continue }
            let nearest = sound.starts.min { abs($0 - expected) < abs($1 - expected) } ?? 0
            if abs(nearest - expected) > 0.06 { print("NOTE|beep \(second) expected \(expected) found \(sound.starts.filter { abs($0 - expected) < 1.2 })") }
            worstSound = max(worstSound, abs(nearest - expected))
        }
        let frames = try await TestMedia.readFrames(file)
        var worstPicture = 0.0
        for frame in frames {
            guard let index = frame.index, index < times.count else { continue }
            // The frame that is on screen at that moment of the recording.
            let error = [-0.001, 0.001].map { offset -> Double in
                let source = recipe.sourceTime(forOutput: max(0, frame.time + offset))
                let wanted = times.lastIndex { $0.seconds <= source + 0.0005 } ?? 0
                return abs(times[index].seconds - times[wanted].seconds)
            }.min() ?? 0
            if error > 0.08 { print("NOTE|frame \(index) at \(frame.time) off by \(error)") }
            worstPicture = max(worstPicture, error)
        }
        perf("50 cuts", "worst sound error", worstSound * 1_000, "ms")
        perf("50 cuts", "worst picture error", worstPicture * 1_000, "ms")
        perf("50 cuts", "length error", (video.duration - recipe.outputDuration) * 1_000, "ms")
        XCTAssertLessThan(worstSound, 0.06)
        XCTAssertLessThan(worstPicture, 0.08)
        XCTAssertEqual(video.duration, recipe.outputDuration, accuracy: 0.08)
    }

    /// Testers, 26 Nov: a 9-minute video split at 2:00 and 4:17 with the middle part deleted never
    /// saved, at any size. Uses the test rig's own sample when the job fetched it (RIG_MEDIA).
    func testNineMinutesWithTheMiddleDeleted() async throws {
        executionTimeAllowance = 3_600
        var url: URL
        if let folder = ProcessInfo.processInfo.environment["RIG_MEDIA"],
           FileManager.default.fileExists(atPath: folder + "/9min.mp4") {
            url = URL(fileURLWithPath: folder + "/9min.mp4")
            print("NOTE|9 min middle deleted: the rig's sample")
        } else {
            url = try await TestMedia.long(minutes: 9, audioShortBy: 0)
            print("NOTE|9 min middle deleted: a made sample")
        }
        let (library, id) = try await TestMedia.library(with: url)
        guard let source = library.video(id) else { return XCTFail("no recording") }
        var recipe = EditRecipe.original(sourceID: id, duration: source.duration)
        XCTAssertTrue(recipe.split(atOutput: 120))
        XCTAssertTrue(recipe.split(atOutput: 257))
        let middle = try XCTUnwrap(recipe.segments.first { abs($0.start - 120) < 0.01 })
        recipe.removeSegment(middle.id)
        recipe.quality = .hd720
        print("NOTE|9 min middle deleted: \(recipe.segments.map { "\($0.start)-\($0.end)" }) = \(recipe.outputDuration) s")
        let started = CACurrentMediaTime()
        let (video, file) = try await TestMedia.export(recipe, library: library, timeout: 3_000)
        perf("9 min middle deleted", "export time", CACurrentMediaTime() - started, "s")
        perf("9 min middle deleted", "export file", Double(TestMedia.fileSize(file)) / 1_000_000, "MB")
        perf("9 min middle deleted", "length error", video.duration - recipe.outputDuration, "s")
        XCTAssertEqual(video.duration, recipe.outputDuration, accuracy: 0.1)
    }

    /// Testers, 26 Nov: on iOS 16 every edit with a text or an arrow failed when the file was
    /// finished (-11800 / -16364), with sound and without.
    func testTextAndArrowSave() async throws {
        for sound in [true, false] {
            var spec = TestMedia.Spec()
            spec.name = sound ? "overlay-sound" : "overlay-silent"
            spec.duration = 12
            spec.audioDuration = sound ? 12 : nil
            spec.variableFrameRate = false
            let (url, _) = try await TestMedia.make(spec)
            let (library, id) = try await TestMedia.library(with: url)
            var recipe = EditRecipe.original(sourceID: id, duration: 12)
            recipe.texts = [EditText(text: "Hi", start: 0, end: 3)]
            recipe.stickers = [EditSticker(kind: .arrow, center: CGPoint(x: 0.4, y: 0.3), rotation: 30, start: 1.5, end: 4.5)]
            let (video, _) = try await TestMedia.export(recipe, library: library)
            XCTAssertEqual(video.duration, 12, accuracy: 0.1, sound ? "with sound" : "without sound")
        }
    }

    /// The picture ends before the sound: no black picture at the end.
    func testPictureShorterThanSound() async throws {
        var spec = TestMedia.Spec()
        spec.name = "short-picture"
        spec.duration = 4
        spec.audioDuration = 6
        let (url, _) = try await TestMedia.make(spec)
        let length = try await AVURLAsset(url: url).load(.duration).seconds
        perf("short picture", "recording length", length, "s")
        let (library, id) = try await TestMedia.library(with: url)
        let recipe = EditRecipe.original(sourceID: id, duration: length)
        let (video, file) = try await TestMedia.export(recipe, library: library)
        let tracks = try await AVURLAsset(url: file).load(.tracks)
        for track in tracks {
            let range = try await track.load(.timeRange)
            print("NOTE|short picture \(track.mediaType.rawValue) \(range.start.seconds)-\(range.end.seconds)")
        }
        let frames = try await TestMedia.readFrames(file)
        print("NOTE|short picture frames \(frames.count), last at \(frames.suffix(4).map(\.time))")
        let end = try await TestMedia.color(file, at: max(0, video.duration - 0.1), x: 0.5, y: 0.5)
        XCTAssertGreaterThan(end.0 + end.1 + end.2, 0.3, "the end of the edit is black")
    }

    /// Text and blur belong to the moment they were placed on: cutting before them must not move
    /// a blur off the password it hides.
    func testOverlaysFollowTheirMoment() {
        let (library, id) = TestMedia.placeholder(duration: 60)
        let model = EditorModel(videoID: id, library: library, isStatic: true)
        model.apply { $0.blurs = [EditBlur(start: 30, end: 34)] }
        model.apply { $0.remove(source: 5...15) }
        let blur = model.recipe.blurs[0]
        XCTAssertEqual(model.recipe.sourceTime(forOutput: blur.start), 30, accuracy: 0.05)
        XCTAssertEqual(model.recipe.sourceTime(forOutput: blur.end), 34, accuracy: 0.05)
    }
}
