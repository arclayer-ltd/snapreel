import LinkPresentation
import SwiftUI
import UIKit

// Presenting UIActivityViewController. What is shared and when is decided in `ShareFlow`.

/// What the share sheet shows and hands over.
@MainActor
struct ShareSheetRequest {
    var file: URL
    /// An MP4 of the same recording that is being made while the sheet is up.
    var copy: ShareCopyOutcome?
    var title: String
    var thumbnailURL: URL?
    var isAudio: Bool
    var root: URL
    /// Offers "Smaller copy" in the sheet.
    var smaller: SmallerCopyPlan?
    var onShown: @MainActor () -> Void
    /// The sheet could not be presented. Nothing else is called after it.
    var onFailed: @MainActor () -> Void
    /// Called for each activity that finished (AirDrop can finish several times while the sheet
    /// stays open), also after the sheet has gone.
    var onComplete: @MainActor (UIActivity.ActivityType?) -> Void
    /// Called once, when the sheet has gone; with the plan if "Smaller copy" was chosen.
    var onClosed: @MainActor (SmallerCopyPlan?) -> Void
}

/// The sheet after it was asked for.
@MainActor
protocol ShareSheetHandle: AnyObject {
    var isOnScreen: Bool { get }
    /// Asked for, and neither up nor given up on.
    var isPending: Bool { get }
    /// No longer wanted: if it isn't up yet, it doesn't come up.
    func abandon()
}

/// Presents the share sheet from the topmost view controller of the key window, so it works
/// from tab roots, sheets, the player and the recorder (both full-screen covers).
@MainActor
enum ShareSheetPresenter {
    /// False until the first share sheet after launch has come up. iOS loads a good deal for that one
    /// on the main thread, which is felt on an older iPhone.
    private(set) static var isWarm = false
    /// Seconds the last sheet took to build and to come up, for the tests and the debug trace.
    private(set) static var lastBuild: TimeInterval = 0
    private(set) static var lastOpen: TimeInterval = 0

    @discardableResult
    static func present(_ request: ShareSheetRequest) -> ShareSheetHandle {
        let started = Date()
        let item = ShareItemProvider(file: request.file, copy: request.copy, title: request.title,
                                     thumbnailURL: request.thumbnailURL, isAudio: request.isAudio, root: request.root)
        let activities = request.smaller.map { [SmallerCopyActivity(estimatedBytes: $0.estimatedBytes)] } ?? []
        let controller = ShareActivityController(activityItems: [item], applicationActivities: activities)
        controller.excludedActivityTypes = [.assignToContact, .addToReadingList, .print, .openInIBooks, .markupAsPDF]
        let session = ShareSheetSession(request: request, controller: controller)
        lastBuild = Date().timeIntervalSince(started)
        session.onShown = {
            isWarm = true
            lastOpen = Date().timeIntervalSince(started)
        }
        controller.onGone = { session.gone() }
        controller.completionWithItemsHandler = { activity, completed, _, _ in
            Task { @MainActor in session.handle(activity: activity, completed: completed) }
        }
        Task { @MainActor in
            // Let a sheet or menu that the caller closed in the same action start closing first,
            // so the share sheet isn't presented on top of something that is going away.
            try? await Task.sleep(nanoseconds: 120_000_000)
            await presentWhenReady(controller, session: session)
        }
        return session
    }

    /// How long iOS gets to bring the sheet up. The first one after a launch can take seconds on an
    /// older iPhone, so it is asked once and waited for; asking again would be ignored.
    static let patience: TimeInterval = 12

    private static func presentWhenReady(_ controller: ShareActivityController, session: ShareSheetSession) async {
        var presenter: UIViewController?
        for _ in 0..<30 {
            // Snapreel left the screen while the file was prepared: wait for it, however long.
            await BackgroundTime.waitUntilActive()
            if let top = topViewController(), !top.isBeingPresented, !top.isBeingDismissed,
               top.transitionCoordinator == nil, top.viewIfLoaded?.window != nil {
                presenter = top
                break
            }
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
        guard session.isPending else { return }
        guard let presenter else { return session.failed() }
        if let popover = controller.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.maxY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        controller.onAppear = { session.shown() }
        presenter.present(controller, animated: true) { session.shown() }
        // iOS can refuse a presentation without saying so.
        // Counted in looks, not by the clock: a main thread busy loading the sheet must not use it up.
        for _ in 0..<Int(patience * 10) where session.isPending {
            if controller.viewIfLoaded?.window != nil { return session.shown() }
            try? await Task.sleep(nanoseconds: 100_000_000)
            if UIApplication.shared.applicationState != .active { await BackgroundTime.waitUntilActive() }
        }
        guard session.isPending else { return }
        // Too late now: it must not come up after the person was told that it didn't.
        controller.presentingViewController?.dismiss(animated: false)
        session.failed()
    }

    static func topViewController() -> UIViewController? {
        guard let window = keyWindow else { return nil }
        var top = window.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }

    static var keyWindow: UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let active = scenes.filter { $0.activationState == .foregroundActive }
        for scene in active + scenes {
            if let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first {
                return window
            }
        }
        return nil
    }

    /// A system alert over whatever is on screen. With `accept` it has that button and Cancel;
    /// without, OK. Returns true for `accept`.
    static func alert(title: String, message: String, accept: String?) async -> Bool {
        for _ in 0..<25 {
            await BackgroundTime.waitUntilActive()
            if let top = topViewController(), !top.isBeingPresented, !top.isBeingDismissed, top.transitionCoordinator == nil {
                return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                    let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
                    if let accept {
                        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in continuation.resume(returning: false) })
                        alert.addAction(UIAlertAction(title: accept, style: .default) { _ in continuation.resume(returning: true) })
                    } else {
                        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in continuation.resume(returning: false) })
                    }
                    Haptics.warning()
                    top.present(alert, animated: true)
                }
            }
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
        return false
    }
}

