import AVFoundation
import Combine
import PhotosUI
import ReplayKit
import SwiftUI
import UIKit

/// Where the recorder is in a take.
enum RecorderStage: Equatable {
    case idle
    case countdown(Int)
    case recording
    case paused
    /// The movie or audio file is being closed.
    case finishing
    /// A video from Photos is being copied in (0...1).
    case importing(Double)
    case saving(UUID)
    case review(UUID)

    var isCapturing: Bool { self == .recording || self == .paused }

    var isCountingDown: Bool {
        if case .countdown = self { return true }
        return false
    }

    /// Showing the camera, audio or screen controls (not saving or review).
    var showsCaptureControls: Bool {
        switch self {
        case .idle, .countdown, .recording, .paused, .finishing: return true
        case .importing, .saving, .review: return false
        }
    }
}

/// What screen mode shows.
enum RecorderScreenStep: Equatable {
    case tutorial
    case broadcast
    case unavailable
    case inProgress
}

enum RecorderSheet: String, Identifiable {
    case settings
    case notes
    case storage

    var id: String { rawValue }
}

enum RecorderPrimer: Equatable {
    case none
    case ask
    case denied
}

enum RecorderCameraState: Equatable {
    case starting
    case running
    case unavailable(String)
}

/// Panels the review screen can open with (debug screenshots).
enum RecorderReviewPanel: Equatable {
    case delete
    case title
    case share
}

struct RecorderAlert: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    var opensSettings = false
}

/// Opens the recorder in a given state without starting the camera, microphone or timers.
/// Used by debug screenshots; the shipped app always passes nil.
struct RecorderPreset {
    var cameraPermission: PermissionState?
    var microphonePermission: PermissionState?
    var stage: RecorderStage?
    var elapsed: TimeInterval = 0
    var showsTutorial: Bool?
    var tutorialPage = 0
    var screenRecorderAvailable = true
    var broadcast: BroadcastState?
    var sheet: RecorderSheet?
    /// Stands in for the live camera picture.
    var cameraStill: UIImage?
    var cameraSide: CameraSide?
    var levels: [CGFloat]?
    var confirmsRestart = false
    var reviewPanel: RecorderReviewPanel?
    /// Shows the "What do you want to record?" chooser (opened without a mode).
    var choosingMode: Bool?
    /// Holds the recorder part-way through a swipe down.
    var swipeOffset: CGFloat = 0
}

/// The recorder's state and actions. One per open recorder.
@MainActor
final class RecorderModel: ObservableObject {
    let library: Library
    let settings: AppSettings
    let router: AppRouter
    let launch: RecorderLaunch
    let preset: RecorderPreset?
    var isStatic: Bool { preset != nil }

    @Published var mode: RecordMode
    /// Opened without a mode (the tab bar's record button, "Start a recording"): nothing runs,
    /// not even the camera, until the person picks Camera, Screen or Audio.
    @Published private(set) var isChoosingMode: Bool
    @Published var stage: RecorderStage = .idle {
        didSet { if stage != oldValue { watchSaving() } }
    }
    @Published var elapsed: TimeInterval = 0
    @Published var cameraPermission: PermissionState
    @Published var microphonePermission: PermissionState
    @Published var cameraSide: CameraSide
    @Published var cameraState: RecorderCameraState = .starting
    @Published var canFlipWhileRecording = false
    /// Camera recordings include sound (starts from the Settings default).
    @Published var microphoneOn: Bool
    @Published var sheet: RecorderSheet?
    @Published var confirmsRestart = false
    @Published var confirmsDiscard = false
    @Published var showsLowSpaceWarning = false
    @Published var showsPhotoPicker = false
    @Published var alert: RecorderAlert?
    @Published var toast: ToastMessage?

    // Screen mode
    @Published var broadcast: BroadcastState
    @Published var screenRecorderAvailable = true
    @Published var showsTutorial: Bool
    @Published var tutorialPage: Int
    @Published var isStoppingBroadcast = false
    @Published private var dismissedFailureAt: Date?

    // Review
    @Published var reviewNote: String?
    var initialReviewPanel: RecorderReviewPanel?

    let meter = RecorderAudioMeter()
    /// Shared: one capture session for the app's lifetime (see `RecorderCameraEngine`).
    let camera = RecorderCameraEngine.shared
    private let audio = RecorderAudioEngine()

