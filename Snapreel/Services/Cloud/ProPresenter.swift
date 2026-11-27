import SwiftUI
import UIKit

/// Why the paywall opened; it changes the headline.
enum PaywallReason: Equatable {
    /// From Settings or the account page.
    case settings
    /// A recording longer than Free's 5 minutes.
    case duration(Double)
    /// The 26th link on Free.
    case links
    /// A Pro-only setting or insight.
    case feature(ProFeature)
}

/// Pro-only things a Free plan meets on the way.
enum ProFeature: String, Equatable {
    case password
    case expiry
    case downloads
    case callToAction
    case insights

    var title: String {
        switch self {
        case .password: return "Passwords"
        case .expiry: return "Link expiry"
        case .downloads: return "Downloads"
        case .callToAction: return "A call-to-action button"
        case .insights: return "Viewer insights"
        }
    }
}

/// Why the sign-in sheet opened.
enum SignInReason: Equatable {
    /// Copy link, the first time.
    case link
    /// Subscribing needs an account to attach Pro to.
    case subscribe
    /// "I already have an account" on Welcome, or Settings.
    case account
}

/// Shows Snapreel Pro's sheets from anywhere: over the tab shell, Settings, the player and the
/// recorder (both full-screen covers). Like the system share sheet, each is presented from the
/// topmost view controller, so it works whatever is on screen; each is a page sheet, so a
/// swipe down closes it.
@MainActor
enum ProPresenter {
    private static weak var shareLinkController: UIViewController?
    private static weak var signInController: UIViewController?
    private static weak var paywallController: UIViewController?
    private static weak var settingsController: UIViewController?
    private static weak var appSettingsController: UIViewController?
    /// Waiting for the top of the stack to be still, or on their way up.
    private static var arriving: Set<ObjectIdentifier> = []

    // MARK: Sheets

    /// `completion` runs once the sheet has gone, so whatever comes next (Apple's payment sheet, the
    /// share sheet) has a still screen to come up on. A second call while it's up does nothing: the
    /// first one's completion stands.
    static func signIn(reason: SignInReason, completion: (@MainActor (Bool) -> Void)? = nil) {
        if AuthService.shared.isSignedIn {
            completion?(true)
            return
        }
        guard !isShowing(signInController) else { return }
        var finished = false
        let finish: @MainActor (Bool) -> Void = { signedIn in
            guard !finished else { return }
            finished = true
            dismiss(signInController) { completion?(signedIn) }
        }
        let view = SignInSheet(reason: reason, onDone: { finish($0) })
        let controller = host(view, detents: [.large()], onDismiss: { finish(AuthService.shared.isSignedIn) })
        signInController = controller
        present(controller, orElse: { finish(false) })
    }

    /// `then` is what the person was doing when they met the limit (copying a link, say). It runs
    /// once they're on Pro and the paywall has gone.
    static func paywall(_ reason: PaywallReason, then: (@MainActor () -> Void)? = nil) {
        guard !isShowing(paywallController) else { return }
        let view = NavigationStack {
            PaywallView(reason: reason, continues: then != nil,
                        onClose: { dismiss(paywallController) },
                        onUnlocked: { dismiss(paywallController) { then?() } })
        }
        let controller = host(view, detents: [.large()])
        paywallController = controller
        present(controller)
    }

    /// Signs out of the account that doesn't have this Apple Account's subscription, then into the one
    /// that does. The paywall underneath follows on its own.
    static func switchAccount() {
        Task { @MainActor in
            await AuthService.shared.signOut()
            signIn(reason: .account)
        }
    }

    /// The share-link sheet for a recording (creating, uploading, ready, offline, failed).
    static func shareLink(_ videoID: UUID) {
        if let existing = shareLinkController, existing.presentingViewController != nil { return }
        let view = ShareLinkSheet(videoID: videoID, onClose: { dismissShareLink() })
        let controller = host(view, detents: [.medium(), .large()], grabber: true)
        shareLinkController = controller
        present(controller)
    }

