#if DEBUG
import SwiftUI

extension DebugCatalog {
    /// Session A owns this list: getting started, settings root, help, legal.
    static var startScreens: [DebugScreen] {
        [
            DebugScreen("start.splash", "Splash", fixture: .fresh, wait: 0.5) { SplashView(onFinish: {}) },
        ]
    }
}
#endif
