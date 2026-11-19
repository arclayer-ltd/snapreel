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

    // MARK: Sheets

    static func signIn(reason: SignInReason, completion: (@MainActor (Bool) -> Void)? = nil) {
        if AuthService.shared.isSignedIn {
            completion?(true)
            return
        }
        var finished = false
        let finish: @MainActor (Bool) -> Void = { signedIn in
            guard !finished else { return }
            finished = true
            dismiss(signInController) { completion?(signedIn) }
        }
        let view = SignInSheet(reason: reason, onDone: { finish($0) })
        let controller = host(view, detents: [.large()], onDismiss: { finish(AuthService.shared.isSignedIn) })
        signInController = controller
        present(controller)
    }

    static func paywall(_ reason: PaywallReason) {
        guard paywallController == nil else { return }
        let view = NavigationStack {
            PaywallView(reason: reason, onClose: { dismiss(paywallController) })
        }
        let controller = host(view, detents: [.large()])
        paywallController = controller
        present(controller)
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

    /// Presents once the top of the stack is still (a sheet or menu the caller just closed has
    /// finished going away).
    private static func present(_ controller: UIViewController) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            for _ in 0..<25 {
                if let top = ShareSheetPresenter.topViewController(), !top.isBeingPresented, !top.isBeingDismissed,
                   top.transitionCoordinator == nil, top.viewIfLoaded?.window != nil {
                    top.present(controller, animated: true)
                    return
                }
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
        }
    }

    private static func dismiss(_ controller: UIViewController?, then completion: (@MainActor () -> Void)? = nil) {
        guard let controller, controller.presentingViewController != nil else {
            completion?()
            return
        }
        (controller as? ProHostingController)?.onDismiss = nil
        controller.dismiss(animated: true) { Task { @MainActor in completion?() } }
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
