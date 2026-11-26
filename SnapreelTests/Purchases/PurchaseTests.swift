import StoreKit
import StoreKitTest
import XCTest
@testable import Snapreel

/// Buying Snapreel Pro, against a StoreKit test store and a server that answers as it likes.
@MainActor
final class PurchaseTests: PurchaseTestCase {

    // MARK: - Buying

    func testBuyingWorksTheFirstTime() async throws {
        try needsTestStore()
        let ending = await service.purchase(yearly)
        XCTAssertEqual(ending, .purchased)
        XCTAssertEqual(service.ending, .purchased)
        XCTAssertEqual(service.standing, .subscribed)
        XCTAssertEqual(service.activeProductID, yearly)
        XCTAssertTrue(service.hasLocalEntitlement)
        XCTAssertNil(service.activity)
        XCTAssertEqual(sheets, 1)
        XCTAssertEqual(backend.sent.count, 1, "the server hears about it once")
        XCTAssertEqual(backend.sent.first?.token, alice)
        XCTAssertGreaterThan(backend.changesSeen, 0, "screens that watch the account redraw")
        // Finished before `purchase` returned; iOS 16's list of unfinished ones can take a moment to follow.
        await assertEventually("finished once the server had it", 10) { await self.unfinished() == 0 }
    }

    func testBuyingWorksWithPlansNotLoadedYet() async throws {
        try needsTestStore()
        XCTAssertTrue(service.products.isEmpty)
        let ending = await service.purchase(monthly)
        XCTAssertEqual(ending, .purchased)
        XCTAssertEqual(service.activeProductID, monthly)
    }

    /// (f) Two quick taps used to start two purchases, and Apple's sheet came up twice.
    func testADoubleTapBuysOnce() async throws {
        try needsTestStore()
        await service.loadProducts()
        service.buy(yearly)
        XCTAssertNotNil(service.activity, "taken before anything slow happens")
        service.buy(yearly)
        service.buy(monthly)
        await assertEventually("bought") { self.service.ending == .purchased }
        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertEqual(sheets, 1)
        XCTAssertEqual(session.allTransactions().count, 1)
        XCTAssertEqual(service.activeProductID, yearly)
    }

    /// The purchase and Transaction.updates both hand the same transaction over (the owner's purchase
    /// was sent to the server twice, five seconds apart).
    func testPurchaseAndUpdatesSendItOnce() async throws {
        try needsTestStore()
        service.startListening()
        backend.delay = 0.5
        let ending = await service.purchase(yearly)
        XCTAssertEqual(ending, .purchased)
        try await Task.sleep(nanoseconds: 2_000_000_000)
        XCTAssertEqual(backend.sent.count, 1)
    }

    func testBuyingAgainChangesNothing() async throws {
        try needsTestStore()
        await service.purchase(yearly)
        let ending = await service.purchase(yearly)
        XCTAssertEqual(ending, .alreadyYours)
        XCTAssertEqual(sheets, 1, "Apple isn't asked again")
        XCTAssertEqual(service.standing, .subscribed)
    }

    func testProFromAnotherAppleAccountIsntBoughtTwice() async throws {
        backend.serverIsPro = true
        backend.planOnServer = true
        let ending = await service.purchase(yearly)
        XCTAssertEqual(ending, .alreadyYours)
        XCTAssertEqual(sheets, 0)
    }

    func testProSwitchedOnElsewhereIsntSoldAgain() async throws {
        // Tester t26: the account went Pro on the server while Settings still said Free; Apple's sheet came up.
        backend.serverIsPro = false
        backend.planOnServer = true
        let ending = await service.purchase(yearly)
        XCTAssertEqual(ending, .alreadyYours)
        XCTAssertEqual(sheets, 0, "Apple isn't asked")
        XCTAssertGreaterThan(backend.refreshes, 0)
    }

    func testOpeningThePaywallReadsThePlanAgain() async throws {
        backend.planOnServer = true
        service.paywallOpened()
        await assertEventually("the plan is read again") { self.backend.refreshes > 0 && self.backend.serverIsPro }
        service.paywallClosed()
    }

    func testAStaleProPlanDoesntStopBuying() async throws {
        try needsTestStore()
        backend.serverIsPro = true
        backend.planOnServer = false
        let ending = await service.purchase(yearly)
        XCTAssertEqual(ending, .purchased)
    }

