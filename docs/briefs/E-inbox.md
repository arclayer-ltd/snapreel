# Session E: notifications, storage management, sharing and save to Photos

Read `docs/briefs/COMMON.md` first. You own `Snapreel/Features/Notifications/`,
`Snapreel/Features/Storage/`, `Snapreel/Features/Sharing/`. `Notifier` (Services) is the lead's
and already posts feed rows and local notifications; you build the UI around it and the settings.

## Screens

| Debug id(s) | Screen | Reference |
|---|---|---|
| `notif.feed` `notif.feed.empty` | Notifications tab: large title, gear, feed grouped by day (`Format.dayTitle`), each row: kind icon, title, body, age, the video's thumbnail when it has one, unread dot; tap marks read and opens the video (`router.play`) or the relevant place (storage low → Settings sheet with Storage); swipe to delete; "Mark all as read" in a menu. Mark rows read when the tab is viewed for a few seconds. Filter chips: All / Recordings / Transcripts (your choice of grouping, own wording). Empty: SF Symbol state ("Nothing new. We'll let you know when a recording is saved or a transcript is ready."). The tab bar's unread dot comes from `library.unreadNotificationCount` already. | mobbin baadcda8, a7678dbf, appstore-05 |
| `settings.notifications` | Notification settings: one toggle per `NotificationKind` with its `settingsDetail`, grouped (Recording: saved, needs title, import; Library: transcript ready; Device: storage low); a banner at the top when system permission is off (`Permissions.state(.notifications)`) with "Turn on in Settings" / "Allow" (request if not determined). | mobbin be1d5c1e, 6bf1eb6d |
| `settings.storage` `settings.storage.confirm` `settings.storage.done` | Storage: a bar showing Snapreel's videos vs other used vs free space on this iPhone (`DiskSpace`), counts by kind, the largest videos (thumbnail, title, size; swipe or button to delete with confirm), "Delete all my data" (destructive, confirm sheet that says exactly what goes: every recording, folder, note, reaction, transcript and notification; settings stay; can't be undone; type-free double confirmation), done state ("All data deleted", back to an empty library). Uses `library.eraseEverything()` + `settings.resetAfterErase()`. | mobbin 3792bec9, 0adb4039 (delete-account screens, craft reference) |

## Flows you provide to other sessions (keep the signatures in `SharingModifiers.swift`)

- `.shareVideo(_ video: Binding<Video?>)`: presents `UIActivityViewController` with the file
  URL (`library.fileURL(for:)`), subject = title; on completion with `completed == true`
  `library.recordShare(id)`. Works from sheets and full-screen covers (present from the topmost
  view controller, or wrap in a SwiftUI sheet with a representable — your call, must work over the
  dark player and the recorder review). Debug id `share.sheet` presents it over the library.
- `.saveToPhotos(_ video: Binding<Video?>)`: permission (add-only; explain before the system
  prompt, denied → Settings), progress while `PHPhotoLibrary.shared().performChanges` adds the file
  with `PHAssetCreationRequest.addResource(with: .video, fileURL:, options:)` (`shouldMoveFile = false`),
  "Saved to Photos" confirmation (toast-like, with Open Photos via `photos-redirect://`), failure
  with reason (out of space, permission). Audio-only recordings can't go to Photos: show a clear
  message suggesting Share instead. `library.recordSavedToPhotos(id)` on success. Give the
  modifier an initial-state hook for debug (`photos.permission`, `photos.progress`, `photos.saved`
  ids over the library tab; C will reuse your states for its player debug ids, so tell the lead
  the exact API in your report).

## Background work

- `StorageMonitor.check(library:)` (called on every foreground): if `DiskSpace.available` <
  `DiskSpace.lowThreshold`, post `.storageLow` at most once per 24 h (remember the last time in
  `AppGroup.defaults`).
