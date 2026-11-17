import AVFoundation
import PhotosUI
import SwiftUI

/// Session B owns this file. Full-screen recorder with Camera / Screen / Audio modes,
/// presented by the shell for `router.recorder`.
struct RecorderView: View {
    let launch: RecorderLaunch
    var preset: RecorderPreset?

    @EnvironmentObject private var library: Library
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: AppRouter

    init(launch: RecorderLaunch) {
        self.launch = launch
        self.preset = nil
    }

    /// Opens straight into a state, without touching the camera or microphone (debug screens).
    init(launch: RecorderLaunch, preset: RecorderPreset?) {
        self.launch = launch
        self.preset = preset
    }

    var body: some View {
        RecorderContainer(launch: launch, preset: preset, library: library, settings: settings, router: router)
    }
}

/// Owns the model for the recorder's lifetime.
private struct RecorderContainer: View {
    @StateObject private var model: RecorderModel

    init(launch: RecorderLaunch, preset: RecorderPreset?, library: Library, settings: AppSettings, router: AppRouter) {
        _model = StateObject(wrappedValue: RecorderModel(launch: launch, library: library, settings: settings,
                                                         router: router, preset: preset))
    }

    var body: some View {
        RecorderScreen()
            .environmentObject(model)
    }
}

private struct RecorderScreen: View {
    @EnvironmentObject private var model: RecorderModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var pickedItem: PhotosPickerItem?

    var body: some View {
        ZStack {
            Color.srInk.ignoresSafeArea()
            content
        }
        .preferredColorScheme(.dark)
        .modifier(RecorderPresentations(pickedItem: $pickedItem))
        .modifier(RecorderEvents())
        .toast($model.toast, bottomInset: 150)
    }

    @ViewBuilder private var content: some View {
        switch model.stage {
        case .saving(let id):
            RecordingSavingView(videoID: id, close: { closeWhileSaving() })
                .transition(.opacity)
        case .review(let id):
            RecordingReviewView(videoID: id, initialPanel: model.initialReviewPanel, done: { finishReview() })
                .id(id)
                .transition(.opacity)
        case .importing(let progress):
            RecorderImportProgressView(progress: progress)
                .transition(.opacity)
        default:
            RecorderCaptureLayout(close: { close() })
                .transition(.opacity)
        }
    }

    private func close() {
        if model.prepareToClose() { dismiss() }
    }

    private func closeWhileSaving() {
        model.closeWhileSaving()
        dismiss()
    }

    private func finishReview() {
        model.finishReview()
        dismiss()
    }
}

/// Sheets, the photo picker, confirmations and alerts.
private struct RecorderPresentations: ViewModifier {
    @EnvironmentObject private var model: RecorderModel
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @Binding var pickedItem: PhotosPickerItem?

    func body(content: Content) -> some View {
        content
            .sheet(item: $model.sheet) { sheet in
                sheetView(sheet)
                    .environmentObject(library)
                    .environmentObject(settings)
                    .environmentObject(router)
            }
            .photosPicker(isPresented: $model.showsPhotoPicker, selection: $pickedItem,
                          matching: .videos, preferredItemEncoding: .current)
            .onChange(of: pickedItem) { item in
                guard let item else { return }
                pickedItem = nil
                model.importPicked(item)
            }
            .confirmationDialog("Start this recording again?", isPresented: $model.confirmsRestart,
                                titleVisibility: .visible) {
                Button("Discard and start again", role: .destructive) { model.restart() }
                Button("Keep recording", role: .cancel) {}
            } message: {
                Text("What you've recorded so far will be thrown away.")
            }
            .confirmationDialog("Discard this recording?", isPresented: $model.confirmsDiscard,
                                titleVisibility: .visible) {
                Button("Discard recording", role: .destructive) {
                    model.discardAndClose()
                    dismiss()
                }
                Button("Keep recording", role: .cancel) {}
            } message: {
                Text("If you close now, this take won't be saved.")
            }
            .alert("Your iPhone is almost full", isPresented: $model.showsLowSpaceWarning) {
                Button("Record anyway") { model.requestStart(skipSpaceCheck: true) }
                Button("Free up space") { model.sheet = .storage }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("There's \(Format.bytes(DiskSpace.available)) left, so a long recording may not save.")
            }
            .alert(model.alert?.title ?? "", isPresented: alertShown, presenting: model.alert) { alert in
                if alert.opensSettings {
                    Button("Open Settings") { Permissions.openSettings() }
                    Button("Not now", role: .cancel) {}
                } else {
                    Button("OK", role: .cancel) {}
                }
            } message: { alert in
                Text(alert.message)
            }
    }

    private var alertShown: Binding<Bool> {
        Binding(get: { model.alert != nil }, set: { shown in if !shown { model.alert = nil } })
    }

    @ViewBuilder private func sheetView(_ sheet: RecorderSheet) -> some View {
        switch sheet {
        case .settings:
            RecordingSettingsSheet()
        case .notes:
            SpeakerNotesSheet()
        case .storage:
            NavigationStack {
                StorageView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { model.sheet = nil }
                        }
                    }
            }
            .preferredColorScheme(.light)
        }
    }
}