    private var countdownTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    private var screenTask: Task<Void, Never>?
    private var importTask: Task<Void, Never>?
    private var importProgress: Progress?
    private var signalObservers: [BroadcastSignalObserver] = []
    private var segmentStart: Date?
    private var accumulated: TimeInterval = 0
    private var captureStartedAt = Date()
    private var captureID: UUID?
    private var captureFileName: String?
    private var lastSpaceCheck = Date.distantPast
    private var isVisible = false
    /// When the system broadcast sheet was last opened from Snapreel's record button.
    private var broadcastPickerOpenedAt: Date?
    /// While `stage` is `.saving`, watches the library so review opens the moment the video is
    /// ready, whatever the saving screen is doing (see `watchSaving`).
    private var savingWatch: AnyCancellable?
    /// The recorder was swiped down mid audio recording; the take carries on from the bar
    /// above the tab bar, so closing the screen mustn't stop anything.
    private(set) var isMinimized = false

    init(launch: RecorderLaunch, library: Library, settings: AppSettings, router: AppRouter,
         preset: RecorderPreset?) {
        self.launch = launch
        self.library = library
        self.settings = settings
        self.router = router
        self.preset = preset
        mode = launch.mode ?? settings.lastRecordMode
        isChoosingMode = preset?.choosingMode ?? (launch.mode == nil && !launch.startsWithImport && !launch.resumesMinimized)
        cameraPermission = preset?.cameraPermission ?? Permissions.currentState(.camera)
        microphonePermission = preset?.microphonePermission ?? Permissions.currentState(.microphone)
        cameraSide = preset?.cameraSide ?? settings.defaultCamera
        microphoneOn = settings.microphoneOnByDefault
        broadcast = preset?.broadcast ?? BroadcastStateStore.read()
        showsTutorial = preset?.showsTutorial ?? !settings.hasSeenScreenTutorial
        tutorialPage = preset?.tutorialPage ?? 0
        if isChoosingMode && preset == nil && isBroadcastLive {
            // A screen recording is running: show it rather than asking what to record.
            mode = .screen
            isChoosingMode = false
        }
        if let preset {
            stage = preset.stage ?? .idle
            elapsed = preset.elapsed
            screenRecorderAvailable = preset.screenRecorderAvailable
            sheet = preset.sheet
            confirmsRestart = preset.confirmsRestart
            initialReviewPanel = preset.reviewPanel
            cameraState = preset.cameraStill == nil ? .starting : .running
            if let levels = preset.levels { meter.show(levels) }
        }
    }

    // MARK: - Derived state

    var primer: RecorderPrimer {
        switch mode {
        case .camera:
            if cameraPermission == .denied { return .denied }
            if cameraPermission == .notDetermined || microphonePermission == .notDetermined { return .ask }
            return .none
        case .audio:
            if microphonePermission == .denied { return .denied }
            if microphonePermission == .notDetermined { return .ask }
            return .none
        case .screen:
            return .none
        }
    }

    /// Camera recordings actually include sound.
    var recordsCameraSound: Bool { microphoneOn && microphonePermission == .granted }

    var isBroadcastLive: Bool {
        guard broadcast.status == .recording || broadcast.status == .finishing else { return false }
        return isStatic || Date().timeIntervalSince(broadcast.updatedAt) < 20
    }

    /// The last screen recording's failure, until the person dismisses it (ten minutes at most).
    var screenFailure: String? {
        guard broadcast.status == .failed, let message = broadcast.errorMessage else { return nil }
        if let dismissedFailureAt, dismissedFailureAt >= broadcast.updatedAt { return nil }
        guard isStatic || Date().timeIntervalSince(broadcast.updatedAt) < 10 * 60 else { return nil }
        return message
    }

    var screenStep: RecorderScreenStep {
        if isBroadcastLive { return .inProgress }
        if !screenRecorderAvailable || screenFailure != nil { return .unavailable }
        return showsTutorial ? .tutorial : .broadcast
    }

    var speakerNotesVisible: Bool {
        settings.showsSpeakerNotes
            && !settings.speakerNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && mode != .screen
            && primer == .none
    }

    // MARK: - Lifecycle

