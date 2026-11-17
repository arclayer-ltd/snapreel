# Snapreel build plan

Snapreel is a native SwiftUI iPhone app (iOS 16.0+) for recording your screen, camera or voice,
keeping recordings organised and sending them as files. Everything stays on the device: no
accounts, no server, no network use.

- Screen-by-screen plan with debug ids, states, owners and references: [PLAN-screens.md](PLAN-screens.md)
  (generated from `scripts/plan_data.py`, which also writes `refs/index.json`).
- References (kept out of git, the repo is public): `refs/mobbin/` (Loom 4.0, 26 flows, 93 screens,
  cropped 1125x2436), `refs/appstore/` (current listing, 7 screenshots). App Store wins where the two disagree.

## What Loom does at its core, and what Snapreel does instead

| Loom (server) | Snapreel (on device) |
|---|---|
| Account sign-up / log in / log out / delete account | None. Welcome → intro → use question → tour. "Delete all my data" in Storage replaces account deletion. |
| Upload, share link, link privacy | Share sheet with the video file (AirDrop, Messages, Mail, any app); Save to Photos. |
| Other people's comments, replies, reactions | Your own notes stamped with the video time ("Note at 0:14"), and your own emoji reactions pinned to the timeline. |
| Viewer insights, engagement notifications | Stats: times played, how far through, last watched, times shared, file size, resolution. |
| Activity notifications (views, comments) | Feed of what the app did: recording saved, waiting for a title, import finished, transcript ready, storage low. |
| AI summary (server) | Summary block only when an on-device model can write it (Apple Intelligence on iOS 26+); hidden otherwise. |
| Workspaces, folder owners | Local folders and tags. |

Feature added from the current Loom listing that works on device: **playback speeds** (1x–2x, the
"Setting video speed" flow), **picture-in-picture**, **import from photo library** (photo icon on
the current camera screen), **recording settings** (gear) and **speaker notes** (pencil-in-square).

## Look

Sampled from the icon (`art/icon-1024.png`): ring `#F04850` (shade `#D32434`, highlight `#FE6262`)
on ink `#13141B` (corners `#1A1C25` → `#07080C`). Recorder and player are dark; lists and settings
are light (`#F4F4F6` canvas, white cards); red is the only accent. System font on Dynamic Type
styles; rounded monospaced digits for timers. Tokens: `Snapreel/Kit/Tokens.swift`.

Characters: five original characters (Maya, Jun, Theo, Priya, Leo) in a flat street-fashion style,
recoloured to the brand palette, animated as eight silent looping Seedance 2.0 clips. Used only on
welcome, the three intro slides, the tour intro, the notification permission step, the empty
library and the empty watch lists. Every other empty state uses an SF Symbol in a soft red circle.

## Architecture

```
Snapreel/                 app target (file-system-synchronised group)
  App/                    SnapreelApp, AppEnvironment, AppRouter, RootView, MainShell (tab bar)
  Kit/                    tokens, buttons, rows, tabs, toast, sheets, thumbnails, CharacterView
  Models/                 Video, Folder, VideoNote, VideoReaction, Transcript, AppNotification, prefs
  Storage/                LibraryStorage protocol; OnDeviceStorage (SQLite + files in the App Group);
                          Library (ObservableObject, single source of truth)
  Services/               AppSettings, Notifier (feed + local notifications), Permissions,
                          MediaInspector, DiskSpace
  Debug/                  DEBUG only: FixtureStorage (sample data), DebugCatalog (-screen <id>)
  Features/<Area>/        one folder per area, owned by one session
SnapreelBroadcast/        ReplayKit broadcast upload extension (writes into the App Group)
Shared/                   compiled into both targets: App Group paths, broadcast state, Darwin signals
```

- **Storage protocol, two implementations**: `OnDeviceStorage` (shipping) and `FixtureStorage`
  (DEBUG builds only, in memory, drawn thumbnails and a short generated clip). The shipped build has
  no sample data.
- **Debug launch argument**: `-screen <id>` opens any screen in any state from fixtures;
  `-dumpScreens` writes the list the CI screenshot script walks.
- **Data protection**: media and database live in the App Group container with
  `completeUntilFirstUserAuthentication`; nothing is uploaded; deleting a video removes its files,
  notes, reactions, transcript and feed rows.

## Features → screens → data