/// App, capture-session and audio-session events, and broadcast hand-offs.
private struct RecorderEvents: ViewModifier {
    @EnvironmentObject private var model: RecorderModel
    @EnvironmentObject private var settings: AppSettings

    func body(content: Content) -> some View {
        content
            .onAppear { model.appear() }
            .onDisappear { model.disappear() }
            .onReceive(RecorderInbox.shared.$reviewRequest) { id in
                if let id { model.takeReview(id) }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                model.appWillResignActive()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                model.appDidBecomeActive()
            }
            .onReceive(NotificationCenter.default.publisher(for: AVCaptureSession.wasInterruptedNotification)) { _ in
                model.captureInterrupted()
            }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { note in
                model.audioInterrupted(note)
            }
            .onChange(of: settings.recordingQuality) { _ in model.cameraSettingsChanged() }
            .onChange(of: settings.mirrorFrontCamera) { _ in model.cameraSettingsChanged() }
    }
}

// MARK: - Capture layout

/// The stage (camera, audio or screen) with the top bar, then the record controls and the
/// mode switch.
private struct RecorderCaptureLayout: View {
    @EnvironmentObject private var model: RecorderModel
    let close: @MainActor () -> Void

    var body: some View {
        VStack(spacing: Space.s) {
            ZStack(alignment: .top) {
                stage
                RecorderTopBar(close: close)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
            RecorderControlsRow()
            RecorderModeRow()
        }
        .padding(.horizontal, Space.xs)
        .padding(.top, Space.xxs)
        .padding(.bottom, Space.xs)
    }

    @ViewBuilder private var stage: some View {
        switch model.mode {
        case .camera: RecorderCameraStage()
        case .audio: RecorderAudioStage()
        case .screen: RecorderScreenStage()
        }
    }
}

/// Close on the left, the timer in the middle, mode tools on the right.
private struct RecorderTopBar: View {
    @EnvironmentObject private var model: RecorderModel
    let close: @MainActor () -> Void

    var body: some View {
        ZStack {
            HStack(spacing: Space.xs) {
                CircleIconButton(systemName: "xmark", label: "Close recorder", tone: .glass, size: 40) { close() }
                Spacer()
                tools
            }
            if showsTimer {
                RecorderTimerPill(elapsed: model.elapsed, stage: model.stage)
            }
        }
        .padding(.horizontal, Space.s)
        .padding(.top, Space.s)
    }

    private var showsTimer: Bool {
        model.mode == .camera && model.primer == .none
    }

    @ViewBuilder private var tools: some View {
        let capturing = model.stage.isCapturing
        switch model.mode {
        case .camera:
            if model.primer == .none && !capturing {
                CircleIconButton(systemName: model.recordsCameraSound ? "mic.fill" : "mic.slash.fill",
                                 label: model.recordsCameraSound ? "Microphone on" : "Microphone off",
                                 tone: .glass, size: 40) { model.toggleMicrophone() }
            }
            if !capturing {
                CircleIconButton(systemName: "square.and.pencil", label: "Speaker notes", tone: .glass, size: 40) {
                    model.sheet = .notes
                }
                CircleIconButton(systemName: "gearshape", label: "Recording settings", tone: .glass, size: 40) {
                    model.sheet = .settings
                }
            }
        case .audio:
            if !capturing {
                CircleIconButton(systemName: "square.and.pencil", label: "Speaker notes", tone: .glass, size: 40) {
                    model.sheet = .notes
                }
                CircleIconButton(systemName: "gearshape", label: "Recording settings", tone: .glass, size: 40) {
                    model.sheet = .settings
                }
            }
        case .screen:
            if model.screenStep == .broadcast {
                CircleIconButton(systemName: "questionmark", label: "How screen recording works", tone: .glass, size: 40) {
                    model.showTutorial()
                }
            }
            if model.screenStep != .inProgress {
                CircleIconButton(systemName: "gearshape", label: "Recording settings", tone: .glass, size: 40) {
                    model.sheet = .settings
                }
            }
        }
    }
}

/// "0:00" while ready, "● 1:23" while recording, "Paused 1:23" while paused.
struct RecorderTimerPill: View {
    let elapsed: TimeInterval
    let stage: RecorderStage

    var body: some View {
        HStack(spacing: 6) {
            if stage == .recording {
                Circle().fill(Color.srRed).frame(width: 8, height: 8)
            } else if stage == .paused {
                Image(systemName: "pause.fill").font(.system(size: 9, weight: .bold))
            }
            Text(Format.clock(elapsed))
                .font(.srTimer)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Space.s)
        .frame(height: 30)
        .background(Capsule().fill(stage == .recording ? Color.srRed.opacity(0.28) : Color.black.opacity(0.42)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stage == .paused ? "Paused at \(Format.clock(elapsed))"
                                             : "Recording time \(Format.clock(elapsed))")
    }
}

// MARK: - Controls

/// Import on the left, the big record button in the middle, flip (or pause) on the right.
private struct RecorderControlsRow: View {
    @EnvironmentObject private var model: RecorderModel

