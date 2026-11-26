import XCTest
@testable import Snapreel

/// What the paywall shows for each state, and the sheets around it. No App Store.
@MainActor
final class PaywallTests: XCTestCase {
    private func stage(_ standing: PurchaseService.Standing = .none, _ ending: PurchaseEnding = .none, isPro: Bool = false,
                       serverIsPro: Bool = false, isSignedIn: Bool = true) -> PaywallView.Stage {
        PaywallView.stage(standing: standing, ending: ending, isPro: isPro, serverIsPro: serverIsPro, isSignedIn: isSignedIn)
    }

    func testEveryStateHasItsStage() {
        XCTAssertEqual(stage(), .plans)
        XCTAssertEqual(stage(.none, .cancelled), .plans)
        XCTAssertEqual(stage(.none, .pending), .plans)
        XCTAssertEqual(stage(.none, .failed("x")), .plans)
        XCTAssertEqual(stage(.none, .restoredNothing), .plans)
        XCTAssertEqual(stage(.paymentProblem), .plans)
        XCTAssertEqual(stage(.subscribed, .purchased, isPro: true, serverIsPro: true), .welcome)
        XCTAssertEqual(stage(.subscribed, .restored, isPro: true, serverIsPro: true), .welcome)
        XCTAssertEqual(stage(.subscribed, isPro: true, serverIsPro: true), .active)
        XCTAssertEqual(stage(.subscribed, .alreadyYours, isPro: true, serverIsPro: true), .active)
        XCTAssertEqual(stage(.none, .alreadyYours, isPro: true, serverIsPro: true), .active)
        XCTAssertEqual(stage(.confirming, .purchased, isPro: true), .confirming)
        XCTAssertEqual(stage(.confirming, isPro: true), .confirming)
        XCTAssertEqual(stage(.refused("x"), .purchased, isPro: true), .refused)
        XCTAssertEqual(stage(.signInNeeded, isSignedIn: false), .signInNeeded)
        XCTAssertEqual(stage(.otherAccount(hint: "h", canMove: true)), .otherAccount(hint: "h", canMove: true))
        // Pro on the server from another Apple Account wins over this one's being somebody else's.
        XCTAssertEqual(stage(.otherAccount(hint: "h", canMove: true), isPro: true, serverIsPro: true), .active)
    }

    func testWhatTheServersAnswersMean() {
        func error(_ status: Int, _ code: String?, hint: String? = nil, canMove: Bool? = nil) -> PurchaseServerError {
            LivePurchaseBackend.error(status: status, code: code, message: "m", hint: hint, canMove: canMove)
        }
        XCTAssertEqual(error(401, "unauthorized"), .signedOut)
        XCTAssertEqual(error(403, "other_account", hint: "h", canMove: true), .otherAccount(hint: "h", canMove: true))
        XCTAssertEqual(error(403, "other_account"), .otherAccount(hint: nil, canMove: false), "a server from before hints")
        XCTAssertEqual(error(409, "already_pro"), .alreadyPro("m"))
        XCTAssertEqual(error(400, "invalid_signature"), .refused("m"))
        // Anything unclear is tried again.
        for status in [0, 400, 403, 404, 408, 413, 429, 500, 502, 503, 504] {
            XCTAssertEqual(error(status, nil), .unavailable, "\(status)")
        }
    }

    // MARK: - Sheets

    private func topSheets() -> [UIViewController] {
        var found: [UIViewController] = []
        var top = ShareSheetPresenter.keyWindow?.rootViewController
        while let next = top?.presentedViewController, !next.isBeingDismissed {
            if next is ProHostingController { found.append(next) }
            top = next
        }
        return found
    }

    private func wait(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func waitFor(_ seconds: Double = 8, _ condition: @MainActor () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if condition() { return true }
            await wait(0.1)
        }
        return condition()
    }

    private func closeAll() async {
        ShareSheetPresenter.keyWindow?.rootViewController?.dismiss(animated: false)
        _ = await waitFor { self.topSheets().isEmpty }
        await wait(0.5)
    }

    /// A double tap on "Try 1 week free" while signed out put up two sign-in sheets.
    func testADoubleTapShowsOneSignInSheet() async throws {
        try XCTSkipIf(AuthService.shared.isSignedIn)
        await closeAll()
        var answers: [Bool] = []
        ProPresenter.signIn(reason: .subscribe) { answers.append($0) }
        ProPresenter.signIn(reason: .subscribe) { answers.append($0) }
        let up = await waitFor { self.topSheets().count == 1 }
        XCTAssertTrue(up)
        await wait(2)
        XCTAssertEqual(topSheets().count, 1)
        topSheets().first?.dismiss(animated: true)
        let answered = await waitFor { answers.count == 1 }
        XCTAssertTrue(answered)
        await wait(1)
        XCTAssertEqual(answers, [false], "answered once, when the sheet had gone")
        XCTAssertTrue(topSheets().isEmpty)
        await closeAll()
    }

    func testThePaywallOpensOnceAndOpensAgain() async throws {
        await closeAll()
        ProPresenter.paywall(.settings)
        ProPresenter.paywall(.links)
        let up = await waitFor { self.topSheets().count == 1 }
        XCTAssertTrue(up)
        await wait(2)
        XCTAssertEqual(topSheets().count, 1)
        topSheets().first?.dismiss(animated: true)
        let gone = await waitFor { self.topSheets().isEmpty }
        XCTAssertTrue(gone)
        ProPresenter.paywall(.settings)
        let again = await waitFor { self.topSheets().count == 1 }
        XCTAssertTrue(again, "closing it doesn't stop the next")
        await closeAll()
    }

    /// Sign-in over the paywall: its completion runs on a still screen, with only the paywall left.
    func testSignInOverThePaywallLeavesThePaywall() async throws {
        try XCTSkipIf(AuthService.shared.isSignedIn)
        await closeAll()
        ProPresenter.paywall(.settings)
        let paywall = await waitFor { self.topSheets().count == 1 }
        XCTAssertTrue(paywall)
        await wait(1)
        var sheetsAtCompletion: Int?
        var still = false
        ProPresenter.signIn(reason: .subscribe) { _ in
            sheetsAtCompletion = self.topSheets().count
            let top = ShareSheetPresenter.topViewController()
            still = top?.transitionCoordinator == nil && top?.isBeingDismissed == false
        }
        let both = await waitFor { self.topSheets().count == 2 }
        XCTAssertTrue(both)
        await wait(1)
        topSheets().last?.dismiss(animated: true)
        let done = await waitFor { sheetsAtCompletion != nil }
        XCTAssertTrue(done)
        XCTAssertEqual(sheetsAtCompletion, 1)
        XCTAssertTrue(still, "nothing is still going away when Apple's sheet comes up")
        await closeAll()
    }
}
