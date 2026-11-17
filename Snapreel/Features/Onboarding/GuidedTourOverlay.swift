import SwiftUI

/// Session A owns this file. Four-step tour over the tab bar, shown once after onboarding.
/// `targets` are the tab bar items' frames in the overlay's (full-screen) coordinates.
/// The last step asks for notification permission, then calls `onFinish`.
struct GuidedTourOverlay: View {
    let targets: [AppTab: CGRect]
    let onFinish: () -> Void

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .onAppear { onFinish() }
    }
}
