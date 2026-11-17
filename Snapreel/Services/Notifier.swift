import Foundation
import UserNotifications

/// Posts what the app itself did: a row in the Notifications feed, plus a local notification
/// when that kind is switched on in Settings and the person allowed notifications.
/// Feature code calls `Notifier.shared.post(...)`; it never talks to UNUserNotificationCenter directly.
@MainActor
final class Notifier {
    static let shared = Notifier()

    private weak var library: Library?
    private weak var settings: AppSettings?
    /// While true (fixtures, screenshots) nothing reaches the system notification center.
    private var deliversSystemNotifications = true

    func configure(library: Library, settings: AppSettings, deliversSystemNotifications: Bool) {
        self.library = library
        self.settings = settings
        self.deliversSystemNotifications = deliversSystemNotifications
    }

    /// Adds a feed row and, if allowed, shows a local notification. `userInfo["videoID"]`
    /// lets a tap open the video.
    func post(_ kind: NotificationKind, title: String, body: String, videoID: UUID? = nil) {
        let item = AppNotification(kind: kind, videoID: videoID, title: title, body: body, createdAt: Date())
        library?.appendNotification(item)

        guard deliversSystemNotifications, settings?.isNotificationEnabled(kind) ?? true else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = kind.rawValue
        var info: [String: String] = ["notificationID": item.id.uuidString, "kind": kind.rawValue]
        if let videoID { info["videoID"] = videoID.uuidString }
        content.userInfo = info
        let request = UNNotificationRequest(identifier: item.id.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Schedules a reminder in the future (for example "still waiting for a title" an hour later).
    /// Replaces any earlier reminder with the same `key`. The feed row is added when it fires
    /// (see `AppDelegate`), not now.
    func schedule(_ kind: NotificationKind, key: String, title: String, body: String,
                  videoID: UUID?, after seconds: TimeInterval) {
        guard deliversSystemNotifications, settings?.isNotificationEnabled(kind) ?? true else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        var info: [String: String] = ["kind": kind.rawValue, "scheduled": "1"]
        if let videoID { info["videoID"] = videoID.uuidString }
        content.userInfo = info
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        let request = UNNotificationRequest(identifier: key, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func cancelScheduled(key: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [key])
    }

    /// Removes every delivered alert and every scheduled reminder (Settings › Storage › Delete all my data).
    func removeAll() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Shows the system prompt (first time only). Returns whether notifications are allowed.
    @discardableResult
    func requestAuthorization() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        AppGroup.defaults.set(granted, forKey: SharedDefaultsKey.notificationsAuthorized)
        return granted
    }
}
