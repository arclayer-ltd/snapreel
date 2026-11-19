import SwiftUI
import UIKit

/// A request to scroll the player's details and notes so `y` (points from the top of the
/// content) sits at the top. A new `id` makes it run again.
struct PlayerScrollRequest: Equatable {
    let id = UUID()
    var y: CGFloat
}

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
    var scrollRequest: PlayerScrollRequest?
    /// The content was pulled down well past the top and let go.
    let onPulledDown: @MainActor () -> Void

    func makeUIViewController(context: Context) -> PlayerScrollerController {
        PlayerScrollerController(content: content)
    }

    func updateUIViewController(_ controller: PlayerScrollerController, context: Context) {
        controller.update(content: content, request: scrollRequest, onPulledDown: onPulledDown)
    }
}

final class PlayerScrollerController: UIViewController, UIScrollViewDelegate {
    private let scrollView = UIScrollView()
    private let relay: PlayerScrollerRelay
    private let host: UIHostingController<PlayerScrollerRoot>
    private var contentHeight: CGFloat = 0
    private var onPulledDown: (@MainActor () -> Void)?
    private var pendingRequest: PlayerScrollRequest?
    private var handledRequestID: UUID?

    init(content: AnyView) {
        let relay = PlayerScrollerRelay()
        self.relay = relay
        host = UIHostingController(rootView: PlayerScrollerRoot(content: content, relay: relay))
        super.init(nibName: nil, bundle: nil)
        relay.onHeight = { [weak self] height in self?.contentHeightChanged(height) }
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

    func update(content: AnyView, request: PlayerScrollRequest?, onPulledDown: @escaping @MainActor () -> Void) {
        host.rootView = PlayerScrollerRoot(content: content, relay: relay)
        self.onPulledDown = onPulledDown
        if let request, request.id != handledRequestID {
            pendingRequest = request
            view.setNeedsLayout()
        }
    }

    // MARK: Sizing

    private func contentHeightChanged(_ height: CGFloat) {
        guard height.isFinite, abs(height - contentHeight) > 0.5 else { return }
        contentHeight = height
        view.setNeedsLayout()
    }

    private func layoutContent() {
        let width = scrollView.bounds.width
        guard width > 0 else { return }
        if contentHeight <= 0 {
            // Before the content has reported its height, measure it once.
            let fitting = host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
            if fitting.height.isFinite, fitting.height > 0 { contentHeight = fitting.height }
        }
        let height = max(contentHeight, 1)
        let frame = CGRect(x: 0, y: 0, width: width, height: height)
        if host.view.frame != frame { host.view.frame = frame }
        let size = CGSize(width: width, height: height)
        if scrollView.contentSize != size { scrollView.contentSize = size }

        // Content got shorter while scrolled near the end: stay inside it.
        let maxOffset = max(0, height - scrollView.bounds.height)
        if !scrollView.isTracking, !scrollView.isDecelerating, scrollView.contentOffset.y > maxOffset {
            scrollView.contentOffset.y = maxOffset
        }

        if let request = pendingRequest, contentHeight > 0 {
            pendingRequest = nil
            handledRequestID = request.id
            scrollView.setContentOffset(CGPoint(x: 0, y: min(max(0, request.y), maxOffset)), animated: false)
        }
    }

    // MARK: Pull down to minimise

    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint,
                                   targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        guard scrollView.contentOffset.y < -SwipeDismiss.pull else { return }
        onPulledDown?()
    }
}

/// Carries the content's measured height from SwiftUI back to the controller.
final class PlayerScrollerRelay {
    var onHeight: ((CGFloat) -> Void)?
}

/// The hosted content at its natural height, top-aligned, reporting that height.
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .environment(\.colorScheme, .dark)
    }
}

private struct PlayerScrollerHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Where the Notes / Transcript switch sits in the scroll content, for "open on the panel".
struct PlayerPanelTopKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