    func testSignedOutCantBuy() async throws {
        backend.userID = nil
        let ending = await service.purchase(yearly)
        guard case .failed = ending else { return XCTFail("\(ending)") }
        XCTAssertEqual(sheets, 0)
        XCTAssertNil(service.activity)
    }

    func testTheAgeGateStopsItWithItsReason() async throws {
        service.ageCheck = { "Ask a parent." }
        let ending = await service.purchase(yearly)
        XCTAssertEqual(ending, .failed("Ask a parent."))
        XCTAssertEqual(sheets, 0)
    }

    func testMonthlyToYearly() async throws {
        try needsTestStore()
        await service.purchase(monthly)
        XCTAssertEqual(service.activeProductID, monthly)
        let ending = await service.purchase(yearly)
        XCTAssertEqual(ending, .purchased)
        await assertEventually("yearly") { self.service.activeProductID == self.yearly }
        XCTAssertEqual(service.standing, .subscribed)
    }

    // MARK: - Not bought

    func testCancelledIsSaidAndCanBeTriedAgain() async throws {
        try needsTestStore()
        let real = service.purchaseProduct
        service.purchaseProduct = { _, _ in .userCancelled }
        let ending = await service.purchase(yearly)
        XCTAssertEqual(ending, .cancelled)
        XCTAssertNil(service.activity, "the button comes back")
        XCTAssertEqual(service.standing, .none)
        XCTAssertTrue(backend.sent.isEmpty)
        service.purchaseProduct = real
        let again = await service.purchase(yearly)
        XCTAssertEqual(again, .purchased)
    }

    func testCancelledAsAnError() async throws {
        service.purchaseProduct = { _, _ in throw StoreKitError.userCancelled }
        let ending = await service.purchase(yearly)
        XCTAssertEqual(ending, .cancelled)
    }

    func testEveryErrorHasWords() async throws {
        let errors: [Error] = [StoreKitError.unknown, StoreKitError.networkError(URLError(.notConnectedToInternet)),
                               StoreKitError.systemError(CocoaError(.fileNoSuchFile)), StoreKitError.notAvailableInStorefront,
                               Product.PurchaseError.purchaseNotAllowed, Product.PurchaseError.productUnavailable,
                               Product.PurchaseError.ineligibleForOffer, URLError(.timedOut)]
        for error in errors {
            service.purchaseProduct = { _, _ in throw error }
            let ending = await service.purchase(yearly)
            guard case .failed(let words) = ending else { XCTFail("\(error): \(ending)"); continue }
            XCTAssertFalse(words.isEmpty)
            XCTAssertNil(service.activity)
        }
        XCTAssertEqual(PurchaseService.ending(for: StoreKitError.networkError(URLError(.notConnectedToInternet))),
                       .failed("The App Store can't be reached. Check your connection and try again. You haven't been charged."))
    }

    // MARK: - Interrupted, pending, silent

    /// Apple needed something first (a password, new terms): purchase() gives up, and the transaction
    /// arrives on its own later.
    func testAnInterruptedPurchaseFinishesByItself() async throws {
        try needsTestStore()
        service.startListening()
        session.interruptedPurchasesEnabled = true
        let ending = await service.purchase(yearly)
        XCTAssertTrue(ending == .cancelled || ending == .pending, "\(ending)")
        XCTAssertNil(service.activity)
        XCTAssertFalse(service.hasLocalEntitlement)
        try letThrough()
        await assertEventually("Pro by itself") { self.service.standing == .subscribed }
        await assertEventually("and it's said") { self.service.ending == .purchased }
        XCTAssertEqual(announcements, ["Snapreel Pro is on"])
        await assertEventually("finished") { await self.unfinished() == 0 }
        XCTAssertEqual(backend.sent.count, 1)
    }

    /// The same, when Apple's answer is "cancelled" but the subscription is there.
    func testBoughtAlthoughAppleSaysCancelled() async throws {
        try needsTestStore()
        service.purchaseProduct = { [unowned self] product, options in
            _ = try await self.buyInStore(product, options)
            return .userCancelled
        }
        let ending = await service.purchase(yearly)
        XCTAssertEqual(ending, .purchased)
        XCTAssertEqual(service.standing, .subscribed)
        XCTAssertEqual(backend.sent.count, 1)
    }

    func testBoughtAlthoughAppleThrows() async throws {
        try needsTestStore()
        service.purchaseProduct = { [unowned self] product, options in
            _ = try await self.buyInStore(product, options)
            throw StoreKitError.unknown
        }
        let ending = await service.purchase(yearly)
        XCTAssertEqual(ending, .purchased)
    }

