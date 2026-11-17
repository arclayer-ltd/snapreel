# Rules for every Snapreel feature session

You are one of five parallel sessions building Snapreel, a native SwiftUI iPhone app for
recording your screen, camera or voice, keeping recordings organised and sending them as files.
Read `docs/PLAN.md` and `docs/PLAN-screens.md` first, then your own brief.

## Non-negotiables

1. **Real app.** Every screen does its job with real recordings from `Library`. Fixtures exist only
   in DEBUG for screenshots (`Snapreel/Debug/FixtureStorage.swift`); never ship sample data and never
   branch on "is fixture" in feature code.
2. **Not a clone.** Loom (the reference app) must not appear anywhere: no name, logo, illustration,
   wording or distinctive layout copied. Study the reference for what each screen must *do* and how
   the flow steps through, then write Snapreel's own words and layout details. Different labels,
   different arrangement where it's a stylistic choice, same completeness.
3. **Everything on the device.** No network calls, no accounts, no analytics, no third-party
   packages.
4. **Premium feel.** Considered spacing, real empty/loading/error states, haptics on meaningful
   actions, springy but quick motion (`Motion.*`), Reduce Motion respected, Dynamic Type, VoiceOver
   labels on every icon-only control.

## You cannot compile

There is no Mac. CI compiles only when the lead starts a run, after merging. So:

- Review every file you write, line by line, for compile errors before you report. Check every
  initializer label, optional, `@MainActor` call, generic, `some View` branch and closure capture.
- Deployment target is **iOS 16.0**, Swift 5 language mode, newest Xcode SDK. Not available on 16:
  `@Observable`, `ContentUnavailableView`, two-parameter `onChange`, `sensoryFeedback`,
  `symbolEffect`, `scrollPosition`, `scrollTargetBehavior`, `.presentationBackground` (16.4),
  `.presentationCornerRadius` (16.4), `fontDesign(_:)` (16.1), `Text` concatenation with images is
  fine. Wrap newer APIs in `if #available(iOS 17, *)` with an iOS 16 fallback.
- `ObservableObject` + `@Published`, `@StateObject`, `@EnvironmentObject`. `Library`, `AppSettings`,
  `AppRouter`, `Notifier`, `TranscriptService` are `@MainActor`.
- Use `onChange(of:) { newValue in }` (single parameter).
- Keep view bodies small: split long bodies into computed properties or subviews so the type
  checker doesn't time out ("unable to type-check this expression in reasonable time").
- Prefer explicit types in complex expressions; avoid long chains of `+` on mixed types.

## Files you may touch

Only your own folders (listed in your brief). New `.swift` files anywhere in those folders are
compiled automatically (file-system-synchronised groups); never edit `Snapreel.xcodeproj`.
Resources (json, md, png, mp4) in your folders are copied into the app bundle **flat**, so prefix
every resource file name with your area (e.g. `help-articles.json`).

Shared code is the lead's: `Snapreel/App`, `Kit`, `Models`, `Storage`, `Services`, `Debug`, `Shared/`,
and other sessions' folders. If you need a change there (a new model field, a router route, a kit
component), do not edit it: write the request in `docs/requests/<your letter>.md` (create it) with the
exact Swift you need, and work around it inside your folder meanwhile (a private extension, a local
helper). Small additive helpers you need only yourself belong in your folder.

## What the shared code gives you

- **Tokens** (`Kit/Tokens.swift`): colours `.srRed .srRedDeep .srRedGlow .srRedSoft .srInk .srInkDeep
  .srInkRaised .srInkControl .srInkLine .srOnDark .srOnDarkSecondary .srOnDarkTertiary .srCanvas
  .srSurface .srFill .srLine .srText .srTextSecondary .srTextTertiary`; fonts `.srLargeTitle .srDisplay
  .srTitle .srTitle3 .srHeadline .srBody .srCallout .srSubheadline .srSubheadlineStrong .srFootnote
  .srCaption .srTimer .srTimerSmall .srStat`; `Space.xxs…xxxl, Space.gutter (20)`, `Radius.s/m/l/xl`,
  `Motion.quick/standard/gentle`, `.srCard()`, `.srCardShadow()`.
- **Kit**: `.buttonStyle(.srPrimary / .srSecondary / .srTertiary / .srDestructive / .srInverted /
  .srPrimaryCompact / .srSecondaryCompact)`, `CircleIconButton(systemName:label:tone:size:action:)`
  (tones `.light .dark .glass .red`), `PressScaleStyle`, `RecordButtonShape(isRecording:diameter:)`,
  `EmptyStateView(character:systemImage:title:message:actionTitle:action:onDark:)`,
  `SectionHeader(title:subtitle:actionTitle:action:)`, `IconTile`, `ListRow`,
  `UnderlineTabs(tabs:selection:title:)`, `PillSwitch(options:selection:title:onDark:)`,
  `ToastMessage` + `.toast($message)`, `SheetHeader`, `UnreadDot`, `ProgressRing`,
  `TitleEditorSheet(initialTitle:heading:onDark:onSave:onCancel:)`,
  `VideoThumbnail(video:cornerRadius:showsDuration:aspectRatio:)` (needs `Library` in the
  environment), `AudioArtwork`, `CharacterView(clip:)`, `LoopingVideoView`, `Format.*` (clock,
  remaining, duration, age, date, dateTime, bytes, resolution, dayTitle, defaultTitle), `Haptics.*`.
- **Models** (`Models/`): `Video` (+ `RecordingKind`, `VideoState`, `TranscriptStatus`), `RecordMode`,
  `Folder`, `VideoNote`, `VideoReaction`, `Transcript`/`TranscriptSegment`, `AppNotification` +
  `NotificationKind`, `UseCase`, `RecordingQuality`, `CountdownLength`, `CameraSide`.
