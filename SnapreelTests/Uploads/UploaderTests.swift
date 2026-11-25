import XCTest
@testable import Snapreel

/// The upload state machine against a stub server.
@MainActor
final class UploaderTests: XCTestCase {
    private var root: URL!
    private var server: StubStorage!
    private var now = Date(timeIntervalSince1970: 1_795_000_000)
    private var waited: Double = 0
    private var signedIn = true
    private var failures: [String] = []
    private var finishes = 0
    private var prepared = 0
    private let id = UUID()
    /// What the preparer stub makes.
    private var video = Data()
    private var poster = Data(repeating: 7, count: 120_000)
    private var preview = Data(repeating: 9, count: 400_000)
    private var prepare: ((PrepareRequest, @escaping @MainActor (PrepareUpdate) -> Void) async throws -> Void)?

    private static let piece = Int(CloudConfig.pieceSize)

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("uploads-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        server = StubStorage()
        video = Self.noise(Self.piece * 3 + 1_234)
        now = Date(timeIntervalSince1970: 1_795_000_000)
        waited = 0
        signedIn = true
        failures = []
        finishes = 0
        prepared = 0
        prepare = nil
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    static func noise(_ count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        var data = Data(capacity: count + 8)
        while data.count < count {
            var value = generator.next()
            withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        }
        return data.prefix(count)
    }

    static let detail = VideoDetail(id: "srv", slug: "abc", url: "https://snapreel.video/v/abc", localId: "x", title: "Test",
                                    kind: .screen, durationS: 10, status: .ready, posterUrl: nil, createdAt: Date(), views: 0,
                                    uniqueViewers: 0, lastViewedAt: nil, commentCount: 0, access: .link, hasPassword: false,
                                    expiresAt: nil, allowDownload: false, allowComments: true, allowReactions: true, cta: nil,
                                    width: 886, height: 1_918, sizeBytes: 1)

    /// One process: an uploader from before a "relaunch" must not go on working behind the new one.
    private final class Life { var alive = true }
    private var life = Life()

    private func makeUploader() -> Uploader {
        life.alive = false
        let life = Life()
        self.life = life
        let environment = UploadEnvironment(
            root: root,
            transfers: { self.server },
            isConfigured: { life.alive },
            isSignedIn: { self.signedIn && life.alive },
            token: { _ in
                guard self.signedIn else { throw CloudError.signedOut }
                return self.server.currentToken
            },
            refreshToken: { self.server.refresh() },
            send: { request in
                do { return try await self.server.send(request) } catch { throw CloudError.from(network: error) }
            },
            signer: { S3Signer(endpoint: URL(string: "https://stub.test/storage/v1/s3")!, region: "us-east-1", accessKey: "ref", secret: "anon") },
            storageURL: { URL(string: "https://stub.test/storage/v1")! },
            finish: { _, size in
                await Task.yield()
                return try self.server.ready(size)
            },
            report: { _, _, _ in },
            prepare: { request, update in
                self.prepared += 1
                if let prepare = self.prepare { return try await prepare(request, update) }
                try self.writeAll(request, update)
            },
            makeStandIn: { _, url, _ in try? Data(repeating: 1, count: 2_000).write(to: url) },
            finished: { _, _ in self.finishes += 1 },
            failed: { _, message in self.failures.append(message) },
            freeDisk: { 10_000_000_000 },
            now: { self.now },
            sleep: { seconds in
                self.now += seconds
                self.waited += seconds
                await Task.yield()
            }
        )
        let uploader = Uploader(environment: environment)
        uploader.setUp(watchesNetwork: false)
        return uploader
    }

    /// The preparer stub: everything at once.
    private func writeAll(_ request: PrepareRequest, _ update: @MainActor (PrepareUpdate) -> Void) throws {
        try poster.write(to: request.folder.appendingPathComponent("poster.jpg"))
        update(.file(.poster, size: Int64(poster.count)))
        try preview.write(to: request.folder.appendingPathComponent("preview.mp4"))
        update(.file(.preview, size: Int64(preview.count)))
        try video.write(to: request.folder.appendingPathComponent("video.mp4"))
        update(.videoDone(copyID: "copy", size: Int64(video.count), headerEnd: 4_096))
    }

    private func start(_ uploader: Uploader) {
        let recording = Video(id: id, title: "Test", createdAt: now, kind: .screen, fileName: "x.mov", duration: 10, fileSize: 1,
                              pixelWidth: 886, pixelHeight: 1_918, state: .ready)
        let link = CreateVideoResponse(id: "srv", slug: "abc", url: "https://snapreel.video/v/abc", status: .uploading,
                                       upload: .init(bucket: "videos", videoPath: "user/video/video.mp4",
                                                     posterPath: "user/video/poster.jpg", previewPath: "user/video/preview.mp4"),
                                       limits: .init(maxDurationS: 7_200, maxLongSide: 1_920))
        uploader.start(video: recording, source: root, link: link)
    }

    private func until(_ what: String, seconds: Double = 8, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() {
            if Date() > deadline {
                XCTFail("timed out waiting for: \(what). log: \(server.log.suffix(20))")
                return
            }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    private func untilEnded(_ uploader: Uploader) async {
        await until("the upload to end") { uploader.jobs[id].map { $0.stage == .done || $0.stage == .failed } ?? true }
    }

    private func expectDone(_ uploader: Uploader, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(uploader.jobs[id]?.stage, .done, "\(failures) \(server.log.suffix(12))", file: file, line: line)
        XCTAssertEqual(server.objects["user/video/video.mp4"], video, file: file, line: line)
        XCTAssertEqual(finishes, 1, file: file, line: line)
        // Nothing but the job's own note is left on the phone.
        let left = (try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(id.uuidString).path)) ?? []
        XCTAssertEqual(left, ["job.json"], file: file, line: line)
    }

    // MARK: - The way it should go

    func testUploadsEverythingInPieces() async {
        let uploader = makeUploader()
        start(uploader)
        await untilEnded(uploader)
        expectDone(uploader)
        XCTAssertEqual(server.objects["user/video/poster.jpg"], poster)
        XCTAssertEqual(server.objects["user/video/preview.mp4"], preview)
        XCTAssertEqual(server.pieceRequests, 4)
        XCTAssertEqual(server.readySizes, [Int64(video.count)])
        XCTAssertEqual(uploader.phase(for: id), .done)
    }

    func testSmallVideoGoesInOneRequest() async {
        video = Self.noise(900_000)
        let uploader = makeUploader()
        start(uploader)
        await untilEnded(uploader)
        expectDone(uploader)
        XCTAssertEqual(server.pieceRequests, 0)
        XCTAssertEqual(server.times(.single("video.mp4")), 1)
    }

    func testThreePiecesAtATimeWhileOpenAndEverythingWhenLeaving() async {
        video = Self.noise(Self.piece * 12)
        server.holdsTransfers = true
        let uploader = makeUploader()
        start(uploader)
        await until("the first transfers") { self.server.activeTags.filter { $0.part == .video }.count == 3 }
        try? await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertEqual(server.activeTags.filter { $0.part == .video }.count, 3)
        uploader.willLeave()
        await until("every piece to be handed over") { self.server.activeTags.filter { $0.part == .video }.count == 12 }
        server.holdsTransfers = false
        server.release()
        await untilEnded(uploader)
        expectDone(uploader)
        XCTAssertEqual(server.pieceRequests, 12)
    }

    func testSendsWhatIsReadyWhileTheRestIsBeingMade() async {
        video = Self.noise(Self.piece * 6 + 500)
        let header = Int64(4_096)
        var finish: CheckedContinuation<Void, Never>?
        prepare = { request, update in
            try self.poster.write(to: request.folder.appendingPathComponent("poster.jpg"))
            update(.file(.poster, size: Int64(self.poster.count)))
            update(.file(.preview, size: 0))
            let file = request.folder.appendingPathComponent("video.mp4")
            // The index isn't written yet, so the first bytes are still zero.
            var growing = self.video.prefix(Self.piece * 4 + 10)
            growing.replaceSubrange(0..<Int(header), with: Data(count: Int(header)))
            try growing.write(to: file)
            update(.video(.init(copyID: "a", fraction: 0.6, finalBytes: Int64(growing.count), headerEnd: header, estimatedBytes: 40_000_000)))
            await withCheckedContinuation { finish = $0 }
            try self.video.write(to: file)
            update(.videoDone(copyID: "a", size: Int64(self.video.count), headerEnd: header))
        }
        let uploader = makeUploader()
        start(uploader)
        // Pieces 2, 3 and 4 are whole and final; 1 holds the index and 5 isn't whole.
        await until("early pieces") { self.server.pieceRequests == 3 }
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(Set(server.log.compactMap { (operation: StubStorage.Operation) -> Int? in if case .piece(let n) = operation { return n } else { return nil } }), [2, 3, 4])
        XCTAssertEqual(uploader.phase(for: id), .preparing)
        let progress = uploader.progress(for: id)
        XCTAssertEqual(progress?.prepared, 0.6)
        XCTAssertEqual(progress?.isEstimate, true)
        XCTAssertEqual(progress?.totalBytes, 40_000_000)
        XCTAssertGreaterThanOrEqual(progress?.sentBytes ?? 0, Int64(Self.piece * 3))
        finish?.resume()
        await untilEnded(uploader)
        expectDone(uploader)
        XCTAssertEqual(server.pieceRequests, 7)
        XCTAssertEqual(server.times(.piece(1)), 1)
    }

    func testAWebCopyStartedOverSendsEveryPieceAgain() async {
        video = Self.noise(Self.piece * 4)
        let wrong = Self.noise(Self.piece * 3)
        var goOn: CheckedContinuation<Void, Never>?
        prepare = { request, update in
            let file = request.folder.appendingPathComponent("video.mp4")
            try wrong.write(to: file)
            update(.video(.init(copyID: "first", fraction: 0.5, finalBytes: Int64(wrong.count), headerEnd: 100, estimatedBytes: 1)))
            await withCheckedContinuation { goOn = $0 }
            try self.video.write(to: file)
            update(.videoDone(copyID: "second", size: Int64(self.video.count), headerEnd: 100))
        }
        let uploader = makeUploader()
        start(uploader)
        await until("pieces of the first copy") { self.server.pieceRequests == 2 }
        goOn?.resume()
        await untilEnded(uploader)
        expectDone(uploader)
    }

    // MARK: - Lost answers

    func testLostAnswerAfterAStoredPiece() async {
        server.fault = { operation, count in operation == .piece(2) && count == 0 ? .lostAnswer : nil }
        let uploader = makeUploader()
        start(uploader)
        await untilEnded(uploader)
        expectDone(uploader)
        XCTAssertEqual(server.times(.piece(2)), 2)
        XCTAssertEqual(server.pieceRequests, 5)
    }

    func testLostAnswerToTheCompletion() async {
        // The file is complete on the server; asking again says the upload is unknown.
        server.fault = { operation, count in operation == .complete && count == 0 ? .lostAnswer : nil }
        let uploader = makeUploader()
        start(uploader)
        await untilEnded(uploader)
        expectDone(uploader)
        XCTAssertEqual(server.pieceRequests, 4, "nothing is sent again")
    }

    func testLostAnswerToReady() async {
        server.fault = { operation, count in operation == .ready && count < 2 ? .lostAnswer : nil }
        let uploader = makeUploader()
        start(uploader)
        await untilEnded(uploader)
        expectDone(uploader)
    }

    func testDamagedPieceIsSentAgain() async {
        server.fault = { operation, count in operation == .piece(3) && count == 0 ? .damaged : nil }
        let uploader = makeUploader()
        start(uploader)
        await untilEnded(uploader)
        expectDone(uploader)
        XCTAssertEqual(server.times(.piece(3)), 2)
    }

    func testDroppedConnections() async {
        // Every third piece request drops.
        var requests = 0
        server.fault = { operation, _ in
            guard case .piece = operation else { return nil }
            requests += 1
            return requests % 3 == 0 ? .dropped : nil
        }
        video = Self.noise(Self.piece * 9 + 77)
        let uploader = makeUploader()
        start(uploader)
        await untilEnded(uploader)
        expectDone(uploader)
    }

    // MARK: - 409

    func testSmallFilesOverwriteWhatIsThere() async {
        server.objects["user/video/poster.jpg"] = Data(repeating: 1, count: 5)
        server.objects["user/video/preview.mp4"] = Data()
        server.objects["user/video/video.mp4"] = Data(repeating: 2, count: 9)
        let uploader = makeUploader()
        start(uploader)
        await untilEnded(uploader)
        expectDone(uploader)
        XCTAssertEqual(server.objects["user/video/poster.jpg"], poster)
        XCTAssertEqual(server.objects["user/video/preview.mp4"], preview)
    }

    func testExistsWithTheRightSizeIsFinished() async {
        video = Self.noise(900_000)
        server.objects["user/video/video.mp4"] = video
        server.fault = { operation, _ in operation == .single("video.mp4") ? .status(409, "The resource already exists") : nil }
        let uploader = makeUploader()
        start(uploader)
        await untilEnded(uploader)
        expectDone(uploader)
        XCTAssertEqual(server.times(.single("video.mp4")), 1)
    }

    func testExistsWithTheWrongSizeIsReplaced() async {
        video = Self.noise(900_000)
        server.objects["user/video/video.mp4"] = Data(repeating: 3, count: 10)
        server.fault = { operation, count in
            operation == .single("video.mp4") && count == 0 ? .status(409, #"{"statusCode":"409","error":"Duplicate","message":"The resource already exists","code":"KeyAlreadyExists"}"#) : nil
        }
        let uploader = makeUploader()
        start(uploader)
        await untilEnded(uploader)
        expectDone(uploader)
        XCTAssertEqual(server.times(.single("video.mp4")), 2)
    }

    func testExistsForEverNeverLoopsHot() async {
        video = Self.noise(900_000)
        server.objects["user/video/video.mp4"] = Data(repeating: 3, count: 10)
        server.fault = { operation, _ in operation == .single("video.mp4") ? .status(409, "The resource already exists") : nil }
        let uploader = makeUploader()
        start(uploader)
        await untilEnded(uploader)
        XCTAssertEqual(uploader.jobs[id]?.stage, .failed)
        XCTAssertLessThan(server.times(.single("video.mp4")), 8)
        XCTAssertEqual(failures.count, 1)
        if case .failed? = uploader.phase(for: id) {} else { XCTFail("not shown as stopped") }
    }

    // MARK: - Tokens

    func testExpiredTokenIsRefreshedOnceForAllItsPieces() async {
        video = Self.noise(Self.piece * 8)
        server.holdsTransfers = true
        let uploader = makeUploader()
        start(uploader)
        await until("transfers with the first token") { self.server.activeTags.count >= 3 }
        uploader.willLeave()
        await until("all handed over") { self.server.activeTags.filter { $0.part == .video }.count == 8 }
        server.expireTokens()
        server.holdsTransfers = false
        server.release()
        await untilEnded(uploader)
        expectDone(uploader)
        XCTAssertLessThanOrEqual(server.refreshes, 2)
        XCTAssertGreaterThanOrEqual(server.refreshes, 1)
    }

    func testExpiredTokenOnEveryKindOfCall() async {
        for operation in [StubStorage.Operation.createMultipart, .complete, .single("poster.jpg"), .piece(4)] {
            try? await setUp()
            server.fault = { asked, count in
                asked == operation && count == 0 ? .status(400, #"{"statusCode":"403","code":"AccessDenied","error":"Unauthorized","message":"\"exp\" claim timestamp check failed"}"#) : nil
            }
            let uploader = makeUploader()
            start(uploader)
            await untilEnded(uploader)
            expectDone(uploader)
            XCTAssertEqual(server.refreshes, 1, "\(operation)")
        }
    }

    func testTokensThatAreNeverAcceptedEndInAClearState() async {
        server.fault = { operation, _ in
            if case .piece = operation { return .status(401, "") } else { return nil }
        }
        let uploader = makeUploader()
        start(uploader)
        await untilEnded(uploader)
        XCTAssertEqual(uploader.jobs[id]?.stage, .failed)
        XCTAssertLessThan(server.pieceRequests, 25)
        XCTAssertTrue(failures.first?.contains("sign") == true || failures.first?.contains("Sign") == true, "\(failures)")
    }

    func testForbiddenEndsInAClearState() async {
        server.fault = { operation, _ in
            if case .piece = operation { return .status(403, "<Error><Code>AccessDenied</Code><Message>new row violates row-level security policy</Message></Error>") } else { return nil }
        }
        let uploader = makeUploader()
        start(uploader)
        await untilEnded(uploader)
        XCTAssertEqual(uploader.jobs[id]?.stage, .failed)
        XCTAssertLessThan(server.pieceRequests, 20)
    }

    func testSignedOutWaitsAndCarriesOn() async {
        let uploader = makeUploader()
        signedIn = false
        start(uploader)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(server.log.count, 0)
        XCTAssertEqual(uploader.phase(for: id), .failed("Sign in to finish this upload."))
        signedIn = true
        uploader.resumeAll()
        await untilEnded(uploader)
        expectDone(uploader)
    }

    // MARK: - Busy and broken servers

    func testLockedThenFree() async {
        server.fault = { operation, count in operation == .piece(1) && count < 3 ? .status(423, "<Error><Code>ResourceLocked</Code></Error>") : nil }
        let uploader = makeUploader()
        start(uploader)
        await untilEnded(uploader)
        expectDone(uploader)
    }

    func testServerErrorsThenFine() async {
        server.fault = { operation, count in
            switch operation {
            case .piece(2): return count < 4 ? .status(503, "") : nil
            case .createMultipart: return count < 2 ? .status(500, "<Error><Code>InternalError</Code></Error>") : nil
            case .complete: return count < 2 ? .status(200, "<Error><Code>InternalError</Code><Message>We encountered an internal error.</Message></Error>") : nil
            case .ready: return count < 2 ? .status(500, "") : nil
            default: return nil
            }
        }
        let uploader = makeUploader()
        start(uploader)
        await untilEnded(uploader)
        expectDone(uploader)
        XCTAssertGreaterThan(waited, 10, "it pauses between tries")
    }

    func testServerDownStopsWithTryAgainAndKeepsWhatIsSent() async {
        server.fault = { operation, _ in operation == .piece(4) ? .status(500, "") : nil }
        let uploader = makeUploader()
        start(uploader)
        await untilEnded(uploader)
        XCTAssertEqual(uploader.jobs[id]?.stage, .failed)
        XCTAssertLessThan(server.times(.piece(4)), 15)
        XCTAssertGreaterThan(waited, 300, "longer and longer pauses")
        XCTAssertEqual(failures.count, 1)
        // Try again: only what is missing goes.
        server.fault = nil
        let before = server.pieceRequests
        uploader.retry(id, library: Library(storage: InMemoryStorage()))
        await untilEnded(uploader)
        expectDone(uploader)
        XCTAssertEqual(server.pieceRequests - before, 1)
        XCTAssertEqual(prepared, 1, "the web copy isn't made again")
    }

    // MARK: - Offline

    func testOfflineWaitsAndCarriesOn() async {
        video = Self.noise(Self.piece * 6)
        server.holdsTransfers = true
        let uploader = makeUploader()
        start(uploader)
        await until("transfers") { self.server.activeTags.filter { $0.part == .video }.count == 3 }
        uploader.networkChanged(online: false)
        if case .waitingForNetwork? = uploader.phase(for: id) {} else { XCTFail("not shown as waiting: \(String(describing: uploader.phase(for: id)))") }
        server.fault = { _, _ in .dropped }
        server.holdsTransfers = false
        server.release()
        try? await Task.sleep(nanoseconds: 80_000_000)
        let quiet = server.log.count
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(server.log.count, quiet, "nothing is tried while offline")
        XCTAssertEqual(uploader.jobs[id]?.stage, .uploading)
        server.fault = nil
        uploader.networkChanged(online: true)
        await untilEnded(uploader)
        expectDone(uploader)
    }

    func testAConnectionThatOnlyPretendsStopsInTheEnd() async {
        server.fault = { _, _ in .dropped }
        let uploader = makeUploader()
        start(uploader)
        await untilEnded(uploader)
        XCTAssertEqual(uploader.jobs[id]?.stage, .failed)
        XCTAssertGreaterThan(waited, 600)
        XCTAssertLessThan(server.log.count, 200)
    }

    func testFortyPiecesFailingTogetherAreOneEvent() async {
        video = Self.noise(Self.piece * 40)
        server.holdsTransfers = true
        let uploader = makeUploader()
        start(uploader)
        await until("the first transfers") { self.server.activeTags.filter { $0.part == .video }.count == 3 }
        uploader.willLeave()
        await until("all handed over", seconds: 30) { self.server.activeTags.filter { $0.part == .video }.count == 40 }
        var dropping = true
        server.fault = { operation, _ in
            guard dropping, case .piece = operation else { return nil }
            return .dropped
        }
        server.holdsTransfers = false
        server.release()
        try? await Task.sleep(nanoseconds: 30_000_000)
        dropping = false
        await until("the upload to end", seconds: 30) { uploader.jobs[self.id].map { $0.stage == .done || $0.stage == .failed } ?? true }
        expectDone(uploader)
    }

    // MARK: - Relaunch

    func testRelaunchCarriesOnWithoutSendingPiecesAgain() async {
        video = Self.noise(Self.piece * 6)
        server.fault = { operation, _ in
            switch operation {
            case .piece(5), .piece(6): return .dropped
            default: return nil
            }
        }
        var uploader: Uploader? = makeUploader()
        start(uploader!)
        await until("four pieces") { uploader!.jobs[self.id]?.parts.last?.pieces?.filter(\.done).count == 4 }
        uploader = nil
        server.fault = nil
        // Transfers of the old process are gone.
        life.alive = false
        server.cancel(id)
        server.onFinish = nil
        try? await Task.sleep(nanoseconds: 30_000_000)
        let before = server.pieceRequests
        let second = makeUploader()
        await untilEnded(second)
        expectDone(second)
        XCTAssertEqual(server.pieceRequests - before, 2)
        XCTAssertEqual(prepared, 1)
    }

    func testRelaunchFindsTransfersIOSKept() async {
        video = Self.noise(Self.piece * 3)
        server.holdsTransfers = true
        var uploader: Uploader? = makeUploader()
        start(uploader!)
        await until("transfers") { self.server.activeTags.filter { $0.part == .video }.count == 3 }
        uploader = nil
        let second = makeUploader()
        try? await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertEqual(server.activeTags.filter { $0.part == .video }.count, 3, "not started twice")
        server.holdsTransfers = false
        server.release()
        await untilEnded(second)
        expectDone(second)
        XCTAssertEqual(server.pieceRequests, 3)
    }

    func testRelaunchWhilePreparing() async {
        prepare = { request, update in
            try self.poster.write(to: request.folder.appendingPathComponent("poster.jpg"))
            update(.file(.poster, size: Int64(self.poster.count)))
            throw WebExport.Interrupted()
        }
        var uploader: Uploader? = makeUploader()
        uploader?.willLeave()
        start(uploader!)
        await until("the pause") { uploader!.pausedPreparing.contains(self.id) }
        XCTAssertEqual(uploader?.progress(for: id)?.isPaused, true)
        // The poster is sent although the rest isn't made yet.
        await until("the poster") { self.server.objects["user/video/poster.jpg"] != nil && self.server.activeTags.isEmpty }
        uploader = nil
        prepare = nil
        let second = makeUploader()
        await untilEnded(second)
        expectDone(second)
    }

    func testUploadForgottenAfterADayStartsOver() async {
        video = Self.noise(Self.piece * 5)
        server.fault = { operation, _ in operation == .piece(5) ? .dropped : nil }
        let uploader = makeUploader()
        start(uploader)
        await until("four pieces") { uploader.jobs[self.id]?.parts.last?.pieces?.filter(\.done).count == 4 }
        uploader.networkChanged(online: false)
        server.forgetUnfinished()
        server.fault = nil
        uploader.networkChanged(online: true)
        await untilEnded(uploader)
        expectDone(uploader)
        XCTAssertEqual(server.times(.createMultipart), 2)
    }

    func testUploadForgottenAgainAndAgainStops() async {
        server.fault = { operation, _ in
            if case .piece = operation { return .status(404, "<Error><Code>NoSuchUpload</Code></Error>") } else { return nil }
        }
        let uploader = makeUploader()
        start(uploader)
        await untilEnded(uploader)
        XCTAssertEqual(uploader.jobs[id]?.stage, .failed)
        XCTAssertLessThan(server.times(.createMultipart), 8)
    }

    // MARK: - Odd files

    func testEmptyPreviewIsNeverSentAndDoesNotHoldTheVideoBack() async {
        preview = Data()
        let uploader = makeUploader()
        start(uploader)
        await untilEnded(uploader)
        expectDone(uploader)
        XCTAssertNil(server.objects["user/video/preview.mp4"])
    }

    func testAServerThatInsistsOnAPreviewGetsAStandIn() async {
        preview = Data()
        server.insistsOnAllFiles = true
        let uploader = makeUploader()
        start(uploader)
        await untilEnded(uploader)
        expectDone(uploader)
        XCTAssertEqual(server.objects["user/video/preview.mp4"]?.count, 2_000)
    }

    func testEmptyVideoStops() async {
        video = Data()
        let uploader = makeUploader()
        start(uploader)
        await untilEnded(uploader)
        XCTAssertEqual(uploader.jobs[id]?.stage, .failed)
        XCTAssertNil(server.objects["user/video/video.mp4"])
    }

    func testOverTwoGigabytesStops() async {
        prepare = { request, update in
            update(.file(.poster, size: 0))
            update(.file(.preview, size: 0))
            let file = request.folder.appendingPathComponent("video.mp4")
            FileManager.default.createFile(atPath: file.path, contents: nil)
            let handle = try FileHandle(forWritingTo: file)
            // Takes no room: a file with a hole.
            try handle.truncate(atOffset: UInt64(CloudConfig.maxFileBytes) + 1)
            try handle.close()
            update(.videoDone(copyID: "a", size: CloudConfig.maxFileBytes + 1, headerEnd: 0))
        }
        let uploader = makeUploader()
        start(uploader)
        await untilEnded(uploader)
        XCTAssertEqual(uploader.jobs[id]?.stage, .failed)
        XCTAssertEqual(failures, ["This video is over 2 GB, the most a link can hold."])
        XCTAssertEqual(server.pieceRequests, 0)
    }

    func testTooLargeForTheServerStops() async {
        server.fault = { operation, _ in operation == .createMultipart ? .status(413, "<Error><Code>EntityTooLarge</Code></Error>") : nil }
        let uploader = makeUploader()
        start(uploader)
        await untilEnded(uploader)
        XCTAssertEqual(uploader.jobs[id]?.stage, .failed)
    }

    func testPreparingThatFailsStopsWithItsReason() async {
        prepare = { _, _ in throw WebExport.Failure.cannotExport("Your iPhone is too full to prepare the video.") }
        let uploader = makeUploader()
        start(uploader)
        await untilEnded(uploader)
        XCTAssertEqual(failures, ["Your iPhone is too full to prepare the video."])
    }

    func testPreparingInterruptedOverAndOverStops() async {
        prepare = { _, _ in throw WebExport.Interrupted() }
        let uploader = makeUploader()
        start(uploader)
        await untilEnded(uploader)
        XCTAssertEqual(uploader.jobs[id]?.stage, .failed)
        XCTAssertLessThan(prepared, 15)
    }

    func testPiecesMissingOnTheServerGoAgain() async {
        server.fault = { operation, count in
            operation == .complete && count == 0 ? .status(400, "<Error><Code>InvalidPart</Code></Error>") : nil
        }
        let uploader = makeUploader()
        start(uploader)
        await untilEnded(uploader)
        expectDone(uploader)
        XCTAssertEqual(server.times(.createMultipart), 2)
    }

    func testDeletedLinkStops() async {
        server.linkIsDeleted = true
        let uploader = makeUploader()
        start(uploader)
        await untilEnded(uploader)
        XCTAssertEqual(failures, ["This link was deleted, so the upload stopped."])
    }

    func testCancelStopsEverything() async {
        server.holdsTransfers = true
        let uploader = makeUploader()
        start(uploader)
        await until("transfers") { !self.server.activeTags.isEmpty }
        uploader.cancel(id)
        XCTAssertNil(uploader.jobs[id])
        server.holdsTransfers = false
        server.release()
        try? await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertTrue(server.activeTags.isEmpty)
        XCTAssertNil(server.objects["user/video/video.mp4"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(id.uuidString).appendingPathComponent("job.json").path))
    }

    // MARK: - The fallback transport

    func testFallsBackToTUSWhenS3RefusesItsKey() async {
        server.fault = { operation, _ in
            switch operation {
            case .createMultipart, .piece, .complete: return .status(403, "<Error><Code>SignatureDoesNotMatch</Code></Error>")
            default: return nil
            }
        }
        let uploader = makeUploader()
        start(uploader)
        await untilEnded(uploader)
        expectDone(uploader)
        XCTAssertEqual(server.times(.tusCreate), 1)
    }

    private func refuseS3(_ more: @escaping (StubStorage.Operation, Int) -> StubStorage.Fault?) {
        server.fault = { operation, count in
            switch operation {
            case .createMultipart, .piece, .complete: return .status(403, "<Error><Code>InvalidAccessKeyId</Code></Error>")
            default: return more(operation, count)
            }
        }
    }

    func testTUSResyncsAfterALostAnswerAndAHalfSentChunk() async {
        let chunk = Int64(CloudConfig.chunkSize)
        refuseS3 { operation, count in
            switch operation {
            case .tusPatch(0): return count == 0 ? .lostAnswer : nil
            case .tusPatch(let offset) where offset == chunk: return count == 0 ? .droppedHalfway : nil
            default: return nil
            }
        }
        let uploader = makeUploader()
        start(uploader)
        await untilEnded(uploader)
        expectDone(uploader)
        XCTAssertEqual(server.times(.tusPatch(0)), 1, "the stored chunk isn't sent again")
        XCTAssertGreaterThanOrEqual(server.times(.tusHead), 2)
    }

    func testTUSOverwritesAnExistingObject() async {
        // Build 47 looped here: the object exists, and every PATCH without x-upsert answers 409.
        server.objects["user/video/video.mp4"] = Data(repeating: 1, count: 100)
        refuseS3 { _, _ in nil }
        let uploader = makeUploader()
        start(uploader)
        await untilEnded(uploader)
        expectDone(uploader)
        XCTAssertLessThan(server.log.count, 20)
    }

    func testTUSConflictsForEverStop() async {
        refuseS3 { operation, _ in
            if case .tusPatch = operation { return .status(409, "Upload-Offset conflict\n") } else { return nil }
        }
        let uploader = makeUploader()
        start(uploader)
        await untilEnded(uploader)
        XCTAssertEqual(uploader.jobs[id]?.stage, .failed)
        XCTAssertLessThan(server.log.count, 60)
    }

    // MARK: - Jobs saved by build 47

    private func saveOldJob(stage: String, parts: String, files: [String: Data], failure: String? = nil) throws {
        let folder = root.appendingPathComponent(id.uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, data) in files { try data.write(to: folder.appendingPathComponent(name)) }
        let date = String(decoding: try JSONEncoder.snapreel.encode([now]), as: UTF8.self).dropFirst().dropLast()
        let json = """
        {"videoID":"\(id.uuidString)","serverID":"srv","bucket":"videos","videoPath":"user/video/video.mp4",
         "posterPath":"user/video/poster.jpg","previewPath":"user/video/preview.mp4","maxLongSide":1920,"title":"Old",
         "stage":"\(stage)","parts":[\(parts)],\(failure.map { "\"failure\":\"\($0)\"," } ?? "")"createdAt":\(date),"updatedAt":\(date)}
        """
        try Data(json.utf8).write(to: folder.appendingPathComponent("job.json"))
    }

    private func oldPart(_ kind: String, _ file: String, _ size: Int, offset: Int, location: String? = nil) -> String {
        """
        {"kind":"\(kind)","fileName":"\(file)","objectName":"user/video/\(file)","contentType":"\(kind == "poster" ? "image/jpeg" : "video/mp4")",
         "size":\(size),"offset":\(offset)\(location.map { ",\"location\":\"\($0)\"" } ?? "")}
        """
    }

    func testBuild47JobStuckInThe409LoopWithAnEmptyPreview() async throws {
        // 82144827: the poster is on the server but the job never learned it; the preview is empty.
        server.objects["user/video/poster.jpg"] = poster
        server.objects["user/video/preview.mp4"] = Data()
        server.addTUS(id: "old", key: "user/video/poster.jpg", length: Int64(poster.count), data: Data())
        let parts = [oldPart("poster", "poster.jpg", poster.count, offset: 0, location: "https://stub.test/storage/v1/upload/resumable/old"),
                     oldPart("preview", "preview.mp4", 0, offset: 0), oldPart("video", "video.mp4", video.count, offset: 0)].joined(separator: ",")
        try saveOldJob(stage: "uploading", parts: parts, files: ["poster.jpg": poster, "preview.mp4": Data(), "video.mp4": video])
        let uploader = makeUploader()
        await untilEnded(uploader)
        expectDone(uploader)
        XCTAssertLessThan(server.log.count, 15)
        XCTAssertEqual(prepared, 0)
    }

    func testBuild47JobKilledByAnExpiredTokenStartsAgainByItself() async throws {
        // 7cb803a9: poster and preview up, 38% of the video sent, then 400 "exp" and stopped.
        let half = video.count * 2 / 5
        let parts = [oldPart("poster", "poster.jpg", poster.count, offset: poster.count), oldPart("preview", "preview.mp4", preview.count, offset: preview.count),
                     oldPart("video", "video.mp4", video.count, offset: half, location: "https://stub.test/storage/v1/upload/resumable/gone")].joined(separator: ",")
        try saveOldJob(stage: "failed", parts: parts, files: ["poster.jpg": poster, "preview.mp4": preview, "video.mp4": video],
                       failure: "snapreel.video didn't answer properly. Try again in a moment.")
        let uploader = makeUploader()
        await untilEnded(uploader)
        expectDone(uploader)
        XCTAssertEqual(server.times(.single("poster.jpg")), 0)
    }

    func testBuild47JobAlmostDoneCarriesOnWithTUS() async throws {
        // ceca7c25 at 99%, while the server still knows the upload.
        let sent = video.count - 1_383_146
        server.addTUS(id: "almost", key: "user/video/video.mp4", length: Int64(video.count), data: video.prefix(sent))
        let parts = [oldPart("poster", "poster.jpg", poster.count, offset: poster.count), oldPart("preview", "preview.mp4", preview.count, offset: preview.count),
                     oldPart("video", "video.mp4", video.count, offset: sent - 5_000, location: "https://stub.test/storage/v1/upload/resumable/almost")].joined(separator: ",")
        try saveOldJob(stage: "failed", parts: parts, files: ["poster.jpg": poster, "preview.mp4": preview, "video.mp4": video], failure: "x")
        let uploader = makeUploader()
        await untilEnded(uploader)
        expectDone(uploader)
        XCTAssertEqual(server.pieceRequests, 0, "only the last bytes were sent")
        XCTAssertEqual(server.times(.tusPatch(Int64(sent))), 1)
    }

    func testBuild47JobAlmostDoneButForgottenByTheServer() async throws {
        let sent = video.count - 1_000
        let parts = [oldPart("poster", "poster.jpg", poster.count, offset: poster.count), oldPart("preview", "preview.mp4", preview.count, offset: preview.count),
                     oldPart("video", "video.mp4", video.count, offset: sent, location: "https://stub.test/storage/v1/upload/resumable/expired")].joined(separator: ",")
        try saveOldJob(stage: "uploading", parts: parts, files: ["poster.jpg": poster, "preview.mp4": preview, "video.mp4": video])
        let uploader = makeUploader()
        await untilEnded(uploader)
        expectDone(uploader)
        XCTAssertEqual(server.pieceRequests, 4)
    }

    func testBuild47JobStillPreparing() async throws {
        try saveOldJob(stage: "preparing", parts: "", files: [:])
        let uploader = makeUploader()
        await untilEnded(uploader)
        expectDone(uploader)
        XCTAssertEqual(prepared, 1)
    }

    func testBuild47JobWhoseWebCopyIsGone() async throws {
        let parts = [oldPart("poster", "poster.jpg", poster.count, offset: poster.count), oldPart("preview", "preview.mp4", preview.count, offset: preview.count),
                     oldPart("video", "video.mp4", video.count, offset: 0)].joined(separator: ",")
        try saveOldJob(stage: "failed", parts: parts, files: [:], failure: "x")
        let uploader = makeUploader()
        await untilEnded(uploader)
        expectDone(uploader)
        XCTAssertEqual(prepared, 1)
    }

    // MARK: - Two at once

    func testTwoRecordingsShareTheConnection() async {
        let other = UUID()
        let uploader = makeUploader()
        start(uploader)
        let recording = Video(id: other, title: "Other", createdAt: now, kind: .screen, fileName: "y.mov", duration: 10, fileSize: 1,
                              pixelWidth: 886, pixelHeight: 1_918, state: .ready)
        let link = CreateVideoResponse(id: "srv2", slug: "def", url: "https://snapreel.video/v/def", status: .uploading,
                                       upload: .init(bucket: "videos", videoPath: "user/other/video.mp4",
                                                     posterPath: "user/other/poster.jpg", previewPath: "user/other/preview.mp4"),
                                       limits: .init(maxDurationS: 7_200, maxLongSide: 1_920))
        uploader.start(video: recording, source: root, link: link)
        await untilEnded(uploader)
        await until("the other") { uploader.jobs[other]?.stage == .done }
        XCTAssertEqual(server.objects["user/other/video.mp4"], video)
        XCTAssertLessThanOrEqual(server.mostAtOnce, 8)
    }
}
