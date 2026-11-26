import SwiftUI

/// The Settings sheet, presented through UIKit (`ProPresenter.openSettings`).
///
/// Tester t26 and the rig (iOS 16.4): once Settings had closed twice, the gear on every tab root was still drawn
/// but no longer a button (the accessibility tree turned it into "Other"), until the app went to the background or
/// the tab was switched. Redrawing the toolbar, keeping this state off the router, and presenting through UIKit
/// instead of SwiftUI's `.sheet` each left it the same. What a tab switch does brings it back, so after Settings
/// has gone the shown tab gets the same nudge (`AppRouter.nudgeTabs`).
@MainActor
final class SettingsSheet: ObservableObject {
    static let shared = SettingsSheet()

    /// Setting it opens or closes the sheet.
    @Published var isPresented = false {
        didSet {
            guard isPresented != oldValue, !isSettling else { return }
            if isPresented {
                ProPresenter.openSettings(path: path)
            } else {
                ProPresenter.closeSettings { AppEnvironment.shared.router.nudgeTabs() }
            }
        }
    }
    /// Read once when the sheet opens.
    var path: [SettingsPage] = []
    private var isSettling = false

    /// The sheet went (a swipe down, or it couldn't be shown).
    func didClose() {
        isSettling = true
        isPresented = false
        isSettling = false
        AppEnvironment.shared.router.nudgeTabs()
    }
}

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
    /// Brings back the recorder that was minimised mid audio recording.
    var resumesMinimized = false
}

/// The player is an overlay owned by the shell so it can minimise into a bar above the tab bar
/// and keep playing.
struct PlayerPresentation: Equatable {
    var videoID: UUID
    var startAt: Double?
    var isMinimized = false
    /// Opens on the Transcript tab (from a "transcript ready" notification).
    var opensTranscript = false
    /// Opens on the Comments tab (from a comment on the recording's share link).
    var opensComments = false
    /// Changes each time `play` is called so the player can react to a new request for the same video.
    var token = UUID()
}

/// The video editor, full screen over everything (`EditorScreen`).
struct EditorLaunch: Identifiable, Equatable {
    let id = UUID()
    var videoID: UUID
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
    /// An audio recording that keeps going in the bar above the tab bar after the recorder was
    /// swiped down.
    @Published var minimizedRecorder: RecorderModel?
    @Published var player: PlayerPresentation?
    @Published var editor: EditorLaunch?
    /// Whether the Settings sheet is up. Kept in `SettingsSheet`, not published here: every tab root watches the
    /// router, and redrawing their toolbars while the sheet came and went left the gear dead on iOS 16.
    var isSettingsPresented: Bool {
        get { SettingsSheet.shared.isPresented }
        set { SettingsSheet.shared.isPresented = newValue }
    }
    /// For a moment after a sheet closed: the shown tab is drawn as if it had just been switched to, which gives its
    /// navigation bar's buttons their taps back (see `SettingsSheet`).
    @Published private(set) var isNudgingTabs = false

    func nudgeTabs() {
        guard !isNudgingTabs else { return }
        isNudgingTabs = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000)
            isNudgingTabs = false
        }
    }

    /// Pages pushed when Settings opens (empty = the root). Set through `openSettings(_:)`.
    var settingsPath: [SettingsPage] {
        get { SettingsSheet.shared.path }
        set { SettingsSheet.shared.path = newValue }
    }
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
        if minimizedRecorder != nil {
            // One take at a time: open the recording that's already running.
            expandRecorder()
            return
        }
        recorder = RecorderLaunch(mode: mode, startsWithImport: startsWithImport)
    }

    func minimizeRecorder(_ model: RecorderModel) {
        withAnimation(Motion.standard) { minimizedRecorder = model }
        recorder = nil
    }

    func expandRecorder() {
        guard minimizedRecorder != nil, recorder == nil else { return }
        recorder = RecorderLaunch(mode: nil, resumesMinimized: true)
    }

    func play(_ videoID: UUID, at time: Double? = nil, opensTranscript: Bool = false, opensComments: Bool = false) {
        if minimizedRecorder != nil {
            // Playing would take the microphone's audio session away from the recording.
            showToast("Stop your recording to play this", systemImage: "mic.fill")
            return
        }
        withAnimation(Motion.standard) {
            player = PlayerPresentation(videoID: videoID, startAt: time, opensTranscript: opensTranscript,
                                        opensComments: opensComments)
        }
    }

    /// Opens the editor on a recording. One full-screen page at a time: the player or the
    /// recorder closes first, and the editor follows once it has gone.
    func edit(_ videoID: UUID, afterClosing: Bool = false) {
        if minimizedRecorder != nil {
            showToast("Stop your recording to edit", systemImage: "mic.fill")
            return
        }
        let waits = afterClosing || recorder != nil || (player.map { !$0.isMinimized } ?? false)
        if player != nil {
            PlaybackSession.shared.close()
            withAnimation(Motion.standard) { player = nil }
        }
        recorder = nil
        isSettingsPresented = false
        guard waits else {
            editor = EditorLaunch(videoID: videoID)
            return
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 650_000_000)
            self.editor = EditorLaunch(videoID: videoID)
        }
    }

    func closeEditor() {
        editor = nil
    }

    /// Closes the editor and plays a recording (a saved edit's "Open").
    func closeEditor(thenPlay videoID: UUID) {
        editor = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 650_000_000)
            self.play(videoID)
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
    func open(videoID: UUID, opensTranscript: Bool = false, opensComments: Bool = false) {
        recorder = nil
        isSettingsPresented = false
        play(videoID, opensTranscript: opensTranscript, opensComments: opensComments)
    }
}
