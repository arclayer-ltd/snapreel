import AVFoundation
import XCTest
@testable import Snapreel

/// The recipe's arithmetic: the two clocks, cutting, trimming, splitting, speed, what follows what.
final class EditRecipeTests: XCTestCase {
    private func recipe(_ duration: Double = 60) -> EditRecipe { .original(sourceID: UUID(), duration: duration) }

    // MARK: - Clocks

    func testClocksAreInverseAcrossCutsAndSpeeds() {
        var r = recipe()
        r.remove(source: 10...20)
        r.remove(source: 35...36.5)
        r.setSpeed(2, segment: r.segments[1].id)
        XCTAssertEqual(r.outputDuration, 10 + 15.0 / 2 + 23.5, accuracy: 1e-9)
        for step in 0..<400 {
            let t = r.outputDuration * Double(step) / 400
            let source = r.sourceTime(forOutput: t)
            XCTAssertEqual(r.outputTime(forSource: source) ?? -1, t, accuracy: 1e-6)
        }
    }

    func testCutMomentsHaveNoOutputTime() {
        var r = recipe()
        r.remove(source: 10...20)
        XCTAssertNil(r.outputTime(forSource: 15))
        XCTAssertEqual(r.nearestOutputTime(forSource: 15), 10, accuracy: 1e-9)
        XCTAssertEqual(r.nearestOutputTime(forSource: 59.9), 49.9, accuracy: 1e-9)
    }

    func testOutputRangesAndKeptFraction() {
        var r = recipe()
        r.remove(source: 10...20)
        let pieces = r.outputRanges(forSource: 8...24)
        XCTAssertEqual(pieces.count, 2)
        XCTAssertEqual(pieces[0].lowerBound, 8, accuracy: 1e-9)
        XCTAssertEqual(pieces[1].upperBound, 14, accuracy: 1e-9)
        XCTAssertEqual(r.keptFraction(ofSource: 8...24), 6.0 / 16, accuracy: 1e-9)
        XCTAssertEqual(r.keptFraction(ofSource: 11...19), 0, accuracy: 1e-9)
        XCTAssertEqual(r.keptFraction(ofSource: 0...60), 50.0 / 60, accuracy: 1e-9)
    }

    func testKeptFractionMatchesPlainSumWithManySections() {
        var r = recipe(600)
        for index in 0..<150 { r.remove(source: (Double(index) * 4 + 1)...(Double(index) * 4 + 1.6)) }
        for step in 0..<300 {
            let a = Double(step) * 2
            let range = a...(a + 1.7)
            let plain = r.segments.reduce(0.0) { $0 + max(0, min(range.upperBound, $1.end) - max(range.lowerBound, $1.start)) } / 1.7
            XCTAssertEqual(r.keptFraction(ofSource: range), min(1, plain), accuracy: 1e-9)
        }
    }

    // MARK: - Untouched

    func testOriginalIsUntouchedAndChangesAreNot() {
        var r = recipe()
        XCTAssertTrue(r.isUntouched)
        r.quality = .hd720
        XCTAssertTrue(r.isUntouched, "the export quality isn't an edit")
        r.split(atOutput: 10)
        XCTAssertFalse(r.isUntouched)
        var sound = recipe()
        sound.audio.volume = 0.5
        XCTAssertFalse(sound.isUntouched)
    }

    func testSameEditIgnoresIdsAndDates() {
        let id = UUID()
        var a = EditRecipe.original(sourceID: id, duration: 60)
        var b = EditRecipe.original(sourceID: id, duration: 60)
        a.remove(source: 5...6)
        b.remove(source: 5...6)
        b.updatedAt = .distantFuture
        XCTAssertTrue(a.sameEdit(as: b))
        b.remove(source: 7...8)
        XCTAssertFalse(a.sameEdit(as: b))
    }