    func testAskToBuyApproved() async throws {
        try needsTestStore()
        service.startListening()
        session.askToBuyEnabled = true
        let ending = await service.purchase(yearly)
        XCTAssertEqual(ending, .pending)
        XCTAssertNil(service.activity)
        XCTAssertFalse(service.hasLocalEntitlement)

        // Closing and opening the paywall still says so, after a relaunch too.
        service.paywallOpened()
        XCTAssertEqual(service.ending, .pending)
        service.paywallClosed()
        service = makeService()
        service.startListening()
        service.paywallOpened()
        XCTAssertEqual(service.ending, .pending)
        service.paywallClosed()

        try letThrough()
        await assertEventually("Pro once approved") { self.service.standing == .subscribed }
        await assertEventually("and it's said") { self.service.ending == .purchased }
        service.paywallOpened()
        XCTAssertNotEqual(service.ending, .pending)
    }

    func testAskToBuyDeclined() async throws {
        try needsTestStore()
        service.startListening()
        session.askToBuyEnabled = true
        let ending = await service.purchase(yearly)
        XCTAssertEqual(ending, .pending)
        XCTAssertFalse(service.hasLocalEntitlement)
        try session.declineAskToBuyTransaction(identifier: try latest().identifier)
        session.askToBuyEnabled = false
        let again = await service.purchase(yearly)
        XCTAssertEqual(again, .purchased, "a declined request doesn't stop the next try")
        service.paywallOpened()
        XCTAssertEqual(service.ending, .none)
    }

    /// An App Store that never answers used to leave "Waiting for the App Store…" for good.
    func testASilentAppStoreCanBeLeft() async throws {
        try needsTestStore()
        service.slowAfter = 1
        let gate = Gate()
        service.purchaseProduct = { [unowned self] product, options in
            await gate.wait()
            return try await self.buyInStore(product, options)
        }
        service.buy(yearly)
        await assertEventually("offers a way out") { self.service.activity?.isSlow == true }
        service.stopWaiting()
        XCTAssertNil(service.activity)
        XCTAssertEqual(service.ending, .none)

        // And when that purchase goes through after all, it counts.
        gate.open()
        await assertEventually("still counts") { self.service.standing == .subscribed && self.service.ending == .purchased }
    }

    func testTryingAgainAfterASilentAppStore() async throws {
        try needsTestStore()
        service.slowAfter = 1
        let real = service.purchaseProduct
        service.purchaseProduct = { _, _ in
            try await Task.sleep(nanoseconds: 60_000_000_000)
            return .userCancelled
        }
        service.buy(yearly)
        await assertEventually("offers a way out") { self.service.activity?.isSlow == true }
        service.stopWaiting()
        service.purchaseProduct = real
        let ending = await service.purchase(yearly)
        XCTAssertEqual(ending, .purchased)
        XCTAssertNil(service.activity)
    }

    // MARK: - Nothing paid for is lost

    /// (c) The transaction used to be finished whatever the server said.
    func testServerDownKeepsTheTransactionAndTriesAgain() async throws {
        try needsTestStore()
        backend.failure = .unavailable
        let ending = await service.purchase(yearly)
        XCTAssertEqual(ending, .purchased)
        XCTAssertEqual(service.standing, .confirming)
        XCTAssertTrue(service.hasLocalEntitlement, "Pro on this iPhone meanwhile")
        let kept = self.kept()
        XCTAssertEqual(kept, 1, "not finished before the server has it")

        await assertEventually("sent again by itself") { self.backend.sent.count >= 3 }
        backend.failure = nil
        await assertEventually("confirmed") { self.service.standing == .subscribed }
        await assertEventually("and finished") { await self.unfinished() == 0 }
        XCTAssertEqual(service.ending, .purchased)
    }

    func testOfflineAtTheWorstMoment() async throws {
        try needsTestStore()
        backend.failure = .offline
        await service.purchase(yearly)
        XCTAssertEqual(service.standing, .confirming)
        backend.failure = nil
        await service.confirmNow()
        XCTAssertEqual(service.standing, .subscribed)
    }

