import SwiftUI
import UIKit

/// Applies Settings > Appearance to the app's windows. "Match iPhone" leaves the style
/// unspecified so the system setting shows through; Light and Dark override it. Screens that
/// are always dark (recorder, player) set their own style on their presentation, so they win.
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