| Feature | Screens (debug ids) | Data / services |
|---|---|---|
| Splash, welcome, intro, use question, tour + notification permission | start.* | AppSettings.hasCompletedOnboarding / hasCompletedTour / useCase; Notifier.requestAuthorization |
| Recorder (Camera / Screen / Audio), primer + denied | rec.shell, rec.primer(.denied) | Permissions (camera, microphone); AppSettings.lastRecordMode |
| Camera: front/back, flip, record, pause/resume, stop, restart, timer | rec.camera, rec.camera.recording/paused/countdown | AVCaptureSession + AVAssetWriter; AppSettings quality, countdown, defaultCamera, mirror |
| Screen: tutorial, broadcast picker with mic, red pill, stop, local notification, AirPlay/CarPlay alert | rec.screen.tutorial.*, rec.broadcast(.unavailable), rec.screen.recording | SnapreelBroadcast (RPBroadcastSampleHandler → AVAssetWriter in App Group Inbox), BroadcastState, Darwin signals, PendingImports |
| Audio with live waveform | rec.audio.recording | AVAudioRecorder metering |
| Import from photo library | rec.import | PhotosPicker → copy into Media/Videos, Notifier(.importFinished) |
| Recording settings, speaker notes | rec.settings, rec.notes(.overlay) | AppSettings.speakerNotes / showsSpeakerNotes |
| Review: preview, delete with confirm, title, share, done | rec.review(.delete), rec.title, rec.share | Library.add/rename/delete; shareVideo modifier |
| Saving: progress, survives app close, failed + retry, out of space | rec.saving(.failed/.nospace) | Video.state (.saving/.failed); PendingImports.resumeInterruptedSaves; DiskSpace |
| Share sheet, Save to Photos (permission, progress, saved) | rec.share, video.photos.* | shareVideo / saveToPhotos modifiers; Library.recordShare / recordSavedToPhotos |
| Home: greeting, Watch Later, History, From my library rail, recently watched rail, empties | home.filled/empty, home.history(.empty), home.later(.empty) | Library.readyVideos / watchLater / history |
| Library: My videos, Folders, cards, row actions, folders CRUD, move, tags | lib.* | Library folders/tags APIs, TitleEditorSheet |
| Player: play/pause, ±5 s, scrubber, reaction markers, speeds, PiP, fullscreen, minimise; details; Notes/Transcript switch; summary; actions | video.* | AVPlayer, AVPictureInPictureController, Library.recordPlayback, notes, reactions, transcript |
| Notes and reactions | video.notes(.empty), video.note.compose/edit, video.reaction, video.emoji | Library.addNote/updateNote/deleteNote, addReaction |
| Transcript (on-device speech, tap to seek, none state) | video.transcript(.none) | TranscriptService (SFSpeechRecognizer, requiresOnDeviceRecognition), Notifier(.transcriptReady) |
| Stats | video.stats | Video.playCount / furthestProgress / lastWatchedAt / shareCount / fileSize / pixel size |
| Notifications feed by day, links to video, unread dot | notif.feed(.empty) | Library.notifications, Notifier, tab bar unread dot |
| Search by title, folder, tag, transcript words | search.idle, search.results/typing/none | Library + transcripts, in memory |
| Settings: notification toggles, recording defaults, storage (+ delete all), help, contact, legal | settings.*, help.*, legal.* | AppSettings toggles, DiskSpace, Library.eraseEverything, bundled help articles and legal drafts |

## Sessions (each in its own worktree, owning only its folders)

| | Owns | Screens |
|---|---|---|
| A | Features/Onboarding, Settings, Help, Legal; Resources/Help, Resources/Legal | start.*, settings.root, help.*, legal.* |
| B | Features/Record, SnapreelBroadcast/ | rec.*, settings.recording |
| C | Features/Player | video.* (save-to-Photos UI comes from E) |
| D | Features/Home, Library, Search | home.*, lib.*, search.* |
| E | Features/Notifications, Storage, Sharing | notif.*, settings.notifications, settings.storage, share/save-to-Photos flows |

Shared files (App/, Kit/, Models/, Storage/, Services/, Debug/, Shared/) are mine; a session that
needs a change there asks me instead of editing.

## CI and run budget

The org's private Actions allowance could not cover the build, so the repo is public (owner's
decision) and macOS minutes are free. Runs are still kept few because each takes ~15–25 minutes of
wall time. Every run compiles both targets with whole-module type-checking (all errors in one
log), screenshots every debug screen at 375x812 pt, and archives + uploads to TestFlight when
asked. Only I start runs.

1. Foundation compile + screenshots (proves project, CI, fixtures).
2. Foundation signed → TestFlight (proves signing with the existing certificate).
3. Session B early TestFlight build when B's code compiles.
4. Merged build(s) with all sessions until green, screenshots of all 93 states.
5. Up to three comparison fix rounds.
6. Final TestFlight build, internal group, processing confirmed.
