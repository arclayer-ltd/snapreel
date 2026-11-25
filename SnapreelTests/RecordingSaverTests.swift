import AVFoundation
import XCTest
@testable import Snapreel

/// Saving a recording, the work after it, and what happens when that is cut short.
@MainActor
final class RecordingSaverTests: XCTestCase {
    private var root: URL!
    private var library: Library!
    private let saver = RecordingSaver.shared

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("saver-\(UUID().uuidString)", isDirectory: true)
        library = Library(storage: InMemoryStorage(mediaRoot: root))
        TidyAttempts.defaults = UserDefaults(suiteName: "saver-tests") ?? .standard
        TidyAttempts.defaults.removePersistentDomain(forName: "saver-tests")
    }

    override func tearDown() async throws {
        TidyAttempts.defaults = .standard
        try? FileManager.default.removeItem(at: root)
    }

    private func twoSounds(seconds: Double = 6) -> TestMovie.Spec {
        var spec = TestMovie.Spec()
        spec.seconds = seconds
        spec.sounds = [.tone(440), .tone(880)]
        return spec
    }

    private func stage(_ spec: TestMovie.Spec, kind: RecordingKind = .screen) async throws -> UUID {
        let id = UUID()
        let name = "\(id.uuidString).mov"
        try await TestMovie.make(spec, at: library.media.staging.appendingPathComponent(name))
        saver.begin(RecordingSaveRequest(id: id, kind: kind, createdAt: Date(), fileName: name), library: library)
        return id
    }

    private func until(_ what: String, seconds: Double = 20, _ condition: () -> Bool) async {
        for _ in 0..<Int(seconds * 100) {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("never: \(what)")
    }

    private func fileURL(_ id: UUID) -> URL { library.fileURL(for: library.video(id)!) }

    func testScreenRecordingIsReadyFirstAndThenGetsOneSound() async throws {
        let id = try await stage(twoSounds())
        await until("ready") { self.library.video(id)?.state.isReady == true }
        XCTAssertTrue(saver.isFileChanging(id), "Share waits for the sound")
        await saver.waitUntilFileSettled(id)
        XCTAssertFalse(saver.isFileChanging(id))
        await saver.waitUntilFinished(id)
        let facts = try await MovieFacts.read(fileURL(id))
        XCTAssertEqual(facts.audioSeconds.count, 1)
        let video = try XCTUnwrap(library.video(id))
        XCTAssertNil(video.isFinishing)
        XCTAssertEqual(video.fileSize, MediaInspector.fileSize(fileURL(id)))
        XCTAssertNotNil(video.thumbnailFileName)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.media.staging.path), [])
        XCTAssertEqual(TidyAttempts.count(id), 0)
    }

    func testOrdinaryRecordingIsNeverWrittenAgain() async throws {
        let id = try await stage(TestMovie.Spec())
        await until("ready") { self.library.video(id)?.state.isReady == true }
        let before = try FileManager.default.attributesOfItem(atPath: fileURL(id).path)[.systemFileNumber] as? Int
        await saver.waitUntilFinished(id)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: fileURL(id).path)[.systemFileNumber] as? Int, before)
    }

    func testCutOffRecordingIsRepaired() async throws {
        var spec = twoSounds(seconds: 12)
        spec.isCutOff = true
        let id = try await stage(spec)
        await saver.waitUntilFinished(id)
        let video = try XCTUnwrap(library.video(id))
        XCTAssertTrue(video.state.isReady)
        XCTAssertGreaterThan(video.duration, 5)
        XCTAssertFalse(try XCTUnwrap(MovieStructure.read(fileURL(id))).isFragmented)
    }

    /// Killed during the work after review: the next launch finishes it.
    func testWorkLeftByAClosedAppIsFinished() async throws {
        let id = UUID()
        let url = library.media.videoURL("\(id.uuidString).mov")
        try await TestMovie.make(twoSounds(), at: url)
        library.add(Video(id: id, title: "Left", createdAt: Date(), kind: .screen, fileName: url.lastPathComponent, duration: 6,
                          fileSize: MediaInspector.fileSize(url), pixelWidth: 360, pixelHeight: 780, isFinishing: true))
        // Half of the new file, as the closed app left it.
        let half = library.media.staging.appendingPathComponent("\(id.uuidString)-mixed.mov")
        try Data(count: 5_000).write(to: half)
        XCTAssertTrue(TidyAttempts.begin(id))

        PendingImports.resumeInterruptedSaves(in: library)
        await until("done") { self.library.video(id)?.isFinishing == nil }
        let facts = try await MovieFacts.read(url)
        XCTAssertEqual(facts.audioSeconds.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: half.path))
    }

    /// Closed or crashed three times in the middle of it: left as it is, never tried forever.
    func testItIsNotTriedForever() async throws {
        let id = UUID()
        let url = library.media.videoURL("\(id.uuidString).mov")
        try await TestMovie.make(twoSounds(), at: url)
        library.add(Video(id: id, title: "Stuck", createdAt: Date(), kind: .screen, fileName: url.lastPathComponent, duration: 6,
                          fileSize: MediaInspector.fileSize(url), pixelWidth: 360, pixelHeight: 780, isFinishing: true))
        for _ in 0..<TidyAttempts.most { XCTAssertTrue(TidyAttempts.begin(id)) }
        saver.resumeFinishing(id, library: library)
        await saver.waitUntilFinished(id)
        XCTAssertNil(library.video(id)?.isFinishing)
        let facts = try await MovieFacts.read(url)
        XCTAssertEqual(facts.audioSeconds.count, 2, "the original is kept as it was")
    }

    func testAttemptsCount() {
        let id = UUID()
        XCTAssertTrue(TidyAttempts.begin(id))
        TidyAttempts.undo(id)
        XCTAssertEqual(TidyAttempts.count(id), 0)
        for _ in 0..<3 { XCTAssertTrue(TidyAttempts.begin(id)) }
        XCTAssertFalse(TidyAttempts.begin(id))
        TidyAttempts.clear(id)
        XCTAssertTrue(TidyAttempts.begin(id))
    }

    func testDeletingWhileItWorksLeavesNothing() async throws {
        let id = try await stage(twoSounds(seconds: 30))
        await until("ready") { self.library.video(id)?.state.isReady == true }
        saver.discard(id, library: library)
        await saver.waitUntilFinished(id)
        XCTAssertNil(library.video(id))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.media.staging.path), [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.media.videos.path), [])
    }

    func testMissingFileFailsAndLetsGo() async throws {
        let id = UUID()
        saver.begin(RecordingSaveRequest(id: id, kind: .screen, createdAt: Date(), fileName: "\(id.uuidString).mov"), library: library)
        await saver.waitUntilFileSettled(id)
        await saver.waitUntilFinished(id)
        guard case .failed(_, let outOfSpace)? = library.video(id)?.state else { return XCTFail("not failed") }
        XCTAssertFalse(outOfSpace)
        XCTAssertFalse(saver.isFileChanging(id))
    }

    // MARK: A nearly full phone

    /// The extension kept the movie but had no room for its manifest.
    func testMovieWithoutManifestIsFound() throws {
        let inbox = root.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let id = UUID()
        func put(_ name: String, bytes: Int = 200_000) throws {
            try Data(count: bytes).write(to: inbox.appendingPathComponent(name))
        }
        try put("\(id.uuidString).mov")
        try put("known.mov")
        try put("\(UUID().uuidString).mov", bytes: 10)
        try put("\(UUID().uuidString).json")
        let later = Date().addingTimeInterval(60)
        XCTAssertEqual(PendingImports.moviesWithoutManifest(in: inbox, known: [], now: later).map(\.id), [id])
        XCTAssertEqual(PendingImports.moviesWithoutManifest(in: inbox, known: ["\(id.uuidString).mov"], now: later).count, 0)
        // Just written: the manifest may be on its way.
        XCTAssertEqual(PendingImports.moviesWithoutManifest(in: inbox, known: [], now: Date()).count, 0)
    }
}