    func testSnapreelClosedBeforeTheServerHadIt() async throws {
        try needsTestStore()
        service.retryDelays = [600]
        backend.failure = .offline
        await service.purchase(yearly)
        service = makeService() // relaunch
        XCTAssertFalse(service.hasLocalEntitlement)
        backend.failure = nil
        service.startListening()
        await service.refreshEntitlements()
        await assertEventually("delivered at the next launch") { self.service.standing == .subscribed }
        await assertEventually("and finished") { await self.unfinished() == 0 }
        if await unfinished() > 0 {
            var listed: [String] = []
            for await result in Transaction.unfinished {
                let t = result.unsafePayloadValue
                listed.append("\(t.id)/\(t.originalID)/\(t.productID)/\(t.expirationDate.map { "\($0.timeIntervalSinceNow)" } ?? "-")")
            }
            print("MEASURE relaunch unfinished \(listed) store \(session.allTransactions().map { "\($0.identifier)/\($0.state.rawValue)" }) sent \(backend.sent.map(\.transactionID))")
        }
    }

    func testARefusedTransactionIsKept() async throws {
        try needsTestStore()
        backend.failure = .refused("signature")
        await service.purchase(yearly)
        XCTAssertEqual(service.standing, .refused("signature"))
        let kept = self.kept()
        XCTAssertEqual(kept, 1)
        let asked = backend.sent.count
        await service.refreshEntitlements()
        XCTAssertEqual(backend.sent.count, asked, "the same answer isn't asked for over and over")
        backend.failure = nil
        await service.confirmNow()
        XCTAssertEqual(service.standing, .subscribed)
    }

    func testTheServerSayingFreeAfterAPurchaseIsTriedAgain() async throws {
        try needsTestStore()
        var free = true
        backend.decide = { _ in free ? CloudPlan(tier: .free, productId: nil, expiresAt: nil) : FakeBackend.pro }
        await service.purchase(yearly)
        XCTAssertEqual(service.standing, .confirming)
        free = false
        await assertEventually("then Pro") { self.service.standing == .subscribed }
    }

    func testTheSessionEndingMidway() async throws {
        try needsTestStore()
        backend.failure = .signedOut
        await service.purchase(yearly)
        XCTAssertEqual(service.standing, .signInNeeded)
        let kept = self.kept()
        XCTAssertEqual(kept, 1)
        backend.failure = nil
        await service.confirmNow()
        XCTAssertEqual(service.standing, .subscribed)
    }

    func testSigningOutWhileItIsBeingSent() async throws {
        try needsTestStore()
        service.startListening()
        backend.delay = 1
        async let ending = service.purchase(yearly)
        await assertEventually("being sent") { self.backend.sent.count == 1 }
        backend.userID = nil
        _ = await ending
        await assertEventually("waits for a sign-in") { self.service.standing == .signInNeeded }
        XCTAssertFalse(service.hasLocalEntitlement)
        backend.delay = 0
        backend.userID = alice
        await assertEventually("and then has it") { self.service.standing == .subscribed }
    }

    // MARK: - Accounts

    func testSignedOutThenIn() async throws {
        try needsTestStore()
        service.startListening()
        await service.purchase(yearly)
        backend.userID = nil
        await assertEventually("asks to sign in") { self.service.standing == .signInNeeded }
        XCTAssertFalse(service.hasLocalEntitlement, "Pro goes with the account")
        XCTAssertEqual(service.ending, .none)
        backend.userID = alice
        await assertEventually("back on") { self.service.standing == .subscribed && self.service.hasLocalEntitlement }
        XCTAssertEqual(sheets, 1)
    }

    /// (d) Another Snapreel account on the same Apple Account.
    func testAnotherAccountsSubscription() async throws {
        try needsTestStore()
        service.startListening()
        await service.purchase(yearly)
        backend.decide = { item in
            if item.token != self.bob, !item.move { throw PurchaseServerError.otherAccount(hint: "a•••e@example.com", canMove: true) }
            return FakeBackend.pro
        }
        backend.userID = bob
        await assertEventually("says whose") {
            self.service.standing == .otherAccount(hint: "a•••e@example.com", canMove: true)
        }
        XCTAssertFalse(service.hasLocalEntitlement, "not Pro here: the server would refuse every Pro thing")
        XCTAssertEqual(backend.sent.filter { $0.move }.count, 0, "nothing moves without asking")

        let ending = await service.purchase(yearly)
        XCTAssertEqual(ending, .none, "the card says it all")
        XCTAssertEqual(sheets, 1, "and Apple isn't asked for money again")

        await service.moveHere()
        XCTAssertEqual(service.ending, .purchased)
        XCTAssertEqual(service.standing, .subscribed)
        XCTAssertTrue(service.hasLocalEntitlement)

        // Still here after a relaunch without a connection.
        backend.decide = { _ in throw PurchaseServerError.offline }
        service = makeService()
        await service.refreshEntitlements()
        XCTAssertTrue(service.hasLocalEntitlement)
    }

