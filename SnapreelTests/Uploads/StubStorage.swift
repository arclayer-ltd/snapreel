import CryptoKit
import Foundation
import XCTest
@testable import Snapreel

/// Supabase Storage as it answered on 25 November 2026 (scripts and results in docs/pro/BACKEND.md, "Uploads"): S3
/// multipart with presigned URLs, single uploads, TUS, object info; plus snapreel.video's `ready` call. Faults can be
/// put in front of any operation.
@MainActor
final class StubStorage: UploadTransfers {
    enum Operation: Hashable {
        case createMultipart
        case piece(Int)
        case complete
        case info
        case single(String)
        case tusCreate
        case tusHead
        case tusPatch(Int64)
        case ready
    }

    enum Fault {
        /// Answer this instead, without doing anything.
        case status(Int, String)
        /// Do it, but the answer never arrives.
        case lostAnswer
        /// The connection drops before anything arrives.
        case dropped
        /// The connection drops half-way; TUS keeps what arrived.
        case droppedHalfway
        /// The bytes arrive damaged.
        case damaged
    }

    private struct Multipart {
        var key: String
        var parts: [Int: Data] = [:]
    }

    private struct TUS {
        var key: String
        var length: Int64
        var data = Data()
    }

    var objects: [String: Data] = [:]
    private var multiparts: [String: Multipart] = [:]
    private var tusUploads: [String: TUS] = [:]
    var validToken = "token-1"
    private(set) var refreshes = 0
    private(set) var log: [Operation] = []
    var fault: ((Operation, Int) -> Fault?)?
    private var counts: [Operation: Int] = [:]
    /// Transfers are held until released.
    var holdsTransfers = false
    private var held: [(URLRequest, Data, TransferTag)] = []
    private(set) var mostAtOnce = 0
    private var atOnce = 0
    /// The old server insists on all three files.
    var insistsOnAllFiles = false
    var linkIsDeleted = false
    private(set) var readySizes: [Int64] = []

    // MARK: UploadTransfers

    var onProgress: ((TransferTag, Int64) -> Void)?
    var onFinish: ((TransferTag, TransferResult) -> Void)?
    private var active: [TransferTag: Bool] = [:]

    var activeTags: [TransferTag] { Array(active.keys) }

    /// When the transfers handed over may begin.
    private(set) var begins: [TransferTag: Date] = [:]
    var now: () -> Date = { Date() }

    func cancelWaiting() {
        let waiting = Set(begins.filter { $0.value > now() }.keys)
        cancel { waiting.contains($0) }
    }

    func start(_ request: URLRequest, file: URL, tag: TransferTag, begins: Date?) {
        self.begins[tag] = begins
        // iOS takes the file as it is when the task starts.
        let data = (try? Data(contentsOf: file)) ?? Data()
        XCTAssertFalse(data.isEmpty, "an empty transfer was started: \(tag.text)")
        XCTAssertNil(active[tag], "started twice: \(tag.text)")
        active[tag] = true
        atOnce += 1
        mostAtOnce = max(mostAtOnce, atOnce)
        if holdsTransfers {
            held.append((request, data, tag))
        } else {
            run(request, data, tag)
        }
    }

    func release() {
        let waiting = held
        held = []
        for item in waiting where active[item.2] != nil { run(item.0, item.1, item.2) }
    }

    private func run(_ request: URLRequest, _ data: Data, _ tag: TransferTag) {
        Task { @MainActor in
            await Task.yield()
            guard self.active[tag] != nil else { return }
            self.onProgress?(tag, Int64(data.count / 2))
            var result = TransferResult()
            do {
                let (body, response) = try self.answer(request, data)
                result.status = response.statusCode
                result.body = body
                for (key, value) in response.allHeaderFields { result.headers["\(key)"] = "\(value)" }
            } catch {
                result.error = error
            }
            self.active[tag] = nil
            self.atOnce -= 1
            self.onFinish?(tag, result)
        }
    }

    func running() async -> [TransferTag] { Array(active.keys) }

    func cancel(_ videoID: UUID) { cancel { $0.videoID == videoID } }

    func cancel(where matches: @escaping (TransferTag) -> Bool) {
        for tag in active.keys where matches(tag) {
            active[tag] = nil
            atOnce -= 1
            var result = TransferResult()
            result.error = URLError(.cancelled)
            result.wasCancelled = true
            Task { @MainActor in self.onFinish?(tag, result) }
        }
    }

