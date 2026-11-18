import SwiftUI

/// Splash, then onboarding on first run, then the tab shell.
struct RootView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var showsSplash = true

    var body: some View {
        content
            // The window exists by the time the root appears; apply the saved appearance to it.
            .onAppear { AppearanceController.apply(settings.appearance) }
    }

    @ViewBuilder private var content: some View {
        #if DEBUG
        if let id = AppEnvironment.shared.debugScreenID {
            DebugHost(screenID: id)
        } else {
            appContent
        }
        #else
        appContent
        #endif
    }

    private var appContent: some View {
        ZStack {
            if settings.hasCompletedOnboarding {
                MainShell()
                    .transition(.opacity)
            } else {
                OnboardingFlow(onFinish: {
                    withAnimation(Motion.gentle) { settings.hasCompletedOnboarding = true }
                })
                .transition(.opacity)
            }
            if showsSplash {
                SplashView(onFinish: {
                    withAnimation(.easeOut(duration: 0.35)) { showsSplash = false }
                })
                .transition(.opacity)
                .zIndex(1)
            }
        }
    }
}
