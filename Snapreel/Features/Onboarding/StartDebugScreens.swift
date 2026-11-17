#if DEBUG
import SwiftUI

extension DebugCatalog {
    /// Session A owns this list: getting started, settings root, help, legal.
    static var startScreens: [DebugScreen] {
        [
            DebugScreen("start.splash", "Splash", fixture: .fresh, wait: 1.8) {
                SplashView(onFinish: {})
            },
            DebugScreen("start.welcome", "Welcome", fixture: .fresh, wait: 2.5) {
                OnboardingFlow(initialStep: .welcome, onFinish: {})
            },
            DebugScreen("start.intro.1", "Intro slides [1 record]", fixture: .fresh) {
                OnboardingFlow(initialStep: .intro1, onFinish: {})
            },
            DebugScreen("start.intro.2", "Intro slides [2 organise]", fixture: .fresh) {
                OnboardingFlow(initialStep: .intro2, onFinish: {})
            },
            DebugScreen("start.intro.3", "Intro slides [3 send]", fixture: .fresh) {
                OnboardingFlow(initialStep: .intro3, onFinish: {})
            },
            DebugScreen("start.use", "What will you use it for", fixture: .fresh) {
                OnboardingFlow(initialStep: .useCase, onFinish: {})
            },
            DebugScreen("start.use.selected", "What will you use it for [selected]", fixture: .fresh) {
                OnboardingFlow(initialStep: .useCase, preselectedUseCase: .personal, onFinish: {})
            },
            tour("start.tour.intro", "Guided tour [intro]", step: .intro),
            tour("start.tour.1", "Guided tour [1 home]", step: .home),
            tour("start.tour.2", "Guided tour [2 library]", step: .library),
            tour("start.tour.3", "Guided tour [3 record]", step: .record),
            tour("start.tour.4", "Guided tour [4 notifications]", step: .notifications),
            tour("start.tour.permission", "Guided tour [notification permission alert]", step: .notifications,
                 requestsPermission: true),
            DebugScreen("settings.root", "Settings root") {
                SettingsDebugHost(path: [])
            },
            DebugScreen("help.home", "Help centre") {
                SettingsDebugHost(path: [.help], useCase: .work)
            },
            DebugScreen("help.article", "Help article") {
                SettingsDebugHost(path: [.help, .helpArticle("screen-start")])
            },
            DebugScreen("help.contact", "Contact support") {
                SettingsDebugHost(path: [.help, .contact(.screen)],
                                  contactMessage: "When I stop a screen recording, my voice is missing even though the microphone was on.")
            },
            DebugScreen("legal.menu", "Legal menu") {
                SettingsDebugHost(path: [.legal])
            },
            DebugScreen("legal.terms", "Terms of use") {
                SettingsDebugHost(path: [.legal, .legalDocument(.terms)])
            },
            DebugScreen("legal.privacy", "Privacy policy") {
                SettingsDebugHost(path: [.legal, .legalDocument(.privacy)])
            },
            DebugScreen("legal.ack", "Acknowledgements") {
                SettingsDebugHost(path: [.legal, .acknowledgements])
            },
        ]
    }

    /// The real tab shell (empty library) with the tour showing at `step`.
    private static func tour(_ id: String, _ title: String, step: TourStep,
                             requestsPermission: Bool = false) -> DebugScreen {
        .shell(id, title, tab: .home, fixture: .empty, wait: requestsPermission ? 4 : 3) { _, _ in
            TourDebug.start = step
            TourDebug.requestsPermission = requestsPermission
            AppEnvironment.shared.settings.hasCompletedTour = false
        }
    }
}

/// The tab shell with Settings open as a sheet, already pushed to `path`. (The shell's own
/// Settings sheet always opens at the root, so this host presents its own.)
struct SettingsDebugHost: View {
    let path: [SettingsPage]
    var useCase: UseCase? = nil
    var contactMessage: String? = nil

    @EnvironmentObject private var library: Library
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: AppRouter
    @State private var presented = false

    init(path: [SettingsPage], useCase: UseCase? = nil, contactMessage: String? = nil) {
        self.path = path
        self.useCase = useCase
        self.contactMessage = contactMessage
    }

    var body: some View {
        MainShell()
            .sheet(isPresented: $presented) {
                SettingsView(initialPath: path)
                    .environmentObject(library)
                    .environmentObject(settings)
                    .environmentObject(router)
            }
            .task {
                router.tab = .home
                if let useCase { settings.useCase = useCase }
                ContactSupportDebug.message = contactMessage
                try? await Task.sleep(nanoseconds: 350_000_000)
                presented = true
            }
    }
}
#endif
