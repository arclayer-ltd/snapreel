#if DEBUG
import SwiftUI
import UIKit

extension DebugCatalog {
    /// Session B owns this list: recorder, permissions, camera, screen, audio, import, review, saving.
    static var recordScreens: [DebugScreen] {
        cameraScreens + screenModeScreens + reviewScreens + build23Screens + liveActivityScreens
    }

    /// Build 23 (owner's phone videos, 2026-11-19): the chooser, swipe down and the minimised
    /// voice recording. (Build 23's floating picture-in-picture button and its `rec.screen.floater`
    /// state were removed for the Live Activity; see `liveActivityScreens`.)
    private static var build23Screens: [DebugScreen] {
        [
            DebugScreen("rec.chooser", "Recorder [choose what to record]") {
                RecordDebug.recorder(.camera) { $0.choosingMode = true }
            },
            .shell("rec.swipe", "Recorder [swiped down, voice recording]", tab: .home) { router, _ in
                router.recorder = RecorderLaunch(mode: .audio)
            },
            .shell("rec.minimized", "Voice recording in the bar above the tab bar", tab: .home) { router, library in
                router.minimizedRecorder = RecordDebug.minimizedRecording(router: router, library: library)
            },
            .shell("rec.minimized.paused", "Voice recording in the bar [paused]", tab: .library) { router, library in
                router.minimizedRecorder = RecordDebug.minimizedRecording(router: router, library: library,
                                                                          paused: true)
            },
        ]
    }

    private static var cameraScreens: [DebugScreen] {
        [
            DebugScreen("rec.shell", "Recorder shell, camera mode") {
                RecordDebug.recorder(.camera) { $0.cameraStill = RecordDebug.still(front: true) }
            },
            DebugScreen("rec.shell.audio", "Recorder shell, audio mode") {
                RecordDebug.recorder(.audio) { _ in }
            },
            DebugScreen("rec.shell.screen", "Recorder shell, screen mode") {
                RecordDebug.recorder(.screen) { $0.showsTutorial = true }
            },
            DebugScreen("rec.primer", "Permission primer") {
                RecordDebug.recorder(.camera) {
                    $0.cameraPermission = .notDetermined
                    $0.microphonePermission = .notDetermined
                }
            },
            DebugScreen("rec.primer.mic", "Permission primer [microphone prompt]", wait: 4,
                        settle: .microphonePrompt) {
                RecordDebug.recorder(.camera) {
                    $0.cameraPermission = .notDetermined
                    $0.microphonePermission = .notDetermined
                }
            },
            DebugScreen("rec.primer.camera", "Permission primer [camera prompt]", wait: 4,
                        settle: .cameraPrompt) {
                RecordDebug.recorder(.camera) {
                    $0.cameraPermission = .notDetermined
                    $0.microphonePermission = .notDetermined
                }
            },
            DebugScreen("rec.primer.denied", "Permission primer [denied]") {
                RecordDebug.recorder(.camera) {
                    $0.cameraPermission = .denied
                    $0.microphonePermission = .denied
                }
            },
            DebugScreen("rec.camera", "Camera viewfinder") {
                RecordDebug.recorder(.camera) {
                    $0.cameraStill = RecordDebug.still(front: false)
                    $0.cameraSide = .back
                }
            },
            DebugScreen("rec.camera.recording", "Camera recording") {
                RecordDebug.recorder(.camera) {
                    $0.cameraStill = RecordDebug.still(front: true)
                    $0.stage = .recording
                    $0.elapsed = 83
                }
            },
            DebugScreen("rec.camera.paused", "Camera recording [paused]") {
                RecordDebug.recorder(.camera) {
                    $0.cameraStill = RecordDebug.still(front: true)
                    $0.stage = .paused
                    $0.elapsed = 83
                }
            },
            DebugScreen("rec.camera.countdown", "Camera recording [countdown]") {
                RecordDebug.recorder(.camera) {
                    $0.cameraStill = RecordDebug.still(front: true)
                    $0.stage = .countdown(3)
                }
            },
            DebugScreen("rec.audio.recording", "Audio recording (live waveform)") {
                RecordDebug.recorder(.audio) {
                    $0.stage = .recording
                    $0.elapsed = 42
                    $0.levels = RecordDebug.levels
                }
            },
            DebugScreen("rec.settings", "Recording settings") {
                RecordDebug.recorder(.camera) {
                    $0.cameraStill = RecordDebug.still(front: true)
                    $0.sheet = .settings
                }
            },
            DebugScreen("rec.notes", "Speaker notes") {
                RecordDebug.withNotes {
                    RecordDebug.recorder(.camera) {
                        $0.cameraStill = RecordDebug.still(front: true)
                        $0.sheet = .notes
                    }
                }
            },
            DebugScreen("rec.notes.overlay", "Speaker notes [overlay]") {
                RecordDebug.withNotes {
                    RecordDebug.recorder(.camera) {
                        $0.cameraStill = RecordDebug.still(front: true)
                        $0.stage = .recording
                        $0.elapsed = 12
                    }
                }
            },
            DebugScreen("rec.import", "Photo library import") {
                RecordDebug.recorder(.camera) { $0.stage = .importing(0.46) }
            },
        ]
    }

