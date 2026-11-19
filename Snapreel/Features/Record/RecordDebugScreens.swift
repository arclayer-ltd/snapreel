#if DEBUG
import AVFoundation
import SwiftUI
import UIKit

extension DebugCatalog {
    /// Session B owns this list: recorder, permissions, camera, screen, audio, import, review, saving.
    static var recordScreens: [DebugScreen] {
        cameraScreens + screenModeScreens + reviewScreens + build23Screens + liveActivityScreens + handoffScreens
    }

    /// Build 30 (owner, 20 November): reviews shown twice or not at all, and slow. The drill runs
    /// the real hand-offs and logs them; the check reads a real AAC file and times the saver.
    private static var handoffScreens: [DebugScreen] {
        [
            .shell("rec.handoff", "Review hand-offs [each recording reviewed once]", tab: .library, wait: 14) { router, library in
                ReviewHandoffDrill.start(router: router, library: library)
            },
            DebugScreen("rec.savecheck", "Audio bars from AAC, and save timing", wait: 6) {
                ReviewSaveCheckView()
            },
        ]
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

// MARK: - Review hand-offs and save timing (builds 29 and 30: reviews shown twice or not at all)

/// Runs the real hand-off paths for the same recordings in different orders, also while the
/// recorder is closing, and logs each one (DebugTrace). CI's debug-trace.txt must show one
/// "review shown" per recording, and the last tap on record opening the chooser.
@MainActor
enum ReviewHandoffDrill {
    static func start(router: AppRouter, library: Library) {
        Task { @MainActor in await run(router: router, library: library) }
    }

    private static func run(router: AppRouter, library: Library) async {
        guard let sample = library.videos.first(where: { $0.state.isReady && !$0.isAudioOnly }) else {
            return DebugTrace.log("drill: no sample recording")
        }
        let movie = library.fileURL(for: sample)
        await wait(1.5)

        // 1. Recorder closed: the finished signal, the app-active import and the notification
        //    tap for one recording, back to back.
        let first = drop(movie)
        DebugTrace.log("drill 1 \(ReviewCoordinator.short(first)): signal, import, tap")
        PendingImports.importFinishedBroadcasts(into: library, source: .extensionFinished)
        PendingImports.importFinishedBroadcasts(into: library, source: .appActive)
        PendingImports.openReviewFromNotification(broadcastID: first, library: library)
        await wait(2.5)

        // 2. Done, and while the recorder is closing: the first one again, and a new one in
        //    another order (tap, signal, import).
        let second = drop(movie)
        DebugTrace.log("drill 2 \(ReviewCoordinator.short(second)): Done, then while closing tap, signal, import")
        tapDone(router)
        ReviewCoordinator.shared.offer(first, note: nil, source: .appActive, presentIfClosed: true,
                                       library: library, router: router)
        PendingImports.openReviewFromNotification(broadcastID: second, library: library)
        PendingImports.importFinishedBroadcasts(into: library, source: .extensionFinished)
        PendingImports.importFinishedBroadcasts(into: library, source: .appActive)
        await wait(3)
        PendingImports.openReviewFromNotification(broadcastID: second, library: library)
        await wait(0.5)

        // 3. Done, then the record button: "What do you want to record?", nothing waiting.
        DebugTrace.log("drill 3: Done, then record")
        tapDone(router)
        await wait(1.2)
        router.record()
        await wait(2)
        let reviewed = [first, second].map { library.video($0)?.reviewedAt == nil ? "no" : "yes" }
        let shows = ReviewCoordinator.shared.visibleRecorder?.traceDescription ?? "nothing"
        DebugTrace.log("drill end: reviewed \(reviewed.joined(separator: ", ")); the recorder shows \(shows)")
    }

    /// A finished screen recording in the App Group inbox, as the broadcast extension leaves it.
    private static func drop(_ movie: URL) -> UUID {
        let id = UUID()
        let ext = movie.pathExtension.isEmpty ? "mov" : movie.pathExtension
        let name = "\(id.uuidString).\(ext)"
        try? FileManager.default.copyItem(at: movie, to: AppGroup.inboxURL.appendingPathComponent(name))
        let manifest = InboxRecording(id: id, movieFileName: name, createdAt: Date().addingTimeInterval(-20),
                                      finishedAt: Date(), microphoneEnabled: true)
        if let data = try? JSONEncoder.snapreel.encode(manifest) {
            try? data.write(to: InboxRecording.manifestURL(for: id), options: .atomic)
        }
        return id
    }

    /// What review's Done does: the model's part, then the cover closes.
    private static func tapDone(_ router: AppRouter) {
        ReviewCoordinator.shared.visibleRecorder?.finishReview()
        router.recorder = nil
    }

    private static func wait(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

/// Writes a 3-second AAC .m4a the way AVAudioRecorder does (loud, silent, quiet), reads it
/// back with `AudioEnvelope`, and times the saver on it as a voice take and on the sample movie
/// as a camera take (stop to ready). Results on screen and in debug-trace.txt.
struct ReviewSaveCheckView: View {
    @EnvironmentObject private var library: Library
    @State private var lines: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Audio bars and save timing").font(.srTitle3).foregroundStyle(Color.srText)
            ForEach(lines, id: \.self) { line in
                Text(line).font(.srFootnote).foregroundStyle(Color.srTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.srCanvas.ignoresSafeArea())
        .task { await run() }
    }

    private func report(_ line: String) {
        lines.append(line)
        DebugTrace.log(line)
    }

    private func run() async {
        let fm = FileManager.default
        let voice = fm.temporaryDirectory.appendingPathComponent("envelope-check.m4a")
        guard Self.writeTestVoice(to: voice) else { return report("AAC: couldn't write the test file") }
        guard let levels = await AudioEnvelope.read(voice), !levels.isEmpty else {
            return report("AAC: FAIL, no levels read")
        }
        func average(_ range: Range<Int>) -> CGFloat {
            let slice = levels[min(range.lowerBound, levels.count)..<min(range.upperBound, levels.count)]
            return slice.isEmpty ? 0 : slice.reduce(0, +) / CGFloat(slice.count)
        }
        let loud = average(2..<8), silent = average(12..<18), quiet = average(22..<28)
        let ok = loud > 0.6 && silent < 0.1 && quiet > 0.12 && quiet < 0.55
        report(String(format: "AAC: %@, %ld values; loud %.2f, silent %.2f, quiet %.2f",
                      ok ? "OK" : "FAIL", levels.count, loud, silent, quiet))

        // Saver timing: a voice take (the AAC file) and a camera take (the sample movie).
        await timeSave(kind: .audio, file: voice, ext: "m4a")
        if let sample = library.videos.first(where: { $0.state.isReady && !$0.isAudioOnly }) {
            await timeSave(kind: .camera, file: library.fileURL(for: sample), ext: library.fileURL(for: sample).pathExtension)
        }
    }

    /// Stop to ready through `RecordingSaver`, as after a real take (minus closing the file).
    private func timeSave(kind: RecordingKind, file: URL, ext: String) async {
        let id = UUID()
        let name = "\(id.uuidString).\(ext)"
        try? FileManager.default.copyItem(at: file, to: library.media.staging.appendingPathComponent(name))
        let started = Date()
        ReviewTiming.mark(id, "stop", at: started)
        ReviewTiming.mark(id, "file closed", at: started)
        RecordingSaver.shared.begin(RecordingSaveRequest(id: id, kind: kind, createdAt: started, fileName: name),
                                    library: library)
        for _ in 0..<500 where library.video(id)?.state.isReady != true {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        let ready = library.video(id)?.state.isReady == true
        ReviewTiming.mark(id, "ready seen")
        report(String(format: "%@ save: %@ in %.2f s", kind.label, ready ? "ready" : "NOT ready",
                      Date().timeIntervalSince(started)))
        ReviewTiming.finish(id, kind: kind)
    }

    /// 1 s of a loud tone, 1 s of silence, 1 s of a quiet tone, as mono AAC in .m4a (44.1 kHz,
    /// the recorder's own settings). The file is closed when this returns.
    private static func writeTestVoice(to url: URL) -> Bool {
        try? FileManager.default.removeItem(at: url)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
        ]
        guard let file = try? AVAudioFile(forWriting: url, settings: settings,
                                          commonFormat: .pcmFormatFloat32, interleaved: false) else { return false }
        let frames = AVAudioFrameCount(44_100)
        for amplitude in [0.5, 0.0, 0.05] {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames),
                  let channel = buffer.floatChannelData?[0] else { return false }
            buffer.frameLength = frames
            for index in 0..<Int(frames) {
                channel[index] = Float(amplitude * sin(2 * Double.pi * 440 * Double(index) / 44_100))
            }
            do { try file.write(from: buffer) } catch { return false }
        }
        return true
    }
}
#endif