    static func dismissShareLink() {
        dismiss(shareLinkController)
    }

    /// Link settings for a shared recording, in its own sheet.
    static func linkSettings(_ videoID: UUID) {
        let view = NavigationStack {
            LinkSettingsView(videoID: videoID, onClose: { dismiss(settingsController) })
        }
        let controller = host(view, detents: [.large()])
        settingsController = controller
        present(controller)
    }

    // MARK: Settings

    /// The app's Settings, from the gear on every tab (through `SettingsSheet`, which `router.openSettings` sets).
    static func openSettings(path: [SettingsPage]) {
        guard !isShowing(appSettingsController) else { return }
        let view = SettingsView(initialPath: path)
        let controller = host(view, detents: [.large()], onDismiss: { SettingsSheet.shared.didClose() })
        appSettingsController = controller
        present(controller, orElse: { SettingsSheet.shared.didClose() })
    }

    static func closeSettings(then completion: (@MainActor () -> Void)? = nil) {
        dismiss(appSettingsController, then: completion)
    }

    // MARK: Hosting

    private static func host<Content: View>(_ view: Content, detents: [UISheetPresentationController.Detent],
                                            grabber: Bool = false,
                                            onDismiss: (@MainActor () -> Void)? = nil) -> UIViewController {
        let environment = AppEnvironment.shared
        let root = view
            .environmentObject(environment.library)
            .environmentObject(environment.settings)
            .environmentObject(environment.router)
        let controller = ProHostingController(rootView: AnyView(root))
        controller.onDismiss = onDismiss
        controller.modalPresentationStyle = .pageSheet
        if let sheet = controller.sheetPresentationController {
            sheet.detents = detents
            sheet.prefersGrabberVisible = grabber
            sheet.preferredCornerRadius = 24
        }
        return controller
    }

    /// On screen, or on its way: a second tap mustn't put up a second one, and one that has been
    /// closed mustn't stop the next.
    private static func isShowing(_ controller: UIViewController?) -> Bool {
        guard let controller else { return false }
        if arriving.contains(ObjectIdentifier(controller)) { return true }
        return controller.presentingViewController != nil && !controller.isBeingDismissed
    }

    /// Presents once the top of the stack is still (a sheet or menu the caller just closed has
    /// finished going away). Gives up after about 6 seconds, and says so.
    private static func present(_ controller: UIViewController, orElse: (@MainActor () -> Void)? = nil) {
        let id = ObjectIdentifier(controller)
        arriving.insert(id)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            for _ in 0..<50 {
                if let top = ShareSheetPresenter.topViewController(), !top.isBeingPresented, !top.isBeingDismissed,
                   top.transitionCoordinator == nil, top.viewIfLoaded?.window != nil {
                    top.present(controller, animated: true) { Task { @MainActor in arriving.remove(id) } }
                    // Refused (UIKit logs why): the tap must not be swallowed for good.
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    if controller.presentingViewController == nil, arriving.contains(id) {
                        arriving.remove(id)
                        orElse?()
                    }
                    return
                }
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
            arriving.remove(id)
            orElse?()
        }
    }

    private static func dismiss(_ controller: UIViewController?, then completion: (@MainActor () -> Void)? = nil) {
        guard let controller, let presenter = controller.presentingViewController else {
            completion?()
            return
        }
        (controller as? ProHostingController)?.onDismiss = nil
        // Through the presenter: asked itself, a sheet with something over it closes that instead.
        presenter.dismiss(animated: true) { Task { @MainActor in completion?() } }
    }
}

/// A hosting controller that reports a swipe-down dismissal.
final class ProHostingController: UIHostingController<AnyView> {
    var onDismiss: (@MainActor () -> Void)?

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || presentingViewController == nil {
            let callback = onDismiss
            onDismiss = nil
            Task { @MainActor in callback?() }
        }
    }
}
