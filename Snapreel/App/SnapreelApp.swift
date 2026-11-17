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
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active, environment.debugScreenID == nil else { return }
            AppLifecycle.becameActive(library: environment.library, settings: environment.settings)
        }
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
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// In the foreground the in-app toast and feed already say it; show only in Notification Centre.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
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
                environment.router.open(videoID: videoID)
            } else if kind == NotificationKind.storageLow.rawValue {
                environment.router.openSettings(.storage)
            } else {
                environment.router.select(.notifications)
            }
            completionHandler()
        }
    }
}