    func testMovingThatCantBeDone() async throws {
        try needsTestStore()
        service.startListening()
        await service.purchase(yearly)
        backend.decide = { item in
            throw item.move ? PurchaseServerError.alreadyPro("This Snapreel account already has Pro.")
                : PurchaseServerError.otherAccount(hint: nil, canMove: true)
        }
        backend.userID = bob
        await assertEventually("other account") { self.service.standing == .otherAccount(hint: nil, canMove: true) }
        await service.moveHere()
        XCTAssertEqual(service.ending, .failed("This Snapreel account already has Pro."))
        backend.decide = { _ in throw PurchaseServerError.offline }
        await service.moveHere()
        XCTAssertEqual(service.ending, .failed(CloudError.offline.message))
        XCTAssertFalse(service.isMoving)
    }

    func testAnotherAccountsSubscriptionWhileOffline() async throws {
        try needsTestStore()
        service.startListening()
        await service.purchase(yearly)
        backend.failure = .offline
        backend.userID = bob
        try await Task.sleep(nanoseconds: 1_500_000_000)
        XCTAssertFalse(service.hasLocalEntitlement)
        let ending = await service.purchase(yearly)
        guard case .failed = ending else { return XCTFail("\(ending)") }
        XCTAssertEqual(sheets, 1)
    }

    // MARK: - Restore

    func testRestoreWithoutApplesPassword() async throws {
        try needsTestStore()
        service.retryDelays = [600]
        backend.failure = .offline
        await service.purchase(yearly)
        backend.failure = nil
        service = makeService()
        var syncs = 0
        service.syncAppStore = { syncs += 1 }
        await service.restoreForPaywall()
        XCTAssertEqual(service.ending, .restored)
        XCTAssertEqual(service.standing, .subscribed)
        XCTAssertEqual(syncs, 0)
    }

    func testRestoreFindsNothing() async throws {
        var syncs = 0
        service.syncAppStore = { syncs += 1 }
        await service.restoreForPaywall()
        XCTAssertEqual(service.ending, .restoredNothing)
        XCTAssertEqual(syncs, 1)
    }

    func testRestoreCancelledOrOffline() async throws {
        service.syncAppStore = { throw StoreKitError.userCancelled }
        await service.restoreForPaywall()
        XCTAssertEqual(service.ending, .restoreCancelled)
        service.syncAppStore = { throw StoreKitError.networkError(URLError(.notConnectedToInternet)) }
        await service.restoreForPaywall()
        guard case .failed = service.ending else { return XCTFail("\(service.ending)") }
    }

    func testRestoreSaysWhoseItIs() async throws {
        try needsTestStore()
        service.startListening()
        await service.purchase(yearly)
        backend.failure = .otherAccount(hint: "a•••e@example.com", canMove: true)
        backend.userID = bob
        await assertEventually("other account") { self.service.standing != .subscribed }
        await service.restoreForPaywall()
        XCTAssertEqual(service.standing, .otherAccount(hint: "a•••e@example.com", canMove: true))
        XCTAssertNotEqual(service.ending, .restoredNothing)
    }

    // MARK: - Later

    func testARenewalReachesTheServer() async throws {
        try needsTestStore()
        service.startListening()
        await service.purchase(monthly)
        let before = backend.sent.count
        try session.forceRenewalOfSubscription(productIdentifier: monthly)
        await assertEventually("renewal sent") { self.backend.sent.count > before }
        XCTAssertEqual(service.standing, .subscribed)
        await assertEventually("and finished") { await self.unfinished() == 0 }
    }

    func testARefundTurnsProOff() async throws {
        try needsTestStore()
        service.startListening()
        await service.purchase(yearly)
        backend.planOnServer = false
        try session.refundTransaction(identifier: try latest().identifier)
        await assertEventually("off") { !self.service.hasLocalEntitlement && self.service.standing == .none }
        await assertEventually("and the plan is read again") { self.backend.refreshes > 0 }
    }

    func testRunningOut() async throws {
        try needsTestStore()
        service.settleTime = 0
        service.startListening()
        await service.purchase(yearly)
        backend.planOnServer = false
        try session.expireSubscription(productIdentifier: yearly)
        await service.refreshEntitlements()
        await assertEventually("off") {
            await self.service.refreshEntitlements()
            return !self.service.hasLocalEntitlement
        }
        let ending = await service.purchase(yearly)
        XCTAssertEqual(ending, .purchased, "and can be bought again")
    }