    // MARK: Requests

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        await Task.yield()
        return try answer(request, request.httpBody ?? Data())
    }

    func refresh() {
        refreshes += 1
        validToken = "token-\(refreshes + 1)"
        currentToken = validToken
    }

    var currentToken = "token-1"

    /// Every live token stops being accepted.
    func expireTokens() { validToken = "token-expired-\(UUID().uuidString)" }

    func ready(_ size: Int64) throws -> VideoDetail {
        log.append(.ready)
        let count = counts[.ready, default: 0]
        counts[.ready] = count + 1
        if let fault = fault?(.ready, count) {
            switch fault {
            case .status(let code, _): throw CloudError.server(status: code, message: nil)
            default: throw CloudError.offline
            }
        }
        if linkIsDeleted { throw CloudError.notFound }
        let video = objects["user/video/video.mp4"]?.count ?? 0
        var missing: [String] = []
        if video == 0 || Int64(video) != size { missing.append("video.mp4") }
        if insistsOnAllFiles {
            for name in ["poster.jpg", "preview.mp4"] where objects["user/video/\(name)"] == nil { missing.append(name) }
        }
        guard missing.isEmpty else { throw CloudError.incomplete(missing) }
        readySizes.append(size)
        return UploaderTests.detail
    }

    private func answer(_ request: URLRequest, _ body: Data) throws -> (Data, HTTPURLResponse) {
        let url = request.url!
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let query = Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        let method = request.httpMethod ?? "GET"
        let path = components.path
        let operation: Operation
        var key = ""
        if path.contains("/s3/videos/") {
            key = String(path.components(separatedBy: "/s3/videos/")[1])
            if query["uploads"] != nil { operation = .createMultipart
            } else if let number = query["partNumber"].flatMap(Int.init) { operation = .piece(number)
            } else { operation = .complete }
        } else if path.contains("/object/info/authenticated/videos/") {
            key = String(path.components(separatedBy: "/authenticated/videos/")[1])
            operation = .info
        } else if path.contains("/object/videos/") {
            key = String(path.components(separatedBy: "/object/videos/")[1])
            operation = .single((key as NSString).lastPathComponent)
        } else if method == "POST" {
            operation = .tusCreate
        } else if method == "HEAD" {
            operation = .tusHead
        } else {
            operation = .tusPatch(Int64(request.value(forHTTPHeaderField: "Upload-Offset") ?? "") ?? -1)
        }
        log.append(operation)
        let count = counts[operation, default: 0]
        counts[operation] = count + 1
        let fault = fault?(operation, count)
        switch fault {
        case .status(let status, let text)?: return respond(url, status, text)
        case .dropped?: throw URLError(.networkConnectionLost)
        default: break
        }
        // Who is asking.
        let token = query["X-Amz-Security-Token"] ?? request.value(forHTTPHeaderField: "Authorization")?.replacingOccurrences(of: "Bearer ", with: "")
        if token != validToken {
            return path.contains("/s3/")
                ? respond(url, 403, "<Error><Code>AccessDenied</Code><Message>\"exp\" claim timestamp check failed</Message></Error>")
                : respond(url, 400, #"{"statusCode":"403","code":"AccessDenied","error":"Unauthorized","message":"\"exp\" claim timestamp check failed"}"#)
        }
        let result = perform(operation, key: key, query: query, request: request, body: body, url: url, fault: fault)
        if case .lostAnswer? = fault { throw URLError(.networkConnectionLost) }
        if case .droppedHalfway? = fault { throw URLError(.networkConnectionLost) }
        return result
    }

    private func perform(_ operation: Operation, key: String, query: [String: String], request: URLRequest, body: Data,
                         url: URL, fault: Fault?) -> (Data, HTTPURLResponse) {
        switch operation {
        case .createMultipart:
            let id = "upload-\(multiparts.count + 1)"
            multiparts[id] = Multipart(key: key)
            return respond(url, 200, "<InitiateMultipartUploadResult><UploadId>\(id)</UploadId></InitiateMultipartUploadResult>")
        case .piece(let number):
            let id = query["uploadId"] ?? ""
            guard multiparts[id] != nil else { return respond(url, 404, "<Error><Code>NoSuchUpload</Code><Message>Upload not found</Message></Error>") }
            var data = body
            if case .damaged? = fault { data[0] = data[0] &+ 1 }
            if case .droppedHalfway? = fault { return respond(url, 0, "") }
            multiparts[id]?.parts[number] = data
            return respond(url, 200, "", ["Etag": "\"\(Self.md5(data))\""])
        case .complete:
            let id = query["uploadId"] ?? ""
            guard let upload = multiparts[id] else { return respond(url, 404, "<Error><Code>NoSuchUpload</Code><Message>Upload not found</Message></Error>") }
            let text = String(decoding: body, as: UTF8.self)
            let listed = text.components(separatedBy: "<Part>").dropFirst().map { part -> (Int, String) in
                let number = Int(part.components(separatedBy: "<PartNumber>")[1].components(separatedBy: "<")[0])!
                let etag = part.components(separatedBy: "<ETag>\"")[1].components(separatedBy: "\"")[0]
                return (number, etag)
            }
            for (index, item) in listed.enumerated() {
                guard let part = upload.parts[item.0], Self.md5(part) == item.1 else {
                    return respond(url, 400, "<Error><Code>InvalidPart</Code><Message>One or more of the specified parts could not be found.</Message></Error>")
                }
                if index < listed.count - 1, part.count < 5 * 1_024 * 1_024 {
                    return respond(url, 400, "<Error><Code>EntityTooSmall</Code><Message>too small</Message></Error>")
                }
            }
            objects[key] = listed.reduce(Data()) { $0 + upload.parts[$1.0]! }
            multiparts[id] = nil
            return respond(url, 200, "<CompleteMultipartUploadResult><ETag>\"x-1\"</ETag></CompleteMultipartUploadResult>")
        case .info:
            guard let data = objects[key] else {
                return respond(url, 400, #"{"statusCode":"404","error":"not_found","message":"Object not found","code":"NoSuchKey"}"#)
            }
            return respond(url, 200, #"{"name":"\#(key)","size":\#(data.count)}"#)
        case .single:
            if objects[key] != nil && request.value(forHTTPHeaderField: "x-upsert") != "true" {
                return respond(url, 400, #"{"statusCode":"409","error":"Duplicate","message":"The resource already exists","code":"KeyAlreadyExists"}"#)
            }
            objects[key] = body
            return respond(url, 200, #"{"Key":"videos/\#(key)"}"#)
        case .tusCreate:
            let length = Int64(request.value(forHTTPHeaderField: "Upload-Length") ?? "") ?? 0
            let name = (request.value(forHTTPHeaderField: "Upload-Metadata") ?? "").components(separatedBy: ",")
                .first { $0.hasPrefix("objectName ") }?.replacingOccurrences(of: "objectName ", with: "") ?? ""
            let id = "tus-\(tusUploads.count + 1)"
            tusUploads[id] = TUS(key: String(decoding: Data(base64Encoded: name) ?? Data(), as: UTF8.self), length: length)
            return respond(url, 201, "", ["Location": "https://stub.test/storage/v1/upload/resumable/\(id)"])
        case .tusHead:
            guard let upload = tusUploads[url.lastPathComponent] else { return respond(url, 404, "") }
            return respond(url, 200, "", ["Upload-Offset": "\(upload.data.count)", "Upload-Length": "\(upload.length)"])
        case .tusPatch(let offset):
            guard var upload = tusUploads[url.lastPathComponent] else { return respond(url, 404, "") }
            if objects[upload.key] != nil && request.value(forHTTPHeaderField: "x-upsert") != "true" {
                // Build 47's loop.
                return respond(url, 409, "The resource already exists")
            }
            guard offset == Int64(upload.data.count) else { return respond(url, 409, "Upload-Offset conflict\n") }
            if case .droppedHalfway? = fault {
                upload.data += body.prefix(body.count / 2)
            } else {
                upload.data += body
            }
            tusUploads[url.lastPathComponent] = upload
            if Int64(upload.data.count) == upload.length { objects[upload.key] = upload.data }
            return respond(url, 204, "", ["Upload-Offset": "\(upload.data.count)"])
        case .ready:
            return respond(url, 500, "")
        }
    }

    /// A TUS upload an earlier build left half done.
    func addTUS(id: String, key: String, length: Int64, data: Data) { tusUploads[id] = TUS(key: key, length: length, data: data) }

    /// Every unfinished upload is over 24 hours old.
    func forgetUnfinished() {
        multiparts = [:]
        tusUploads = [:]
    }

    func times(_ operation: Operation) -> Int { counts[operation, default: 0] }

    var pieceRequests: Int {
        log.filter { if case .piece = $0 { return true } else { return false } }.count
    }

    private func respond(_ url: URL, _ status: Int, _ text: String, _ headers: [String: String] = [:]) -> (Data, HTTPURLResponse) {
        (Data(text.utf8), HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!)
    }

    static func md5(_ data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
