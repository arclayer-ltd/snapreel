# Session C (player) requests and notes for the lead

Branch `claude/feature-c-player-fccf89`. Everything is in `Snapreel/Features/Player/`; no shared file
was edited.

## 1. Merge order: C needs E's Sharing commit

`PlayerScreen` calls E's debug overload and type, which exist only on E's branch
(`claude/feature-e-inbox-25e018`, commit 7a99132):

```swift
.saveToPhotos($photosTarget, initialStage: initial.photosStage)   // PhotosSaveStage?
```

C does not compile against the foundation stub alone. Merge E's Sharing files with or before C.

## 2. FoundationModels on an iOS 16 deployment target (please check on the first build)

`OnDeviceSummarizer.swift` imports FoundationModels under `#if canImport(FoundationModels)` and uses it
only inside `if #available(iOS 26.0, *)`. The linker should weak-link the framework because every
symbol from it is weak. If an iOS 16–25 device or simulator fails to launch with "Library not loaded:
FoundationModels", add this to the app target's build settings (both configurations):

```
OTHER_LDFLAGS = $(inherited) -weak_framework FoundationModels
```

(Same effect: add FoundationModels.framework under Link Binary With Libraries with status Optional.)

## 3. Optional: Delete all my data (E's Storage)

The player keeps two small things in `UserDefaults.standard` under `player.` (why a transcript
couldn't be made, recent reactions). To clear them with everything else, E's erase step can call:

```swift
PlayerLocalData.erase()   // @MainActor; also stops playback
```

## 4. For B (recorder)

- Call `TranscriptService.shared.enqueue(videoID: video.id, library: library)` once a recording or
  import is `.ready`. It only runs when speech recognition is already allowed (never prompts).
- `PlaybackSession` pauses itself when `router.recorder` becomes non-nil, so playback and recording
  don't fight over the audio session. The player sets `.playback` / `.moviePlayback` when it plays;
  the recorder should set its own category when it starts.

## 5. Behaviour the shell relies on (no change needed)

- `PlaybackSession` subscribes to `AppEnvironment.shared.router.$player` and stops playback when the
  player is closed from anywhere. The picture-in-picture restore button calls
  `router.expandPlayer()` (or `router.play(id)` if the player was closed).
- `router.showToast` is hidden under the player's full-screen cover, so the player shows its own
  toasts; it uses `router.showToast` only after deleting a recording (the cover is closing).
