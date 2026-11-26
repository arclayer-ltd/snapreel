import Combine
import StoreKit
import UIKit

/// A Pro plan as the paywall shows it: the App Store's own localised price when it has
/// loaded. Until then there is no price to show, and buying waits for the App Store.
struct ProPlan: Identifiable, Hashable {
    enum Period: Hashable {
        case month
        case year
    }

    var id: String
    var period: Period
    /// "$39.99". The US price until the App Store answers; the paywall draws it as a blank.
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

/// How the last try at buying or restoring ended. Each one has something to show on the paywall.
enum PurchaseEnding: Equatable {
    /// Nothing tried yet.
    case none
    /// Bought. `PurchaseService.standing` says whether the server has it too.
    case purchased
    /// Ask to Buy, or a bank that has to approve first.
    case pending
    /// Apple's sheet was closed, or Apple gave up (a password that wasn't finished, for example).
    case cancelled
    /// This account already has that plan, so nothing was bought.
    case alreadyYours
    case restored
    /// Restore found no subscription on this Apple Account.
    case restoredNothing
    /// Apple's sheet for Restore was closed, so nothing was looked up.
    case restoreCancelled
    /// Anything else, in words for the person.
    case failed(String)
}

/// Snapreel Pro through StoreKit 2.
///
/// A purchase carries the user's id as `appAccountToken`, and its signed transaction (JWS) goes to
/// `POST /api/purchases/verify`, which checks it with Apple and stores the plan. Three rules keep it whole:
///
/// - **One purchase at a time.** `buy` takes the tap before anything slow happens, so a second tap
///   can't open Apple's sheet twice.
/// - **Nothing paid for is lost.** A transaction is finished only once the server has it. Until then
///   StoreKit keeps handing it back (`Transaction.unfinished`), and it is sent again: at once, after a
///   growing pause, when Snapreel comes to the foreground, after signing in and at the next launch.
/// - **The App Store and the server both count.** This Apple Account's entitlement switches Pro on
///   straight away, offline included, unless it belongs to another Snapreel account (`standing`).
@MainActor
final class PurchaseService: ObservableObject {
    static let shared = PurchaseService(backend: LivePurchaseBackend())

    /// Where this Apple Account's subscription and the signed-in Snapreel account stand.
    enum Standing: Equatable {
        /// This Apple Account has no running subscription.
        case none
        /// It has, and it is this account's.
        case subscribed
        /// It has, but the server hasn't confirmed it yet. Being sent again on its own.
        case confirming
        /// It has, but nobody is signed in to have it.
        case signInNeeded
        /// It has, but on another Snapreel account. `hint` is that account's masked address.
        case otherAccount(hint: String?, canMove: Bool)
        /// It has, but the server won't accept the transaction.
        case refused(String?)
        /// It ran out because Apple couldn't charge the renewal, and is still trying.
        case paymentProblem
    }

    enum Phase: Equatable {
        /// Checking what this account and Apple Account have, before asking Apple.
        case starting
        /// Apple has it: its sheet is coming up, or up.
        case appStore
        /// Bought; telling the server.
        case confirming
    }

    /// The purchase being made right now.
    struct Activity: Equatable {
        var productID: String
        var phase: Phase
        /// Apple hasn't answered for a while and its sheet isn't up.
        var isSlow = false
    }

    @Published private(set) var products: [String: Product] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var loadFailed = false
    /// Whether this Apple Account can still get the yearly plan's free week.
    @Published private(set) var trialEligible = false
    /// The plan this account is subscribed to right now, by StoreKit's word.
    @Published private(set) var activeProductID: String?
    @Published private(set) var activeExpiry: Date?
    @Published private(set) var willRenew: Bool?
    /// The plan the subscription changes to at the next renewal, when that's another one.
    @Published private(set) var nextProductID: String?
    @Published private(set) var standing: Standing = .none
    @Published private(set) var activity: Activity?
    @Published private(set) var ending: PurchaseEnding = .none
    /// Apple's subscription page is being opened (it can take seconds to draw).
    @Published private(set) var isOpeningManage = false
    /// The subscription is being moved to this account.
    @Published private(set) var isMoving = false

    /// The plan being bought right now.
    var purchasing: String? { activity?.productID }
    var hasLocalEntitlement: Bool { activeProductID != nil }
    /// A paywall is on screen, so a purchase finishing shows there instead of as a toast.
    var isPaywallOpen = false

