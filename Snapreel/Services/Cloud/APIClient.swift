import Foundation

/// What can go wrong talking to snapreel.video or Supabase, in words the screens can show.
enum CloudError: Error, Equatable {
    /// The Supabase values in `CloudConfig` are still placeholders.
    case notConfigured
    /// Not signed in, or the session ended.
    case signedOut
    /// No connection.
    case offline
    /// 402: a plan limit.
    case limit(CloudLimitReason)
    /// Sign-in refused (wrong or expired code…), with a message to show.
    case auth(String)
    /// 404 or 410: the link was deleted or expired.
    case notFound
    /// 409: the server doesn't have all of the upload's files.
    case incomplete([String])
    /// Any other HTTP error.
    case server(status: Int, message: String?)
    /// A response that doesn't match the contract.
    case unreadable

    var message: String {
        switch self {
        case .notConfigured: return "Share links aren't switched on in this version of Snapreel yet."
        case .signedOut: return "Sign in to share links."
        case .offline: return "You're offline. Check your connection and try again."
        case .limit(.links): return "You've used all \(CloudConfig.freeLinkLimit) free links."
        case .limit(.duration): return "This recording is longer than your plan allows."
        case .limit(.proFeature): return "That's part of Snapreel Pro."
        case .auth(let text): return text
        case .notFound: return "This link no longer exists."
        case .incomplete: return "The upload isn't complete yet."
        case .server(let status, let text):
            // A server fault's own words ("Something went wrong.") don't help; say what's known and what to do.
            if status >= 500 {
                return "snapreel.video is having a problem right now (error \(status)). It isn't your connection. Try again in a few minutes."
            }
            if let text, !text.isEmpty { return text }
            return status > 0
                ? "snapreel.video didn't accept that (error \(status)). Try again in a moment."
                : "snapreel.video didn't answer properly. Try again in a moment."
        case .unreadable: return "snapreel.video sent something Snapreel couldn't read. Try again in a moment."
        }
    }

    static func from(network error: Error) -> CloudError {
        if let cloud = error as? CloudError { return cloud }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut,
                 NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed,
                 NSURLErrorDataNotAllowed, NSURLErrorInternationalRoamingOff:
                return .offline
            default: break
            }
        }
        return .server(status: 0, message: nil)
    }
}

/// Every owner endpoint in docs/pro/API.md, with the Bearer token from `AuthService`. A 401
/// refreshes the token and tries once more. In DEBUG fixture screens a `stub` answers instead
/// of the network.
@MainActor
final class APIClient {
    static let shared = APIClient()

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 25
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    #if DEBUG
    /// Answers requests in debug fixture screens; nothing reaches the network while set.
    var stub: CloudStub?
    #endif

    // MARK: Account

    func me() async throws -> CloudMe {
        try await send("GET", "me")
    }

    func updateMe(_ change: UpdateMeRequest) async throws -> CloudMe {
        try await send("PATCH", "me", body: change)
    }

    func deleteAccount() async throws {
        try await sendEmpty("POST", "account/delete")
    }

    /// A one-time link that opens the web dashboard signed in as this account.
    func webSignInLink() async throws -> URL {
        let response: WebSignInLinkResponse = try await send("POST", "auth/handoff")
        return response.url
    }

    // MARK: Videos

    func createVideo(_ request: CreateVideoRequest) async throws -> CreateVideoResponse {
        try await send("POST", "videos", body: request)
    }

    func videos() async throws -> [VideoSummary] {
        try await send("GET", "videos")
    }

    func video(_ id: String) async throws -> VideoDetail {
        try await send("GET", "videos/\(id)")
    }

    @discardableResult
    func updateVideo(_ id: String, _ change: UpdateVideoRequest) async throws -> VideoDetail {
        try await send("PATCH", "videos/\(id)", body: change)
    }

    /// All files are up: the link can be watched. The server checks the video is stored, with this size.
    func finishUpload(_ id: String, size: Int64) async throws -> VideoDetail {
        try await updateVideo(id, UpdateVideoRequest(status: .ready, sizeBytes: size > 0 ? size : nil))
    }

