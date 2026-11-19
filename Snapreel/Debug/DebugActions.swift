#if DEBUG
import AVFoundation
import Photos
import UIKit

/// Things a debug screen can do once it has settled, so a screenshot shows a later moment of
/// a flow: a list scrolled down, or a real system prompt over the screen.
enum DebugSettle {
    /// Scroll the screen's main vertical list to `fraction` of the way down (0 = top, 1 = end).
    case scroll(CGFloat)
    /// Ask iOS for microphone access (shows the system prompt the first time).
    case microphonePrompt
    /// Ask iOS for camera access.
    case cameraPrompt
    /// Ask iOS for add-only Photos access.
    case photosPrompt
    /// Log (DebugTrace) which view the system hit-tests at points down the main list, and
    /// whether that view is inside the list: the simulator can't tap, so this is how CI shows
    /// that touches on the player's details reach them.
    case probeTouches

    /// System prompts stay on screen until answered, even across relaunches, so the screenshot
    /// script shoots these last, each on a fresh install.
    var raisesSystemPrompt: Bool {
        switch self {
        case .microphonePrompt, .cameraPrompt, .photosPrompt: return true
        case .scroll, .probeTouches: return false
        }
    }

    @MainActor
    func run() {
        switch self {
        case .probeTouches:
            DebugSettle.probeTouches()
        case .scroll(let fraction):
            DebugSettle.scrollMainList(to: fraction)
        case .microphonePrompt:
            AVAudioSession.sharedInstance().requestRecordPermission { _ in }
        case .cameraPrompt:
            AVCaptureDevice.requestAccess(for: .video) { _ in }
        case .photosPrompt:
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { _ in }
        }
    }

    // MARK: Helpers

    @MainActor
    private static var topView: UIView? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.windows.first(where: \.isKeyWindow) }
            .first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top?.view ?? window
    }

    @MainActor
    private static func views<T: UIView>(of type: T.Type, in root: UIView) -> [T] {
        var found: [T] = []
        var stack: [UIView] = [root]
        while let view = stack.popLast() {
            if let match = view as? T { found.append(match) }
            stack.append(contentsOf: view.subviews)
        }
        return found
    }

    /// The tallest vertically scrollable view on the front-most screen (lists, not rails or pagers).
    @MainActor
    private static func mainList() -> UIScrollView? {
        guard let root = topView else { return nil }
        let candidates = views(of: UIScrollView.self, in: root).filter {
            !($0 is UITextView) && $0.isScrollEnabled && !$0.isHidden && $0.window != nil
                && $0.contentSize.height > $0.bounds.height + 1
        }
        return candidates.max(by: { $0.bounds.height < $1.bounds.height })
    }

    @MainActor
    private static func probeTouches() {
        guard let list = mainList(), let window = list.window else {
            DebugTrace.log("touch probe: no scrollable list on screen")
            return
        }
        let frame = list.convert(list.bounds, to: window)
        DebugTrace.log("touch probe: list at y \(Int(frame.minY))...\(Int(frame.maxY)) in a \(Int(window.bounds.height))-point window")
        // "middle" sits under the speed menu when it is open (it starts 58 points from the left).
        for (label, x) in [("left", frame.minX + 40), ("middle", frame.minX + 150), ("right", frame.maxX - 40)] {
            for depth in stride(from: CGFloat(16), to: frame.height, by: 48) {
                let point = CGPoint(x: x, y: frame.minY + depth)
                let hit = window.hitTest(point, with: nil)
                let inside = hit.map { $0 === list || $0.isDescendant(of: list) } ?? false
                let name = hit.map { String(describing: type(of: $0)) } ?? "nothing"
                DebugTrace.log("touch probe: \(label) +\(Int(depth)) -> \(inside ? "list" : "NOT the list") (\(name))")
            }
        }
    }

    @MainActor
    private static func scrollMainList(to fraction: CGFloat) {
        guard let list = mainList() else { return }
        let insets = list.adjustedContentInset
        let top = -insets.top
        let bottom = list.contentSize.height - list.bounds.height + insets.bottom
        let y = top + (bottom - top) * min(max(fraction, 0), 1)
        list.setContentOffset(CGPoint(x: list.contentOffset.x, y: y), animated: false)
    }
}
#endif
