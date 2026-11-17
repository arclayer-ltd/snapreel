# Session A: getting started, character animation, settings, help, legal

Read `docs/briefs/COMMON.md` first. You own:
`Snapreel/Features/Onboarding/`, `Snapreel/Features/Settings/`, `Snapreel/Features/Help/`,
`Snapreel/Features/Legal/` (create Help and Legal). Resources go in your folders, prefixed
`help-` / `legal-`.

The eight character clips already exist (`Snapreel/Resources/Characters/`) and play through
`CharacterView(clip:)`. Your "character animation" work is placing them well: framing, entrance
motion, slide transitions, and how they sit with type. Do not generate new art.

## Screens (references are in `refs/`; open them, they are the bar to meet)

| Debug id(s) | Screen | Reference |
|---|---|---|
| `start.splash` | Splash: brand mark on ink, a short considered animation (ring draws, dot settles, ~0.9 s), then `onFinish`. Respect Reduce Motion. | mobbin f475b086 |
| `start.welcome` | Welcome: `CharacterView(.welcome)` large, the name, a one-line promise, primary "Get started", a quiet line that everything stays on this iPhone. Dark (ink). No sign-in. | mobbin 0ce2a2f6 (their carousel with Sign in/up) |
| `start.intro.1` `.2` `.3` | Three intro slides, swipeable and with Next, page indicator, Skip. 1 Record (screen, camera or voice) with `.introRecord`; 2 Keep it organised (folders, tags, search, notes) with `.introLibrary`; 3 Send it your way (AirDrop, Messages, save to Photos) with `.introSend`. Dark. | mobbin 0ce2a2f6, 38ff4bf6, 8b5b84cc |
| `start.use` `start.use.selected` | "What will you use Snapreel for?" Three choices from `UseCase` (work, education, personal). Selecting one expands its hint (`UseCase.hint`). Continue disabled until chosen. Saves `settings.useCase`. Light or dark: your call, consistent with the flow. | mobbin 3812ca86, 9520b8b2 |
| `start.tour.intro` `start.tour.1`…`start.tour.4` `start.tour.permission` | Guided tour over the real tab shell (`GuidedTourOverlay(targets:onFinish:)`): dimmed shell, spotlight on the target tab item (`targets[tab]` is its frame), a bottom card with title, body, progress, Next. Intro card uses `CharacterView(.tour)` ("A 20-second tour"). Steps: 1 Home, 2 Library, 3 Record (the red button), 4 Notifications, which asks for notification permission: card with `CharacterView(.notify)`, "Turn on notifications" (calls `Notifier.shared.requestAuthorization()`, shows the system alert) and "Not now". Finishing (either way) calls `onFinish`. `start.tour.permission` is step 4 with the system alert actually showing (call the request on appear in that debug entry). | mobbin 19689a04, 8cf23f32, ae0b8ff4, 6ad134c1, 83ffab4c, 55a17d4d |
| `settings.root` | Settings sheet root: grouped rows with icon tiles: Notifications → `NotificationSettingsView()` (E), Recording → `RecordingDefaultsView()` (B), Storage → `StorageView()` (E), Help centre, Contact support, Legal. Footer with app name, version and build from the bundle, and a short privacy line. Done button. | mobbin 74aeb655 |
| `help.home` | Help centre: search field (filters articles live, with a no-results state), categories with their articles, "See all" expanding a category. | mobbin f9c3e1f6, 49885582, 92adeabb |
| `help.article` | Article view: title, category, readable body with headings and steps, "Was this helpful?" yes/no (stored locally only), related articles, Contact support link. | mobbin 5b3089b4 (theirs is a web view; yours is native) |
| `help.contact` | Contact support: topic picker, message field, toggle to attach device info (model, iOS version, app version, free space; never recordings), Send opens Mail (`MFMailComposeViewController`) to `support@arclayer.co`; when Mail isn't set up, offer Copy address and a `mailto:` link. | compose icon in f9c3e1f6; designed fresh |
| `legal.menu` | Legal: Terms of use, Privacy policy, Acknowledgements. | mobbin 35a24f63 |
| `legal.terms` `legal.privacy` | Native document viewer for bundled Markdown (`AttributedString(markdown:)` with a simple block renderer for headings and paragraphs), "Last updated" date, share button. | mobbin d2910d61, dc86d237 |
| `legal.ack` | Acknowledgements: Apple frameworks used, SQLite (public domain), SF Symbols, original character art made for Snapreel. | mobbin 939b73c4 |

## Content you write

- **Help articles** (`Features/Help/help-articles.json`): about 20, in your own words, accurate to
  how Snapreel actually works (read `docs/PLAN.md` and the other briefs in `docs/briefs/` to know
  each feature). Categories: Getting started, Recording, Screen recording, Your library, Watching,
  Notes and reactions, Sharing and saving, Privacy and storage, Troubleshooting (e.g. "Screen
  recording won't start", "The microphone isn't recorded", "My iPhone is full").
- **Terms of use and privacy policy** (`Features/Legal/legal-terms.md`, `legal-privacy.md`): drafts
  for the owner's review, written for an app that collects nothing, has no accounts or servers,
  keeps recordings on the device, uses on-device speech recognition, and asks for camera,
  microphone, photos, speech and notification permissions. Publisher "Arclayer Ltd". Also put a
  copy of both in `docs/legal/` with a "DRAFT for owner review" header (not in the app).

## Wiring

- `RootView` shows `SplashView` over everything on launch, then `OnboardingFlow` until
  `settings.hasCompletedOnboarding`, then `MainShell`, whose tour overlay shows until
  `settings.hasCompletedTour`.
- The onboarding flow is one view with internal steps (welcome → intro 1-3 → use question); give
  it an initial-step parameter for debug entries.
- Debug entries for tour states use `.shell(..., fixture: .empty)` with
  `settings.hasCompletedTour = false` set in the configure closure (it receives the router and
  library; reach settings through `AppEnvironment.shared.settings`), plus an initial step for the
  overlay.
