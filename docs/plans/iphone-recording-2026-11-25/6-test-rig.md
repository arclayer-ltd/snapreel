# 6. Test rig: the Snapreel app on a cloud iPhone, driven from this PC (25-26 Nov 2026)

(Asked for at `E:\Snapreel\docs\plans\iphone-recording-2026-11-25\6-test-rig.md`; a guard in this session refuses writes to
the main checkout, so it is here and in the worktree's `docs\plans\...`. The parent session can copy it over.)

Branch `claude/test-rig-adc90d` (pushed, not merged). Only new files: `.github/workflows/ui-live.yml` and
`scripts/ui-rig/`. `ios.yml`, the Xcode project, `Snapreel/**` and the tests are untouched.

| File | What |
| --- | --- |
| `scripts/ui-rig/README.md` | one page for a tester: start, steps, reading the answers |
| `scripts/ui-rig/TESTER.md` | brief for app testers: role, method, faults, report, 14 areas |
| `scripts/ui-rig/TESTER-WEB.md` | the same for the website (headless Chrome in the cloud, phone and desktop sizes) |
| `rig.py` | the client on this PC |
| `gitwire.py` | the channel (see below) |
| `agent.py`, `ios_driver.py`, `web_driver.py` | the runner's side: steps, phone, browser |
| `cloud_stub.py`, `start_stub.sh` | practice server (sign-in, links, uploads, Pro) and the cut-off from the real services |
| `site_local.sh`, `web_seed.py` | the whole website with its own throwaway Supabase on a Linux runner, with made-up data |
| `build_app.sh`, `make_media.sh`, `get_*.sh`, `ocr.swift` | stored builds, sample videos, touch driver, reading words off the picture |

## For the parent session, before the testers start

1. The combined fix branch must be pushed. `python scripts/ui-rig/rig.py build --app BRANCH` (8 to 12 min, once; kept 30 days).
2. Stored already: sample videos (90 days) and prepared phones; see "Status at hand-over".
3. Free the Mac slots: five macOS jobs for the whole organisation, one per phone. While five sessions were building, a
   phone waited 10 to 60 minutes for a slot. Web sessions run on Linux and don't count.
4. Give each tester: TESTER.md, an area number, a session name, the branch, a folder for the report. Tell them to use
   `python scripts/ui-rig/rig.py -s NAME do "step" "step" ...` with several steps per call.
5. Afterwards `rig.py stop --all`, `rig.py clean`.

**On merge** nothing has to change: the workflow starts from a push to `ui-rig/**` (the client pushes a throwaway branch that
holds only the workflow and `scripts/ui-rig`), so it works from any checkout that has those files. `workflow_dispatch` is not
used. The job needs `contents: write` (it pushes `refs/rig/*` and deletes its own branch) and `actions: read`.

## How it works

- **Channel**: small parentless commits on refs that are not branches (`refs/rig/<session>/in|out/0..3`), pushed and read
  over git-over-HTTPS with one open connection. Nothing listens anywhere; no secret is involved beyond each side's own
  GitHub login. Four lanes each way, because GitHub sometimes takes 15 s over one ref or answers "Internal Server Error".
  Steps are a fixed vocabulary; nothing that arrives is run as a command. Only people with push access can send any.
- **Touch driver**: Appium's WebDriverAgent 16.15.3, prebuilt for simulators, pinned by SHA-256. No Xcode build needed.
- **What is on screen** comes from the accessibility tree without visibility attributes (asking for those runs in the app's
  main thread and stalled it for minutes), filtered by reading the words off the picture with Apple's Vision on the Mac,
  because the app keeps its other tabs in the tree.
- **Hang**: the app does not describe its screen for 8 s *and* its main thread is busy (thread CPU time), then a `sample`
  with the stack. A slow Mac is reported as that.
- **Shut-down**: after `--minutes` (120), 20 idle minutes, or `stop`; the job deletes its branch.
- **Safety**: every host of ours in the app's source is sent to 127.0.0.1 on the runner and each one is proven to be
  answered by the practice server (a marker header) before a session counts as ready; otherwise there is no session.

## Measured

| | iOS 16.4, iPhone X (macos-26 runner) | iOS 27.2, iPhone 13 mini (xcode-27 runner) |
| --- | --- | --- |
| Start, from getting a Mac | 10 to 12 min, from a prepared phone and a stored build (2 min of it downloads iOS 16.4) | 6 to 8 min |
| One step and nothing else, there and back | 4.0 to 4.3 s | 4.0 to 5.0 s |
| Look (picture + list), there and back | **5.3 to 5.9 s** (1 s on the phone) | 6 to 8 s on a good Mac, up to 60 s in a bad moment |
| 15 steps, from a closed editor to an Arrow in a 4-minute video | 34 s | not timed |
| 13 steps through Settings, a picture after each | not timed | 64 s |
| Delete and reinstall the app | 17 s | 34 s |
| Web session (Linux): start / look | 3 min / 7 s | |

iOS 26.5 on the same Macs was as slow as iOS 27. Intel runners (`macos-15-intel`) start at once but a look took 45 s: not usable.
So the default is iPhone X with iOS 16, which is also the owner's phone and system.

## Proof runs on main (the app is the same in 5c533e8 and 5aa9219)

- **Arrow hang: yes, the simulator shows it.** iOS 16.4: adding the Arrow makes the editor wider than the screen; dragging it
  puts the main thread at 100% for good (memory keeps growing). Seen 4 of 4. iOS 26.5: same overflow, no hang; the arrow
  follows a quarter of the finger; dragging it by its middle deletes it (the x's touch area covers it).
  Evidence in `E:\Snapreel\docs\plans\iphone-recording-2026-11-25\rig-evidence\` and `rig-arrow-hang.md` here; the ios-editor
  session was told.
- **Settings** on iOS 27 in Light: Account, Notifications, Recording, Appearance, Storage, Help centre, Legal and sign-in
  opened and pictured; Contact support, Take the tour again and the pages under Legal were listed but not opened.
  Seen on the way: "Import-ed" is broken in two on the Storage page at 375 pt.
- **Sign-in** with an email code against the practice server, up to the Account page (Free plan). Copy link and uploads
  were tested against the practice server only by its own requests, not from the app.
- **Website**: email-code sign-in, dashboard, watch page playing, comments and reactions from the seed.

## One mistake to know about

Before the cut-off was fail-closed, its script redirected a made-up project name from a code comment instead of the real
one, so one tap on "Email me a code" for `robin@example.com` reached the **production** Supabase. The server refused it
(its Send Email hook answered 500); I checked, with one read-only query, that no such user exists there. Nothing else was
sent by the app on purpose before the fix (commit "Test rig: fail closed against the real services"). Two things it shows
about the product: the app shows the person the raw text "Unexpected status code returned from hook: 500", and the hook
returns 500 for that address.

## Limits

- No camera, no screen broadcast, no picture in picture, no real purchases, no Sign in with Apple, no pushes from the server.
  Voice recording should work but record silence (not tried). The phone turns only where the app allows it.
- **StoreKit test purchases**: `store` drops Xcode's test-store file into the simulator; NOT tried. Pro screens are
  reachable with `plan pro` on the practice server.
- `net offline` breaks the server's answers; the phone itself stays "online" (the app's network monitor sees a connection).
- The simulator is not a real phone's speed or memory; CPU and memory numbers are for comparing, not for quoting.
- While an app is hung, only pictures, `home`, `reopen`, `kill` and `launch` work (XCTest waits for the hung app).
- iOS 16's Photos picker gives wrong positions; the rig corrects them. On newer iOS, tap videos in the picker by point.
- GitHub keeps a session's pictures as unreferenced objects for a while after `stop`; only made-up content is in them.

## Status at hand-over

- Pushed: 31 commits on `claude/test-rig-adc90d`. All sessions stopped and their refs removed; `image-se-16` (a prepared
  iPhone SE on iOS 16) was still being made and cleans up after itself; run `rig.py clean` once later.
- Stored: app build for main (`ui-app-v3-...-x27`, until 25 Dec), sample videos (`ui-media-small|long|big`, until 23 Feb),
  prepared phones `iphonex`, `large` on iOS 16 and `small` on iOS 27 (until 23 Feb), `se` on iOS 16 if that job finished.
- Proven: two live phones driven at the same time (s1, s2) and a batch run (16 steps: a picture per step, video, app log,
  report) beside a live phone; Copy link with sign-in and a complete upload to the practice server ("Ready to watch",
  the link on the clipboard); Dark mode; text sizes; Home, app switcher, notifications, background and back; permissions;
  a URL; recording a video of the screen; the practice server's `net` and `plan`.
- Not proven: every web area (only sign-in, dashboard and one watch page), `30min` and `big` from Photos, the `se` phone,
  `normal`. Testers will meet the rig's rough edges; the README tells them what to do in each case.
