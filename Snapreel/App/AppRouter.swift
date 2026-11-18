import SwiftUI

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case home
    case library
    case record
    case notifications
    case search

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .library: return "Library"
        case .record: return "Record"
        case .notifications: return "Notifications"
        case .search: return "Search"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .library: return "play.rectangle.on.rectangle"
        case .record: return "record.circle"
        case .notifications: return "bell"
        case .search: return "magnifyingglass"
        }
    }

    var selectedSystemImage: String {
        switch self {
        case .home: return "house.fill"
        case .library: return "play.rectangle.on.rectangle.fill"
        case .record: return "record.circle.fill"
        case .notifications: return "bell.fill"
        case .search: return "magnifyingglass"
        }
    }
}

/// Destinations pushed inside a tab's NavigationStack. Mapped to views in `RouteDestination`.
enum Route: Hashable {
    case folder(UUID)
    case watchLater
    case history
    case allVideos
}

/// How the recorder was opened.
struct RecorderLaunch: Identifiable, Equatable {
    let id = UUID()
    var mode: RecordMode?
    /// Opens the photo library import straight away.
    var startsWithImport = false
}

/// The player is an overlay owned by the shell so it can minimise into a bar above the tab bar
/// and keep playing.
struct PlayerPresentation: Equatable {
    var videoID: UUID
    var startAt: Double?
    var isMinimized = false
    /// Opens on the Transcript tab (from a "transcript ready" notification).
    var opensTranscript = false
    /// Changes each time `play` is called so the player can react to a new request for the same video.
    var token = UUID()
}

/// App-wide navigation state. Views use `@EnvironmentObject var router: AppRouter`.
@MainActor
final class AppRouter: ObservableObject {
    @Published var tab: AppTab = .home
    @Published var homePath = NavigationPath()
    @Published var libraryPath = NavigationPath()
    @Published var notificationsPath = NavigationPath()
    @Published var searchPath = NavigationPath()

    @Published var recorder: RecorderLaunch?
    @Published var player: PlayerPresentation?
    @Published var isSettingsPresented = false
    /// Pages pushed when Settings opens (empty = the root). Set through `openSettings(_:)`.
    @Published var settingsPath: [SettingsPage] = []
    @Published var toast: ToastMessage?

    /// Selecting the Record tab opens the recorder instead of switching tabs.
    func select(_ newTab: AppTab) {
        if newTab == .record {
            record()
            return
        }
        if newTab == tab {
            // Second tap pops to the tab's root, like system tab bars.
            switch newTab {
            case .home: homePath = NavigationPath()
            case .library: libraryPath = NavigationPath()
            case .notifications: notificationsPath = NavigationPath()
            case .search: searchPath = NavigationPath()
            case .record: break
            }
        }
        tab = newTab
    }

    func record(_ mode: RecordMode? = nil, startsWithImport: Bool = false) {
        recorder = RecorderLaunch(mode: mode, startsWithImport: startsWithImport)
    }

    func play(_ videoID: UUID, at time: Double? = nil, opensTranscript: Bool = false) {
        withAnimation(Motion.standard) {
            player = PlayerPresentation(videoID: videoID, startAt: time, opensTranscript: opensTranscript)
        }
    }

    func minimizePlayer() {
        withAnimation(Motion.standard) { player?.isMinimized = true }
    }

    func expandPlayer() {
        withAnimation(Motion.standard) { player?.isMinimized = false }
    }

    func closePlayer() {
        withAnimation(Motion.standard) { player = nil }
    }

    /// Switches to `tab` and pushes `route` on its stack.
    func show(_ route: Route, in tab: AppTab) {
        self.tab = tab
        switch tab {
        case .home: homePath.append(route)
        case .library: libraryPath.append(route)
        case .notifications: notificationsPath.append(route)
        case .search: searchPath.append(route)
        case .record: break
        }
    }

    /// Opens the Settings sheet, optionally at a page: `router.openSettings(.storage)`.
    func openSettings(_ page: SettingsPage? = nil) {
        recorder = nil
        settingsPath = page.map { [$0] } ?? []
        isSettingsPresented = true
    }

    func showToast(_ text: String, systemImage: String = "checkmark.circle.fill") {
        toast = ToastMessage(text: text, systemImage: systemImage)
    }

    /// Notification tap or deep link: open the video.
    func open(videoID: UUID, opensTranscript: Bool = false) {
        recorder = nil
        isSettingsPresented = false
        play(videoID, opensTranscript: opensTranscript)
    }
}
