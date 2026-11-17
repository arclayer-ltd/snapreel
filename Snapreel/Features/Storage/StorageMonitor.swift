import Foundation
import UserNotifications

/// Session E owns this file. Posts `.storageLow` (at most once a day) when free space is low.
/// Called by `AppLifecycle.becameActive` each time Snapreel comes to the foreground.
@MainActor
enum StorageMonitor {
    /// `AppGroup.defaults` key: when the last low-storage warning was posted.
    static let lastWarningKey = "storage.lastLowWarning"
    static let warningInterval: TimeInterval = 24 * 60 * 60

    static func check(library: Library) {
        // Links made for sharing are only needed while a share is in progress.
        ShareFileLink.cleanUp(olderThan: 60 * 60, root: library.media.root)

        let available = DiskSpace.available
        guard available > 0, available < DiskSpace.lowThreshold else { return }
        let defaults = AppGroup.defaults
        let now = Date()
        if let last = defaults.object(forKey: lastWarningKey) as? Date,
           now.timeIntervalSince(last) < warningInterval {
            return
        }
        defaults.set(now, forKey: lastWarningKey)
        Notifier.shared.post(.storageLow,
                             title: "Your iPhone is almost full",
                             body: message(available: available, recordingBytes: library.totalVideoBytes))
    }

    static func message(available: Int64, recordingBytes: Int64) -> String {
        let left = "Only \(Format.bytes(available)) left, so new recordings may not save."
        guard recordingBytes > 0 else { return left }
        return "\(left) Your recordings use \(Format.bytes(recordingBytes))."
    }
}

/// Removes Snapreel's alerts from Notification Centre and any reminders still waiting, after
/// "Delete all my data", so no recording titles are left on the Lock Screen.
/// (Requested as `Notifier.removeAll()` in docs/requests/E.md; local until then.)
enum DeliveredAlerts {
    static func removeAll() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }
}
