import Combine
import Foundation

/// What the server says about a purchase it was sent, when it isn't a plain yes.
enum PurchaseServerError: Error, Equatable {
    /// Not signed in, or the session has ended.
    case signedOut
    /// No connection.
    case offline
    /// The subscription is on another Snapreel account. `hint` is that account's masked address
    /// ("r•••n@gmail.com"); `canMove` when it can be moved here.
    case otherAccount(hint: String?, canMove: Bool)
    /// This account already has Pro from another subscription, so this one can't be moved to it.
    case alreadyPro(String?)
    /// It didn't accept the transaction, and would say the same next time.
    case refused(String?)
    /// It had a problem of its own. Worth trying again.
    case unavailable
}

/// The Snapreel account and server, as `PurchaseService` needs them. Tests use their own.
@MainActor
protocol PurchaseBackend: AnyObject {
    /// The signed-in account, which a purchase is made for (StoreKit's `appAccountToken`).
    var userID: UUID? { get }
    /// Whether the server's last answer had this account on Pro.
    var serverIsPro: Bool { get }
    /// Emits after the signed-in account has changed.
    var accountChanges: AnyPublisher<Void, Never> { get }

    /// `POST /api/purchases/verify`. Throws `PurchaseServerError`.
    func verify(signedTransaction: String, move: Bool) async throws -> CloudPlan
    /// Shows `plan` everywhere straight away.
    func apply(_ plan: CloudPlan)
    /// Asks the server for the account's plan again; quiet on failure.
    func refreshPlan() async
    /// The App Store's word on this account changed: screens showing the plan redraw.
    func entitlementChanged()
}

/// The real account (`AuthService`) and server (snapreel.video).
@MainActor
final class LivePurchaseBackend: PurchaseBackend {
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    var userID: UUID? { AuthService.shared.session?.userUUID }
    var serverIsPro: Bool { AuthService.shared.me?.isPro == true }

    lazy var accountChanges: AnyPublisher<Void, Never> = AuthService.shared.$session
        .map { $0?.userID }
        .removeDuplicates()
        .dropFirst()
        // @Published emits before the value is set.
        .receive(on: DispatchQueue.main)
        .map { _ in () }
        .eraseToAnyPublisher()

    func apply(_ plan: CloudPlan) {
        if AuthService.shared.me == nil {
            Task { await self.refreshPlan() }
        } else {
            AuthService.shared.apply(plan: plan)
        }
    }

    func refreshPlan() async {
        await AuthService.shared.refreshMe()
    }

    func entitlementChanged() {
        // `AuthService.isPro` reads the entitlement, but most screens only watch `AuthService`.
        AuthService.shared.objectWillChange.send()
    }

    private struct Request: Encodable {
        var signedTransaction: String
        var move: Bool?
    }

    private struct Failure: Decodable {
        var error: String?
        var message: String?
        var hint: String?
        var canMove: Bool?
    }

    func verify(signedTransaction: String, move: Bool) async throws -> CloudPlan {
        #if DEBUG
        if APIClient.shared.stub != nil { throw PurchaseServerError.offline }
        #endif
        guard CloudConfig.isConfigured else { throw PurchaseServerError.unavailable }
        let body = try CloudJSON.encoder.encode(Request(signedTransaction: signedTransaction, move: move ? true : nil))
        var token = try await accessToken()
        for attempt in 0..<2 {
            var request = URLRequest(url: CloudConfig.apiBaseURL.appendingPathComponent("purchases/verify"))
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = body
            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                throw PurchaseServerError.offline
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(status) {
                guard let answer = try? CloudJSON.decoder.decode(VerifyPurchaseResponse.self, from: data) else {
                    throw PurchaseServerError.unavailable
                }
                return answer.plan
            }
            if status == 401, attempt == 0 {
                token = try await accessToken(refreshing: true)
                continue
            }
            let failure = try? CloudJSON.decoder.decode(Failure.self, from: data)
            throw Self.error(status: status, code: failure?.error, message: failure?.message,
                             hint: failure?.hint, canMove: failure?.canMove)
        }
        throw PurchaseServerError.signedOut
    }

    /// What an HTTP answer means for the purchase. Anything unclear is worth another try:
    /// giving up on a paid transaction is the one thing that must not happen by mistake.
    static func error(status: Int, code: String?, message: String?, hint: String?, canMove: Bool?) -> PurchaseServerError {
        switch (status, code) {
        case (401, _): return .signedOut
        case (403, "other_account"): return .otherAccount(hint: hint, canMove: canMove ?? false)
        case (409, "already_pro"): return .alreadyPro(message)
        case (400, "invalid_signature"), (400, "wrong_app"), (400, "unknown_product"), (400, "bad_request"):
            return .refused(message)
        default: return .unavailable
        }
    }

    private func accessToken(refreshing: Bool = false) async throws -> String {
        do {
            return refreshing ? try await AuthService.shared.refresh().accessToken
                : try await AuthService.shared.validAccessToken()
        } catch CloudError.signedOut {
            throw PurchaseServerError.signedOut
        } catch CloudError.auth {
            throw PurchaseServerError.signedOut
        } catch CloudError.offline {
            throw PurchaseServerError.offline
        } catch {
            throw PurchaseServerError.unavailable
        }
    }
}