    func appear() {
        guard !isVisible else { return }
        isVisible = true
        guard !isStatic else { return }
        if isMinimized {
            // Back from the bar above the tab bar: everything is still running.
            isMinimized = false
            if router.minimizedRecorder === self { router.minimizedRecorder = nil }
            return
        }
        signalObservers = [
            BroadcastSignalObserver(.started) { [weak self] in
                Task { @MainActor in self?.broadcastDidStart() }
            },
            BroadcastSignalObserver(.finished) { [weak self] in
                Task { @MainActor in self?.broadcastDidFinish() }
            },
        ]
        enterMode()
        if launch.startsWithImport {
            showsPhotoPicker = true
        }
    }

    func disappear() {
        isVisible = false
        guard !isStatic, !isMinimized else { return }
        countdownTask?.cancel()
        clockTask?.cancel()
        screenTask?.cancel()
        if stage.isCapturing { discardCapture() }
        camera.shutDown()
        signalObservers = []
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: - Choosing a mode and minimising

    /// The person picked what to record from the chooser.
    func chooseMode(_ newMode: RecordMode) {
        guard isChoosingMode else { return }
        Haptics.selection()
        mode = newMode
        settings.lastRecordMode = newMode
        isChoosingMode = false
        enterMode()
    }

    /// Only a voice recording can keep going with the recorder out of sight.
    var canMinimize: Bool { !isStatic && mode == .audio && stage.isCapturing }

    /// Swiped down mid audio recording: hand the take to the bar above the tab bar.
    func minimize() {
        guard canMinimize else { return }
        isMinimized = true
        router.minimizeRecorder(self)
    }

    /// Close button. Returns true when the recorder can close now.
    func prepareToClose() -> Bool {
        // Closing the file takes a moment; the saving screen follows straight after.
        if stage == .finishing { return false }
        if stage.isCapturing {
            confirmsDiscard = true
            return false
        }
        if stage.isCountingDown { cancelCountdown() }
        if case .importing = stage { cancelImport() }
        return true
    }

    func discardAndClose() {
        discardCapture()
    }

    func appWillResignActive() {
        guard !isStatic else { return }
        if stage.isCountingDown { cancelCountdown() }
        // The camera stops in the background; audio keeps going.
        if mode == .camera && stage == .recording { pause() }
    }

    func appDidBecomeActive() {
        guard !isStatic else { return }
        // A save that finished while Snapreel was away: go straight to review.
        if case .saving(let id) = stage, library.video(id)?.state.isReady == true {
            savingFinished(id)
        }
        let camera = Permissions.currentState(.camera)
        let microphone = Permissions.currentState(.microphone)
        let changed = camera != cameraPermission || microphone != microphonePermission
        cameraPermission = camera
        microphonePermission = microphone
        if changed { enterMode() }
        refreshBroadcast()
    }

    func captureInterrupted() {
        guard !isStatic, mode == .camera, stage == .recording else { return }
        pause()
    }

    func audioInterrupted(_ notification: Notification) {
        guard !isStatic, mode == .audio, stage == .recording,
              let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
        pause()
    }

    // MARK: - Modes

    func switchMode(to newMode: RecordMode) {
        guard newMode != mode, !stage.isCapturing, stage != .finishing else { return }
        if stage.isCountingDown { cancelCountdown() }
        mode = newMode
        settings.lastRecordMode = newMode
        enterMode()
    }

    /// Starts what the current mode needs and stops what it doesn't.
    private func enterMode() {
        guard !isStatic else { return }
        if isChoosingMode {
            camera.stopRunning()
            return
        }
        if mode == .camera && stage.showsCaptureControls {
            startCamera()
        } else {
            camera.stopRunning()
        }
        if mode == .screen {
            startScreenMonitoring()
        } else {
            screenTask?.cancel()
            screenTask = nil
        }
    }

    // MARK: - Permissions

    func requestPermissions() {
        Task {
            if mode == .camera, cameraPermission == .notDetermined {
                cameraPermission = await Permissions.request(.camera)
            }
            if mode != .screen, microphonePermission == .notDetermined {
                microphonePermission = await Permissions.request(.microphone)
            }
            enterMode()
        }
    }

    // MARK: - Camera

    private func startCamera() {
        guard !isStatic, mode == .camera, cameraPermission == .granted else { return }
        if cameraState != .running { cameraState = .starting }
        configureCamera(keepPreset: false)
    }

    private func configureCamera(keepPreset: Bool) {
        camera.configure(side: cameraSide, quality: settings.recordingQuality,
                         mirrorsFront: settings.mirrorFrontCamera, microphone: recordsCameraSound,
                         keepPreset: keepPreset) { [weak self] setup in
            Task { @MainActor in self?.cameraConfigured(setup) }
        }
    }

    private func cameraConfigured(_ setup: RecorderCameraSetup) {
        canFlipWhileRecording = setup.canFlipWhileRecording
        if setup.isAvailable {
            cameraState = .running
        } else {
            cameraState = .unavailable(setup.message ?? "The camera isn't available right now.")
        }
    }

    /// Quality or mirroring changed in the settings sheet.
    func cameraSettingsChanged() {
        guard !isStatic, mode == .camera, stage == .idle else { return }
        startCamera()
    }

    func flipCamera() {
        let target: CameraSide = cameraSide == .front ? .back : .front
        if stage.isCapturing && !canFlipWhileRecording {
            toast = ToastMessage(text: "Switch cameras before you start at this quality", systemImage: "arrow.triangle.2.circlepath.camera")
            return
        }
        Haptics.tap()
        cameraSide = target
        guard !isStatic else { return }
        configureCamera(keepPreset: stage.isCapturing)
    }

    func toggleMicrophone() {
        guard !stage.isCapturing else { return }
        switch microphonePermission {
        case .denied:
            alert = RecorderAlert(title: "Microphone access is off",
                                  message: "To record your voice, turn on Microphone for Snapreel in Settings.",
                                  opensSettings: true)
        case .notDetermined:
            Task {
                microphonePermission = await Permissions.request(.microphone)
                microphoneOn = microphonePermission == .granted
                startCamera()
            }
        case .granted:
            Haptics.selection()
            microphoneOn.toggle()
            toast = ToastMessage(text: microphoneOn ? "Microphone on" : "Microphone off",
                                 systemImage: microphoneOn ? "mic.fill" : "mic.slash.fill")
            startCamera()
        }
    }

    // MARK: - Recording (camera and audio)

    func recordTapped() {
        switch stage {
        case .idle: requestStart(skipSpaceCheck: false)
        case .countdown: cancelCountdown()
        case .recording, .paused: stop()
        default: break
        }
    }

    func requestStart(skipSpaceCheck: Bool) {
        guard stage == .idle, primer == .none, mode != .screen else { return }
        if mode == .camera && cameraState != .running { return }
        if !skipSpaceCheck && !DiskSpace.hasRoom(for: 300_000_000) {
            showsLowSpaceWarning = true
            return
        }
        let seconds = settings.countdown.rawValue
        if seconds > 0 && !isStatic {
            runCountdown(seconds)
        } else {
            beginCapture()
        }
    }

    private func runCountdown(_ seconds: Int) {
        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            for remaining in stride(from: seconds, through: 1, by: -1) {
                guard let self, !Task.isCancelled else { return }
                self.stage = .countdown(remaining)
                Haptics.tap()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            guard let self, !Task.isCancelled, self.stage.isCountingDown else { return }
            self.beginCapture()
        }
    }

    func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        if stage.isCountingDown { stage = .idle }
    }