    let backend: PurchaseBackend
    private let defaults: UserDefaults

    // Replaced by the tests.
    var fetchProducts: ([String]) async throws -> [Product] = { try await Product.products(for: $0) }
    var purchaseProduct: @MainActor (Product, Set<Product.PurchaseOption>) async throws -> Product.PurchaseResult = { product, options in
        // Apple's sheet goes to the scene it was asked from (iOS 17); before that StoreKit picks it.
        if #available(iOS 17.0, *), let scene = PurchaseService.activeScene {
            return try await product.purchase(confirmIn: scene, options: options)
        }
        return try await product.purchase(options: options)
    }
    var syncAppStore: () async throws -> Void = { try await AppStore.sync() }
    /// US app-store age laws (see `AgeGate`): nil to go ahead, or why not.
    var ageCheck: @MainActor () async -> String? = {
        let age = await AgeGate.check(.purchase)
        return AgeGate.message(for: age, moment: .purchase)
    }
    var announce: @MainActor (String) -> Void = {
        AppEnvironment.shared.router.showToast($0, systemImage: "checkmark.seal.fill")
    }
    var retryDelays: [Double] = [2, 4, 8, 15, 30, 60, 120, 300]
    /// Seconds in the foreground without Apple's answer before the paywall offers a way out.
    var slowAfter = 20
    /// How long a purchase just made stands on Apple's word alone.
    var settleTime: TimeInterval = 20

    private var held: Held?
    /// Just bought: the store's own list of entitlements can be a moment behind.
    private var fresh: (held: Held, at: Date)?
    private var reloads = 0
    private var hasPaymentProblem = false
    private var answers: [UInt64: Answer] = [:]
    private var acceptedTransactions: Set<UInt64> = []
    private var delivering: [UInt64: Task<Answer, Never>] = [:]
    private var loadTask: Task<Void, Never>?
    private var updatesTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    private var retryCount = 0
    private var attempt = 0
    private var observers: Set<AnyCancellable> = []

    init(backend: PurchaseBackend, defaults: UserDefaults = .standard) {
        self.backend = backend
        self.defaults = defaults
    }

    deinit {
        updatesTask?.cancel()
        retryTask?.cancel()
        expiryTask?.cancel()
    }

