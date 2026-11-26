import XCTest
@testable import Snapreel

/// What the server's answers mean, how requests are signed, and how a recording goes to the web.
final class UploadUnitTests: XCTestCase {
    private func classify(_ status: Int, _ body: String = "") -> UploadAnswer {
        UploadAnswer.classify(status: status, body: Data(body.utf8))
    }

    // MARK: - Answers (bodies as the live project sent them)

    func testAnswers() {
        XCTAssertEqual(classify(200), .ok)
        XCTAssertEqual(classify(204), .ok)
        // TUS: an object that exists, and a wrong offset, are both 409.
        XCTAssertEqual(classify(409, "The resource already exists"), .exists)
        XCTAssertEqual(classify(409, "Upload-Offset conflict\n"), .offsetConflict)
        XCTAssertEqual(classify(400, #"{"statusCode":"409","error":"Duplicate","message":"The resource already exists","code":"KeyAlreadyExists"}"#), .exists)
        // An expired token has several costumes; the first two are from a token that really ran out.
        XCTAssertEqual(classify(400, #"{"statusCode":"403","code":"AccessDenied","error":"Unauthorized","message":"\"exp\" claim timestamp check failed"}"#), .tokenExpired)
        XCTAssertEqual(classify(403, "<Error><Code>AccessDenied</Code><Message>\"exp\" claim timestamp check failed</Message></Error>"), .tokenExpired)
        XCTAssertEqual(classify(400, "<Error><Code>ExpiredToken</Code><Message>The provided token has expired.</Message></Error>"), .tokenExpired)
        XCTAssertEqual(classify(403, "<Error><Code>AccessDenied</Code><Message>signature verification failed</Message></Error>"), .tokenExpired)
        XCTAssertEqual(classify(400, #"{"statusCode":"403","error":"Unauthorized","message":"Invalid Compact JWS","code":"AccessDenied"}"#), .tokenExpired)
        XCTAssertEqual(classify(401), .tokenExpired)
        // Refused for good.
        XCTAssertEqual(classify(403, "<Error><Code>AccessDenied</Code><Message>new row violates row-level security policy</Message></Error>"), .denied)
        XCTAssertEqual(classify(403, "<Error><Code>SignatureDoesNotMatch</Code></Error>"), .keyRefused)
        XCTAssertEqual(classify(403, "<Error><Code>RequestTimeTooSkewed</Code></Error>"), .clockSkew)
        XCTAssertEqual(classify(404, "<Error><Code>NoSuchUpload</Code><Message>Upload not found</Message></Error>"), .gone)
        XCTAssertEqual(classify(400, #"{"statusCode":"404","error":"not_found","message":"Object not found","code":"NoSuchKey"}"#), .gone)
        XCTAssertEqual(classify(410), .gone)
        XCTAssertEqual(classify(413, "Maximum size exceeded\n"), .tooLarge)
        XCTAssertEqual(classify(400, "<Error><Code>InvalidPart</Code></Error>"), .badPieces)
        XCTAssertEqual(classify(400, "<Error><Code>EntityTooSmall</Code></Error>"), .badPieces)
        XCTAssertEqual(classify(423), .busy)
        XCTAssertEqual(classify(429), .temporary(429))
        XCTAssertEqual(classify(503), .temporary(503))
        XCTAssertEqual(classify(0), .temporary(0))
        XCTAssertEqual(classify(415, "<Error><Code>InvalidMimeType</Code></Error>"), .refused(415))
        // S3 may say 200 and carry an error.
        XCTAssertEqual(classify(200, "<Error><Code>InternalError</Code></Error>"), .temporary(503))
        XCTAssertEqual(UploadAnswer.uploadID(in: Data("<R><UploadId>a.b-c_d</UploadId></R>".utf8)), "a.b-c_d")
        XCTAssertNil(UploadAnswer.uploadID(in: Data("<R></R>".utf8)))
    }

    // MARK: - Signing

    /// The same request signed by the Node script that uploaded to the live project (scripts/upload-bench.mjs).
    func testSignatureMatchesTheScriptThatWorksAgainstTheProject() {
        let signer = S3Signer(endpoint: URL(string: "https://abcdefghijklmnopqrst.storage.supabase.co/storage/v1/s3")!,
                              region: "us-east-1", accessKey: "abcdefghijklmnopqrst", secret: "anon-key")
        let url = signer.url("PUT", bucket: "videos", key: "user-1/video-1/video.mp4",
                             query: ["partNumber": "3", "uploadId": "a+b/c=d.e_f-g~h"], token: "header.payload.signature",
                             date: Date(timeIntervalSince1970: 1_795_000_000), expires: 86_400)
        XCTAssertEqual(url?.absoluteString, "https://abcdefghijklmnopqrst.storage.supabase.co/storage/v1/s3/videos/user-1/video-1/video.mp4?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=abcdefghijklmnopqrst%2F20261118%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Date=20261118T110640Z&X-Amz-Expires=86400&X-Amz-Security-Token=header.payload.signature&X-Amz-SignedHeaders=host&partNumber=3&uploadId=a%2Bb%2Fc%3Dd.e_f-g~h&X-Amz-Signature=6302b5fecd2db0f8fae24c663e437a18e00d5ed0be49e87e93474dcf64157a0e")
    }

    func testStamp() {
        XCTAssertEqual(S3Signer.stamp(Date(timeIntervalSince1970: 0)), "19700101T000000Z")
        XCTAssertEqual(S3Signer.encode("a b+c/d=é~"), "a%20b%2Bc%2Fd%3D%C3%A9~")
    }

    // MARK: - Plans

    func testPlans() {
        let mb = 1_000_000.0
        // The owner's 8:50 recording, 2.5 Mbit/s at 886 x 1918: already web-sized on Pro.
        let own = WebPlan.make(VideoFacts(width: 886, height: 1_918, bitRate: 2.49 * mb, duration: 530), maxLongSide: 1_920, isScreen: true)
        XCTAssertTrue(own.copies)
        // Free: 1280 on the long side, about 1.2 Mbit/s.
        let free = WebPlan.make(VideoFacts(width: 886, height: 1_918, bitRate: 2.49 * mb, duration: 290), maxLongSide: 1_280, isScreen: true)
        XCTAssertFalse(free.copies)
        XCTAssertEqual(free.height, 1_280)
        XCTAssertEqual(free.width, 592)
        XCTAssertGreaterThan(free.bitRate, 1_000_000)
        XCTAssertLessThan(free.bitRate, 1_500_000)
        // A heavier screen recording from a newer iPhone.
        let heavy = WebPlan.make(VideoFacts(width: 1_080, height: 2_340, bitRate: 6.4 * mb, duration: 300), maxLongSide: 1_920, isScreen: true)
        XCTAssertFalse(heavy.copies)
        XCTAssertLessThan(heavy.bitRate, 2_700_000)
        // Camera: 10 Mbit/s at 1080p becomes 5, 720p about 2.6.
        let camera = WebPlan.make(VideoFacts(width: 1_080, height: 1_920, bitRate: 10.4 * mb, duration: 60), maxLongSide: 1_920, isScreen: false)
        XCTAssertFalse(camera.copies)
        XCTAssertEqual(Double(camera.bitRate), 5 * mb, accuracy: 0.1 * mb)
        let small = WebPlan.make(VideoFacts(width: 1_080, height: 1_920, bitRate: 10.4 * mb, duration: 60), maxLongSide: 1_280, isScreen: false)
        XCTAssertEqual(Double(small.bitRate), 2.6 * mb, accuracy: 0.2 * mb)
        // Two hours fit in 2 GB whatever the target.
        for seconds in [7_200.0, 5_000] {
            let long = WebPlan.make(VideoFacts(width: 1_080, height: 1_920, bitRate: 10 * mb, duration: seconds), maxLongSide: 1_920, isScreen: false)
            XCTAssertLessThan(long.estimatedBytes, CloudConfig.maxFileBytes)
        }
        let longCopy = WebPlan.make(VideoFacts(width: 886, height: 1_918, bitRate: 2.6 * mb, duration: 7_200), maxLongSide: 1_920, isScreen: true)
        XCTAssertLessThan(longCopy.estimatedBytes, CloudConfig.maxFileBytes)
        // Not H.264, edited inside, or HDR: always encoded.
        XCTAssertFalse(WebPlan.make(VideoFacts(width: 640, height: 360, bitRate: mb, duration: 9, isH264: false), maxLongSide: 1_920, isScreen: false).copies)
        XCTAssertFalse(WebPlan.make(VideoFacts(width: 640, height: 360, bitRate: mb, duration: 9, isSimple: false), maxLongSide: 1_920, isScreen: false).copies)
        XCTAssertFalse(WebPlan.make(VideoFacts(width: 640, height: 360, bitRate: mb, duration: 9, isHDR: true), maxLongSide: 1_920, isScreen: false).copies)
        // The file's sides are even.
        XCTAssertEqual(free.encodedWidth % 2, 0)
    }

    // MARK: - Pieces

    func testPieces() {
        var part = UploadJob.Part(kind: .video, fileName: "v", objectName: "o", contentType: "video/mp4", size: 0)
        part.growing = true
        part.headerEnd = 1_000
        part.size = CloudConfig.pieceSize * 3 + 5
        part.layOutPieces()
        XCTAssertEqual(part.pieces?.map(\.number), [2, 3])
        part.pieces?[0].done = true
        part.growing = nil
        part.layOutPieces()
        XCTAssertEqual(part.pieces?.map(\.number), [1, 2, 3, 4])
        XCTAssertEqual(part.pieces?.map(\.done), [false, true, false, false])
        XCTAssertEqual(part.pieces?.last?.size, 5)
        XCTAssertEqual(part.pieces?.reduce(0) { $0 + $1.size }, part.size)
        XCTAssertEqual(TransferTag(TransferTag(videoID: UUID(), part: .video, number: 7, lane: "ab").text)?.number, 7)
        XCTAssertNil(TransferTag("\(UUID().uuidString)|video|6291456"), "build 47's tags aren't ours")
    }

    func testTimeLeft() {
        var progress = UploadProgress(sentBytes: 10_000_000, totalBytes: 70_000_000)
        XCTAssertNil(progress.timeLabel)
        progress.rate = 250_000
        XCTAssertEqual(progress.timeLabel, "About 4 min left")
        progress.sentBytes = 69_000_000
        XCTAssertEqual(progress.timeLabel, "A few seconds left")
        progress.sentBytes = 62_000_000
        XCTAssertEqual(progress.timeLabel, "About 40 sec left")
        progress.totalBytes = 1_800_000_000
        XCTAssertEqual(progress.timeLabel, "About 1 hr 56 min left")
    }

    /// What the share-link sheet says while an upload waits to try again (tester t26-link: "sits at 3%").
    func testRetryWords() {
        let now = Date(timeIntervalSince1970: 1_795_000_000)
        let soon = UploadRetry(reason: .unreachable, at: now.addingTimeInterval(29.2))
        XCTAssertEqual(UploadText.retryTitle(soon), "Can't reach snapreel.video")
        XCTAssertEqual(UploadText.retryDetail(soon, now: now), "Trying again in 30 s. Check your connection; what is sent is kept.")
        let later = UploadRetry(reason: .serverTrouble, at: now.addingTimeInterval(110))
        XCTAssertEqual(UploadText.retryDetail(later, now: now), "Trying again in 2 min by itself. What is sent is kept.")
        XCTAssertTrue(UploadText.retryDetail(UploadRetry(reason: .unreachable, at: nil), now: now).hasPrefix("Trying again now"))
    }

    /// The call-to-action address may be typed without https://; nonsense is refused.
    func testWebAddress() {
        XCTAssertEqual(LinkDraft.webAddress("example.com"), "https://example.com")
        XCTAssertEqual(LinkDraft.webAddress(" https://example.com/book "), "https://example.com/book")
        XCTAssertEqual(LinkDraft.webAddress("http://cal.example.org/x?y=1"), "http://cal.example.org/x?y=1")
        XCTAssertNil(LinkDraft.webAddress(""))
        XCTAssertNil(LinkDraft.webAddress("Book a call"))
        XCTAssertNil(LinkDraft.webAddress("example"))
        XCTAssertNil(LinkDraft.webAddress("https://"))
    }
}