    private func beginCapture() {
        countdownTask = nil
        guard !isStatic else {
            stage = .recording
            return
        }
        let id = UUID()
        let fileName: String
        switch mode {
        case .camera:
            fileName = "\(id.uuidString).mov"
            let url = library.media.staging.appendingPathComponent(fileName)
            camera.startRecording(to: url, quality: settings.recordingQuality, includesAudio: recordsCameraSound)
        case .audio:
            fileName = "\(id.uuidString).m4a"
            let url = library.media.staging.appendingPathComponent(fileName)
            do {
                try audio.start(to: url)
            } catch {
                stage = .idle
                alert = RecorderAlert(title: "Couldn't start recording",
                                      message: "The microphone is busy. Close any call or other app using it, then try again.")
                return
            }
            meter.reset()
        case .screen:
            return
        }
        captureID = id
        captureFileName = fileName
        RecordingSaver.shared.activeCaptureFiles.insert(fileName)
        captureStartedAt = Date()
        accumulated = 0
        segmentStart = Date()
        elapsed = 0
        stage = .recording
        Haptics.firm()
        UIApplication.shared.isIdleTimerDisabled = true
        startClock()
        if mode == .audio { RecordingLiveActivity.voiceChanged(.recording(clockStart: Date())) }
    }

    func togglePause() {
        switch stage {
        case .recording: pause()
        case .paused: resume()
        default: break
        }
    }

