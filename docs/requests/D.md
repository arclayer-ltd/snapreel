# Session D: shared-code requests and cross-session notes

Nothing here blocks D's code from compiling; every item has a workaround inside D's folders.

## 1. Retry for a failed save (B, `PendingImports`)

Failed cards in My videos and folders have **Try again**. D does:

```swift
library.update(id) { $0.state = .saving(progress: 0) }
PendingImports.resumeInterruptedSaves(in: library)
// then reads library.video(id)?.state: .ready → "Saved" toast, .failed → "Still couldn't save it"
```

If the row is still `.saving(progress: 0)` eight seconds later (nothing picked it up, as with
today's empty stub), D puts the original `.failed` state back and says "Couldn't try again right
now". An async resume should therefore move the progress above 0 or finish within that time.

Please make `resumeInterruptedSaves(in:)` treat any row in `.saving` that has no save running
right now as resumable: finish it if the file is complete, otherwise set `.failed(reason:outOfSpace:)`
again. It must leave alone a save the recorder is actively running. If B prefers an explicit API,
this is what D would call instead (one-line change in `Features/Library/VideoActions.swift`,
`LibraryActionsModel.retry`):

```swift
@MainActor enum PendingImports {
    /// Retries one failed save. Ends in .ready or .failed (with the reason).
    static func retrySave(_ id: UUID, in library: Library)
}
```

**Free up space** on an out-of-space card presents `StorageView()` (E) in a sheet inside a
`NavigationStack` with a Done button, with the three environment objects passed in.

## 2. Delete all my data should clear recent searches (E, Storage)

Recent searches live in `UserDefaults.standard` (`search.recent`). After
`library.eraseEverything()` + `settings.resetAfterErase()`, please also call:

```swift
RecentSearchStore.shared.clear()
```

## 3. Sharing and Photos (E)

D's actions sheet and long-press menus use exactly the documented modifiers, attached once per
screen by `.libraryVideoActions(model)`:

```swift
.shareVideo($model.shareTarget)     // Binding<Video?>
.saveToPhotos($model.photosTarget)  // Binding<Video?>
```

They are set only after D's own sheet has finished dismissing, so the share sheet always
presents from a settled screen. Audio recordings still reach `.saveToPhotos` (E shows the
"use Share instead" message).

## 4. For the player (C)

- Tags in the player's details can open D's editor:
  `TagEditorSheet(videoID: id, initialTags: video.tags, onDone: { ... })` (light sheet,
  needs `Library` and `AppRouter` in the environment; use `.presentationDetents([.large])`).
- Move to folder is available the same way: `MoveToFolderSheet(videoID: id, onDone: { ... })`.

## 5. Nice to have (lead)

- `AppRouter` has no way to open a tab root in a given state, so D added `BrowseIntent.shared`
  (Features/Library/BrowseSupport.swift): Home's "See all" sets `libraryTab`, and D's debug
  entries use `librarySheet` / `search` to open sheets and fill the search field. If you add
  something similar to the router later, D will switch to it.