    var body: some View {
        HStack(spacing: 0) {
            leading
                .frame(width: 64, height: 64)
            Spacer(minLength: 0)
            center
            Spacer(minLength: 0)
            trailing
                .frame(width: 64, height: 64)
        }
        .padding(.horizontal, Space.l)
        .frame(height: 92)
    }

    // MARK: Slots

    @ViewBuilder private var leading: some View {
        if model.stage.isCapturing {
            RecorderSideButton(systemName: "arrow.counterclockwise", title: "Restart") {
                model.confirmsRestart = true
            }
        } else if model.stage == .idle && !(model.mode == .screen && model.screenStep == .inProgress) {
            RecorderSideButton(systemName: "photo.on.rectangle", title: "Import") {
                model.showsPhotoPicker = true
            }
        }
    }

    @ViewBuilder private var center: some View {
        switch model.mode {
        case .camera, .audio:
            captureButton
        case .screen:
            screenButton
        }
    }

    @ViewBuilder private var trailing: some View {
        if model.stage.isCapturing {
            RecorderSideButton(systemName: model.stage == .paused ? "play.fill" : "pause.fill",
                               title: model.stage == .paused ? "Resume" : "Pause") {
                model.togglePause()
            }
        } else if model.mode == .camera && model.stage == .idle && model.primer == .none {
            RecorderSideButton(systemName: "arrow.triangle.2.circlepath.camera", title: "Flip") {
                model.flipCamera()
            }
        }
    }

    // MARK: Record buttons

    @ViewBuilder private var captureButton: some View {
        if model.primer != .none {
            Color.clear.frame(width: 76, height: 76)
        } else if model.stage == .finishing {
            ProgressView()
                .tint(.white)
                .frame(width: 76, height: 76)
                .accessibilityLabel("Finishing the recording")
        } else {
            Button {
                model.recordTapped()
            } label: {
                RecordButtonShape(isRecording: model.stage.isCapturing, diameter: 76)
            }
            .buttonStyle(PressScaleStyle(scale: 0.92))
            .disabled(model.mode == .camera && model.cameraState != .running && !model.stage.isCapturing)
            .accessibilityLabel(recordLabel)
        }
    }

    private var recordLabel: String {
        switch model.stage {
        case .recording, .paused: return "Stop recording"
        case .countdown: return "Cancel countdown"
        default: return model.mode == .audio ? "Start audio recording" : "Start camera recording"
        }
    }

    @ViewBuilder private var screenButton: some View {
        switch model.screenStep {
        case .inProgress:
            Button {
                model.stopBroadcast()
            } label: {
                ZStack {
                    RecordButtonShape(isRecording: true, diameter: 76)
                    if model.isStoppingBroadcast {
                        Circle().fill(Color.srInk.opacity(0.6))
                        ProgressView().tint(.white)
                    }
                }
                .frame(width: 76, height: 76)
            }
            .buttonStyle(PressScaleStyle(scale: 0.92))
            .disabled(model.isStoppingBroadcast)
            .accessibilityLabel("Stop screen recording")
        case .unavailable:
            RecordButtonShape(isRecording: false, diameter: 76)
                .opacity(0.35)
                .accessibilityLabel("Screen recording unavailable")
        case .tutorial, .broadcast:
            ZStack {
                RecordButtonShape(isRecording: false, diameter: 76)
                    .accessibilityHidden(true)
                if !model.isStatic {
                    BroadcastPickerButton(onTap: { model.broadcastPickerTapped() })
                        .frame(width: 76, height: 76)
                }
            }
            .frame(width: 76, height: 76)
            .accessibilityElement(children: model.isStatic ? .ignore : .contain)
            .accessibilityLabel("Record screen")
        }
    }
}

/// Small round button with a caption under it.
private struct RecorderSideButton: View {
    let systemName: String
    let title: String
    let action: @MainActor () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemName)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.srInkControl))
                Text(title)
                    .font(.srCaption)
                    .foregroundStyle(Color.srOnDarkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }
}

/// Camera / Screen / Audio switch, or what's happening while a take is running.
private struct RecorderModeRow: View {
    @EnvironmentObject private var model: RecorderModel

    var body: some View {
        ZStack {
            if model.stage.isCapturing || model.stage == .finishing {
                Text(statusText)
                    .font(.srSubheadlineStrong)
                    .foregroundStyle(Color.srOnDarkSecondary)
                    .transition(.opacity)
            } else {
                PillSwitch(options: RecordMode.allCases, selection: modeBinding, title: { $0.label })
                    .disabled(model.mode == .screen && model.screenStep == .inProgress)
                    .transition(.opacity)
            }
        }
        .frame(height: 40)
        .animation(Motion.quick, value: model.stage)
    }

    private var statusText: String {
        switch model.stage {
        case .paused: return "Paused. Resume or stop when you're ready."
        case .finishing: return "Finishing up…"
        default: return model.mode == .audio ? "Recording your voice" : "Recording"
        }
    }

    private var modeBinding: Binding<RecordMode> {
        Binding(get: { model.mode }, set: { model.switchMode(to: $0) })
    }
}
