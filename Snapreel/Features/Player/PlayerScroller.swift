import SwiftUI
import UIKit

/// The scrolling area under the player's video: the details, the Notes / Transcript switch and
/// its panel, in a UIKit scroll view.
///
/// The owner's iPhone X (iOS 16.7, builds 22 and 23) showed SwiftUI's ScrollView here losing
/// track of its own top: after scrolling down to the notes it sprang back to them on its own
/// and couldn't be scrolled up again, usually right after the video reached its end. Moving
/// the video into the scroll view's safe-area inset (build 23) didn't change that. Here UIKit
/// owns the content size and insets: the content reports its height, the scroll view gets no
/// automatic insets, and nothing else moves it.
struct PlayerScroller: UIViewControllerRepresentable {
    let content: AnyView
    /// Open with the Notes / Transcript switch at the top (`PlayerPanelTopKey` marks it), as
    /// from a "transcript ready" notification.
    var opensOnPanel = false
    /// The content was pulled down well past the top and let go.
    let onPulledDown: @MainActor () -> Void

    func makeUIViewController(context: Context) -> PlayerScrollerController {
        PlayerScrollerController(content: content, opensOnPanel: opensOnPanel)
    }

    func updateUIViewController(_ controller: PlayerScrollerController, context: Context) {
        controller.update(content: content, onPulledDown: onPulledDown)
    }
}

final class PlayerScrollerController: UIViewController, UIScrollViewDelegate {
    private let scrollView = UIScrollView()
    private let relay: PlayerScrollerRelay
    private let host: UIHostingController<PlayerScrollerRoot>
    /// The content's height as SwiftUI measured it; 0 until it has reported.
    private var contentHeight: CGFloat = 0
    private var onPulledDown: (@MainActor () -> Void)?

    // Opening on the panel. Build 25 asked from PlayerScreen 0.3 s after appearing, with the
    // panel's position passed back through PlayerScreen's state; in CI the page still opened
    // at the top. Now the controller hears the position itself and keeps the panel at the top
    // while the content settles, until the person scrolls or `panelHold` has passed.
    private var holdsPanel: Bool
    private var panelTop: CGFloat = 0
    private var panelHeldSince: Date?
    private static let panelHold: TimeInterval = 1.5

    init(content: AnyView, opensOnPanel: Bool) {
        let relay = PlayerScrollerRelay()
        self.relay = relay
        holdsPanel = opensOnPanel
        host = UIHostingController(rootView: PlayerScrollerRoot(content: content, relay: relay))
        super.init(nibName: nil, bundle: nil)
        relay.onHeight = { [weak self] height in self?.contentHeightChanged(height) }
        relay.onPanelTop = { [weak self] top in self?.panelTopChanged(top) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.alwaysBounceVertical = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.indicatorStyle = .white
        scrollView.delegate = self
        view.addSubview(scrollView)

        addChild(host)
        host.view.backgroundColor = .clear
        if #available(iOS 16.4, *) { host.safeAreaRegions = [] }
        scrollView.addSubview(host.view)
        host.didMove(toParent: self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if scrollView.frame != view.bounds { scrollView.frame = view.bounds }
        layoutContent()
    }

    func update(content: AnyView, onPulledDown: @escaping @MainActor () -> Void) {
        host.rootView = PlayerScrollerRoot(content: content, relay: relay)
        self.onPulledDown = onPulledDown
    }

    // MARK: Sizing

    private func contentHeightChanged(_ height: CGFloat) {
        guard height.isFinite, height > 0, abs(height - contentHeight) > 0.5 else { return }
        contentHeight = height
        view.setNeedsLayout()
    }

    private func panelTopChanged(_ top: CGFloat) {
        guard top.isFinite, abs(top - panelTop) > 0.5 else { return }
        panelTop = top
        if holdsPanel { view.setNeedsLayout() }
    }

    private func layoutContent() {
        let width = scrollView.bounds.width
        guard width > 0 else { return }
        // Until the content reports its height, give it the visible height: it measures its
        // own natural height either way (see PlayerScrollerRoot).
        let height = contentHeight > 0 ? contentHeight : max(scrollView.bounds.height, 1)
        let frame = CGRect(x: 0, y: 0, width: width, height: height)
        if host.view.frame != frame { host.view.frame = frame }
        let size = CGSize(width: width, height: height)
        if scrollView.contentSize != size { scrollView.contentSize = size }

        // Content got shorter while scrolled near the end: stay inside it.
        let maxOffset = max(0, height - scrollView.bounds.height)
        if !scrollView.isTracking, !scrollView.isDecelerating, scrollView.contentOffset.y > maxOffset {
            scrollView.contentOffset.y = maxOffset
        }
        holdPanelAtTop(maxOffset: maxOffset)
    }

    private func holdPanelAtTop(maxOffset: CGFloat) {
        guard holdsPanel else { return }
        if let since = panelHeldSince, Date().timeIntervalSince(since) > Self.panelHold {
            holdsPanel = false
            return
        }
        guard contentHeight > 0, panelTop > 0, !scrollView.isTracking else { return }
        let y = min(panelTop, maxOffset)
        if abs(scrollView.contentOffset.y - y) > 0.5 { scrollView.contentOffset.y = y }
        if panelHeldSince == nil { panelHeldSince = Date() }
    }

    // MARK: Pull down to minimise

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        holdsPanel = false
    }

    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint,
                                   targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        guard scrollView.contentOffset.y < -SwipeDismiss.pull else { return }
        onPulledDown?()
    }
}

/// Carries the content's measured height, and where its panel starts, from SwiftUI back to
/// the controller.
final class PlayerScrollerRelay {
    var onHeight: ((CGFloat) -> Void)?
    var onPanelTop: ((CGFloat) -> Void)?
}

/// The hosted content at its natural height, top-aligned, reporting that height and the
/// panel's position.
struct PlayerScrollerRoot: View {
    let content: AnyView
    let relay: PlayerScrollerRelay

    var body: some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: PlayerScrollerHeightKey.self, value: proxy.size.height)
            })
            .onPreferenceChange(PlayerScrollerHeightKey.self) { height in relay.onHeight?(height) }
            .onPreferenceChange(PlayerPanelTopKey.self) { top in relay.onPanelTop?(top) }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .environment(\.colorScheme, .dark)
    }
}

private struct PlayerScrollerHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Where the Notes / Transcript switch sits in the scroll content (points from its top), for
/// "open on the panel".
struct PlayerPanelTopKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