    static var activeScene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }

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
                           trialDays: nil, perMonth: nil, isPurchasable: false)
        }
    }

    /// "Save 44%" for the yearly plan against twelve months of the monthly one.
    var yearlySaving: Int? {
        #if DEBUG
        if debugPlans != nil { return 44 }
        #endif
        guard let yearly = products[CloudConfig.yearlyProductID], let monthly = products[CloudConfig.monthlyProductID],
              monthly.price > 0 else { return nil }
        let ratio = (yearly.price as NSDecimalNumber).doubleValue / ((monthly.price as NSDecimalNumber).doubleValue * 12)
        let saving = Int(((1 - ratio) * 100).rounded())
        return saving > 0 ? saving : nil
    }

    private var hasAllProducts: Bool { CloudConfig.productIDs.allSatisfy { products[$0] != nil } }

    /// Loads both plans from the App Store. Callers that arrive while it's loading wait for it.
    func loadProducts() async {
        #if DEBUG
        if debugPlans != nil { return }
        #endif
        if hasAllProducts { return }
        if let loadTask { return await loadTask.value }
        let task = Task { @MainActor in
            isLoading = true
            do {
                let loaded = try await fetchProducts(CloudConfig.productIDs)
                for product in loaded { products[product.id] = product }
                loadFailed = !hasAllProducts
            } catch {
                loadFailed = true
            }
            isLoading = false
            await refreshTrial()
        }
        loadTask = task
        await task.value
        loadTask = nil
    }

    /// Keeps asking until the plans are there, for as long as the caller (the paywall) is on screen.
    func keepLoadingProducts() async {
        var delay = 1.0
        while !Task.isCancelled {
            await loadProducts()
            if hasAllProducts { return }
            #if DEBUG
            if debugPlans != nil { return }
            #endif
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            delay = min(delay * 2, 15)
        }
    }

    private func refreshTrial() async {
        guard let subscription = products[CloudConfig.yearlyProductID]?.subscription else { return }
        trialEligible = await subscription.isEligibleForIntroOffer
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

    /// Starts buying `productID` for the signed-in account. The result is in `ending` and `standing`.
    /// Does nothing while another purchase is being made.
    func buy(_ productID: String) {
        guard activity == nil else { return }
        Task { @MainActor in await purchase(productID) }
        // Taken before the task runs, so a second tap finds it taken.
        activity = Activity(productID: productID, phase: .starting)
        ending = .none
    }

    /// `buy`, waiting for the end of it.
    @discardableResult
    func purchase(_ productID: String) async -> PurchaseEnding {
        if activity == nil {
            activity = Activity(productID: productID, phase: .starting)
            ending = .none
        }
        attempt += 1
        let mine = attempt
        let result = await runPurchase(productID, attempt: mine)
        if attempt == mine {
            activity = nil
            ending = result
            if result == .purchased { announceIfNeeded() }
        } else if result == .purchased, activity == nil {
            // The person stopped waiting, and then it went through after all.
            ending = .purchased
            announceIfNeeded()
        }
        return result
    }

    /// Stops waiting for an App Store that isn't answering, so the person can try again. If that
    /// purchase does go through later, it still counts.
    func stopWaiting() {
        guard let activity, activity.phase == .appStore else { return }
        attempt += 1
        self.activity = nil
        ending = .none
    }

    private func setPhase(_ phase: Phase, attempt: Int) {
        guard attempt == self.attempt, activity != nil else { return }
        activity?.phase = phase
        activity?.isSlow = false
    }

    private func runPurchase(_ productID: String, attempt: Int) async -> PurchaseEnding {
        guard let userID = backend.userID else { return .failed(CloudError.signedOut.message) }
        if let refusal = await ageCheck() { return .failed(refusal) }

        // What this Apple Account has already. Buying on top of a subscription gets Apple's "You're
        // already subscribed" at best, and for another Snapreel account's it would buy nothing.
        await reload()
        if let current = held {
            if !owns(current.transaction) || needsServer(current) {
                let answer = await deliver(current.verification)
                if case .other = answer { return .none } // the card for `standing` says it all
            }
            guard owns(current.transaction) else {
                return .failed("This Apple Account already has Snapreel Pro for another Snapreel account, and it can't be checked right now. Check your connection and try again.")
            }
            if current.transaction.productID == productID { return .alreadyYours }
        } else {
            // Pro from another Apple Account, or switched on or off since the plan was last read: the server's
            // word, before Apple's sheet offers to sell what the account has.
            await refreshPlanBriefly()
            if backend.serverIsPro { return .alreadyYours }
        }

        if products[productID] == nil { await loadProducts() }
        guard let product = products[productID] else { return .failed(PurchaseError.unavailable.text) }
        guard AppStore.canMakePayments else { return .failed(PurchaseError.notAllowed.text) }

        setPhase(.appStore, attempt: attempt)
        let watch = watchForSilence(attempt: attempt)
        defer { watch.cancel() }
        do {
            let result = try await purchaseProduct(product, [.appAccountToken(userID)])
            watch.cancel()
            switch result {
            case .success(let verification):
                setPhase(.confirming, attempt: attempt)
                return await bought(verification)
            case .pending:
                // A subscription that is already there (the approval was quick) wins.
                if let ending = await boughtAfterAll(productID) { return ending }
                pendingSince = Date()
                return .pending
            case .userCancelled:
                return await boughtAfterAll(productID) ?? .cancelled
            @unknown default:
                return await boughtAfterAll(productID) ?? .cancelled
            }
        } catch {
            watch.cancel()
            if let ending = await boughtAfterAll(productID) { return ending }
            return Self.ending(for: error)
        }
    }

    /// Apple took the purchase: Pro on this iPhone now, then the server.
    private func bought(_ verification: VerificationResult<Transaction>) async -> PurchaseEnding {
        pendingSince = nil
        if case .verified(let transaction) = verification, isRunning(transaction) {
            let bought = Held(verification: verification, transaction: transaction, expiry: transaction.expirationDate)
            fresh = (bought, Date())
            reloads += 1 // whatever is being read now is from before
            publish(bought)
        }
        _ = await deliver(verification)
        // StoreKit's own lists can take long to read (over a minute on a cold device): not in the way.
        Task { @MainActor in
            await reload()
            await refreshRenewal()
            await refreshTrial()
        }
        return .purchased
    }

    /// Apple said it didn't happen, or not yet. An interrupted purchase (Apple asked for a password,
    /// new terms or a card, and the person came back) is answered as cancelled and can still have
    /// gone through: believe the entitlement, not the answer.
    private func boughtAfterAll(_ productID: String) async -> PurchaseEnding? {
        guard let current = await currentHeld(), current.transaction.productID == productID,
              owns(current.transaction) else { return nil }
        return await bought(current.verification)
    }

    private func watchForSilence(attempt: Int) -> Task<Void, Never> {
        Task { @MainActor in
            var seconds = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                // Apple's sheet makes Snapreel inactive, so this counts only while nothing is up.
                seconds = UIApplication.shared.applicationState == .active ? seconds + 1 : 0
                guard !Task.isCancelled, attempt == self.attempt, activity?.phase == .appStore else { return }
                let slow = seconds >= slowAfter
                if activity?.isSlow != slow { activity?.isSlow = slow }
            }
        }
    }

    enum PurchaseError: LocalizedError {
        case unavailable
        case notAllowed

        var text: String {
            switch self {
            case .unavailable: return "The App Store isn't answering. Check your connection and try again."
            case .notAllowed: return "Purchases are switched off on this iPhone (Settings › Screen Time › Content & Privacy Restrictions)."
            }
        }

        var errorDescription: String? { text }
    }

    /// Apple's errors in words. None of these charged anybody.
    static func ending(for error: Error) -> PurchaseEnding {
        if let store = error as? StoreKitError {
            switch store {
            case .userCancelled: return .cancelled
            case .networkError: return .failed("The App Store can't be reached. Check your connection and try again. You haven't been charged.")
            case .notAvailableInStorefront: return .failed("Snapreel Pro isn't sold in your App Store country.")
            default: break
            }
        }
        if let purchase = error as? Product.PurchaseError {
            switch purchase {
            case .purchaseNotAllowed: return .failed(PurchaseError.notAllowed.text)
            case .productUnavailable: return .failed("This plan isn't available in your App Store country right now.")
            case .ineligibleForOffer: return .failed("This Apple Account can't use that offer. Try again for the normal price.")
            default: break
            }
        }
        return .failed("The App Store had a problem and nothing was bought. Try again in a moment.")
    }

    // MARK: - Restoring

    /// Restore Purchases: what this Apple Account has goes to the server. Apple is asked (with its
    /// password sheet) only when this iPhone knows of no subscription. Returns whether this account
    /// has one; `standing` says why not.
    func restore() async throws -> Bool {
        ending = .none
        answers = [:]
        await reload()
        if held == nil {
            try await syncAppStore()
            await reload()
        }
        await settle(force: true)
        await refreshRenewal()
        if held == nil { await backend.refreshPlan() }
        return hasLocalEntitlement
    }

    /// Restore from the paywall, with its ending.
    func restoreForPaywall() async {
        do {
            let found = try await restore()
            if found || backend.serverIsPro {
                ending = .restored
            } else if standing == .none || standing == .paymentProblem {
                ending = .restoredNothing
            }
        } catch {
            ending = Self.restoreProblem(error).map { .failed($0) } ?? .restoreCancelled
        }
    }

    /// Why a restore didn't finish, in words; nil when the person closed Apple's sheet.
    static func restoreProblem(_ error: Error) -> String? {
        if let storeKit = error as? StoreKitError {
            switch storeKit {
            case .userCancelled: return nil
            case .networkError: return "Restore didn't finish because you're offline. Check your connection and try again."
            default: break
            }
        }
        if error is URLError { return "Restore didn't finish because you're offline. Check your connection and try again." }
        return "Restore didn't finish: the App Store didn't answer. Try again in a moment."
    }

    /// Takes the subscription over from the other Snapreel account it is on. The person was asked.
    func moveHere() async {
        guard let held, !isMoving else { return }
        isMoving = true
        defer { isMoving = false }
        ending = .none
        switch await deliver(held.verification, move: true) {
        case .accepted:
            ending = .purchased
        case .other:
            ending = .failed("This subscription can't be moved. Sign in to the account it's on instead.")
        case .alreadyPro(let message):
            ending = .failed(message ?? "This Snapreel account already has Pro.")
        case .later:
            ending = .failed(CloudError.offline.message)
        case .signedOut:
            ending = .failed("Your session has ended. Sign in again.")
        case .refused(let message):
            ending = .failed(message ?? "Snapreel's server didn't accept this subscription.")
        }
    }

    // MARK: - The App Store's word

    private struct Held {
        let verification: VerificationResult<Transaction>
        let transaction: Transaction
        /// When it ends; in the billing grace period, when that ends.
        let expiry: Date?
    }

    /// Listens for transactions for as long as Snapreel runs: renewals, refunds, purchases on another
    /// device, Ask to Buy approvals, interrupted purchases. Started at launch.
    func startListening() {
        guard updatesTask == nil else { return }
        #if DEBUG
        // The unit tests run inside the app and make services of their own, on a test store that has to
        // be there before the App Store is first asked for anything.
        if self === Self.shared, ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        #endif
        updatesTask = Task { @MainActor [weak self] in
            for await update in Transaction.updates {
                await self?.received(update)
            }
        }
        backend.accountChanges
            .sink { [weak self] in Task { @MainActor in await self?.accountChanged() } }
            .store(in: &observers)
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in Task { @MainActor in await self?.becameActive() } }
            .store(in: &observers)
        Task { @MainActor [weak self] in
            await self?.reload()
        }
    }

    private func received(_ update: VerificationResult<Transaction>) async {
        let transaction = update.unsafePayloadValue
        guard CloudConfig.productIDs.contains(transaction.productID) else { return }
        if transaction.revocationDate != nil { fresh = nil }
        await reload()
        let answer = await deliver(update)
        await reload()
        if transaction.revocationDate != nil { await backend.refreshPlan() }
        // An approval that came through, or an interrupted purchase that went on without us.
        let waited = ending == .pending || ending == .cancelled || pendingSince != nil
        if waited, activity == nil, isRunning(transaction), owns(transaction) {
            pendingSince = nil
            ending = .purchased
            if answer == .accepted { announceIfNeeded() }
        }
        await refreshRenewal()
    }

    private func accountChanged() async {
        // Answers were for the other account, and so was the last purchase's ending.
        answers = [:]
        acceptedTransactions = []
        if activity == nil { ending = .none }
        // Pro goes with the account at once; reading StoreKit again can take long on a cold device.
        publish(held)
        await refreshEntitlements()
    }

    private func becameActive() async {
        #if DEBUG
        if debugPlans != nil { return }
        #endif
        // Mid-purchase the app becomes active each time an Apple sheet closes: the purchase itself
        // reports what happened.
        guard activity == nil else { return }
        retryTask?.cancel()
        retryTask = nil
        retryCount = 0
        await refreshEntitlements()
        if isPaywallOpen { await loadProducts() }
    }

    /// What this Apple Account has now, and the server told about it when it doesn't know.
    func refreshEntitlements(forceServer: Bool = false) async {
        #if DEBUG
        if debugPlans != nil { return }
        #endif
        await reload()
        await settle(force: forceServer)
        await refreshRenewal()
    }

    /// The server's plan, read again; a slow server isn't waited for long, and its answer still lands later.
    private func refreshPlanBriefly(_ seconds: Double = 4) async {
        let backend = backend
        // A race, not a task group: a group would wait for the request even after the time ran out.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let once = Once(continuation)
            Task { @MainActor in
                await backend.refreshPlan()
                once.resume()
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                once.resume()
            }
        }
    }

    /// Resumes a continuation the first time only.
    /// Both callers run on the main actor, one after the other.
    private final class Once {
        private var continuation: CheckedContinuation<Void, Never>?

        init(_ continuation: CheckedContinuation<Void, Never>) {
            self.continuation = continuation
        }

        func resume() {
            continuation?.resume()
            continuation = nil
        }
    }

    /// Reads what this Apple Account has and shows it, unless a newer reading overtook this one.
    private func reload() async {
        reloads += 1
        let mine = reloads
        let current = await currentHeld()
        if mine == reloads { publish(current) }
    }

    private func currentHeld() async -> Held? {
        var best: Held?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, transaction.productType == .autoRenewable,
                  CloudConfig.productIDs.contains(transaction.productID), transaction.revocationDate == nil,
                  !transaction.isUpgraded else { continue }
            var expiry = transaction.expirationDate
            if let date = expiry, date <= Date() {
                // Past its date, it counts only in Apple's billing grace period.
                guard let grace = await graceEnd(of: transaction) else { continue }
                expiry = grace
            }
            if best == nil || (expiry ?? .distantFuture) > (best?.expiry ?? .distantFuture) {
                best = Held(verification: result, transaction: transaction, expiry: expiry)
            }
        }
        if best == nil, let fresh, Date().timeIntervalSince(fresh.at) < settleTime, isRunning(fresh.held.transaction) {
            return fresh.held
        }
        return best
    }

    private func graceEnd(of transaction: Transaction) async -> Date? {
        guard let group = transaction.subscriptionGroupID,
              let statuses = try? await Product.SubscriptionInfo.status(for: group) else { return nil }
        for status in statuses where status.state == .inGracePeriod {
            guard case .verified(let renewal) = status.renewalInfo else { continue }
            if let end = renewal.gracePeriodExpirationDate, end > Date() { return end }
        }
        return nil
    }

    private func isRunning(_ transaction: Transaction) -> Bool {
        guard transaction.revocationDate == nil, !transaction.isUpgraded else { return false }
        return (transaction.expirationDate ?? .distantFuture) > Date()
    }

    /// Whether `transaction`'s subscription is the signed-in account's, as far as is known here.
    private func owns(_ transaction: Transaction) -> Bool {
        guard let user = backend.userID else { return false }
        if case .other = answers[transaction.originalID] { return false }
        let acceptedFor = acceptedOwner(of: transaction.originalID)
        if acceptedFor == user { return true }
        // Bought outside the app, and nobody's yet.
        if acceptedFor == nil, transaction.appAccountToken == nil { return true }
        return transaction.appAccountToken == user
    }

    private func publish(_ held: Held?) {
        #if DEBUG
        if debugPlans != nil { return }
        #endif
        self.held = held
        var mine: Held?
        if let held, owns(held.transaction) { mine = held }
        let had = activeProductID
        if activeProductID != mine?.transaction.productID { activeProductID = mine?.transaction.productID }
        if activeExpiry != mine?.expiry { activeExpiry = mine?.expiry }
        if mine == nil, willRenew != nil { willRenew = nil }
        if mine == nil, nextProductID != nil { nextProductID = nil }
        // Approved while waiting, and found by reading the App Store again rather than through `Transaction.updates`
        // (the approval came while Snapreel was closed, or another listener had it): bought, not "waiting".
        if let mine, ending == .pending, activity == nil, let since = pendingSince,
           mine.transaction.purchaseDate >= since.addingTimeInterval(-5) {
            pendingSince = nil
            ending = .purchased
            announceIfNeeded()
        }
        updateStanding()
        if (had == nil) != (activeProductID == nil) {
            backend.entitlementChanged()
            // It ended, was refunded or is another account's: the kept plan may say Pro for too long.
            if had != nil, backend.userID != nil { Task { @MainActor in await backend.refreshPlan() } }
        }
        scheduleExpiryCheck()
    }

    private func updateStanding() {
        var next: Standing = hasPaymentProblem ? .paymentProblem : .none
        if let held {
            if backend.userID == nil {
                next = .signInNeeded
            } else {
                let mine = owns(held.transaction)
                let confirmed = backend.serverIsPro || acceptedOwner(of: held.transaction.originalID) == backend.userID
                switch answers[held.transaction.originalID] {
                case .accepted: next = .subscribed
                case .other(let hint, let canMove): next = .otherAccount(hint: hint, canMove: canMove)
                case .refused(let message): next = backend.serverIsPro ? .subscribed : .refused(message)
                case .signedOut: next = .signInNeeded
                case .later, .alreadyPro: next = !mine ? .none : backend.serverIsPro ? .subscribed : .confirming
                case nil: next = !mine ? .none : confirmed ? .subscribed : .confirming
                }
            }
        }
        guard standing != next else { return }
        let caughtUp = standing == .confirming && next == .subscribed && ending == .purchased
        standing = next
        if caughtUp { announceIfNeeded() }
    }

    private func scheduleExpiryCheck() {
        expiryTask?.cancel()
        expiryTask = nil
        guard let expiry = activeExpiry else { return }
        let wait = expiry.timeIntervalSinceNow + 2
        guard wait > 0, wait < 86_400 * 7 else { return }
        expiryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.refreshEntitlements()
        }
    }

    /// Whether it renews, into what, and whether Apple is having trouble charging for it.
    private func refreshRenewal() async {
        guard let group = held?.transaction.subscriptionGroupID
                ?? products[CloudConfig.yearlyProductID]?.subscription?.subscriptionGroupID,
              let statuses = try? await Product.SubscriptionInfo.status(for: group) else { return }
        var problem = false
        for status in statuses {
            guard case .verified(let renewal) = status.renewalInfo, case .verified(let last) = status.transaction,
                  owns(last) else { continue }
            if status.state == .inBillingRetryPeriod { problem = true }
            if held != nil {
                willRenew = renewal.willAutoRenew
                nextProductID = renewal.willAutoRenew && renewal.autoRenewPreference != renewal.currentProductID
                    ? renewal.autoRenewPreference : nil
            }
        }
        hasPaymentProblem = problem
        updateStanding()
    }

    // MARK: - The server

    /// What came of sending a transaction to the server.
    private enum Answer: Equatable {
        case accepted
        case other(hint: String?, canMove: Bool)
        case alreadyPro(String?)
        case refused(String?)
        case signedOut
        /// No connection, or trouble on the server: sent again by itself.
        case later
    }

    /// Sends `verification` to the server, once however many places have it at the same time
    /// (the purchase itself and `Transaction.updates` both hand it over).
    private func deliver(_ verification: VerificationResult<Transaction>, move: Bool = false) async -> Answer {
        let transaction = verification.unsafePayloadValue
        if !move {
            if let running = delivering[transaction.id] { return await running.value }
            if acceptedTransactions.contains(transaction.id), transaction.revocationDate == nil, backend.serverIsPro {
                await transaction.finish()
                return .accepted
            }
        }
        let task = Task { @MainActor in await self.send(verification, move: move) }
        if !move { delivering[transaction.id] = task }
        let answer = await task.value
        if !move { delivering[transaction.id] = nil }
        return answer
    }

    private func send(_ verification: VerificationResult<Transaction>, move: Bool) async -> Answer {
        let transaction = verification.unsafePayloadValue
        let running = isRunning(transaction)
        var answer: Answer
        let user = backend.userID
        if let user {
            do {
                let plan = try await backend.verify(signedTransaction: verification.jwsRepresentation, move: move)
                // Signed out or into another account while it was on its way: that answer is about the
                // account before. The new one sends it itself (`accountChanged`).
                guard backend.userID == user else { return .signedOut }
                setAcceptedOwner(user, of: transaction.originalID)
                acceptedTransactions.insert(transaction.id)
                await transaction.finish()
                backend.apply(plan)
                answer = plan.tier == .pro || !running ? .accepted : .later
            } catch let error as PurchaseServerError {
                switch error {
                case .signedOut: answer = .signedOut
                case .offline, .unavailable: answer = .later
                case .otherAccount(let hint, let canMove): answer = .other(hint: hint, canMove: canMove)
                case .alreadyPro(let message): answer = .alreadyPro(message)
                case .refused(let message): answer = .refused(message)
                }
            } catch {
                answer = .later
            }
        } else {
            answer = .signedOut
        }
        if backend.userID != user { return .signedOut }

        if running {
            if case .alreadyPro = answer {} else { answers[transaction.originalID] = answer }
        } else if answer != .accepted, answer != .later {
            // Over and done with, and not this account's to send: Apple tells the server itself.
            await transaction.finish()
        }
        switch answer {
        case .accepted: retryCount = 0
        case .later: scheduleRetry()
        default: break
        }
        publish(held)
        return answer
    }

    private func needsServer(_ held: Held) -> Bool {
        if answers[held.transaction.originalID] == .later { return true }
        return !backend.serverIsPro
    }

    /// Sends the server whatever it hasn't got: unfinished transactions, and the running subscription
    /// when the account isn't on Pro there.
    private func settle(force: Bool = false) async {
        guard backend.userID != nil else { return }
        var waiting: [VerificationResult<Transaction>] = []
        for await result in Transaction.unfinished where CloudConfig.productIDs.contains(result.unsafePayloadValue.productID) {
            waiting.append(result)
        }
        var sent: Set<UInt64> = []
        for result in waiting {
            let transaction = result.unsafePayloadValue
            if !force, isRunning(transaction), isSettled(answers[transaction.originalID]) { continue }
            sent.insert(transaction.id)
            _ = await deliver(result)
        }
        guard let held, !sent.contains(held.transaction.id) else { return }
        if force || (needsServer(held) && !isSettled(answers[held.transaction.originalID])) {
            _ = await deliver(held.verification)
        }
    }

    /// The server has said no for this account; asking again gets the same answer.
    private func isSettled(_ answer: Answer?) -> Bool {
        switch answer {
        case .other, .refused: return true
        default: return false
        }
    }

    private func scheduleRetry() {
        guard retryTask == nil else { return }
        let delay = retryDelays[min(retryCount, retryDelays.count - 1)]
        retryCount += 1
        retryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.retryTask = nil
            await self.settle()
        }
    }

    /// Tries the server again now (the paywall's "Try now").
    func confirmNow() async {
        retryTask?.cancel()
        retryTask = nil
        retryCount = 0
        await reload()
        await settle(force: true)
    }

    private static let acceptedKey = "purchases.acceptedOwners"
    private static let pendingKey = "purchases.pendingSince"

    /// The Snapreel account the server last accepted a subscription for, kept so Pro holds offline
    /// when it isn't the account that bought it (moved, or bought outside the app).
    private func acceptedOwner(of originalID: UInt64) -> UUID? {
        let owners = defaults.dictionary(forKey: Self.acceptedKey) as? [String: String]
        return owners?[String(originalID)].flatMap(UUID.init(uuidString:))
    }

    private func setAcceptedOwner(_ user: UUID, of originalID: UInt64) {
        var owners = defaults.dictionary(forKey: Self.acceptedKey) as? [String: String] ?? [:]
        owners[String(originalID)] = user.uuidString
        defaults.set(owners, forKey: Self.acceptedKey)
    }

    /// Since when a purchase has been waiting for approval. Apple drops Ask to Buy requests after a day.
    private var pendingSince: Date? {
        get {
            guard let date = defaults.object(forKey: Self.pendingKey) as? Date,
                  Date().timeIntervalSince(date) < 86_400 else { return nil }
            return date
        }
        set { defaults.set(newValue, forKey: Self.pendingKey) }
    }

    private func announceIfNeeded() {
        if !isPaywallOpen { announce("Snapreel Pro is on") }
    }

    // MARK: - The paywall

    /// A paywall came up: what was on the last one is over, except a purchase still being made or
    /// waiting for approval.
    func paywallOpened() {
        isPaywallOpen = true
        #if DEBUG
        if debugPlans != nil { return }
        #endif
        if activity == nil { ending = pendingSince == nil ? .none : .pending }
        Task { @MainActor in
            // The plan may have changed since it was read (on the web, on another iPhone).
            if activity == nil { await backend.refreshPlan() }
            if activity == nil { await refreshEntitlements() }
            await refreshTrial()
        }
    }

    func paywallClosed() {
        isPaywallOpen = false
    }

    func clearEnding() {
        if activity == nil { ending = .none }
    }

    // MARK: - Managing

    /// Apple's own subscription sheet, where you change plan or cancel. Apple draws it, and it can
    /// stay blank for seconds on a slow connection; on iOS 17 and later it opens at Snapreel's own.
    func manageSubscriptions() {
        guard !isOpeningManage else { return }
        isOpeningManage = true
        Task { @MainActor in
            defer { isOpeningManage = false }
            do {
                guard let scene = Self.activeScene else { throw PurchaseError.unavailable }
                let group = held?.transaction.subscriptionGroupID
                    ?? products[CloudConfig.yearlyProductID]?.subscription?.subscriptionGroupID
                if #available(iOS 17.0, *), let group {
                    try await AppStore.showManageSubscriptions(in: scene, subscriptionGroupID: group)
                } else {
                    try await AppStore.showManageSubscriptions(in: scene)
                }
            } catch {
                if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                    _ = await UIApplication.shared.open(url)
                }
            }
            // Cancelled, changed or renewed in there.
            await refreshEntitlements()
        }
    }

    // MARK: - Debug

    #if DEBUG
    /// Fixture screens: plans to show without the App Store.
    var debugPlans: [ProPlan]?

    /// Fixture screens: pretend this Apple Account is (or isn't) subscribed.
    func debugSetActive(_ productID: String?, expiry: Date?) {
        activeProductID = productID
        activeExpiry = expiry
        willRenew = productID == nil ? nil : true
        nextProductID = nil
        standing = productID == nil ? .none : .subscribed
        ending = .none
        activity = nil
    }

    /// Fixture screens: any state of a purchase.
    func debugShow(_ standing: Standing = .none, ending: PurchaseEnding = .none, activity: Activity? = nil,
                   willRenew: Bool? = nil, next: String? = nil, loading: Bool = false, loadFailed: Bool = false) {
        self.standing = standing
        self.ending = ending
        self.activity = activity
        self.isLoading = loading
        self.loadFailed = loadFailed
        if let willRenew { self.willRenew = willRenew }
        nextProductID = next
    }
    #endif
}
