#if DEBUG
import SwiftUI

// Every way buying Snapreel Pro can go (ids under pro.buy.): on sample data, with no App Store and
// no server. `DebugCatalog.all` adds them with `+ purchaseScreens`.

extension DebugCatalog {
    static var purchaseScreens: [DebugScreen] {
        let yearly = CloudConfig.yearlyProductID
        return [
            purchase("pro.buy.loading", "Paywall [prices loading]", hasPrices: false) {
                $0.debugShow(loading: true)
            },
            purchase("pro.buy.noprices", "Paywall [App Store not answering]", hasPrices: false) {
                $0.debugShow(loadFailed: true)
            },
            purchase("pro.buy.starting", "Paywall [tapped, checking first]") {
                $0.debugShow(activity: .init(productID: yearly, phase: .starting))
            },
            purchase("pro.buy.waiting", "Paywall [waiting for the App Store]") {
                $0.debugShow(activity: .init(productID: yearly, phase: .appStore))
            },
            purchase("pro.buy.slow", "Paywall [App Store taking long, stop waiting]") {
                $0.debugShow(activity: .init(productID: yearly, phase: .appStore, isSlow: true))
            },
            purchase("pro.buy.switching", "Paywall [bought, switching on]") {
                $0.debugShow(activity: .init(productID: yearly, phase: .confirming))
            },
            purchase("pro.buy.cancelled", "Paywall [cancelled]") { $0.debugShow(ending: .cancelled) },
            purchase("pro.buy.pending", "Paywall [waiting for approval]") { $0.debugShow(ending: .pending) },
            purchase("pro.buy.offline", "Paywall [failed: App Store unreachable]") {
                $0.debugShow(ending: .failed("The App Store can't be reached. Check your connection and try again. You haven't been charged."))
            },
            purchase("pro.buy.notallowed", "Paywall [failed: purchases switched off]") {
                $0.debugShow(ending: .failed(PurchaseService.PurchaseError.notAllowed.text))
            },
            purchase("pro.buy.confirming", "Paywall [paid, server not reached yet]") {
                $0.debugShow(.confirming, ending: .purchased)
            },
            purchase("pro.buy.refused", "Paywall [paid, server can't confirm]") { $0.debugShow(.refused(nil)) },
            purchase("pro.buy.other", "Paywall [Pro is on another account]") {
                $0.debugShow(.otherAccount(hint: "s•••y@example.com", canMove: true))
            },
            purchase("pro.buy.other.fixed", "Paywall [Pro is on another account, can't be moved]") {
                $0.debugShow(.otherAccount(hint: nil, canMove: false),
                             ending: .failed("This subscription can't be moved. Sign in to the account it's on instead."))
            },
            purchase("pro.buy.signin", "Paywall [this Apple Account has Pro, signed out]", .signedOut) {
                $0.debugShow(.signInNeeded)
            },
            purchase("pro.buy.nothing", "Paywall [nothing to restore]") { $0.debugShow(ending: .restoredNothing) },
            purchase("pro.buy.payment", "Paywall [renewal couldn't be charged]") { $0.debugShow(.paymentProblem) },
            purchase("pro.buy.welcome", "Paywall [bought on the way to a link]", .pro, reason: .duration(555), continues: true,
                     outcome: .purchased) { _ in },
            purchase("pro.buy.restored", "Paywall [restored]", .pro, outcome: .restored) { _ in },
            purchase("pro.buy.already", "Paywall [already yours]", .pro) {
                $0.debugShow(.subscribed, ending: .alreadyYours)
            },
            purchase("pro.buy.upgrade", "Paywall [monthly, can switch to yearly]", .pro) {
                $0.debugSetActive(CloudConfig.monthlyProductID, expiry: Date().addingTimeInterval(86_400 * 19))
            },
            purchase("pro.buy.ending", "Paywall [cancelled, ends at the end of the period]", .pro) {
                $0.debugShow(.subscribed, willRenew: false)
            },
            purchase("pro.buy.downgrade", "Paywall [changes to monthly at renewal]", .pro) {
                $0.debugShow(.subscribed, next: CloudConfig.monthlyProductID)
            },
        ]
    }

    private static func purchase(_ id: String, _ title: String, _ scenario: CloudFixtures.Scenario = .free,
                                 hasPrices: Bool = true, reason: PaywallReason = .settings, continues: Bool = false,
                                 outcome: PurchaseEnding = .none,
                                 _ show: @escaping @MainActor (PurchaseService) -> Void) -> DebugScreen {
        DebugScreen(id, title, wait: 3.5) {
            ProDebugHost(scenario, present: {
                let store = PurchaseService.shared
                if !hasPrices {
                    store.debugPlans = store.debugPlans?.map {
                        ProPlan(id: $0.id, period: $0.period, displayPrice: $0.displayPrice, trialDays: nil, perMonth: nil,
                                isPurchasable: false)
                    }
                }
                show(store)
            }) {
                NavigationStack {
                    PaywallView(reason: reason, outcome: outcome, continues: continues, onClose: {})
                }
            }
        }
    }
}
#endif
