# Snapreel

Record your screen, camera or voice on iPhone, keep the recordings organised, and send them to
people as files. Everything stays on the device: no account, no server, no network.

- Native SwiftUI, iOS 16.0+, iPhone.
- `Snapreel/`: the app. `SnapreelBroadcast/`: the ReplayKit broadcast upload extension that records
  the screen into a shared App Group container. `Shared/`: code compiled into both.
- The Xcode project uses file-system-synchronised groups, so new source files need no project edits.
- CI (`.github/workflows/ios.yml`, started by hand) compiles both targets, screenshots every screen
  state from the DEBUG `-screen <id>` launch argument, and can archive and upload to TestFlight.

See `docs/PLAN.md` for the plan, architecture and screen list.

© Arclayer Ltd. All rights reserved.
