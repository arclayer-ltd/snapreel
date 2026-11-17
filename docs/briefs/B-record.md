# Session B: recording, broadcast extension, import, review, saving

Read `docs/briefs/COMMON.md` first. You own `Snapreel/Features/Record/` and
`SnapreelBroadcast/` (the ReplayKit broadcast upload extension; its Info.plist and entitlements
are already set up and must not change). `Shared/` (App Group paths, `BroadcastState`,
`InboxRecording`, `BroadcastSignal`, `BroadcastSignalObserver`) is the lead's; request changes.

This is the riskiest part. **Milestone 1** = camera + screen + audio recording, review and saving
work end to end. When it is written and self-reviewed, commit, then message the lead (your
parent session) "B milestone 1 ready <commit>". The lead compiles it, ships a TestFlight build
from your branch and sends back any compile errors. Then carry on with the rest.

## Screens

| Debug id(s) | Screen | Reference |
|---|---|---|
| `rec.shell` `rec.shell.audio` `rec.shell.screen` | Recorder shell: full-screen dark, close X, gear (recording settings) and pencil-in-square (speaker notes) top-right, mode switch Camera / Screen / Audio at the bottom, photo-library import button bottom-left, flip camera bottom-right (camera mode). Opens in `launch.mode ?? settings.lastRecordMode`. | appstore-02 (current Loom camera screen) |
| `rec.primer` `rec.primer.denied` | Permission primer before the system prompts: what camera and microphone are used for, that recordings stay on this iPhone, one button that requests camera then microphone. Denied state explains and links to Settings (`Permissions.openSettings()`). Audio mode needs microphone only. | mobbin c0ee6731 (+ system alerts 565c5843, 8c0ebeed) |
| `rec.camera` | Camera viewfinder (front/back, flip, timer readout 0:00, big record button). In DEBUG on the simulator there is no camera: show a still frame drawn from fixtures behind the controls for the debug entry only. | appstore-02 |
| `rec.camera.recording` `rec.camera.paused` `rec.camera.countdown` | Recording: elapsed timer with red dot, pause/resume, stop, restart (discard and start again, with confirm), speaker notes overlay when on. Countdown (3/5/10 s from settings) before recording starts. | designed fresh |
| `rec.audio.recording` | Audio only: big live waveform from microphone levels, timer, pause/resume, stop. | designed fresh |
| `rec.screen.tutorial.1` `.2` `.3` | Three-card tutorial, swipeable: Start (tap record, choose Snapreel, Start broadcast, mic toggle), Stop (red status pill in the status bar or come back and tap Stop), Share (come back to Snapreel to title and send; the notification takes you there). Draw the illustrations natively in SwiftUI (phone frame, pill, sheet), in Snapreel's style. Shown until seen once (`settings.hasSeenScreenTutorial`), then reachable from a help button. | mobbin 8a4bd556, 9873040f, 9e42071f |
| `rec.broadcast` `rec.broadcast.unavailable` | Broadcast step: explains what will be recorded (everything on screen, including notifications; suggest Do Not Disturb), microphone default shown, and the record button which is an `RPSystemBroadcastPickerView` (`preferredExtension = AppGroup.broadcastExtensionBundleID`, `showsMicrophoneButton = true`) styled under your own button. Unavailable state: the alert/explainer when screen recording can't start (AirPlay, CarPlay, mirroring, Screen Time restrictions; `RPRecordingErrorCode` has `.carPlay`, `.disabled`, `.failedToStart` and others), with what to do. | mobbin fe567cf9, 1245d328 |
| `rec.screen.recording` | Screen recording in progress (app in foreground): red "Recording 1:23" pill, what's happening, big Stop button (posts `BroadcastSignal.stopRequested`; the extension calls `finishBroadcastWithError` with a friendly "Recording saved" reason), mic state. | mobbin 8f0f7c0f, 15f044ca, 3dfe7131 |
| `rec.settings` | Recording settings sheet (gear): quality (`RecordingQuality`), microphone default, countdown, camera mirror, show speaker notes. Same values as Settings › Recording. | designed fresh |
| `rec.notes` `rec.notes.overlay` | Speaker notes editor (pencil-in-square): a text editor saved to `settings.speakerNotes`, with show-while-recording toggle; overlay state shows the notes scrolling over the viewfinder, readable, not recorded into the video. | designed fresh |
| `rec.import` | Import from photo library: `PhotosPicker` for videos (no Photos permission needed), then a copy-in progress screen; imported videos get kind `.imported`, a thumbnail, and a `.importFinished` notification. | appstore-02 photo icon; flow designed fresh |
| `rec.review` `rec.review.delete` | Review after recording: dark, the recording playing (AVPlayer, loop off, tap to pause), title row (shows the default title, tap to edit), bottom bar: Delete (confirm dialog), Title, Share (`.shareVideo`), Save to Photos (`.saveToPhotos`), Done (closes the recorder, toast "Saved to your library"). | mobbin c0702bfb, 9bed6b10, 4f5b94d4 |
| `rec.title` | Title editor over review (`TitleEditorSheet(onDark: true)`). | mobbin 4f4426ef, 18dfff18 |
| `rec.share` | System share sheet with the file over review (from E's `.shareVideo`; your debug entry presents it on appear). | mobbin 96967148 (link version; yours shares the file) |
| `rec.saving` `rec.saving.failed` `rec.saving.nospace` | Saving: progress while the movie is finalised, moved into `library.media.videos`, inspected and thumbnailed. Failed with Retry and Delete; out-of-space version says how much is needed and links to Settings › Storage (`router` can't push into the settings sheet; present `StorageView()` yourself in a sheet). | designed fresh |
| `settings.recording` | `RecordingDefaultsView()` inside Settings: quality, mic default, countdown, default camera, mirror front camera. | designed fresh |

## How recording must work

- **Camera**: `AVCaptureSession` (video + audio), `AVCaptureVideoDataOutput` +
  `AVCaptureAudioDataOutput` into `AVAssetWriter` (H.264/HEVC + AAC) so pause/resume works by
  dropping samples and offsetting timestamps. Quality from settings (720p/1080p/4K where the device
  supports it; front camera max 1080p on older phones). Portrait orientation. Flip works before
  and during recording if feasible, otherwise before only (say which in your report). Write to
  `library.media.staging`, then move into videos/ on save.
- **Audio**: `AVAudioRecorder` (AAC .m4a) with metering for the waveform, pause/resume.
- **Screen**: `SampleHandler` (`RPBroadcastSampleHandler`) writes `.video`, `.audioApp` and
  `.audioMic` with `AVAssetWriter` (`expectsMediaDataInRealTime = true`) straight to
  `AppGroup.inProgressURL`, never buffering frames in memory (the extension's memory limit is about
  50 MB). Handle `RPVideoSampleOrientationKey` for rotation, start the session at the first video
  sample, write app audio and mic audio as two audio tracks (or mix if you prefer; say which). On
  finish (user stop, app's stop request via Darwin signal, or `broadcastFinished`) finalise, move
  movie + `InboxRecording` manifest to `AppGroup.inboxURL`, update `BroadcastStateStore`, post
  `BroadcastSignal.finished`, and schedule a local notification (if the `recordingSaved` toggle in
  `AppGroup.defaults` allows) inviting the user back to finish ("Your screen recording is ready.
  Tap to give it a title."). If the disk fills, stop gracefully and keep what was written.
- **App side**: `PendingImports.importFinishedBroadcasts(into:)` moves inbox movies into the library
  (state `.saving` → `.ready`, thumbnail, `needsTitle = true`, `Notifier .recordingSaved`), and opens
  review for the newest when the app was opened from that notification or the recorder is on
  screen. Observe `BroadcastSignal.started/.finished` while the recorder is open to switch between
  broadcast step, in-progress, and review.
- **Saving survives the app closing**: the `Video` row is added with `.saving` before the move;
  `resumeInterruptedSaves(in:)` on next launch finishes any whose file is complete, or marks them
  `.failed` with a reason. Out-of-space errors (`DiskSpace.isOutOfSpace`) produce `.failed(outOfSpace: true)`.
  Check `DiskSpace.hasRoom` before recording and warn.
- After a recording or import is saved: `TranscriptService.shared.enqueue(videoID:library:)` (C),
  `Notifier.shared.post(.recordingSaved …)`, and schedule a `.needsTitle` reminder an hour later
  (cancel it when titled; `Notifier.schedule` / `cancelScheduled`).
- Haptics on record/stop; the record button uses `RecordButtonShape`.