- **Library** (`Storage/Library.swift`, environment object): queries (`video(_:)`, `allVideos`,
  `readyVideos`, `videos(inFolder:)`, `sortedFolders`, `watchLater`, `history`, `notes(for:)`,
  `reactions(for:)`, `transcript(for:)`, `sortedNotifications`, `unreadNotificationCount`, `allTags`,
  `fileURL(for:)`, `thumbnailURL(for:)`, `totalVideoBytes`, `media` (`MediaLocations`: videos,
  thumbnails, staging)) and mutations (`add`, `update(id){…}`, `rename`, `delete`,
  `toggleWatchLater`, `recordPlayStarted`, `recordPlayback`, `recordShare`, `recordSavedToPhotos`,
  `setTags`, `move(_:toFolder:)`, `createFolder`, `renameFolder`, `deleteFolder`, `addNote`,
  `updateNote`, `deleteNote`, `addReaction`, `deleteReaction`, `saveTranscript`,
  `appendNotification`, `markNotificationRead`, `markAllNotificationsRead`, `deleteNotification`,
  `eraseEverything`). Every mutation persists immediately.
- **AppSettings** (environment object): onboarding/tour flags, use case, recording quality, mic
  default, countdown, default camera, mirror, last mode, screen tutorial seen, speaker notes,
  playback rate, per-kind notification toggles (`isNotificationEnabled`, `setNotification`,
  `notificationBinding`).
- **AppRouter** (environment object): `tab`, per-tab `NavigationPath`s, `select(_:)`,
  `record(_:startsWithImport:)`, `play(_:at:)`, `minimizePlayer/expandPlayer/closePlayer`,
  `show(_ route:in:)`, `isSettingsPresented`, `showToast(_:systemImage:)`, `open(videoID:)`.
  Routes: `.folder(id) .watchLater .history .allVideos`.
- **Services**: `Notifier.shared.post(kind,title:body:videoID:)`, `.schedule(...)`,
  `.requestAuthorization()`; `Permissions.state/currentState/request(kind)`, `openSettings()`;
  `MediaInspector.inspect/thumbnail/writeThumbnail`; `DiskSpace.available/total/hasRoom/isOutOfSpace`.
- **Shell**: `MainShell` hosts the four tab stacks, the tab bar (red centre Record button),
  the mini player, the recorder and player full-screen covers and the Settings sheet. Tab roots
  call `.settingsToolbar()` for the gear.
- **Cross-session entry points** (stubs exist with these exact signatures; the owner fills them):
  A `SplashView(onFinish:)`, `OnboardingFlow(onFinish:)`, `GuidedTourOverlay(targets:onFinish:)`,
  `SettingsView()`; B `RecorderView(launch:)`, `RecordingDefaultsView()`,
  `PendingImports.importFinishedBroadcasts(into:)`, `.resumeInterruptedSaves(in:)`;
  C `PlayerScreen(presentation:)`, `MiniPlayerBar(videoID:)`,
  `TranscriptService.shared.enqueue(videoID:library:)`; D `HomeView()`, `LibraryView()`,
  `SearchView()`, `FolderDetailView(folderID:)`, `WatchLaterView()`, `WatchHistoryView()`;
  E `NotificationsView()`, `NotificationSettingsView()`, `StorageView()`,
  `StorageMonitor.check(library:)`, `.shareVideo(_ video: Binding<Video?>)`,
  `.saveToPhotos(_ video: Binding<Video?>)`. Keep these signatures; you may add more initialisers.

## Characters

Eight looping clips, five original characters: `.welcome .introRecord .introLibrary .introSend`
(dark background) and `.tour .notify .emptyLibrary .emptyWatch` (cream background). Use them only
where the plan places them: welcome, the three intro slides, the tour intro card, the notification
permission step, the empty library, the empty watch lists. Nowhere else.

## Debug screens (how your work gets screenshotted)

Your brief lists debug ids. Each one must open the exact screen *and state* with no taps, from the
launch argument `-screen <id>`, by adding entries to your list in your `*DebugScreens.swift`
(`DebugScreen(id, title, fixture:wait:) { view }` or `.shell(id, title, tab:fixture:wait:) { router, library in … }`).
Give views an initial-state parameter (e.g. `PlayerScreen(presentation:, initialPanel: .speed)`) so a
debug entry can open a menu, sheet, alert or error state directly. Fixture ids:
`FixtureStorage.IDs.checkout` (screen recording with notes, reactions, transcript),
`.onboardingFeedback` (landscape camera), `.mapBug` (short screen, no transcript), `.weeklyUpdate`
(portrait camera), `.launchMemo` (audio with transcript), `.shelf`, `.mitosis` (imported, landscape),
`.untitled` (needs a title), folders `.product .clients .personal`. Fixture sets: `.filled`,
`.empty` (no data, onboarding done), `.fresh` (first launch). Screenshots are 375x812 pt, light
appearance; the status bar shows 9:41.

## Copy

Short, plain, warm, second person, British spelling (organise, colour, minimise). Sentence case for
titles and buttons. Never mention a server, account, link or upload. Say where data lives when it
reassures ("Stays on this iPhone").

## Done means

- Every screen and state in your brief exists, is reachable from real navigation, and has its
  debug id.
- Every feature in your brief works with real recordings, offline.
- You reviewed every file for compile errors against the rules above.
- You committed on your branch (clear messages, end each with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`). Do not push, merge or start CI runs.
- Your final report lists: files added/changed, every debug id, shared-code requests, anything not
  finished, and what only a real iPhone can verify.
