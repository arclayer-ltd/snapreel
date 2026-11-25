import Combine
import StoreKit
import StoreKitTest
import XCTest
@testable import Snapreel

/// A Snapreel account and server that answer as each test needs.
@MainActor
final class FakeBackend: PurchaseBackend {
    struct Sent: Equatable {
        var transactionID: String
        var token: UUID?
        var move: Bool
    }

    private let changes = PassthroughSubject<Void, Never>()
    var accountChanges: AnyPublisher<Void, Never> { changes.eraseToAnyPublisher() }

    var userID: UUID? {
        didSet {
            guard userID != oldValue else { return }
            serverIsPro = false
            changes.send()
        }
    }
    var serverIsPro = false
    /// What `refreshPlan` finds; nil leaves it as it is.
    var planOnServer: Bool?
    private(set) var sent: [Sent] = []
    private(set) var refreshes = 0
    private(set) var changesSeen = 0
    /// Thrown instead of accepting.
    var failure: PurchaseServerError?
    /// Holds each answer back this long.
    var delay: Double = 0
    /// Decides instead of `failure`.
    var decide: ((Sent) throws -> CloudPlan)?

    init(user: UUID? = UUID()) {
        userID = user
    }

    func verify(signedTransaction: String, move: Bool) async throws -> CloudPlan {
        let claims = Self.claims(signedTransaction)
        let item = Sent(transactionID: claims["transactionId"] as? String ?? "?",
                        token: (claims["appAccountToken"] as? String).flatMap(UUID.init(uuidString:)), move: move)
        sent.append(item)
        if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        if let decide { return try decide(item) }
        if let failure { throw failure }
        return Self.pro
    }

    func apply(_ plan: CloudPlan) { serverIsPro = plan.tier == .pro }

    func refreshPlan() async {
        refreshes += 1
        if let planOnServer { serverIsPro = planOnServer }
    }

    func entitlementChanged() { changesSeen += 1 }

    static let pro = CloudPlan(tier: .pro, productId: CloudConfig.yearlyProductID,
                               expiresAt: Date().addingTimeInterval(86_400 * 7))

    static func claims(_ jws: String) -> [String: Any] {
        let parts = jws.split(separator: ".")
        guard parts.count == 3 else { return [:] }
        var base64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}

/// A StoreKit test store, a fake account, and the purchase service between them.
@MainActor
class PurchaseTestCase: XCTestCase {
    let yearly = CloudConfig.yearlyProductID
    let monthly = CloudConfig.monthlyProductID
    let alice = UUID()
    let bob = UUID()

    var session: SKTestSession!
    var backend: FakeBackend!
    var service: PurchaseService!
    var defaults: UserDefaults!
    /// Every time Apple's purchase sheet would have come up.
    var sheets = 0
    var announcements: [String] = []
    private var suite = ""

    override func setUp() async throws {
        try await super.setUp()
        session = try Self.makeSession()
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        suite = "purchase-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        backend = FakeBackend(user: alice)
        sheets = 0
        announcements = []
        service = makeService()
        await settleStore()
    }

    override func tearDown() async throws {
        session?.clearTransactions()
        defaults?.removePersistentDomain(forName: suite)
        service = nil
        session = nil
        try await super.tearDown()
    }

    /// Transactions of the test before can take a moment to go.
    private func settleStore() async {
        _ = await eventually(5) { await self.entitlements() == 0 }
    }

    private static func makeSession() throws -> SKTestSession {
        let beside = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Snapreel.storekit")
        let url = Bundle(for: PurchaseTestCase.self).url(forResource: "Snapreel", withExtension: "storekit") ?? beside
        if #available(iOS 17.0, *) { return try SKTestSession(contentsOf: url) }
        return try SKTestSession(configurationFileNamed: "Snapreel")
    }

    /// As after a relaunch, when made a second time: the same store, the same server.
    func makeService() -> PurchaseService {
        let service = PurchaseService(backend: backend, defaults: defaults)
        service.ageCheck = { nil }
        service.announce = { [weak self] in self?.announcements.append($0) }
        service.retryDelays = [0.3]
        service.syncAppStore = {}
        service.purchaseProduct = { [weak self] product, options in
            guard let self else { throw StoreKitError.unknown }
            return .success(try await self.buyInStore(product, options))
        }
        return service
    }

    /// Apple's sheet, with the person tapping Subscribe.
    ///
    /// On the iOS 26 and 27 simulators `product.purchase()` leaves the test store and waits for a real
    /// Apple Account to be typed in, so from iOS 17 on the test store makes the purchase. The
    /// transaction is the same: signed, with the token, in `unfinished` and `currentEntitlements`, and
    /// in `Transaction.updates` as well, as happens on iPhones.
    func buyInStore(_ product: Product, _ options: Set<Product.PurchaseOption>) async throws -> VerificationResult<Transaction> {
        sheets += 1
        if #available(iOS 17.0, *) {
            let bought = try await session.buyProduct(identifier: product.id, options: options)
            for await result in Transaction.all where result.unsafePayloadValue.id == bought.id { return result }
        } else if case .success(let result) = try await product.purchase(options: options) {
            return result
        }
        throw StoreKitError.unknown
    }

    /// Bought without Snapreel: on the App Store's page, with an offer code, or a purchase that was
    /// held up and went through later (`token` is whoever started it).
    func arrivesLater(_ productID: String, token: UUID?) async throws {
        if #available(iOS 17.0, *) {
            _ = try await session.buyProduct(identifier: productID, options: token.map { [.appAccountToken($0)] } ?? [])
        } else if let token {
            let found = try await Product.products(for: [productID])
            _ = try await XCTUnwrap(found.first).purchase(options: [.appAccountToken(token)])
        } else {
            try session.buyProduct(productIdentifier: productID)
        }
    }

    func eventually(_ seconds: Double = 8, _ condition: @escaping @MainActor () async -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return await condition()
    }

    func assertEventually(_ what: String, _ seconds: Double = 8, file: StaticString = #filePath, line: UInt = #line,
                          _ condition: @escaping @MainActor () async -> Bool) async {
        let held = await eventually(seconds, condition)
        XCTAssertTrue(held, what + " (standing \(service.standing), ending \(service.ending), sent \(backend.sent.count))",
                      file: file, line: line)
    }

    func entitlements() async -> Int {
        var count = 0
        for await _ in Transaction.currentEntitlements { count += 1 }
        return count
    }

    func unfinished() async -> Int {
        var count = 0
        for await _ in Transaction.unfinished { count += 1 }
        return count
    }

    /// The newest transaction in the test store.
    func latest() throws -> SKTestTransaction {
        try XCTUnwrap(session.allTransactions().max { $0.identifier < $1.identifier })
    }
}