    private func pause() {
        guard stage == .recording else { return }
        if !isStatic {
            if mode == .camera { camera.pauseRecording() } else { audio.pause() }
        }
        if let segmentStart { accumulated += Date().timeIntervalSince(segmentStart) }
        segmentStart = nil
        elapsed = accumulated
        stage = .paused
        Haptics.tap()
        if !isStatic && mode == .audio { RecordingLiveActivity.voiceChanged(.paused(elapsed: accumulated)) }
    }

    private func resume() {
        guard stage == .paused else { return }
        if !isStatic {
            if mode == .camera { camera.resumeRecording() } else { audio.resume() }
        }
        segmentStart = Date()
        stage = .recording
        Haptics.tap()
        if !isStatic && mode == .audio {
            RecordingLiveActivity.voiceChanged(.recording(clockStart: Date().addingTimeInterval(-accumulated)))
        }
    }

    func stop() {
        guard stage.isCapturing else { return }
        clockTask?.cancel()
        if let segmentStart { accumulated += Date().timeIntervalSince(segmentStart) }
        segmentStart = nil
        elapsed = accumulated
        Haptics.firm()
        UIApplication.shared.isIdleTimerDisabled = false
        if !isStatic && mode == .audio { RecordingLiveActivity.voiceChanged(nil) }
        guard !isStatic, let id = captureID, let fileName = captureFileName else {
            stage = .idle
            return
        }
        stage = .finishing
        let createdAt = captureStartedAt
        switch mode {
        case .camera:
            camera.stopRecording { [weak self] result in
                Task { @MainActor in
                    self?.captureEnded(result, id: id, fileName: fileName, kind: .camera, createdAt: createdAt)
                }
            }
        case .audio:
            audio.stop()
            let url = library.media.staging.appendingPathComponent(fileName)
            captureEnded(.finished(url), id: id, fileName: fileName, kind: .audio, createdAt: createdAt)
        case .screen:
            stage = .idle
        }
    }

    private func captureEnded(_ result: RecorderCaptureResult, id: UUID, fileName: String,
                              kind: RecordingKind, createdAt: Date) {
        RecordingSaver.shared.activeCaptureFiles.remove(fileName)
        captureID = nil
        captureFileName = nil
        switch result {
        case .finished, .partial:
            RecordingSaver.shared.begin(RecordingSaveRequest(id: id, kind: kind, createdAt: createdAt, fileName: fileName),
                                        library: library)
            stage = .saving(id)
            camera.stopRunning()
        case .failed(let message, let outOfSpace):
            stage = .idle
            alert = RecorderAlert(title: outOfSpace ? "Your iPhone is full" : "Couldn't save this recording",
                                  message: message)
            Haptics.error()
        }
    }

    /// Restart: throw this take away and start again (countdown included).
    func restart() {
        guard stage.isCapturing else { return }
        discardCapture()
        requestStart(skipSpaceCheck: true)
    }

    private func discardCapture() {
        clockTask?.cancel()
        guard stage.isCapturing || stage == .finishing else { return }
        if !isStatic {
            switch mode {
            case .camera: camera.cancelRecording()
            case .audio:
                audio.cancel()
                RecordingLiveActivity.voiceChanged(nil)
            case .screen: break
            }
        }
        if let captureFileName { RecordingSaver.shared.activeCaptureFiles.remove(captureFileName) }
        captureID = nil
        captureFileName = nil
        segmentStart = nil
        accumulated = 0
        elapsed = 0
        stage = .idle
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func startClock() {
        clockTask?.cancel()
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.tick()
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    private func tick() {
        if let segmentStart {
            let now = accumulated + Date().timeIntervalSince(segmentStart)
            if Int(now) != Int(elapsed) { elapsed = now }
        }
        if mode == .audio {
            meter.push(stage == .recording ? audio.level() : 0)
        }
        // Stop before the disk fills so the recording can still be saved.
        if stage == .recording, Date().timeIntervalSince(lastSpaceCheck) > 5 {
            lastSpaceCheck = Date()
            if DiskSpace.available < 150_000_000 {
                stop()
                toast = ToastMessage(text: "Your iPhone is almost full, so recording stopped",
                                     systemImage: "externaldrive.fill.badge.exclamationmark")
            }
        }
    }

    // MARK: - Screen recording

    private func startScreenMonitoring() {
        refreshBroadcast()
        screenTask?.cancel()
        screenTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { return }
                self.refreshBroadcast()
            }
        }
    }

