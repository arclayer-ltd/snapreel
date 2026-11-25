import UIKit
import XCTest
@testable import Snapreel

/// What happens between a tap on Share and its end, with the sheet and the slow parts replaced.
@MainActor
final class ShareFlowTests: XCTestCase {
    private var root: URL!
    private var library: Library!
    private var world: FakeWorld!
    private var flow: ShareFlow!
    private var ends = 0

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("flow-\(UUID().uuidString)", isDirectory: true)
        library = Library(storage: InMemoryStorage(mediaRoot: root))
        world = FakeWorld()
        flow = ShareFlow(ports: world.ports)
        ends = 0
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func addVideo(_ kind: RecordingKind = .screen, ext: String = "mp4", bytes: Int64 = 1_000,
                          state: VideoState = .ready, hasFile: Bool = true) -> Video {
        let id = UUID()
        let video = Video(id: id, title: "Demo", createdAt: Date(), kind: kind, fileName: "\(id.uuidString).\(ext)",
                          duration: 530, fileSize: bytes, pixelWidth: kind == .audio ? 0 : 886,
                          pixelHeight: kind == .audio ? 0 : 1918, state: state)
        library.add(video)
        if hasFile { try? Data(repeating: 1, count: 1_000).write(to: library.fileURL(for: video)) }
        return video
    }

    private func start(_ video: Video) {
        flow.start(video, library: library, onEnd: { [weak self] in self?.ends += 1 })
    }

    private func until(_ what: String, _ condition: () -> Bool) async {
        for _ in 0..<300 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("never: \(what)")
    }

    // MARK: Opening

    func testSheetOpensAtOnceWithTheNamedFile() async {
        let video = addVideo()
        start(video)
        await until("sheet") { self.flow.phase == .sheet }
        XCTAssertEqual(world.sheets.count, 1)
        XCTAssertEqual(world.sheets[0].request.file.lastPathComponent, "Demo.mp4")
        XCTAssertNil(world.sheets[0].request.copy, "an MP4 needs no second one")
        XCTAssertNil(flow.card)
        XCTAssertEqual(ends, 0)
    }

    func testVoiceRecordingAndEditShareTheirOwnFile() async {
        start(addVideo(.audio, ext: "m4a"))
        await until("sheet") { self.flow.phase == .sheet }
        XCTAssertEqual(world.sheets[0].request.file.lastPathComponent, "Demo.m4a")
        XCTAssertNil(world.sheets[0].request.smaller)
        XCTAssertEqual(world.plans, 0)
    }

    func testQuickTimeRecordingAlsoGetsAnMP4() async {
        start(addVideo(.camera, ext: "mov"))
        await until("sheet") { self.flow.phase == .sheet }
        XCTAssertNotNil(world.sheets[0].request.copy)
        XCTAssertEqual(world.sheets[0].request.file.pathExtension, "mov")
    }

    func testImportedAndVeryLargeMoviesGoAsTheyAre() async {
        start(addVideo(.imported, ext: "mov"))
        await until("sheet") { self.flow.phase == .sheet }
        XCTAssertNil(world.sheets[0].request.copy)
        world.sheets[0].close()
        await until("end") { self.ends == 1 }
        start(addVideo(.screen, ext: "mov", bytes: 2_000_000_000))
        await until("sheet") { self.flow.phase == .sheet }
        XCTAssertNil(world.sheets[1].request.copy)
        XCTAssertNotNil(world.sheets[1].request.smaller)
    }

    /// The first sheet after launch is slow to build: the card is up before that.
    func testFirstSheetAfterLaunchShowsACardFirst() async {
        world.isWarm = false
        start(addVideo())
        await until("card") { self.flow.card?.step == .opening }
        XCTAssertTrue(world.sheets.isEmpty)
        await until("sheet") { self.flow.phase == .sheet }
        XCTAssertNil(flow.card)
    }

    // MARK: The second tap

    func testASecondTapIsIgnoredWhileTheSheetIsUp() async {
        let video = addVideo()
        start(video)
        await until("sheet") { self.flow.phase == .sheet }
        XCTAssertTrue(flow.isBusy(with: video.id))
        start(video)
        XCTAssertEqual(world.sheets.count, 1)
    }

