# Session B: shared-code requests

Everything below works without these changes; each one makes a flow better. Exact Swift is given.

## 1. Notification tap on "Screen recording finished" opens review (App/SnapreelApp.swift)

The broadcast extension posts a local notification with `userInfo["broadcastID"]` (no
`videoID`, because the video doesn't exist yet when the extension finishes). Today
`AppDelegate.userNotificationCenter(_:didReceive:)` falls through to `router.select(.notifications)`.
Meanwhile `PendingImports.importFinishedBroadcasts` (run on `becameActive`) already opens review for a
recording that finished in the last 15 minutes, so the common case works. To make the tap always
open review, add this branch before the existing `if let videoID` in the `Task { @MainActor in … }`:

```swift
if let broadcastID = (info["broadcastID"] as? String).flatMap(UUID.init(uuidString:)) {
    PendingImports.openReviewFromNotification(broadcastID: broadcastID, library: environment.library)
    completionHandler()
    return
}
```

## 2. Renaming elsewhere should cancel the "needs a title" reminder (Storage/Library.swift)

After every save, `RecordingSaver` schedules `Notifier.schedule(.needsTitle, key: "needs-title-<uuid>", …)`
for an hour later. Review cancels it when you title the recording there, but a rename from the
player or library (`library.rename`) doesn't. In `Library.rename(_:to:)`, after `update(id) { … }`:

```swift
Notifier.shared.cancelScheduled(key: "needs-title-\(id.uuidString)")
```

(Or `RecordingSaver.reminderKey(id)` if you prefer the helper; it lives in Features/Record.)
`Library.delete(_:)` could do the same.

## 3. Retry for failed saves from the library (for sessions C and D, no shared change)

A video in `.failed` state can be retried with `RecordingSaver.shared.retry(id, library: library)`
and deleted (including its staged file) with `RecordingSaver.shared.discard(id, library: library)`.
`VideoThumbnail` already shows "Not saved" for these.

## 4. Inbox file names (Shared/BroadcastShared.swift, comment only)

`InboxRecording`'s comment says the movie is `<id>.mp4`; the extension writes `<id>.mov` (fragmented
QuickTime movie, readable even if the extension is killed) and sets `movieFileName` accordingly.
The app reads `movieFileName`, so only the comment is out of date.
