#if DEBUG
import SwiftUI

/// The recorder the newest debug screen made (RecorderModel registers itself when it starts from a
/// preset), so a flow can change its stage, timer and waveform the way a real recording does.
@MainActor
enum DebugFlowHooks {
    static weak var recorder: RecorderModel?
}

/// Flows: short scripted runs through the real screens, for the iPhones on snapreel.video.
/// scripts/ci-flows.sh launches each one on the simulator (`-screen flow.share`) and records the screen
/// for `wait` seconds, in Light and in Dark. Each flow makes the same state changes a person's taps and a
/// live recording would (open the share sheet, upload progress, the countdown, the timer, the waveform);
/// everything on screen is the app's own views.
extension DebugCatalog {
    static var flowScreens: [DebugScreen] {
        [
            DebugScreen("flow.share", "Flow: a camera recording plays, Copy link, ready to watch", wait: 11) {
                FlowShare()
            },
            DebugScreen("flow.comments", "Flow: a shared recording plays with viewers' comments", wait: 9) {
                FlowComments()
            },
            DebugScreen("flow.camera", "Flow: camera countdown, then recording", wait: 9) {
                FlowRecorder(mode: .camera)
            },
            DebugScreen("flow.voice", "Flow: a voice recording with its live waveform", wait: 9) {
                FlowRecorder(mode: .audio)
            },
            DebugScreen("flow.screen", "Flow: the screen recording steps", wait: 9) {
                FlowRecorder(mode: .screen)
            },
        ]
    }
}

@MainActor
private func pause(_ seconds: Double) async {
    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
}

/// The desk camera recording plays (a real talking clip), then Copy link: the link is made, the video
/// uploads, and the sheet says it's ready to watch in any browser.
private struct FlowShare: View {
    private let id = FixtureStorage.IDs.onboardingFeedback

    var body: some View {
        ProDebugHost(.pro) {
            WatchDebugHost(videoID: id, prepare: { _ in }, initial: { _ in
                ShareLinks.shared.debugStates[id] = .notShared
                Uploader.shared.debugPhases[id] = nil
                return PlayerInitialState()
            })
        }
        .task { await run() }
    }

    private func run() async {
        let links = ShareLinks.shared
        await pause(3.2)
        links.debugStates[id] = .creating
        ProPresenter.shareLink(id)
        await pause(0.8)
        for step in 1...14 {
            links.debugStates[id] = .uploading(Double(step) / 14)
            await pause(0.2)
        }
        links.debugStates[id] = .finishing
        await pause(0.6)
        links.debugStates[id] = .ready
    }
}

/// A shared recording playing, with the viewers' comments and reactions under it.
private struct FlowComments: View {
    private let id = FixtureStorage.IDs.onboardingFeedback

    var body: some View {
        ProDebugHost(.pro) {
            WatchDebugHost(videoID: id, prepare: { _ in }, initial: { _ in
                ShareLinks.shared.debugStates[id] = .ready
                Uploader.shared.debugPhases[id] = nil
                var state = PlayerInitialState()
                state.panel = .comments
                state.scrollsToPanel = true
                state.activity = CloudFixtures.checkoutActivity
                return state
            })
        }
    }
}

/// The recorder: camera (countdown, then the timer runs), voice (the waveform moves with speech) or screen
/// (the three steps before a screen recording).
private struct FlowRecorder: View {
    let mode: RecordMode

    var body: some View {
        RecordDebug.recorder(mode) { preset in
            preset.stage = .idle
            switch mode {
            case .camera:
                preset.cameraStill = RecordDebug.still(front: true)
            case .screen:
                preset.showsTutorial = true
                preset.tutorialPage = 0
            case .audio:
                break
            }
        }
        .task { await run() }
    }

    private func run() async {
        await pause(0.5)
        guard let model = DebugFlowHooks.recorder else { return }
        switch mode {
        case .camera:
            await pause(1.0)
            for count in [3, 2, 1] {
                withAnimation(Motion.quick) { model.stage = .countdown(count) }
                await pause(1.0)
            }
            model.elapsed = 0
            withAnimation(Motion.quick) { model.stage = .recording }
            for _ in 0..<6 {
                await pause(1.0)
                model.elapsed += 1
            }
        case .audio:
            await pause(0.8)
            model.elapsed = 0
            withAnimation(Motion.quick) { model.stage = .recording }
            // Speech-like levels: syllables inside words, with short gaps between words.
            var tick = 0
            while tick < 20 * 8 {
                let inWord = (tick / 7) % 4 != 3
                let syllable = 0.5 + 0.5 * sin(Double(tick) * 1.7) * cos(Double(tick) * 0.37)
                let level = inWord ? 0.25 + 0.7 * syllable : 0.04 + 0.04 * Double(tick % 3)
                model.meter.push(CGFloat(min(1, max(0.03, level))))
                tick += 1
                if tick % 20 == 0 { model.elapsed += 1 }
                await pause(0.05)
            }
        case .screen:
            for page in [1, 2] {
                await pause(2.6)
                withAnimation(Motion.standard) { model.tutorialPage = page }
            }
        }
    }
}
#endif