    func testShareWorksAgainAfterTheSheetCloses() async {
        let video = addVideo()
        for round in 1...3 {
            start(video)
            await until("sheet \(round)") { self.flow.phase == .sheet }
            world.sheets[round - 1].close()
            await until("end \(round)") { self.ends == round }
            XCTAssertFalse(flow.isBusy(with: video.id))
        }
    }

    /// The sheet went away without iOS saying so: the next tap must not be swallowed.
    func testALostSheetDoesNotBlockShare() async {
        let video = addVideo()
        start(video)
        await until("sheet") { self.flow.phase == .sheet }
        world.sheets[0].isOnScreen = false
        XCTAssertFalse(flow.isBusy(with: video.id))
        start(video)
        await until("second sheet") { self.world.sheets.count == 2 }
        // The lost sheet reporting in late changes nothing.
        world.sheets[0].close()
        XCTAssertEqual(ends, 0)
        world.sheets[1].close()
        await until("end") { self.ends == 1 }
    }

    func testASheetThatCantOpenEndsWithAMessage() async {
        world.opens = false
        let video = addVideo()
        start(video)
        await until("end") { self.ends == 1 }
        XCTAssertNotNil(flow.toast)
        XCTAssertFalse(flow.isBusy(with: video.id))
        let left = try? FileManager.default.contentsOfDirectory(atPath: ShareFileLink.directory(root: root).path)
        XCTAssertEqual(left ?? [], [])
        world.opens = true
        start(video)
        await until("sheet") { self.flow.phase == .sheet }
    }

    func testMissingFileEndsWithAMessage() async {
        let video = addVideo(hasFile: false)
        start(video)
        await until("end") { self.ends == 1 }
        XCTAssertEqual(flow.toast?.text, "This recording's file is missing")
        XCTAssertFalse(flow.isBusy(with: video.id))
    }

    func testFailedRecordingEndsWithAMessage() async {
        start(addVideo(state: .failed(reason: "x", outOfSpace: false)))
        await until("end") { self.ends == 1 }
        XCTAssertNotNil(flow.toast)
        XCTAssertTrue(world.sheets.isEmpty)
    }

    func testAnotherRecordingTakesOver() async {
        let first = addVideo(), second = addVideo()
        world.changing = [first.id]
        start(first)
        await until("card") { self.flow.card?.video.id == first.id }
        start(second)
        await until("sheet") { self.flow.phase == .sheet }
        world.settle(first.id)
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(world.sheets.count, 1)
        XCTAssertEqual(flow.isBusy(with: second.id), true)
    }

    // MARK: Waiting

    func testWaitingShowsProgressAndThenOpens() async {
        let video = addVideo()
        world.changing = [video.id]
        world.fraction = 0.3
        start(video)
        XCTAssertNil(flow.card, "nothing flashes up for short work")
        await until("card") { self.flow.card != nil }
        XCTAssertEqual(flow.card?.step, .sound)
        XCTAssertEqual(flow.card?.progress, 0.3)
        world.fraction = 0.8
        await until("progress") { self.flow.card?.progress == 0.8 }
        world.settle(video.id)
        await until("sheet") { self.flow.phase == .sheet }
        XCTAssertNil(flow.card)
    }

    func testCancelWhileWaiting() async {
        let video = addVideo()
        world.changing = [video.id]
        start(video)
        await until("card") { self.flow.card != nil }
        flow.cancel()
        XCTAssertEqual(ends, 1)
        XCTAssertNil(flow.card)
        XCTAssertFalse(flow.isBusy(with: video.id))
        world.settle(video.id)
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertTrue(world.sheets.isEmpty, "a cancelled share must not open later")
        start(video)
        await until("sheet") { self.flow.phase == .sheet }
    }

    func testLeavingTheScreenStopsWaiting() async {
        let video = addVideo()
        world.changing = [video.id]
        start(video)
        await until("card") { self.flow.card != nil }
        flow.screenDisappeared()
        XCTAssertEqual(ends, 1)
        world.settle(video.id)
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertTrue(world.sheets.isEmpty)
    }

    func testDeletedWhileWaiting() async {
        let video = addVideo()
        world.changing = [video.id]
        start(video)
        await until("card") { self.flow.card != nil }
        library.delete(video.id)
        world.settle(video.id)
        await until("end") { self.ends == 1 }
        XCTAssertNotNil(flow.toast)
        XCTAssertTrue(world.sheets.isEmpty)
    }

    // MARK: Counting

