import StoreKit
import SwiftUI
import UIKit

/// A Pro plan as the paywall shows it: the App Store's own localised price when it has
/// loaded, otherwise the US price as a placeholder (and buying waits for the App Store).
struct ProPlan: Identifiable, Hashable {
    enum Period: Hashable {
        case month
        case year
    }

    var id: String
    var period: Period
    /// "$39.99"
    var displayPrice: String
    /// Days of free trial this Apple Account can still get, if any.
    var trialDays: Int?
    /// "$3.33 a month", for the yearly plan.
    var perMonth: String?
    /// True when the price came from the App Store, so the plan can be bought.
    var isPurchasable: Bool

    /// "a year", "a month".
    var periodText: String { period == .year ? "a year" : "a month" }
    var title: String { period == .year ? "Yearly" : "Monthly" }

    /// "1 week free, then $39.99 a year" or "$5.99 a month".
    var priceLine: String {
        if let trialDays { return "\(Self.trialText(trialDays)) free, then \(displayPrice) \(periodText)" }
        return "\(displayPrice) \(periodText)"
    }

    static func trialText(_ days: Int) -> String {
        switch days {
        case 7: return "1 week"
        case 14: return "2 weeks"
        case 30, 31: return "1 month"
        case 1: return "1 day"
        default: return days % 7 == 0 ? "\(days / 7) weeks" : "\(days) days"
        }
    }
}

enum PurchaseOutcome: Equatable {
    case purchased
    case pending
    case cancelled
}

/// Snapreel Pro through StoreKit 2. A purchase carries the user's id as `appAccountToken`,
/// and its signed transaction (JWS) goes to `POST /api/purchases/verify`, which checks it with
/// Apple and stores the plan. `Transaction.updates` catches renewals, purchases made elsewhere
/// and Ask to Buy approvals; `currentEntitlements` says what this Apple Account has now.
@MainActor
final class PurchaseService: ObservableObject {
    static let shared = PurchaseService()

    @Published private(set) var products: [String: Product] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var loadFailed = false
    /// Whether this Apple Account can still get the yearly plan's free week.
    @Published private(set) var trialEligible = true
    /// The plan this Apple Account is subscribed to right now, by StoreKit's word.
    @Published private(set) var activeProductID: String?
    @Published private(set) var activeExpiry: Date?
    @Published private(set) var willRenew: Bool?
    /// The plan being bought right now.
    @Published var purchasing: String?

    #if DEBUG
    /// Fixture screens: plans to show without the App Store.
    var debugPlans: [ProPlan]?

    /// Fixture screens: pretend this Apple Account is (or isn't) subscribed.
    func debugSetActive(_ productID: String?, expiry: Date?) {
        activeProductID = productID
        activeExpiry = expiry
        willRenew = productID == nil ? nil : true
    }
    #endif

    var hasLocalEntitlement: Bool { activeProductID != nil }

    private var updatesTask: Task<Void, Never>?

    private init() {}

    // MARK: - Plans

    var plans: [ProPlan] {
        #if DEBUG
        if let debugPlans { return debugPlans }
        #endif
        return CloudConfig.productIDs.map { id in
            let period: ProPlan.Period = id == CloudConfig.yearlyProductID ? .year : .month
            if let product = products[id] {
                var trial: Int?
                if trialEligible, let offer = product.subscription?.introductoryOffer, offer.paymentMode == .freeTrial {
                    trial = Self.days(offer.period)
                }
                var perMonth: String?
                if period == .year {
                    let monthly = product.price / 12
                    perMonth = monthly.formatted(product.priceFormatStyle) + " a month"
                }
                return ProPlan(id: id, period: period, displayPrice: product.displayPrice, trialDays: trial,
                               perMonth: perMonth, isPurchasable: true)
            }
            return ProPlan(id: id, period: period,
                           displayPrice: period == .year ? CloudConfig.fallbackYearlyPrice : CloudConfig.fallbackMonthlyPrice,
                           trialDays: period == .year && trialEligible ? 7 : nil,
                           perMonth: period == .year ? "$3.33 a month" : nil, isPurchasable: false)
        }
    }

    /// "Save 44%" for the yearly plan against twelve months of the monthly one.
    var yearlySaving: Int? {
        guard let yearly = products[CloudConfig.yearlyProductID], let monthly = products[CloudConfig.monthlyProductID],
              monthly.price > 0 else { return 44 }
        let ratio = (yearly.price as NSDecimalNumber).doubleValue / ((monthly.price as NSDecimalNumber).doubleValue * 12)
        let saving = Int(((1 - ratio) * 100).rounded())
        return saving > 0 ? saving : nil
    }

