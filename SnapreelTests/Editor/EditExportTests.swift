import AVFoundation
import XCTest
@testable import Snapreel

/// Saving: what the file holds, and what happens when saving is stopped, interrupted or repeated.
@MainActor
final class EditExportTests: XCTestCase {
    private func clip(_ name: String, duration: Double = 10, _ change: (inout TestMedia.Spec) -> Void = { _ in }) async throws
        -> (url: URL, times: [CMTime], library: Library, id: UUID) {
        var spec = TestMedia.Spec()
        spec.name = name
        spec.duration = duration
        spec.audioDuration = duration
        change(&spec)
        let (url, times) = try await TestMedia.make(spec)
        let (library, id) = try await TestMedia.library(with: url)
        return (url, times, library, id)
    }

    /// Only the end changes: the recording's own data is copied, in no time and without loss.
    func testTrimmingTheEndCopies() async throws {
        let (url, times, library, id) = try await clip("copy20", duration: 20)
        var recipe = EditRecipe.original(sourceID: id, duration: 20)
        recipe.cut(afterOutput: 12)
        let started = CACurrentMediaTime()
        let (video, file) = try await TestMedia.export(recipe, library: library)
        perf("copy", "trim the end of 20 s", (CACurrentMediaTime() - started) * 1_000, "ms")
        XCTAssertEqual(video.duration, 12, accuracy: 0.1)
        let frames = try await TestMedia.readFrames(file)
        XCTAssertTrue(frames.allSatisfy { $0.index != nil })
        for (frame, time) in zip(frames, times).prefix(200) { XCTAssertEqual(frame.time, time.seconds, accuracy: 0.002) }
        XCTAssertLessThan(TestMedia.fileSize(file), TestMedia.fileSize(url))
    }

    /// Half speed and double speed keep the picture and sound together.
    func testSpeedKeepsPictureAndSoundTogether() async throws {
        for speed in [0.5, 1.5, 2.0] {
            let (_, times, library, id) = try await clip("vfr10")
            var recipe = EditRecipe.original(sourceID: id, duration: 10)
            recipe.setSpeed(speed)
            let (video, file) = try await TestMedia.export(recipe, library: library)
            XCTAssertEqual(video.duration, 10 / speed, accuracy: 0.1, "\(speed)")
            var worst = 0.0
            for frame in try await TestMedia.readFrames(file) {
                guard let index = frame.index, index < times.count else { continue }
                worst = max(worst, abs(times[index].seconds / speed - frame.time))
            }
            // A frame stands for at most 3/60 s, then may be repeated where it stands longer.
            perf("speed \(speed)", "worst picture error", worst * 1_000, "ms")
            XCTAssertLessThan(worst, 0.12 / min(1, speed), "\(speed)")
            let sound = try await TestMedia.beeps(file)
            XCTAssertEqual(sound.starts.count, 10, "\(speed)")
            for (index, start) in sound.starts.enumerated() {
                XCTAssertEqual(start, Double(index) / speed, accuracy: 0.12, "\(speed) beep \(index)")
            }
        }
    }

    /// Sound that starts late (the owner's recording: 16 ms; here half a second).
    func testSoundStartingLateStaysInPlace() async throws {
        let (_, _, library, id) = try await clip("late-sound") { $0.audioStart = 0.5; $0.audioDuration = 9 }
        var recipe = EditRecipe.original(sourceID: id, duration: 10)
        recipe.remove(source: 4.7...5.3)
        let (_, file) = try await TestMedia.export(recipe, library: library)
        let sound = try await TestMedia.beeps(file)
        // Beeps at 0.5, 1.5, 2.5, 3.5, 4.5; then 5.5 on, 0.6 s earlier.
        let wanted = [0.5, 1.5, 2.5, 3.5, 4.5, 4.9, 5.9, 6.9, 7.9]
        XCTAssertEqual(sound.starts.count, wanted.count, "\(sound.starts)")
        for (start, expected) in zip(sound.starts, wanted) { XCTAssertEqual(start, expected, accuracy: 0.06) }
    }

    func testNoiseReductionStaysInStep() async throws {
        let (_, _, library, id) = try await clip("late-sound") { $0.audioStart = 0.5; $0.audioDuration = 9 }
        var recipe = EditRecipe.original(sourceID: id, duration: 10)
        recipe.audio.reducesNoise = true
        recipe.remove(source: 8...9)
        let (_, file) = try await TestMedia.export(recipe, library: library)
        let sound = try await TestMedia.beeps(file)
        XCTAssertGreaterThanOrEqual(sound.starts.count, 7, "\(sound.starts)")
        for start in sound.starts.prefix(7) {
            XCTAssertEqual((start - 0.5).truncatingRemainder(dividingBy: 1), 0, accuracy: 0.08, "\(sound.starts)")
        }
    }