    /// Apple can't charge the renewal. With a grace period Pro stays; without one it stops, and the
    /// paywall says why.
    func testARenewalThatCantBeCharged() async throws {
        try needsTestStore()
        service.startListening()
        service.settleTime = 0
        session.billingGracePeriodIsEnabled = false
        session.shouldEnterBillingRetryOnRenewal = true
        session.timeRate = .oneSecondIsOneDay
        await service.purchase(monthly)
        backend.planOnServer = false
        await assertEventually("off, with the reason", 60) {
            await self.service.refreshEntitlements()
            return self.service.standing == .paymentProblem && !self.service.hasLocalEntitlement
        }
    }

    /// Bought on the App Store's own page, or with an offer code: no account token.
    func testBoughtOutsideTheApp() async throws {
        try needsTestStore()
        service.startListening()
        try await buyOutside(yearly)
        await assertEventually("Pro") {
            await self.service.refreshEntitlements()
            return self.service.standing == .subscribed
        }
        XCTAssertEqual(backend.sent.first?.token, nil)
        XCTAssertTrue(service.hasLocalEntitlement)
    }

    func testBoughtOutsideTheAppWhileSignedOut() async throws {
        try needsTestStore()
        backend.userID = nil
        service.startListening()
        try await buyOutside(yearly)
        await assertEventually("asks to sign in") {
            await self.service.refreshEntitlements()
            return self.service.standing == .signInNeeded
        }
        XCTAssertFalse(service.hasLocalEntitlement)
        backend.userID = alice
        await assertEventually("then Pro") { self.service.standing == .subscribed }
    }

    // MARK: - Plans

    func testTheTrialIsShownOnlyWhileItCanBeHad() async throws {
        try needsTestStore()
        await service.loadProducts()
        XCTAssertEqual(service.plans.first { $0.period == .year }?.trialDays, 7)
        XCTAssertEqual(service.plans.first { $0.period == .year }?.displayPrice, "$39.99")
        XCTAssertNil(service.plans.first { $0.period == .month }?.trialDays)
        XCTAssertEqual(service.yearlySaving, 44)
        await service.purchase(yearly)
        await assertEventually("trial used") { self.service.plans.first { $0.period == .year }?.trialDays == nil }
    }

    func testNoPriceIsMadeUpBeforeTheAppStoreAnswers() async throws {
        XCTAssertTrue(service.plans.allSatisfy { !$0.isPurchasable && $0.trialDays == nil })
        XCTAssertNil(service.yearlySaving)
    }

    /// (e) A second caller used to return at once and throw "unavailable".
    func testCallersWaitForALoadInProgress() async throws {
        var fetches = 0
        service.fetchProducts = { ids in
            fetches += 1
            try await Task.sleep(nanoseconds: 500_000_000)
            return try await Product.products(for: ids)
        }
        async let first: Void = service.loadProducts()
        async let second: Void = service.loadProducts()
        _ = await (first, second)
        XCTAssertEqual(service.products.count, 2)
        XCTAssertEqual(fetches, 1)
    }

    func testPlansThatFailToLoadAreTriedAgain() async throws {
        try needsTestStore()
        var fetches = 0
        service.fetchProducts = { ids in
            fetches += 1
            if fetches < 3 { throw URLError(.notConnectedToInternet) }
            return try await Product.products(for: ids)
        }
        await service.loadProducts()
        XCTAssertTrue(service.loadFailed)
        let ending = await service.purchase(yearly)
        XCTAssertEqual(ending, .failed(PurchaseService.PurchaseError.unavailable.text))
        await service.keepLoadingProducts()
        XCTAssertFalse(service.loadFailed)
        let again = await service.purchase(yearly)
        XCTAssertEqual(again, .purchased)
    }

    func testOnePlanMissingIsNotDone() async throws {
        var fetches = 0
        service.fetchProducts = { ids in
            fetches += 1
            let all = try await Product.products(for: ids)
            return fetches == 1 ? Array(all.prefix(1)) : all
        }
        await service.loadProducts()
        XCTAssertTrue(service.loadFailed)
        await service.loadProducts()
        XCTAssertEqual(service.products.count, 2)
        XCTAssertFalse(service.loadFailed)
    }
}

/// Lets a test hold something up and let it go.
@MainActor
final class Gate {
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func open() {
        isOpen = true
        waiting.forEach { $0.resume() }
        waiting = []
    }
}