    func refreshBroadcast() {
        guard !isStatic else { return }
        let state = BroadcastStateStore.read()
        if state != broadcast { broadcast = state }
        let available = RPScreenRecorder.shared().isAvailable
        if available != screenRecorderAvailable { screenRecorderAvailable = available }
        if isStoppingBroadcast && !isBroadcastLive { isStoppingBroadcast = false }
    }

    private func broadcastDidStart() {
        refreshBroadcast()
        settings.hasSeenScreenTutorial = true
        showsTutorial = false
        if isChoosingMode {
            mode = .screen
            isChoosingMode = false
            enterMode()
        } else if mode != .screen && stage == .idle {
            switchMode(to: .screen)
        }
        // iOS leaves its broadcast sheet up after the countdown; close it so the recorder's
        // "Snapreel is recording your screen" page shows.
        // The sheet runs outside Snapreel on iOS 14 and later: coming back to the front closes
        // it. The in-app dismissal stays for iOS versions that show it inside the app.
        let openedRecently = broadcastPickerOpenedAt.map { Date().timeIntervalSince($0) < 180 } ?? false
        BroadcastSheetCloser.broadcastStarted()
        BroadcastPickerSheet.dismissIfShowing(openedFromSnapreel: openedRecently)
        broadcastPickerOpenedAt = nil
    }

    private func broadcastDidFinish() {
        refreshBroadcast()
        isStoppingBroadcast = false
        PendingImports.importFinishedBroadcasts(into: library)
        if screenFailure != nil { Haptics.warning() }
    }

    /// The picker's own button was tapped (the system sheet is opening).
    func broadcastPickerTapped() {
        broadcastPickerOpenedAt = Date()
        if !isStatic {
            BroadcastSheetCloser.sheetOpened()
            // While Snapreel is still in front, the only time iOS lets it start a Live Activity.
            RecordingLiveActivity.screenSheetOpened()
        }
        Haptics.firm()
        if !settings.hasSeenScreenTutorial { settings.hasSeenScreenTutorial = true }
    }

    func showTutorial() {
        tutorialPage = 0
        withAnimation(Motion.standard) { showsTutorial = true }
    }

    func finishTutorial() {
        settings.hasSeenScreenTutorial = true
        withAnimation(Motion.standard) { showsTutorial = false }
    }

