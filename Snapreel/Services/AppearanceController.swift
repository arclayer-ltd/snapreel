import SwiftUI
import UIKit

/// Applies Settings > Appearance to the app's windows. "Match iPhone" leaves the style
/// unspecified so the system setting shows through; Light and Dark override it. Every screen
/// follows it, the recorder and the player included: none sets its own style. Only the picture
/// itself (live camera, video, full-screen playback) is drawn dark, with fixed ink colours.
@MainActor
enum AppearanceController {
    static func apply(_ mode: AppearanceMode) {
        let style = mode.interfaceStyle
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where window.overrideUserInterfaceStyle != style {
                window.overrideUserInterfaceStyle = style
            }
        }
    }
}

extension AppearanceMode {
    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }
}