    func testDraftSurvivesSavingAndLoading() throws {
        var r = recipe()
        r.remove(source: 5...6)
        r.texts = [EditText(text: "Hi", start: 1, end: 4)]
        r.voiceClips = [EditVoiceClip(fileName: "a.m4a", start: 3, duration: 2, lead: 0.1)]
        let data = try JSONEncoder().encode(r)
        XCTAssertEqual(try JSONDecoder().decode(EditRecipe.self, from: data), r)
        // A draft from build 47 has no `lead`.
        let old = Data(#"{"fileName":"a.m4a","start":1,"duration":2,"id":"33333333-0000-4000-8000-000000000001"}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(EditVoiceClip.self, from: old).lead)
    }

    func testRepairedDraftFitsTheRecording() {
        var r = recipe(100)
        r.remove(source: 20...30)
        r.voiceClips = [EditVoiceClip(fileName: "gone.m4a", start: 1, duration: 2), EditVoiceClip(fileName: "here.m4a", start: 3, duration: 2)]
        let fixed = r.repaired(duration: 50) { $0 == "here.m4a" }
        XCTAssertEqual(fixed.sourceDuration, 50)
        XCTAssertEqual(fixed.segments.last?.end ?? 0, 50, accuracy: 1e-9)
        XCTAssertEqual(fixed.voiceClips.map(\.fileName), ["here.m4a"])
        XCTAssertFalse(recipe(10).repaired(duration: 4) { _ in true }.segments.isEmpty)
    }

    // MARK: - Split, delete, trim

    func testSplitKeepsTheLengthAndPlaysAsOne() {
        var r = recipe()
        XCTAssertTrue(r.split(atOutput: 25))
        XCTAssertEqual(r.segments.count, 2)
        XCTAssertEqual(r.outputDuration, 60, accuracy: 1e-9)
        XCTAssertEqual(r.playedSegments.count, 1, "a split that cut nothing must not cut the playback")
        XCTAssertFalse(r.split(atOutput: 25.05), "too close to an edge")
        r.setSpeed(2, segment: r.segments[0].id)
        XCTAssertEqual(r.playedSegments.count, 2)
    }

    func testDeleteClosesTheGapAndNeverEmpties() {
        var r = recipe()
        r.split(atOutput: 20)
        r.removeSegment(r.segments[0].id)
        XCTAssertEqual(r.outputDuration, 40, accuracy: 1e-9)
        XCTAssertEqual(r.sourceTime(forOutput: 0), 20, accuracy: 1e-9)
        r.removeSegment(r.segments[0].id)
        XCTAssertEqual(r.segments.count, 1)
        r.remove(source: 0...60)
        XCTAssertEqual(r.segments.count, 1)
    }

    func testTrimStaysBetweenNeighbours() {
        var r = recipe()
        r.remove(source: 20...30)
        let second = r.segments[1].id
        r.trim(second, start: 5)
        XCTAssertEqual(r.segments[1].start, 20, accuracy: 1e-9)
        r.trim(second, start: 100)
        XCTAssertEqual(r.segments[1].outputLength, 0.2, accuracy: 1e-9)
        r.trim(r.segments[0].id, end: 2)
        XCTAssertEqual(r.segments[0].end, 2, accuracy: 1e-9)
        r.trim(r.segments[0].id, end: 25)
        XCTAssertEqual(r.segments[0].end, r.segments[1].start, accuracy: 25)
        XCTAssertLessThanOrEqual(r.segments[0].end, r.segments[1].start + 1e-9)
    }

    func testStartAndEndHere() {
        var r = recipe()
        XCTAssertTrue(r.cut(beforeOutput: 12))
        XCTAssertEqual(r.segments[0].start, 12, accuracy: 1e-9)
        XCTAssertTrue(r.cut(afterOutput: 30))
        XCTAssertEqual(r.segments.last?.end ?? 0, 42, accuracy: 1e-9)
        XCTAssertEqual(r.outputDuration, 30, accuracy: 1e-9)
        XCTAssertFalse(r.cut(beforeOutput: 0))
        XCTAssertFalse(r.cut(afterOutput: 30))
        XCTAssertFalse(r.cut(beforeOutput: 29.9), "something has to be left")
    }

    func testSpeed() {
        var r = recipe()
        r.setSpeed(1.5)
        XCTAssertEqual(r.outputDuration, 40, accuracy: 1e-9)
        XCTAssertEqual(r.sourceTime(forOutput: 10), 15, accuracy: 1e-9)
        r.remove(source: 15...30)
        XCTAssertEqual(r.outputDuration, 30, accuracy: 1e-9)
        r.keep(source: 15...30)
        XCTAssertEqual(r.outputDuration, 40, accuracy: 1e-9, "what comes back plays at the speed of what it joins")
    }

    func testRemoveThenKeepGivesTheRecordingBack() {
        var r = recipe()
        for index in 0..<20 { r.remove(source: (Double(index) * 3 + 0.7)...(Double(index) * 3 + 1.1)) }
        for index in 0..<20 { r.keep(source: (Double(index) * 3 + 0.7)...(Double(index) * 3 + 1.1)) }
        XCTAssertEqual(r.outputDuration, 60, accuracy: 0.001)
        XCTAssertEqual(r.playedSegments.count, 1)
    }

    // MARK: - What follows the content

    func testOverlaysFollowCutsTrimsAndSpeed() {
        var r = recipe()
        r.texts = [EditText(text: "A", start: 30, end: 34)]
        r.blurs = [EditBlur(start: 40, end: 42)]
        r.voiceClips = [EditVoiceClip(fileName: "v", start: 50, duration: 3)]
        r.thumbnailTime = 45
        r.remove(source: 0...10)
        XCTAssertEqual(r.texts[0].start, 20, accuracy: 0.01)
        XCTAssertEqual(r.blurs[0].end, 32, accuracy: 0.01)
        XCTAssertEqual(r.voiceClips[0].start, 40, accuracy: 0.01)
        XCTAssertEqual(r.thumbnailTime ?? 0, 35, accuracy: 0.01)
        r.setSpeed(2)
        XCTAssertEqual(r.texts[0].start, 10, accuracy: 0.01)
        XCTAssertEqual(r.texts[0].end, 12, accuracy: 0.01)
        XCTAssertEqual(r.sourceTime(forOutput: r.blurs[0].start), 40, accuracy: 0.05)
    }

    func testBlurGoesWithItsMomentButTextStays() {
        var r = recipe()
        r.texts = [EditText(text: "Title", start: 2, end: 5)]
        r.blurs = [EditBlur(start: 2, end: 5)]
        r.remove(source: 0...10)
        XCTAssertTrue(r.blurs.isEmpty)
        XCTAssertEqual(r.texts.count, 1)
        XCTAssertEqual(r.texts[0].start, 0, accuracy: 0.01)
        XCTAssertEqual(r.texts[0].end, 3, accuracy: 0.01)
    }

    func testOverlayOverACutShrinks() {
        var r = recipe()
        r.blurs = [EditBlur(start: 10, end: 20)]
        r.remove(source: 12...15)
        XCTAssertEqual(r.blurs[0].start, 10, accuracy: 0.01)
        XCTAssertEqual(r.blurs[0].end, 17, accuracy: 0.01)
        r.keep(source: 12...15)
        XCTAssertEqual(r.blurs[0].end, 20, accuracy: 0.01)
    }

    func testOverlaysEndInsideTheVideo() {
        var r = recipe()
        r.texts = [EditText(text: "A", start: 55, end: 60)]
        r.cut(afterOutput: 57)
        XCTAssertLessThanOrEqual(r.texts[0].end, r.outputDuration + 1e-9)
        XCTAssertGreaterThanOrEqual(r.texts[0].start, 0)
    }

    // MARK: - Captions

    private func transcript() -> Transcript {
        let words = ["So", "um", "this", "is", "the", "new", "checkout"]
        let timed = words.enumerated().map { TranscriptWord(text: $1, start: 1 + Double($0) * 0.5, duration: 0.4) }
        return Transcript(videoID: UUID(), localeIdentifier: "en", segments: [
            TranscriptSegment(start: 1, duration: 3.5, text: words.joined(separator: " "), words: timed),
            TranscriptSegment(start: 6, duration: 3, text: "Second line", words: nil),
        ], createdAt: Date(), summary: nil)
    }

    func testCaptionsDropCutWordsAndCanBeHiddenAndEmptied() {
        let t = transcript()
        var r = recipe()
        r.captions = EditCaptions()
        r.remove(source: 1.48...1.95)
        XCTAssertEqual(r.captionLines(from: t)[0].text, "So this is the new checkout")
        let key = t.segments[1].id.uuidString
        r.captions?.edits[key] = "   "
        let line = r.captionLines(from: t)[1]
        XCTAssertTrue(line.isHidden, "an emptied line is hidden, not lost")
        XCTAssertEqual(line.text, "Second line")
        r.remove(source: 5.5...9.5)
        XCTAssertEqual(r.captionLines(from: t).count, 1)
    }

    func testLongCaptionsAreShownInPieces() {
        let text = (0..<40).map { "word\($0)" }.joined(separator: " ")
        let line = EditCaptionLine(id: "a", text: text, start: 10, end: 20, isHidden: false)
        let pieces = line.pieces(limit: 59)
        XCTAssertGreaterThan(pieces.count, 3)
        XCTAssertEqual(pieces.map(\.text).joined(separator: " "), text)
        XCTAssertTrue(pieces.allSatisfy { $0.text.count <= 66 })
        XCTAssertEqual(pieces.first?.start ?? 0, 10, accuracy: 1e-9)
        XCTAssertEqual(pieces.last?.end ?? 0, 20, accuracy: 1e-9)
        for (a, b) in zip(pieces, pieces.dropFirst()) { XCTAssertEqual(a.end, b.start, accuracy: 1e-6) }
        XCTAssertEqual(line.pieces(limit: 1_000).count, 1)
    }

    func testRetimedTranscriptFollowsTheEdit() {
        let t = transcript()
        var r = recipe()
        r.remove(source: 0...0.5)
        r.setSpeed(2)
        let moved = r.retimedTranscript(t, for: UUID())
        XCTAssertEqual(moved.segments[0].start, 0.25, accuracy: 0.01)
        XCTAssertEqual(moved.segments[1].start, 2.75, accuracy: 0.01)
    }

    func testFillers() {
        let found = EditFillerFinder.find(in: transcript())
        XCTAssertEqual(found.map(\.text), ["um"])
        XCTAssertEqual(found[0].start, 1.5, accuracy: 1e-9)
    }

    // MARK: - Picture and file size

    func testRenderSizeIsEvenAndNeverLarger() {
        var r = recipe()
        let source = CGSize(width: 886, height: 1918)
        XCTAssertEqual(r.renderSize(source: source, quality: .original), source)
        XCTAssertEqual(r.renderSize(source: source, quality: .hd1080), source)
        let small = r.renderSize(source: source, quality: .hd720)
        XCTAssertEqual(small.width, 720)
        XCTAssertEqual(Int(small.height) % 2, 0)
        r.crop.rect = CGRect(x: 0.1, y: 0.1, width: 0.333, height: 0.777)
        r.quarterTurns = 1
        for quality in ExportQuality.allCases {
            let size = r.renderSize(source: source, quality: quality)
            XCTAssertEqual(Int(size.width) % 2, 0)
            XCTAssertEqual(Int(size.height) % 2, 0)
        }
    }

    func testGeometryRoundTrips() {
        for turns in 0..<4 {
            for flipped in [false, true] {
                let geometry = EditFrameGeometry(quarterTurns: turns, flipped: flipped)
                let rect = CGRect(x: 0.1, y: 0.25, width: 0.4, height: 0.3)
                let back = geometry.toSource(geometry.toDisplay(rect))
                XCTAssertEqual(back.minX, rect.minX, accuracy: 1e-9)
                XCTAssertEqual(back.height, rect.height, accuracy: 1e-9)
            }
        }
    }

    /// The owner's recording: 8:50, 886x1918, 2.5 Mbit/s.
    func testSavedSizeIsCloseToTheRecordingsOwn() {
        let r = recipe(530)
        let source = CGSize(width: 886, height: 1918)
        for quality in ExportQuality.allCases {
            let settings = EditExportSettings(recipe: r, picture: source, sourceBitRate: 2_494_377, frameRate: 37.1, quality: quality)
            let megabytes = Double(EditEstimate.bytes(recipe: r, settings: settings)) / 1_000_000
            XCTAssertLessThan(megabytes, 230, "\(quality)")
            XCTAssertGreaterThan(megabytes, 80, "\(quality)")
        }
        let low = EditExportSettings(recipe: r, picture: source, sourceBitRate: 2_494_377, frameRate: 37.1, quality: .hd720)
        let high = EditExportSettings(recipe: r, picture: source, sourceBitRate: 2_494_377, frameRate: 37.1, quality: .original)
        XCTAssertLessThan(low.videoBitRate, high.videoBitRate)
        let unknown = EditExportSettings(recipe: r, picture: source, sourceBitRate: 0, frameRate: 30, quality: .hd1080)
        XCTAssertGreaterThan(unknown.videoBitRate, 1_000_000)
    }

    func testSpaceCheckCountsTheTemporaryCopy() {
        XCTAssertTrue(EditEstimate.hasRoom(for: 200_000_000, available: 1_600_000_000))
        XCTAssertFalse(EditEstimate.hasRoom(for: 200_000_000, available: 600_000_000))
    }
}
