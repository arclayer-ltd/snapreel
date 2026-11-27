import CryptoKit
import Foundation
import SwiftUI

/// The signed-in session: Supabase Auth (GoTrue) tokens, kept in the Keychain.
struct AuthSession: Codable, Hashable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userID: String
    var email: String?

    /// The user's id as a UUID, for StoreKit's `appAccountToken`.
    var userUUID: UUID? { UUID(uuidString: userID) }
}

/// Signing in and staying signed in, by talking to GoTrue directly with URLSession (no SDK):
/// a 6-digit email code, or Sign in with Apple through its identity token. Every call sends
/// the publishable key as `apikey`. Owner calls to snapreel.video get the access token from
/// `validAccessToken()`, which refreshes it a minute before it runs out.
@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published private(set) var session: AuthSession?
    /// Who you are, your plan and usage (`GET /api/me`), kept so the screens know your plan offline.
    @Published private(set) var me: CloudMe?

    var isSignedIn: Bool { session != nil }

    /// Pro by the server's word, or by an App Store entitlement on this iPhone that the server
    /// hasn't confirmed yet (for example while offline after buying).
    var isPro: Bool { me?.isPro == true || PurchaseService.shared.hasLocalEntitlement }

    var email: String? { me?.user.email ?? session?.email }

    /// "Sam Lee", or the part of the email before the @.
    var displayName: String {
        if let name = me?.user.displayName?.trimmingCharacters(in: .whitespaces), !name.isEmpty { return name }
        if let email, let local = email.split(separator: "@").first { return String(local) }
        return "Your account"
    }

    private var refreshTask: Task<AuthSession, Error>?

    private static let sessionKey = "session"
    private static let meKey = "me"

    private init() {
        if let data = Keychain.data(for: Self.sessionKey) {
            session = try? CloudJSON.decoder.decode(AuthSession.self, from: data)
        }
        if session != nil, let data = Keychain.data(for: Self.meKey) {
            me = try? CloudJSON.decoder.decode(CloudMe.self, from: data)
        }
    }

    // MARK: - Email code

    /// Sends a 6-digit code to `email` (creates the account the first time).
    func sendCode(to email: String) async throws {
        struct Body: Encodable {
            var email: String
            var create_user = true
        }
        _ = try await gotrue("otp", body: Body(email: email))
    }

    /// Checks the code and signs in.
    func verify(email: String, code: String) async throws {
        struct Body: Encodable {
            var type = "email"
            var email: String
            var token: String
        }
        let data = try await gotrue("verify", body: Body(email: email, token: code))
        try await finishSignIn(with: data, fullName: nil)
    }

    // MARK: - Sign in with Apple

    /// Exchanges Apple's identity token for a session. `rawNonce` is the value whose SHA256
    /// went into the Apple request. Apple sends the name only the first time, so it is saved
    /// to the profile then.
    func signInWithApple(identityToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws {
        struct Body: Encodable {
            var provider = "apple"
            var id_token: String
            var nonce: String
        }
        let data = try await gotrue("token", query: "grant_type=id_token",
                                    body: Body(id_token: identityToken, nonce: rawNonce))
        try await finishSignIn(with: data, fullName: fullName)
    }

    /// A random nonce for Sign in with Apple.
    static func makeNonce(length: Int = 32) -> String {
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in characters[Int.random(in: 0..<characters.count, using: &generator)] })
    }

    /// Hex SHA256, as Apple expects in `ASAuthorizationAppleIDRequest.nonce`.
    static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Tokens

    /// A current access token, refreshed first when it runs out within `seconds` (a minute unless an upload needs it
    /// to stay good longer). When refreshing fails but the token is still good, the token is used.
    func validAccessToken(for seconds: TimeInterval = 60) async throws -> String {
        guard let current = session else { throw CloudError.signedOut }
        let left = current.expiresAt.timeIntervalSinceNow
        if left > seconds { return current.accessToken }
        do {
            return try await refresh().accessToken
        } catch {
            if left > 60, (error as? CloudError) != .signedOut { return current.accessToken }
            throw error
        }
    }

    /// Refreshes the session once, however many callers ask at the same time.
    @discardableResult
    func refresh() async throws -> AuthSession {
        if let refreshTask { return try await refreshTask.value }
        guard let current = session else { throw CloudError.signedOut }
        let task = Task { @MainActor () throws -> AuthSession in
            struct Body: Encodable { var refresh_token: String }
            do {
                let data = try await self.gotrue("token", query: "grant_type=refresh_token",
                                                 body: Body(refresh_token: current.refreshToken))
                let next = try Self.session(from: data, fallbackEmail: current.email)
                self.store(next)
                return next
            } catch CloudError.auth {
                // The refresh token was revoked or used up: sign out locally. Uploads wait for the next sign-in.
                self.clearLocal(keepsUploads: true)
                throw CloudError.signedOut
            }
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    // MARK: - Signing out

    /// Signs out on the server (best effort) and forgets the session here. Recordings stay.
    func signOut() async {
        await PushService.shared.unregister()
        if let session, CloudConfig.isConfigured, let url = CloudConfig.authURL?.appendingPathComponent("logout") {
            var request = URLRequest(url: url, timeoutInterval: 10)
            request.httpMethod = "POST"
            request.setValue(CloudConfig.publishableKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            _ = try? await URLSession.shared.data(for: request)
        }
        // Uploads wait and links stay with their recordings until someone else signs in (`finishSignIn`).
        clearLocal(keepsUploads: true)
    }

    /// Forgets the session, the cached profile and this iPhone's copy of your links. Used
    /// after signing out and after deleting the account. A session that ended by itself keeps its uploads, which carry
    /// on when the same person signs in again.
    func clearLocal(keepsUploads: Bool = false) {
        Keychain.remove(Self.sessionKey)
        Keychain.remove(Self.meKey)
        session = nil
        me = nil
        // Kept for the same person: uploads carry on and links show on their recordings when they sign in again.
        guard !keepsUploads else { return }
        Uploader.shared.cancelAll()
        AppEnvironment.shared.library.removeAllLinks()
        UserDefaults.standard.removeObject(forKey: Self.lastUserKey)
    }

    // MARK: - Profile and plan

    private var meTask: (user: String, task: Task<Void, Never>)?

    /// Reloads `me` from the server; quiet on failure. Callers at the same time share one request. The plan can
    /// change anywhere (the web, another iPhone, Apple), so screens that show it ask again when they appear.
    func refreshMe() async {
        guard let asked = session?.userID else { return }
        if let meTask, meTask.user == asked { return await meTask.task.value }
        let task = Task { @MainActor in
            guard let latest = try? await APIClient.shared.me() else { return }
            // Signed out, or into another account, while it was asked.
            guard self.session?.userID.lowercased() == asked.lowercased(),
                  latest.user.id.lowercased() == asked.lowercased() else { return }
            self.setMe(latest)
        }
        meTask = (asked, task)
        await task.value
        if meTask?.task == task { meTask = nil }
    }

    func setMe(_ latest: CloudMe) {
        me = latest
        #if DEBUG
        // Fixture screens keep nothing in the Keychain.
        if APIClient.shared.stub != nil { return }
        #endif
        if let data = try? CloudJSON.encoder.encode(latest) { Keychain.set(data, for: Self.meKey) }
    }

    /// Applies a plan the server returned (after a purchase was verified).
    func apply(plan: CloudPlan) {
        guard var current = me else { return }
        current.plan = plan
        if plan.tier == .pro {
            current.usage.linkLimit = nil
            current.usage.maxDurationS = CloudConfig.proMaxDuration
            current.usage.quality = "1080p"
        }
        setMe(current)
    }

    // MARK: - Private

    private func finishSignIn(with data: Data, fullName: PersonNameComponents?) async throws {
        let next = try Self.session(from: data, fallbackEmail: nil)
        let previous = UserDefaults.standard.string(forKey: Self.lastUserKey)
        store(next)
        // Someone else's links and uploads, kept since they signed out, go.
        if let previous, previous.lowercased() != next.userID.lowercased() {
            AppEnvironment.shared.library.removeAllLinks()
        }
        Uploader.shared.cancelJobs(notOwnedBy: next.userID)
        Haptics.success()
        await refreshMe()
        if let fullName, me?.user.displayName?.isEmpty ?? true {
            let name = PersonNameComponentsFormatter.localizedString(from: fullName, style: .default)
                .trimmingCharacters(in: .whitespaces)
            if !name.isEmpty, let updated = try? await APIClient.shared.updateMe(UpdateMeRequest(displayName: name)) {
                setMe(updated)
            }
        }
        CloudServices.didSignIn()
    }

    /// Who signed in last on this iPhone, also after signing out.
    private static let lastUserKey = "cloud.lastUserID"

    private func store(_ next: AuthSession) {
        session = next
        UserDefaults.standard.set(next.userID, forKey: Self.lastUserKey)
        if let data = try? CloudJSON.encoder.encode(next) { Keychain.set(data, for: Self.sessionKey) }
    }

    private struct GoTrueSession: Decodable {
        struct User: Decodable {
            var id: String
            var email: String?
        }

        var access_token: String
        var refresh_token: String
        var expires_in: Double?
        var expires_at: Double?
        var user: User?
    }

    private static func session(from data: Data, fallbackEmail: String?) throws -> AuthSession {
        guard let decoded = try? JSONDecoder().decode(GoTrueSession.self, from: data) else {
            throw CloudError.unreadable
        }
        let expiry: Date
        if let at = decoded.expires_at {
            expiry = Date(timeIntervalSince1970: at)
        } else {
            expiry = Date().addingTimeInterval(decoded.expires_in ?? 3_600)
        }
        let userID = decoded.user?.id ?? Self.subject(of: decoded.access_token) ?? ""
        return AuthSession(accessToken: decoded.access_token, refreshToken: decoded.refresh_token,
                           expiresAt: expiry, userID: userID, email: decoded.user?.email ?? fallbackEmail)
    }

    /// The `sub` claim of a JWT, when a refresh response leaves out the user.
    private static func subject(of jwt: String) -> String? {
        let parts = jwt.split(separator: ".")
        guard parts.count > 1 else { return nil }
        var base64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["sub"] as? String
    }

    private struct GoTrueError: Decodable {
        var error: String?
        var error_description: String?
        var error_code: String?
        var msg: String?
        var message: String?
    }

    /// POSTs `body` to `<SUPABASE_URL>/auth/v1/<path>` and returns the response body.
    private func gotrue<Body: Encodable>(_ path: String, query: String? = nil, body: Body) async throws -> Data {
        guard CloudConfig.isConfigured, let base = CloudConfig.authURL else { throw CloudError.notConfigured }
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.percentEncodedQuery = query
        guard let url = components?.url else { throw CloudError.notConfigured }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(CloudConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw CloudError.from(network: error)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let details = try? JSONDecoder().decode(GoTrueError.self, from: data)
            let code = details?.error_code ?? details?.error ?? ""
            if status == 429 { throw CloudError.auth("Too many tries. Wait a minute, then try again.") }
            if code.contains("otp") || code == "invalid_grant" || status == 403 {
                throw CloudError.auth(path == "verify"
                                      ? "That code didn't work. Check it, or send a new one."
                                      : "Your sign-in has expired. Sign in again.")
            }
            if code.contains("email") || status == 422 {
                throw CloudError.auth("Check the email address and try again.")
            }
            throw CloudError.server(status: status,
                                    message: details?.msg ?? details?.error_description ?? details?.message)
        }
        return data
    }

    // MARK: - Debug

    #if DEBUG
    /// Fixture screens: pretend to be signed in as `me` (nothing is stored or sent).
    func debugInstall(me fixture: CloudMe?) {
        if let fixture {
            session = AuthSession(accessToken: "debug", refreshToken: "debug",
                                  expiresAt: Date().addingTimeInterval(86_400),
                                  userID: fixture.user.id, email: fixture.user.email)
            me = fixture
        } else {
            session = nil
            me = nil
        }
    }
    #endif
}
