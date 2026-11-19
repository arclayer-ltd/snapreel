import SwiftUI
import UIKit

/// Shared numbers for "drag down to minimise or close" on the full-screen covers (player and
/// recorder). iOS doesn't let a full-screen cover be swiped away, so each screen moves its own
/// page with the finger and then dismisses.
enum SwipeDismiss {
    /// How far the finger has to travel before letting go minimises.
    static let distance: CGFloat = 110
    /// A quick flick counts too, judged by where the drag would have ended.
    static let projected: CGFloat = 320
    /// How far past the top a scrolled page has to be pulled down.
    static let pull: CGFloat = 96
    /// Far enough below any iPhone screen to slide the page out of sight.
    static let offscreen: CGFloat = 1400
    static let springBack = Animation.spring(response: 0.3, dampingFraction: 0.86)
    static let slideAway = Animation.easeOut(duration: 0.2)

    /// The drag is heading down more than sideways.
    static func isDownward(_ value: DragGesture.Value) -> Bool {
        value.translation.height > 0 && value.translation.height > abs(value.translation.width)
    }

    /// Letting go here should minimise or close.
    static func commits(_ value: DragGesture.Value) -> Bool {
        value.translation.height > distance || value.predictedEndTranslation.height > projected
    }
}

extension View {
    /// Lets the app show through a full-screen cover, so a page dragged down reveals what is
    /// underneath instead of a black gap. The page draws its own background.
    @ViewBuilder func clearCoverBackground() -> some View {
        if #available(iOS 16.4, *) {
            presentationBackground(Color.clear)
        } else {
            background(ClearCoverBackground())
        }
    }
}

/// iOS 16.0–16.3: clears the cover's container views once the page is on screen.
private struct ClearCoverBackground: UIViewRepresentable {
    func makeUIView(context: Context) -> ClearingView { ClearingView() }
    func updateUIView(_ uiView: ClearingView, context: Context) {}

    final class ClearingView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                self?.superview?.superview?.backgroundColor = .clear
            }
        }
    }
}