    private static var screenModeScreens: [DebugScreen] {
        [
            DebugScreen("rec.screen.tutorial.1", "Screen tutorial") {
                RecordDebug.recorder(.screen) {
                    $0.showsTutorial = true
                    $0.tutorialPage = 0
                }
            },
            DebugScreen("rec.screen.tutorial.2", "Screen tutorial [2]") {
                RecordDebug.recorder(.screen) {
                    $0.showsTutorial = true
                    $0.tutorialPage = 1
                }
            },
            DebugScreen("rec.screen.tutorial.3", "Screen tutorial [3]") {
                RecordDebug.recorder(.screen) {
                    $0.showsTutorial = true
                    $0.tutorialPage = 2
                }
            },
            DebugScreen("rec.broadcast", "Broadcast step") {
                RecordDebug.recorder(.screen) { $0.showsTutorial = false }
            },
            DebugScreen("rec.broadcast.unavailable", "Broadcast step [unavailable]") {
                RecordDebug.recorder(.screen) {
                    $0.showsTutorial = false
                    $0.screenRecorderAvailable = false
                }
            },
            DebugScreen("rec.screen.recording", "Screen recording in progress") {
                RecordDebug.recorder(.screen) {
                    $0.showsTutorial = false
                    $0.broadcast = BroadcastState(status: .recording, recordingID: UUID(),
                                                  startedAt: Date().addingTimeInterval(-83),
                                                  updatedAt: Date(), microphoneEnabled: true)
                }
            },
        ]
    }

    private static var reviewScreens: [DebugScreen] {
        let id = FixtureStorage.IDs.untitled
        return [
            DebugScreen("rec.review", "Review after recording") {
                RecordDebug.recorder(.screen) { $0.stage = .review(id) }
            },
            DebugScreen("rec.review.audio", "Review after recording [voice, mid-way]") {
                RecordDebug.recorder(.audio) {
                    $0.stage = .review(FixtureStorage.IDs.launchMemo)
                    $0.reviewPosition = 4.2
                }
            },
            DebugScreen("rec.review.delete", "Review after recording [delete]") {
                RecordDebug.recorder(.screen) {
                    $0.stage = .review(id)
                    $0.reviewPanel = .delete
                }
            },
            DebugScreen("rec.title", "Title editor", wait: 4) {
                RecordDebug.recorder(.screen) {
                    $0.stage = .review(id)
                    $0.reviewPanel = .title
                }
            },
            DebugScreen("rec.title.typed", "Title editor [typed]", wait: 4) {
                RecordDebug.titled(id) {
                    RecordDebug.recorder(.screen) {
                        $0.stage = .review(id)
                        $0.reviewPanel = .title
                    }
                }
            },
            DebugScreen("rec.review.titled", "Review after recording [titled]") {
                RecordDebug.titled(id) {
                    RecordDebug.recorder(.screen) { $0.stage = .review(id) }
                }
            },
            DebugScreen("rec.share", "Share sheet", wait: 4) {
                RecordDebug.recorder(.screen) {
                    $0.stage = .review(id)
                    $0.reviewPanel = .share
                }
            },
            DebugScreen("rec.saving", "Saving progress") {
                RecordDebug.saving(id, state: .saving(progress: 0.62))
            },
            DebugScreen("rec.saving.failed", "Saving progress [failed]") {
                RecordDebug.saving(id, state: .failed(reason: "The recording was cut short and can't be played.",
                                                      outOfSpace: false))
            },
            DebugScreen("rec.saving.nospace", "Saving progress [no space]") {
                RecordDebug.saving(id, state: .failed(reason: "Your iPhone ran out of space while saving.",
                                                      outOfSpace: true))
            },
            DebugScreen("settings.recording", "Recording defaults") {
                NavigationStack { RecordingDefaultsView() }
            },
        ]
    }
}