/// Reports when the sheet has really left the screen.
final class ShareActivityController: UIActivityViewController {
    var onGone: (@MainActor () -> Void)?
    var onAppear: (@MainActor () -> Void)?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        onAppear?()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Also called when an activity covers the sheet with its own screen; then it is still presented.
        if isBeingDismissed || presentingViewController == nil { onGone?() }
    }
}

/// Tracks one share sheet from presentation to dismissal. Always ends, once, whatever iOS reports.
@MainActor
final class ShareSheetSession: ShareSheetHandle {
    private let request: ShareSheetRequest
    private weak var controller: UIViewController?
    private(set) var wasShown = false
    private var isFinished = false
    private var choseSmaller = false
    private var watch: Task<Void, Never>?
    fileprivate var onShown: (@MainActor () -> Void)?

    init(request: ShareSheetRequest, controller: UIViewController) {
        self.request = request
        self.controller = controller
    }

    var isOnScreen: Bool { controller?.presentingViewController != nil || controller?.viewIfLoaded?.window != nil }

    var isPending: Bool { !wasShown && !isFinished }

    func abandon() {
        guard isPending else { return }
        isFinished = true
        controller?.presentingViewController?.dismiss(animated: false)
    }

    func shown() {
        guard !wasShown else { return }
        guard !isFinished else {
            controller?.presentingViewController?.dismiss(animated: false)
            return
        }
        wasShown = true
        onShown?()
        request.onShown()
    }

    func failed() {
        guard !isFinished else { return }
        isFinished = true
        request.onFailed()
    }

    func gone() { finish() }

    func handle(activity: UIActivity.ActivityType?, completed: Bool) {
        if activity == SmallerCopyActivity.type {
            choseSmaller = completed
        } else if completed {
            request.onComplete(activity)
        }
        // The sheet is closing, or stays open (AirDrop): the end is when it has left the screen. With a
        // large file that can take well over a second.
        guard watch == nil, !isFinished else { return }
        watch = Task { @MainActor [weak self] in
            while let self, !self.isFinished {
                if !self.isOnScreen { return self.finish() }
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
    }

    private func finish() {
        guard !isFinished else { return }
        isFinished = true
        watch?.cancel()
        // The completion handler and the sheet's disappearance come in either order.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            request.onClosed(choseSmaller ? request.smaller : nil)
        }
    }
}

/// The file plus the title and thumbnail the share sheet shows in its header. The sheet appears at
/// once with the recording's own file; an app that is better served by an MP4 gets the one made
/// meanwhile, waiting for it if need be. If it isn't there in time, the recording itself goes.
final class ShareItemProvider: UIActivityItemProvider, @unchecked Sendable {
    private let file: URL
    private let copy: ShareCopyOutcome?
    private let title: String
    private let thumbnailURL: URL?
    private let isAudio: Bool
    private let root: URL

    /// How long an app waits for the MP4 before it gets the recording as it is.
    static let patience: TimeInterval = 15

    init(file: URL, copy: ShareCopyOutcome?, title: String, thumbnailURL: URL?, isAudio: Bool, root: URL) {
        self.file = file
        self.copy = copy
        self.title = title
        self.thumbnailURL = thumbnailURL
        self.isAudio = isAudio
        self.root = root
        super.init(placeholderItem: file)
    }

    /// Runs on a background queue, once something was chosen in the sheet.
    override var item: Any { resolve(for: activityType) }

    func resolve(for activity: UIActivity.ActivityType?) -> URL {
        guard let copy, Self.wantsCopy(activity), let made = copy.url(waiting: Self.patience) else { return file }
        let link = ShareFileLink.prepare(made, title: title, root: root)
        ShareFileLink.released(link)
        return link
    }

    /// iOS's own destinations take the original, which also keeps its exact form.
    static func wantsCopy(_ activity: UIActivity.ActivityType?) -> Bool {
        switch activity {
        case UIActivity.ActivityType.airDrop, UIActivity.ActivityType.saveToCameraRoll, SmallerCopyActivity.type: return false
        default: return true
        }
    }

    override func activityViewController(_ activityViewController: UIActivityViewController,
                                         subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        title
    }

    override func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = title
        if let thumbnailURL, FileManager.default.fileExists(atPath: thumbnailURL.path),
           let provider = NSItemProvider(contentsOf: thumbnailURL) {
            metadata.iconProvider = provider
        } else if let symbol = UIImage(systemName: isAudio ? "waveform" : "video.fill") {
            metadata.iconProvider = NSItemProvider(object: symbol)
        }
        return metadata
    }
}

/// "Smaller copy, about 34 MB" in the share sheet. Choosing it closes the sheet; `ShareFlow` makes
/// the copy and opens the sheet again with it.
final class SmallerCopyActivity: UIActivity {
    static let type = UIActivity.ActivityType("co.arclayer.snapreel.smaller-copy")
    private let estimatedBytes: Int64

    init(estimatedBytes: Int64) {
        self.estimatedBytes = estimatedBytes
        super.init()
    }

    override class var activityCategory: UIActivity.Category { .action }
    override var activityType: UIActivity.ActivityType? { Self.type }
    override var activityTitle: String? { "Smaller copy, about \(Format.bytes(estimatedBytes))" }
    override var activityImage: UIImage? { UIImage(systemName: "arrow.down.right.and.arrow.up.left") }
    override func canPerform(withActivityItems activityItems: [Any]) -> Bool { true }
    override func perform() { activityDidFinish(true) }
}