    /// How far an upload is, for the watch page. Nothing depends on it, so failures are ignored (a server from before
    /// this call answers 404).
    func reportUpload(_ id: String, sent: Int64, total: Int64) async {
        try? await sendEmpty("POST", "videos/\(id)/progress", body: UploadProgressRequest(uploadedBytes: sent, totalBytes: total))
    }

    /// Stops sharing: the server deletes the files and keeps nothing.
    func deleteVideo(_ id: String) async throws {
        try await sendEmpty("DELETE", "videos/\(id)")
    }

    func insights(_ id: String) async throws -> CloudInsights {
        try await send("GET", "videos/\(id)/insights")
    }

    func activity(_ id: String) async throws -> CloudActivity {
        try await send("GET", "videos/\(id)/activity")
    }

    // MARK: Moderation

    func deleteComment(_ id: String) async throws {
        try await sendEmpty("DELETE", "comments/\(id)")
    }

    /// Publishes a comment the word filter held, so viewers can see it.
    func approveComment(_ id: String) async throws -> CloudComment {
        try await send("POST", "comments/\(id)/approve")
    }

    /// Blocks the viewer who wrote `commentID` (or sent `reactionID`) from all your videos.
    func block(commentID: String? = nil, reactionID: String? = nil) async throws {
        try await sendEmpty("POST", "blocks", body: BlockRequest(commentId: commentID, reactionId: reactionID))
    }

    // MARK: Devices and purchases

    func registerDevice(token: String, environment: String) async throws {
        try await sendEmpty("POST", "devices",
                            body: RegisterDeviceRequest(token: token, environment: environment, appVersion: AppInfo.version))
    }

    func unregisterDevice(token: String) async throws {
        try await sendEmpty("DELETE", "devices/\(token)")
    }

    func verifyPurchase(signedTransaction: String) async throws -> CloudPlan {
        let response: VerifyPurchaseResponse = try await send("POST", "purchases/verify",
                                                              body: VerifyPurchaseRequest(signedTransaction: signedTransaction))
        return response.plan
    }

    // MARK: - Transport

    private struct Nothing: Encodable {}

    private func send<Response: Decodable>(_ method: String, _ path: String) async throws -> Response {
        try await send(method, path, body: Optional<Nothing>.none)
    }

    private func send<Response: Decodable, Body: Encodable>(_ method: String, _ path: String,
                                                           body: Body?) async throws -> Response {
        let data = try await perform(method, path, body: body)
        do {
            return try CloudJSON.decoder.decode(Response.self, from: data)
        } catch {
            throw CloudError.unreadable
        }
    }

    private func sendEmpty(_ method: String, _ path: String) async throws {
        _ = try await perform(method, path, body: Optional<Nothing>.none)
    }

    private func sendEmpty<Body: Encodable>(_ method: String, _ path: String, body: Body) async throws {
        _ = try await perform(method, path, body: body)
    }

    private func perform<Body: Encodable>(_ method: String, _ path: String, body: Body?) async throws -> Data {
        #if DEBUG
        if let stub { return try stub.answer(method, path) }
        #endif
        guard CloudConfig.isConfigured else { throw CloudError.notConfigured }
        let auth = AuthService.shared
        var token = try await auth.validAccessToken()
        let bodyData = try body.map { try CloudJSON.encoder.encode($0) }
        for attempt in 0..<2 {
            var request = URLRequest(url: CloudConfig.apiBaseURL.appendingPathComponent(path))
            request.httpMethod = method
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let bodyData {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = bodyData
            }
            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                throw CloudError.from(network: error)
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch status {
            case 200..<300:
                return data
            case 401 where attempt == 0:
                token = try await auth.refresh().accessToken
                continue
            case 401:
                auth.clearLocal(keepsUploads: true)
                throw CloudError.signedOut
            case 402:
                let details = try? CloudJSON.decoder.decode(APIErrorBody.self, from: data)
                throw CloudError.limit(details?.reason ?? .proFeature)
            case 404, 410:
                throw CloudError.notFound
            default:
                let details = try? CloudJSON.decoder.decode(APIErrorBody.self, from: data)
                if status == 409, details?.error == "upload_incomplete" {
                    throw CloudError.incomplete(details?.missing ?? ["video.mp4"])
                }
                throw CloudError.server(status: status, message: details?.message)
            }
        }
        throw CloudError.signedOut
    }
}
