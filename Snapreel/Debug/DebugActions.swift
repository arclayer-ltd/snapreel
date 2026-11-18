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

    /// System prompts stay on screen until answered, even across relaunches, so the screenshot
    /// script shoots these last, each on a fresh install.
    var raisesSystemPrompt: Bool {
        switch self {
        case .microphonePrompt, .cameraPrompt, .photosPrompt: return true
        case .scroll: return false
        }
    }

    @MainActor
    func run() {
        switch self {
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
    private static func scrollMainList(to fraction: CGFloat) {
        guard let root = topView else { return }
        let candidates = views(of: UIScrollView.self, in: root).filter {
            !($0 is UITextView) && $0.isScrollEnabled && !$0.isHidden && $0.window != nil
                && $0.contentSize.height > $0.bounds.height + 1
        }
        guard let list = candidates.max(by: { $0.bounds.height < $1.bounds.height }) else { return }
        let insets = list.adjustedContentInset
        let top = -insets.top
        let bottom = list.contentSize.height - list.bounds.height + insets.bottom
        let y = top + (bottom - top) * min(max(fraction, 0), 1)
        list.setContentOffset(CGPoint(x: list.contentOffset.x, y: y), animated: false)
    }
}
#endif