    func loadProducts() async {
        #if DEBUG
        if debugPlans != nil { return }
        #endif
        guard products.isEmpty, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await Product.products(for: CloudConfig.productIDs)
            products = Dictionary(loaded.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            loadFailed = loaded.isEmpty
            if let yearly = products[CloudConfig.yearlyProductID], let subscription = yearly.subscription {
                trialEligible = await subscription.isEligibleForIntroOffer
            }
        } catch {
            loadFailed = true
        }
    }

    private static func days(_ period: Product.SubscriptionPeriod) -> Int {
        switch period.unit {
        case .day: return period.value
        case .week: return period.value * 7
        case .month: return period.value * 30
        case .year: return period.value * 365
        @unknown default: return period.value
        }
    }

    // MARK: - Buying

    /// Buys `productID` for the signed-in user. Throws `CloudError.signedOut` without a session.
    func purchase(_ productID: String) async throws -> PurchaseOutcome {
        guard let userID = AuthService.shared.session?.userUUID else { throw CloudError.signedOut }
        if products.isEmpty { await loadProducts() }
        guard let product = products[productID] else { throw PurchaseError.unavailable }
        purchasing = productID
        defer { purchasing = nil }
        let result = try await product.purchase(options: [.appAccountToken(userID)])
        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else { throw PurchaseError.unverified }
            await sendToServer(verification.jwsRepresentation)
            await transaction.finish()
            await refreshEntitlements()
            return .purchased
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    /// Restore Purchases: asks the App Store to sync, then sends what this Apple Account has to
    /// the server. Returns whether a subscription was found.
    func restore() async throws -> Bool {
        try await AppStore.sync()
        await refreshEntitlements(forceServer: true)
        return hasLocalEntitlement
    }

    enum PurchaseError: LocalizedError {
        case unavailable
        case unverified

        var errorDescription: String? {
            switch self {
            case .unavailable: return "The App Store isn't answering. Check your connection and try again."
            case .unverified: return "The App Store couldn't confirm this purchase."
            }
        }
    }

    // MARK: - Entitlements

    /// Listens for transactions for as long as Snapreel runs: renewals, refunds, purchases on
    /// another device, Ask to Buy approvals. Started at launch.
    func startListening() {
        guard updatesTask == nil else { return }
        updatesTask = Task { @MainActor in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await self.sendToServer(update.jwsRepresentation)
                    await transaction.finish()
                }
                await self.refreshEntitlements()
            }
        }
    }

    /// What this Apple Account has now. When the server still thinks you're on Free (a
    /// purchase it never heard about), the newest entitlement is sent to it.
    func refreshEntitlements(forceServer: Bool = false) async {
        #if DEBUG
        if debugPlans != nil { return }
        #endif
        var newest: (id: String, expiry: Date?, jws: String)?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, transaction.productType == .autoRenewable,
                  transaction.revocationDate == nil, CloudConfig.productIDs.contains(transaction.productID) else { continue }
            if let expiry = transaction.expirationDate, expiry < Date() { continue }
            if newest == nil || (transaction.expirationDate ?? .distantFuture) > (newest?.expiry ?? .distantPast) {
                newest = (transaction.productID, transaction.expirationDate, result.jwsRepresentation)
            }
        }
        activeProductID = newest?.id
        activeExpiry = newest?.expiry
        if let id = newest?.id, let product = products[id], let statuses = try? await product.subscription?.status {
            for status in statuses {
                if case .verified(let renewal) = status.renewalInfo { willRenew = renewal.willAutoRenew }
            }
        }
        guard let newest, AuthService.shared.isSignedIn else { return }
        if forceServer || AuthService.shared.me?.isPro != true {
            await sendToServer(newest.jws)
        }
    }

    private func sendToServer(_ jws: String) async {
        guard AuthService.shared.isSignedIn, CloudConfig.isConfigured else { return }
        if let plan = try? await APIClient.shared.verifyPurchase(signedTransaction: jws) {
            AuthService.shared.apply(plan: plan)
        }
    }

    // MARK: - Managing

    /// Apple's own subscription sheet, where you change plan or cancel.
    func manageSubscriptions() {
        Task { @MainActor in
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
            if let scene {
                try? await AppStore.showManageSubscriptions(in: scene)
            } else if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                _ = await UIApplication.shared.open(url)
            }
        }
    }
}