    func testSilentVideo() async throws {
        let (_, _, library, id) = try await clip("silent", duration: 6) { $0.audioDuration = nil }
        var recipe = EditRecipe.original(sourceID: id, duration: 6)
        recipe.remove(source: 1...2)
        recipe.audio.volume = 0.5
        recipe.audio.fadeIn = true
        let (video, file) = try await TestMedia.export(recipe, library: library)
        XCTAssertEqual(video.duration, 5, accuracy: 0.08)
        let tracks = try await AVURLAsset(url: file).loadTracks(withMediaType: .audio)
        XCTAssertTrue(tracks.isEmpty)
    }

    /// A voice recording: trim, speed, volume.
    func testVoiceRecording() async throws {
        let (url, _, _, _) = try await clip("vfr10")
        let m4a = TestMedia.folder.appendingPathComponent("voice.m4a")
        if !FileManager.default.fileExists(atPath: m4a.path) {
            let session = AVAssetExportSession(asset: AVURLAsset(url: url), presetName: AVAssetExportPresetAppleM4A)!
            session.outputURL = m4a
            session.outputFileType = .m4a
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                session.exportAsynchronously { continuation.resume() }
            }
        }
        let (library, id) = try await TestMedia.library(with: m4a, kind: .audio)
        var recipe = EditRecipe.original(sourceID: id, duration: library.video(id)!.duration)
        recipe.remove(source: 2.5...4.5)
        recipe.audio.fadeOut = true
        let (video, file) = try await TestMedia.export(recipe, library: library)
        XCTAssertEqual(file.pathExtension, "m4a")
        XCTAssertEqual(video.duration, recipe.outputDuration, accuracy: 0.1)
        let sound = try await TestMedia.beeps(file)
        XCTAssertEqual(sound.starts.first ?? 1, 0, accuracy: 0.06)
        XCTAssertGreaterThanOrEqual(sound.starts.count, 7)
    }

    func testHEVCSource() async throws {
        let (_, times, library, id) = try await clip("hevc", duration: 5) { $0.codec = .hevc }
        var recipe = EditRecipe.original(sourceID: id, duration: 5)
        recipe.remove(source: 1...2)
        let (video, file) = try await TestMedia.export(recipe, library: library)
        XCTAssertEqual(video.duration, 4, accuracy: 0.08)
        let track = try await AVURLAsset(url: file).loadTracks(withMediaType: .video)[0]
        let format = try await track.load(.formatDescriptions)[0]
        XCTAssertEqual(CMFormatDescriptionGetMediaSubType(format), kCMVideoCodecType_H264, "edits are H.264, which everything plays")
        let first = try await TestMedia.readFrames(file).first { $0.time > 1.2 }
        let source = times[first?.index ?? 0].seconds
        XCTAssertEqual(source, recipe.sourceTime(forOutput: first?.time ?? 0), accuracy: 0.07)
    }

    /// Edits of edits stay right: cut, save, then cut the saved one.
    func testEditOfAnEdit() async throws {
        let (_, times, library, id) = try await clip("vfr10")
        var recipe = EditRecipe.original(sourceID: id, duration: 10)
        recipe.remove(source: 2...4)
        let (first, _) = try await TestMedia.export(recipe, library: library)
        XCTAssertEqual(first.editedFrom, id)
        var again = EditRecipe.original(sourceID: first.id, duration: first.duration)
        again.remove(source: 3...5)
        let (second, file) = try await TestMedia.export(again, library: library)
        XCTAssertEqual(second.duration, 6, accuracy: 0.1)
        for frame in try await TestMedia.readFrames(file) where frame.time > 3.1 {
            guard let index = frame.index else { continue }
            XCTAssertEqual(times[index].seconds, frame.time + 4, accuracy: 0.1)
        }
        let sound = try await TestMedia.beeps(file)
        XCTAssertEqual(sound.length, second.duration, accuracy: 0.1)
    }

    /// Cancel at any moment leaves nothing behind.
    func testCancelLeavesNothing() async throws {
        let (_, _, library, id) = try await clip("minute", duration: 60)
        var recipe = EditRecipe.original(sourceID: id, duration: 60)
        recipe.remove(source: 1...2)
        for delay in [0.0, 0.15, 1.2] {
            let source = library.video(id)!
            let output = EditRenderer.shared.begin(recipe: recipe, source: source, library: library)
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            EditRenderer.shared.cancel(output)
            let name = library.video(output)?.fileName ?? ""
            RecordingSaver.shared.discard(output, library: library)
            await RecordingSaver.shared.waitUntilFinished(output)
            XCTAssertNil(library.video(output))
            XCTAssertFalse(EditRenderer.shared.isRendering(output))
            XCTAssertFalse(FileManager.default.fileExists(atPath: library.media.staging.appendingPathComponent(name).path))
            let folder = library.media.editFolder(id)
            let left = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            XCTAssertTrue(left.filter { $0.hasPrefix("saving-") }.isEmpty, "\(left)")
        }
    }

    /// Leaving the app in the middle pauses; coming back carries on and gives the same result.
    func testLeavingAndComingBackCarriesOn() async throws {
        let (_, times, library, id) = try await clip("minute", duration: 60)
        var recipe = EditRecipe.original(sourceID: id, duration: 60)
        recipe.remove(source: 1...2)
        let output = EditRenderer.shared.begin(recipe: recipe, source: library.video(id)!, library: library)
        var pauses = 0
        while pauses < 2 {
            try await Task.sleep(nanoseconds: 100_000_000)
            guard case .saving(let progress)? = library.video(output)?.state else { break }
            if progress > 0.2 + Double(pauses) * 0.25 {
                EditRenderer.shared.setBackground(true)
                try await Task.sleep(nanoseconds: 600_000_000)
                if case .saving(let before)? = library.video(output)?.state {
                    try await Task.sleep(nanoseconds: 800_000_000)
                    if case .saving(let after)? = library.video(output)?.state { XCTAssertEqual(after, before, accuracy: 0.02, "paused") }
                }
                EditRenderer.shared.setBackground(false)
                pauses += 1
            }
        }
        perf("resume", "times the save was interrupted", Double(pauses), "")
        while case .saving? = library.video(output)?.state { try await Task.sleep(nanoseconds: 100_000_000) }
        await RecordingSaver.shared.waitUntilFinished(output)
        let video = try XCTUnwrap(library.video(output))
        XCTAssertTrue(video.state.isReady, "\(video.state)")
        XCTAssertEqual(video.duration, 59, accuracy: 0.1)
        let frames = try await TestMedia.readFrames(library.fileURL(for: video))
        var worst = 0.0
        for frame in frames {
            guard let index = frame.index, index < times.count else {
                XCTFail("a broken frame at \(frame.time)")
                continue
            }
            worst = max(worst, abs(times[index].seconds - recipe.sourceTime(forOutput: frame.time + 0.002)))
        }
        perf("resume", "worst picture error", worst * 1_000, "ms")
        XCTAssertLessThan(worst, 0.08)
        let gaps = zip(frames.dropFirst(), frames).map { $0.time - $1.time }
        XCTAssertLessThan(gaps.max() ?? 1, 0.15, "a hole where a piece was joined")
        XCTAssertGreaterThan(gaps.min() ?? 0, 0.005, "two frames at one moment")
    }

    /// The app was closed halfway: the pieces already made are used.
    func testPiecesSurviveAClosedApp() async throws {
        let (_, _, library, id) = try await clip("minute", duration: 60)
        var recipe = EditRecipe.original(sourceID: id, duration: 60)
        recipe.remove(source: 1...2)
        let info = try await EditSource.load(library.fileURL(for: library.video(id)!))
        let folder = library.media.editFolder(id)
        let build = try await EditCompositionBuilder.build(recipe: recipe, source: info, editFolder: folder, cleanedAudio: nil, originalSound: true)
        let settings = EditExportSettings(recipe: recipe, picture: info.uprightSize, sourceBitRate: info.videoBitRate,
                                          frameRate: Double(info.frameRate), quality: .hd1080)
        func plan() -> EditExportPlan {
            EditExportPlan(id: UUID(), recipe: recipe, source: info, build: build, settings: settings,
                           workFolder: folder.appendingPathComponent("saving-test"), output: folder.appendingPathComponent("out.mp4"),
                           overlays: { _ in [] }, overlayTimes: [])
        }
        let first = EditExporter(plan: plan()) { _ in }
        let run = Task { try await first.run() }
        let piece = folder.appendingPathComponent("saving-test/piece-1.mov")
        for _ in 0..<600 where !FileManager.default.fileExists(atPath: piece.path) { try await Task.sleep(nanoseconds: 50_000_000) }
        first.cancel()
        _ = try? await run.value
        XCTAssertTrue(FileManager.default.fileExists(atPath: piece.path))
        let made = try FileManager.default.attributesOfItem(atPath: piece.path)[.modificationDate] as? Date
        var seen: [Double] = []
        let second = EditExporter(plan: plan()) { seen.append($0) }
        try await second.run()
        XCTAssertGreaterThan(seen.first ?? 0, 0.3, "starts where it stopped")
        XCTAssertNotNil(made)
        let length = try await AVURLAsset(url: folder.appendingPathComponent("out.mp4")).load(.duration).seconds
        XCTAssertEqual(length, 59, accuracy: 0.08)
        XCTAssertFalse(FileManager.default.fileExists(atPath: piece.path), "the pieces go once the file is there")
    }

    /// What is drawn lands where and when it was placed, and captions are never cut off.
    func testOverlaysLandInPlaceAndTime() async throws {
        let (_, _, library, id) = try await clip("vfr10")
        var recipe = EditRecipe.original(sourceID: id, duration: 10)
        recipe.texts = [EditText(text: "███", style: .plain, color: .green, center: CGPoint(x: 0.5, y: 0.8), scale: 2, start: 3, end: 6)]
        recipe.remove(source: 0...1)
        let (_, file) = try await TestMedia.export(recipe, library: library)
        func green(_ seconds: Double) async throws -> Bool {
            let color = try await TestMedia.color(file, at: seconds, x: 0.5, y: 0.8)
            return color.1 > color.0 + 0.25 && color.1 > color.2 + 0.1
        }
        let before = try await green(1.9), start = try await green(2.05), middle = try await green(4)
        let end = try await green(4.95), after = try await green(5.1)
        XCTAssertFalse(before)
        XCTAssertTrue(start)
        XCTAssertTrue(middle)
        XCTAssertTrue(end)
        XCTAssertFalse(after)
    }

    /// The colours of a saved edit are the recording's.
    func testColoursStayTheSame() async throws {
        let (url, _, library, id) = try await clip("vfr10")
        for drawn in [false, true] {
            var recipe = EditRecipe.original(sourceID: id, duration: 10)
            recipe.remove(source: 8...9)
            if drawn { recipe.blurs = [EditBlur(rect: CGRect(x: 0.4, y: 0.9, width: 0.1, height: 0.05), start: 0, end: 9)] }
            let (video, file) = try await TestMedia.export(recipe, library: library)
            for (x, y) in [(0.03, 0.01), (0.97, 0.01), (0.5, 0.08), (0.5, 0.5), (0.02, 0.6)] {
                let a = try await TestMedia.color(url, at: 5, x: x, y: y), b = try await TestMedia.color(file, at: 5, x: x, y: y)
                XCTAssertEqual(a.0, b.0, accuracy: 0.06, "drawn \(drawn) at \(x),\(y)")
                XCTAssertEqual(a.1, b.1, accuracy: 0.06, "drawn \(drawn) at \(x),\(y)")
                XCTAssertEqual(a.2, b.2, accuracy: 0.06, "drawn \(drawn) at \(x),\(y)")
            }
            library.delete(video.id)
        }
    }

    /// The player shows every orientation upright when it draws (crop, turn, blur).
    func testPreviewIsUprightForEveryOrientation() async throws {
        let w: CGFloat = 640, h: CGFloat = 360
        let turns: [(String, CGAffineTransform)] = [
            ("up", .identity),
            ("right", CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: h, ty: 0)),
            ("down", CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: w, ty: h)),
            ("left", CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: w)),
        ]
        for (name, transform) in turns {
            let (url, _, library, id) = try await clip("turn-\(name)", duration: 2) {
                $0.size = CGSize(width: w, height: h)
                $0.variableFrameRate = false
                $0.transform = transform
            }
            let info = try await EditSource.load(url)
            var recipe = EditRecipe.original(sourceID: id, duration: 2)
            recipe.blurs = [EditBlur(rect: CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1), start: 0, end: 2)]
            let build = try await EditCompositionBuilder.build(recipe: recipe, source: info, editFolder: library.media.editFolder(id),
                                                               cleanedAudio: nil, originalSound: true)
            let generator = AVAssetImageGenerator(asset: build.composition)
            generator.videoComposition = EditCompositionBuilder.previewVideoComposition(recipe: recipe, source: info, build: build, fullFrame: false)
            XCTAssertNotNil(generator.videoComposition)
            let got = try await generator.image(at: CMTime(seconds: 1.2, preferredTimescale: 600)).image
            let wanted = try await TestMedia.image(url, at: 1.2)
            for (x, y) in [(0.02, 0.02), (0.98, 0.02), (0.02, 0.98), (0.98, 0.98)] {
                let a = TestMedia.color(wanted, x: x, y: y), b = TestMedia.color(got, x: x, y: y)
                XCTAssertEqual(b.0, a.0, accuracy: 0.2, "\(name) red at \(x),\(y)")
                XCTAssertEqual(b.2, a.2, accuracy: 0.2, "\(name) blue at \(x),\(y)")
            }
        }
    }
}
