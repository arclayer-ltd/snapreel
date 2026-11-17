# Session C: player, transcript, notes, reactions, stats

Read `docs/briefs/COMMON.md` first. You own `Snapreel/Features/Player/`.

The player is presented by the shell as a full-screen cover while `router.player` is set and not
minimised (`PlayerScreen(presentation:)`), and as `MiniPlayerBar(videoID:)` above the tab bar
when minimised. Playback must continue across minimise/expand: keep the `AVPlayer` in a
long-lived object you own (e.g. `PlaybackSession.shared`, `@MainActor ObservableObject`), not in
the view. The whole player is dark.

## Screens

| Debug id(s) | Screen | Reference |
|---|---|---|
| `video.player` | Player: video at top (portrait videos centred on a blurred fill; landscape full width), controls overlay that auto-hides: minimise chevron, speed pill, PiP, fullscreen; centre skip back 5 s, play/pause, skip forward 5 s; scrubber with elapsed and remaining time; reaction markers (emoji) pinned along the timeline at their times. Below: date, title, duration, expandable details; Notes / Transcript switch (`PillSwitch`); reaction bar (6 quick emoji + more) and add-note button docked at the bottom. | mobbin 333244de, 2633dd18, appstore-04 |
| `video.fullscreen` | Fullscreen: landscape-capable full-screen player (rotate the view for landscape videos), same controls, close. | designed fresh |
| `video.pip` | PiP active state: the video area shows a placeholder ("Playing in picture in picture", restore button) while PiP runs. | mobbin 307833f4 |
| `video.speed` | Speed menu: 1x, 1.2x, 1.5x, 1.7x, 2x (the reference flow's speeds) with a check; choice persists in `settings.playbackRate`. | mobbin 5bdf10e6, 7fbf9539 |
| `video.notes` `video.notes.empty` | Notes tab: your notes sorted by time, each "Note at 0:14" chip (tap seeks and plays), text, edited time; swipe/menu to edit or delete. Empty state explains notes. | mobbin 08b623c3, dfc7a242, 68117697 |
| `video.transcript` `video.transcript.none` | Transcript tab: segments with timestamps, the current line highlighted while playing, tap a line to seek. States: in progress (spinner + "Transcribing on this iPhone"), none available (no speech / language unsupported / permission denied, each with its own message and an action where one exists, e.g. allow speech recognition), not started (button "Make a transcript"). | mobbin 1cf35f2e |
| `video.details` | Details expanded: kind, recorded date and time, duration, resolution, file size, folder, tags (tap to edit is D's tag editor: just show them here), and the **summary** block only when `transcript.summary != nil`. | mobbin 333244de ("More"), appstore-04 (summary) |
| `video.note.compose` | Note composer sheet: header "Note at 0:14" (the time when opened; playback pauses), text field, send. | mobbin d8cee37f, e835b4d8 |
| `video.note.edit` | Edit note: same sheet prefilled, Save, Delete. | mobbin 66e3bbdc, 20d71ce8 |
| `video.reaction` | Reaction overlay: a large emoji rises over the video when you react (from the bar or the overlay grid); the reaction is saved at the current time and appears as a timeline marker. | mobbin 69165b4c, b670b4bf |
| `video.emoji` | Full emoji picker sheet: categories + search across a built-in emoji list (no keyboard emoji input needed), recently used at the top. | designed fresh |
| `video.actions` `video.actions.delete` | Actions sheet: edit title (`TitleEditorSheet(onDark: true)`), save to Photos (`.saveToPhotos`), share (`.shareVideo`), watch later toggle, stats, delete (confirm: "Delete this recording? This removes the video, its notes and transcript from this iPhone."). | mobbin 5c3f6863 |
| `video.photos.permission` `video.photos.progress` `video.photos.saved` | Save to Photos states, hosted in the player (E builds the flow as the `.saveToPhotos` modifier; your debug entries open the player with the flow at each state; coordinate by reading E's code once it exists, or ask the lead). | mobbin 7abeda8d |
| `video.stats` | Stats: times played, how far through (furthest progress as a bar), last watched, times shared, saved to Photos count, file size, resolution, duration, recorded date. Big rounded numbers (`.srStat`). | mobbin 4ebeb7dc, c71f7bb9 (viewer stats, server-only; yours is on-device) |

## Behaviour

- `library.recordPlayStarted` when playback starts from closed; `library.recordPlayback(id, position:)`
  every few seconds and on pause/close; resume from `resumePosition`; `presentation.startAt` wins.
- PiP: `AVPictureInPictureController` with an `AVPlayerLayer` you own; start only from the user's tap;
  audio session `.playback` / `.moviePlayback` while playing (the app has the audio background mode).
  Restoring from PiP re-opens the player.
- Audio recordings play with `AudioArtwork`-style art in the video area.
- Videos still saving or failed show a clear state instead of a player.
- **TranscriptService** (`Features/Player/TranscriptService.swift`, keep `enqueue(videoID:library:)`):
  serial queue of jobs; request speech permission if not determined only when the person asks for a
  transcript (from the transcript tab) — automatic jobs run only when already authorised; use
  `SFSpeechRecognizer` (device locale, fall back to en-US) with `requiresOnDeviceRecognition = true`
  when `supportsOnDeviceRecognition`, otherwise mark `.unavailable` (never send audio off the
  device); `SFSpeechURLRecognitionRequest` on the file (extract audio to m4a first if needed); build
  segments from `bestTranscription.segments` grouped into sentence-sized lines; save with
  `library.saveTranscript`; post `.transcriptReady`. Set `transcriptStatus` along the way. Long files:
  chunk into ≤ 60 s pieces if recognition stops early.
- **Summary**: only if it can be produced honestly on the device. If the SDK has Apple's on-device
  model (`#if canImport(FoundationModels)`, `if #available(iOS 26, *)`, model availability
  `.available`), generate a 2–3 sentence summary from the transcript and store it in
  `Transcript.summary`; otherwise leave nil and hide the block. Never fake it.
- `MiniPlayerBar`: thumbnail, title, play/pause, close; tap expands.