    func stopBroadcast() {
        guard !isStoppingBroadcast else { return }
        isStoppingBroadcast = true
        Haptics.firm()
        BroadcastSignal.stopRequested.post()
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard let self, self.isStoppingBroadcast else { return }
            self.refreshBroadcast()
            if self.isBroadcastLive {
                self.isStoppingBroadcast = false
                self.toast = ToastMessage(text: "Tap the red pill at the top of the screen to stop",
                                          systemImage: "record.circle")
            }
        }
    }

    func dismissScreenFailure() {
        dismissedFailureAt = broadcast.updatedAt
        refreshBroadcast()
        if RPScreenRecorder.shared().isAvailable || isStatic {
            screenRecorderAvailable = true
        }
    }

    // MARK: - Import

    func importPicked(_ item: PhotosPickerItem) {
        guard stage == .idle else { return }
        stage = .importing(0)
        camera.stopRunning()
        let progress = item.loadTransferable(type: RecorderPickedMovie.self) { [weak self] result in
            Task { @MainActor in self?.importLoaded(result) }
        }
        importProgress = progress
        importTask?.cancel()
        importTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, case .importing = self.stage else { return }
                self.stage = .importing(progress.fractionCompleted)
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
    }

    func cancelImport() {
        importProgress?.cancel()
        importProgress = nil
        importTask?.cancel()
        if case .importing = stage {
            stage = .idle
            enterMode()
        }
    }

    private func importLoaded(_ result: Result<RecorderPickedMovie?, Error>) {
        importTask?.cancel()
        importProgress = nil
        guard case .importing = stage else {
            if case .success(let movie?) = result { try? FileManager.default.removeItem(at: movie.url) }
            return
        }
        switch result {
        case .success(let movie?):
            let id = UUID()
            let ext = movie.url.pathExtension.isEmpty ? "mov" : movie.url.pathExtension.lowercased()
            let fileName = "\(id.uuidString).\(ext)"
            let staged = library.media.staging.appendingPathComponent(fileName)
            do {
                try? FileManager.default.removeItem(at: staged)
                try FileManager.default.moveItem(at: movie.url, to: staged)
            } catch {
                try? FileManager.default.removeItem(at: movie.url)
                importFailed(error)
                return
            }
            RecordingSaver.shared.begin(RecordingSaveRequest(id: id, kind: .imported, createdAt: Date(), fileName: fileName),
                                        library: library)
            stage = .saving(id)
        case .success(nil):
            importFailed(nil)
        case .failure(let error):
            importFailed(error)
        }
    }

    private func importFailed(_ error: Error?) {
        stage = .idle
        enterMode()
        let outOfSpace = error.map { DiskSpace.isOutOfSpace($0) } ?? false
        alert = RecorderAlert(title: outOfSpace ? "Your iPhone is full" : "Couldn't import this video",
                              message: outOfSpace
                                ? "There isn't enough space to copy this video. Free up some space, then try again."
                                : "This video couldn't be copied from your photo library. Try another one.")
        Haptics.error()
    }

    // MARK: - Saving and review

    /// A recording to review arrived (a screen recording finished, or the app was opened from
    /// its notification).
    func takeReview(_ id: UUID) {
        let inbox = RecorderInbox.shared
        inbox.reviewRequest = nil
        guard !stage.isCapturing, stage != .finishing, let video = library.video(id) else { return }
        if stage.isCountingDown { cancelCountdown() }
        if case .importing = stage { cancelImport() }
        reviewNote = inbox.reviewNote
        inbox.reviewNote = nil
        if video.kind == .screen && mode != .screen {
            mode = .screen
        }
        camera.stopRunning()
        stage = video.state.isReady ? .review(id) : .saving(id)
    }

    /// Moves on to review as soon as the video being saved is ready.
    ///
    /// On build 23 a screen recording stopped from the status-bar pill left the recorder on its
    /// saving screen with the video already saved: a blank page with a spinner, for good. That
    /// hand-over used to depend on the saving screen seeing the change (`onAppear`/`onChange`),
    /// which can miss it when the save finishes while Snapreel is in the background or the
    /// screen is still being presented. The model now watches the library itself.
    private func watchSaving() {
        guard case .saving(let id) = stage, !isStatic else {
            savingWatch = nil
            return
        }
        // objectWillChange fires before the change lands; receive(on:) reads it a moment later.
        savingWatch = library.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.library.video(id)?.state.isReady == true else { return }
                    self.savingFinished(id)
                }
            }
        if library.video(id)?.state.isReady == true {
            Task { @MainActor in self.savingFinished(id) }
        }
    }

    /// The saving screen saw the video become ready.
    func savingFinished(_ id: UUID) {
        guard stage == .saving(id) else { return }
        Haptics.success()
        stage = .review(id)
    }

    func retrySave(_ id: UUID) {
        Haptics.tap()
        RecordingSaver.shared.retry(id, library: library)
    }

    /// Delete from review or from a failed save: back to the recorder for another take.
    func deleteRecording(_ id: UUID) {
        RecordingSaver.shared.discard(id, library: library)
        reviewNote = nil
        stage = .idle
        toast = ToastMessage(text: "Recording deleted", systemImage: "trash.fill")
        enterMode()
    }

    func renameRecording(_ id: UUID, to title: String) {
        library.rename(id, to: title)
        Notifier.shared.cancelScheduled(key: RecordingSaver.reminderKey(id))
    }

    /// Done in review. The recorder closes; the shell shows the toast.
    func finishReview() {
        Haptics.success()
        router.showToast("Saved to your library")
    }

    /// Leave saving running in the background and close.
    func closeWhileSaving() {
        router.showToast("Still saving. It'll be in your library in a moment.", systemImage: "arrow.down.circle.fill")
    }
}