    func testSharesAreCounted() async {
        let video = addVideo()
        start(video)
        await until("sheet") { self.flow.phase == .sheet }
        let link = world.sheets[0].request.file
        world.sheets[0].request.onComplete(.message)
        world.sheets[0].close()
        await until("end") { self.ends == 1 }
        XCTAssertEqual(library.video(video.id)?.shareCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: link.path), "whoever got it may still be reading it")
    }

    func testSaveVideoCountsAsPhotos() async {
        let video = addVideo()
        start(video)
        await until("sheet") { self.flow.phase == .sheet }
        world.sheets[0].request.onComplete(.saveToCameraRoll)
        XCTAssertEqual(library.video(video.id)?.photosSaveCount, 1)
        XCTAssertEqual(library.video(video.id)?.shareCount, 0)
    }

    func testClosingWithoutSharingRemovesTheLink() async {
        start(addVideo())
        await until("sheet") { self.flow.phase == .sheet }
        let link = world.sheets[0].request.file
        XCTAssertTrue(FileManager.default.fileExists(atPath: link.path))
        world.sheets[0].close()
        await until("end") { self.ends == 1 }
        XCTAssertFalse(FileManager.default.fileExists(atPath: link.path))
    }

    /// The whole way with a real two-sound recording: mixed, then shared as one MP4.
    func testTwoSoundRecordingIsFinishedFirst() async throws {
        let id = UUID()
        let url = library.media.videoURL("\(id.uuidString).mov")
        var spec = TestMovie.Spec()
        spec.sounds = [.tone(440), .tone(880)]
        try await TestMovie.make(spec, at: url)
        let video = Video(id: id, title: "Two sounds", createdAt: Date(), kind: .screen, fileName: url.lastPathComponent,
                          duration: 6, fileSize: MediaInspector.fileSize(url), pixelWidth: 360, pixelHeight: 780)
        library.add(video)
        world.usesRealPlan = true
        start(video)
        await until("sheet") { self.flow.phase == .sheet }
        let file = world.sheets[0].request.file
        XCTAssertEqual(file.lastPathComponent, "Two sounds.mp4")
        let facts = try await MovieFacts.read(file)
        XCTAssertEqual(facts.audioSeconds.count, 1)
    }

    func testPlanThatFailsStillShares() async {
        world.planFails = true
        start(addVideo(.screen, ext: "mov"))
        await until("sheet") { self.flow.phase == .sheet }
    }
}

/// Stands in for the recorder, the share sheet and the movie reader.
@MainActor
final class FakeWorld {
    var changing = Set<UUID>()
    var fraction: Double?
    var opens = true
    var planFails = false
    var usesRealPlan = false
    var isWarm = true
    private(set) var plans = 0
    private(set) var sheets: [FakeSheet] = []
    private var waiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]

    func settle(_ id: UUID) {
        changing.remove(id)
        for waiter in waiters.removeValue(forKey: id) ?? [] { waiter.resume() }
    }

    var ports: ShareFlowPorts {
        ShareFlowPorts(
            isFileChanging: { self.changing.contains($0) },
            fileProgress: { _ in self.fraction },
            waitUntilFileSettled: { id in
                guard self.changing.contains(id) else { return }
                await withCheckedContinuation { self.waiters[id, default: []].append($0) }
            },
            plan: { url, isScreen in
                self.plans += 1
                if self.planFails { throw MovieRewriteError.unreadable }
                if self.usesRealPlan { return try await MoviePlan.make(for: url, isScreenRecording: isScreen) }
                return MoviePlan(reasons: [], sound: .none, transform: .identity, duration: 530)
            },
            copy: { ShareCopies.shared.job(for: $0, source: $1, kind: $2, root: $3) },
            waitUntilActive: {},
            isSheetWarm: { self.isWarm },
            present: { request in
                let sheet = FakeSheet(request)
                self.sheets.append(sheet)
                let opens = self.opens
                Task { @MainActor in
                    if opens {
                        sheet.isOnScreen = true
                        request.onShown()
                    } else {
                        request.onFailed()
                    }
                }
                return sheet
            },
            tell: { _, _ in },
            ask: { _, _, _ in true })
    }
}

@MainActor
final class FakeSheet: ShareSheetHandle {
    let request: ShareSheetRequest
    var isOnScreen = false

    init(_ request: ShareSheetRequest) { self.request = request }

    func close(smaller: SmallerCopyPlan? = nil) {
        isOnScreen = false
        request.onClosed(smaller)
    }
}
