# Session E: shared-code requests

Nothing here blocks E's screens; each has a local workaround in E's folders today.

## 1. `Notifier.removeAll()` for "Delete all my data"

After erasing, Snapreel's delivered alerts (with recording titles) stay in Notification Centre
and scheduled "waiting for a title" reminders still fire. E calls `UNUserNotificationCenter`
directly from `Features/Storage/StorageMonitor.swift` (`DeliveredAlerts.removeAll()`) until this
exists; swap the call in `StorageView.erase()` for `Notifier.shared.removeAll()` once added.

```swift
// Services/Notifier.swift, inside Notifier
/// Removes every delivered alert and every scheduled reminder (Settings › Storage › Delete all my data).
func removeAll() {
    let center = UNUserNotificationCenter.current()
    center.removeAllPendingNotificationRequests()
    center.removeAllDeliveredNotifications()
}
```

## 2. Open Settings at a page (`AppRouter.openSettings(_:)`)

The feed's "Your iPhone is almost full" row should open Settings › Storage, and a tapped
`.storageLow` system alert has no video, so `AppDelegate` currently just selects the
Notifications tab. Today E presents its own sheet (`NavigationStack { StorageView() }` with
Done) from `NotificationsView`. With this, E would call `router.openSettings(.storage)` and
session A's `SettingsView` would push the page.

```swift
// App/AppRouter.swift
enum SettingsPage: Hashable {
    case notifications
    case recording
    case storage
}

// inside AppRouter
/// The page Settings should show when it opens (session A pushes it, then sets this to nil).
@Published var settingsPage: SettingsPage?

func openSettings(_ page: SettingsPage? = nil) {
    recorder = nil
    settingsPage = page
    isSettingsPresented = true
}
```

```swift
// App/SnapreelApp.swift, AppDelegate.didReceive, replacing the `else` branch
} else if (info["kind"] as? String) == NotificationKind.storageLow.rawValue {
    environment.router.openSettings(.storage)
} else {
    environment.router.select(.notifications)
}
```

## 3. Cancel the "waiting for a title" reminder when a recording is named

The feed lets you name a recording straight from its "needs a title" row
(`library.rename`). A reminder scheduled with `Notifier.schedule(.needsTitle, key: …)` for that
video would still fire. If B schedules it with a key derived from the video id, a shared helper
lets every renaming screen (B review, C player, D library, E feed) cancel it:

```swift
// Services/Notifier.swift, inside Notifier
static func titleReminderKey(for videoID: UUID) -> String { "needsTitle.\(videoID.uuidString)" }

func cancelTitleReminder(for videoID: UUID) {
    cancelScheduled(key: Self.titleReminderKey(for: videoID))
}
```

and in `Library.rename(_:to:)` after the update: `Notifier.shared.cancelTitleReminder(for: id)`.

## 4. Debug wait for `notif.feed`

Not a code change: `notif.feed` uses `wait: 2` because the feed marks visible rows read after
4 seconds on screen (brief: "mark rows read when the tab is viewed for a few seconds"). If the
screenshot script's `wait` is measured from launch, 2 s keeps the unread dots in the shot.
