import SwiftUI
import UserNotifications

@main
struct SnapreelApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var environment = AppEnvironment.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment.library)
                .environmentObject(environment.settings)
                .environmentObject(environment.router)
                .onOpenURL { url in AppLinks.open(url) }
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active, environment.debugScreenID == nil else { return }
            AppLifecycle.becameActive(library: environment.library, settings: environment.settings)
        }
    }
}

/// `snapreel://` links and universal links. `snapreel://recording` opens the recording in
/// progress, where Stop is: tapping the recording's Live Activity sends it
/// (`RecordingLiveActivity`), and Snapreel opens it itself to come back over the system's
/// broadcast sheet (`BroadcastSheetCloser`). `https://snapreel.video/v/{slug}` opens your own
/// recording when it is on this iPhone, otherwise the watch page in Safari.
@MainActor
enum AppLinks {
    static func open(_ url: URL) {
        if url.scheme == "https" || url.scheme == "http",
           url.host == CloudConfig.linkHost || url.host == "www." + CloudConfig.linkHost {
            openShareLink(url)
            return
        }
        guard url.scheme == "snapreel", url.host == "recording" else { return }
        let router = AppEnvironment.shared.router
        guard router.recorder == nil else { return }
        let state = BroadcastStateStore.read()
        let live = state.status == .recording && Date().timeIntervalSince(state.updatedAt) < 20
        if router.minimizedRecorder != nil {
            // A voice recording carrying on in the bar above the tab bar.
            router.expandRecorder()
        } else if live {
            router.record(.screen)
        }
    }

    /// `/v/{slug}`: the recording behind one of your own links, or Safari for anyone else's.
    static func openShareLink(_ url: URL) {
        let parts = url.pathComponents
        guard parts.count >= 3, parts[1] == "v" else {
            ShareLinks.openInSafari(url)
            return
        }
        let slug = parts[2]
        if openOwnRecording(slug: slug) { return }
        Task { @MainActor in
            // A link made on this account before this iPhone knew it (a reinstall, the web).
            await ShareLinks.shared.refresh(force: true)
            if !openOwnRecording(slug: slug) { ShareLinks.openInSafari(url) }
        }
    }

    private static func openOwnRecording(slug: String) -> Bool {
        let environment = AppEnvironment.shared
        guard let link = environment.library.links.values.first(where: { $0.slug == slug }),
              let video = environment.library.video(link.videoID), video.state.isReady else { return false }
        let router = environment.router
        guard let showing = router.player, showing.videoID != video.id else {
            router.open(videoID: video.id)
            return true
        }
        // The player shows another recording: close it (and its playback, saving how far that one got) and open
        // this one in a new player. Swapping the video in the open player kept the old picture playing under the
        // new title, and counted its watching for this recording (tester t26-link, S2).
        PlaybackSession.shared.close()
        router.closePlayer()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            router.open(videoID: video.id)
        }
        return true
    }
}

/// Work that runs each time the app comes to the foreground.
@MainActor
enum AppLifecycle {
    static func becameActive(library: Library, settings: AppSettings) {
        // Screen recordings finished while Snapreel was in the background (session B).
        PendingImports.importFinishedBroadcasts(into: library)
        // Saves interrupted by the app being closed get resumed or marked failed (session B).
        PendingImports.resumeInterruptedSaves(in: library)
        // Warn once a day when the phone is nearly full (session E).
        StorageMonitor.check(library: library)
        // End a recording's Live Activity left over from a recording that stopped while
        // Snapreel was suspended, or start one it couldn't start from the background.
        RecordingLiveActivity.sync()
        // Share links: resume uploads, refresh counts, pick up pushes that arrived meanwhile.
        CloudServices.becameActive()
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Share-link uploads that still need Snapreel (must be registered before launching ends).
        UploadBackground.register()
        Task { @MainActor in
            RecordingLiveActivity.startObserving()
            if AppEnvironment.shared.debugScreenID == nil { CloudServices.start() }
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in PushService.shared.didRegister(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // No token (the simulator, or no connection): pushes about links simply don't arrive.
    }

    /// iOS relaunched Snapreel to deliver share-link upload events (`Uploader`).
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            Uploader.shared.handleBackgroundEvents(identifier: identifier, completion: completionHandler)
        }
    }

    /// In the foreground the in-app toast and feed already say it; show only in Notification
    /// Centre. A push about a share link shows as a banner and joins the feed.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let content = notification.request.content
        if let payload = PushService.payload(from: content.userInfo) {
            let title = content.title, body = content.body, identifier = notification.request.identifier
            Task { @MainActor in
                PushService.shared.received(payload, title: title, body: body, identifier: identifier)
            }
            completionHandler([.banner, .list, .sound])
            return
        }
        completionHandler([.list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if let payload = PushService.payload(from: info) {
            let content = response.notification.request.content
            let title = content.title, body = content.body, identifier = response.notification.request.identifier
            Task { @MainActor in
                PushService.shared.opened(payload, title: title, body: body, identifier: identifier)
                completionHandler()
            }
            return
        }
        let videoID = (info["videoID"] as? String).flatMap(UUID.init(uuidString:))
        let notificationID = (info["notificationID"] as? String).flatMap(UUID.init(uuidString:))
        let broadcastID = (info["broadcastID"] as? String).flatMap(UUID.init(uuidString:))
        let kind = info["kind"] as? String
        Task { @MainActor in
            let environment = AppEnvironment.shared
            if let notificationID { environment.library.markNotificationRead(notificationID) }
            if let broadcastID {
                // Posted by the broadcast extension before the video exists in the library.
                PendingImports.openReviewFromNotification(broadcastID: broadcastID, library: environment.library)
            } else if let videoID, environment.library.video(videoID) != nil {
                environment.router.open(videoID: videoID,
                                        opensTranscript: kind == NotificationKind.transcriptReady.rawValue)
            } else if kind == NotificationKind.storageLow.rawValue {
                environment.router.openSettings(.storage)
            } else {
                environment.router.select(.notifications)
            }
            completionHandler()
        }
    }
}
