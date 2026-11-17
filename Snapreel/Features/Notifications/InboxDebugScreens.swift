#if DEBUG
import SwiftUI

extension DebugCatalog {
    /// Session E owns this list: notifications feed, notification settings, storage, sharing, save to Photos.
    static var inboxScreens: [DebugScreen] {
        [
            // Rows are marked read after 4 s on screen, so this one is taken sooner.
            .shell("notif.feed", "Notifications feed", tab: .notifications, wait: 2),
            .shell("notif.feed.empty", "Notifications feed [empty]", tab: .notifications, fixture: .empty),

            DebugScreen("settings.notifications", "Notification settings") {
                InboxSettingsDebugHost { NotificationSettingsView(permission: .notDetermined) }
            },
            DebugScreen("settings.notifications.off", "Notification settings [alerts off]") {
                InboxSettingsDebugHost { NotificationSettingsView(permission: .denied) }
            },

            DebugScreen("settings.storage", "Storage") {
                InboxSettingsDebugHost { StorageView() }
            },
            DebugScreen("settings.storage.confirm", "Storage [delete all, confirm]", wait: 4) {
                InboxSettingsDebugHost { StorageView(initialErase: .confirm) }
            },
            DebugScreen("settings.storage.done", "Storage [all data deleted]", fixture: .empty, wait: 4) {
                InboxSettingsDebugHost { StorageView(initialErase: .done) }
            },

            DebugScreen("share.sheet", "Share sheet over the library", wait: 5) {
                SharingDebugHost(action: .share)
            },
            DebugScreen("photos.permission", "Save to Photos [permission]", wait: 4) {
                SharingDebugHost(action: .photos(.permission))
            },
            DebugScreen("photos.progress", "Save to Photos [saving]") {
                SharingDebugHost(action: .photos(.saving))
            },
            DebugScreen("photos.saved", "Save to Photos [saved]") {
                SharingDebugHost(action: .photos(.saved))
            },
            DebugScreen("photos.denied", "Save to Photos [access off]", wait: 4) {
                SharingDebugHost(action: .photos(.denied))
            },
            DebugScreen("photos.audio", "Save to Photos [audio recording]", wait: 4) {
                SharingDebugHost(action: .photos(.audioOnly), videoID: FixtureStorage.IDs.launchMemo)
            },
            DebugScreen("photos.nospace", "Save to Photos [not enough space]", wait: 4) {
                SharingDebugHost(action: .photos(.failed(.outOfSpace)))
            },
        ]
    }
}

/// A Settings navigation stack with `content` already pushed, as it looks when opened from
/// Settings (back button, inline title).
@MainActor
struct InboxSettingsDebugHost<Content: View>: View {
    private let content: @MainActor () -> Content
    @State private var path: [Int] = [1]

    init(@ViewBuilder content: @escaping @MainActor () -> Content) {
        self.content = content
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Text("Settings")
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Int.self) { _ in content() }
        }
    }
}

/// The real tab shell on the Library tab with the share sheet or a save-to-Photos stage open
/// for a fixture recording.
@MainActor
struct SharingDebugHost: View {
    enum Action {
        case share
        case photos(PhotosSaveStage)
    }

    let action: Action
    var videoID: UUID = FixtureStorage.IDs.checkout

    @EnvironmentObject private var library: Library
    @State private var shareTarget: Video?
    @State private var photosTarget: Video?

    var body: some View {
        DebugShellHost(tab: .library, configure: nil)
            .shareVideo($shareTarget)
            // Lifted above the shell's tab bar; on a tab root the default inset is enough.
            .modifier(SaveToPhotosModifier(video: $photosTarget, initialStage: photosStage, bottomInset: 72))
            .task { await open() }
    }

    private var photosStage: PhotosSaveStage? {
        if case .photos(let stage) = action { return stage }
        return nil
    }

    private func open() async {
        // Let the shell finish its first layout before presenting over it.
        try? await Task.sleep(nanoseconds: 600_000_000)
        let video = library.video(videoID)
        switch action {
        case .share: shareTarget = video
        case .photos: photosTarget = video
        }
    }
}
#endif