/// Builders for the recorder's debug screens.
@MainActor
enum RecordDebug {
    /// The recorder in `mode`, permissions granted unless the preset says otherwise.
    static func recorder(_ mode: RecordMode, _ change: (inout RecorderPreset) -> Void) -> RecorderView {
        var preset = RecorderPreset()
        preset.cameraPermission = .granted
        preset.microphonePermission = .granted
        preset.showsTutorial = false
        change(&preset)
        return RecorderView(launch: RecorderLaunch(mode: mode), preset: preset)
    }

    /// The recorder the shell presents (`RecorderView(launch:)`), for debug ids that show it
    /// over the tab shell. Nil for every other screen and in normal use.
    static func shellCoverPreset() -> RecorderPreset? {
        guard AppEnvironment.shared.debugScreenID == "rec.swipe" else { return nil }
        var preset = RecorderPreset()
        preset.cameraPermission = .granted
        preset.microphonePermission = .granted
        preset.showsTutorial = false
        preset.stage = .recording
        preset.elapsed = 42
        preset.levels = levels
        preset.swipeOffset = 230
        return preset
    }

    /// A voice recording carrying on in the bar above the tab bar (no microphone in use).
    static func minimizedRecording(router: AppRouter, library: Library, paused: Bool = false) -> RecorderModel {
        var preset = RecorderPreset()
        preset.cameraPermission = .granted
        preset.microphonePermission = .granted
        preset.stage = paused ? .paused : .recording
        preset.elapsed = paused ? 95 : 42
        preset.levels = levels
        return RecorderModel(launch: RecorderLaunch(mode: .audio), library: library,
                             settings: AppEnvironment.shared.settings, router: router, preset: preset)
    }

    /// A drawn stand-in for the camera picture (the simulator has no camera).
    static func still(front: Bool) -> UIImage {
        FixtureArt.thumbnail(style: .camera(hue: front ? 0 : 2), portrait: true)
    }

    static var levels: [CGFloat] { RecorderAudioMeter.sampleLevels }

    /// Fills in speaker notes and turns them on.
    static func withNotes<Content: View>(_ content: () -> Content) -> Content {
        let settings = AppEnvironment.shared.settings
        settings.speakerNotes = """
        Hi team, quick update on the checkout work.
        1. Coupon bug: totals now refresh when a code is removed.
        2. Apple Pay moves above the card form, as Sam suggested.
        3. Address autocomplete is faster. Thanks, Priya!
        Next: test on older iPhones, then ship on Thursday.
        """
        settings.showsSpeakerNotes = true
        return content()
    }

    /// The untitled fixture recording after its person has typed a title.
    static func titled<Content: View>(_ id: UUID, _ content: () -> Content) -> Content {
        AppEnvironment.shared.library.rename(id, to: "Coupon bug on the staging checkout")
        return content()
    }

    /// The saving screen with the untitled fixture recording in `state`.
    static func saving(_ id: UUID, state: VideoState) -> RecorderView {
        let library = AppEnvironment.shared.library
        if library.video(id)?.state != state {
            library.update(id) { $0.state = state }
        }
        return recorder(.screen) { $0.stage = .saving(id) }
    }
}
#endif
