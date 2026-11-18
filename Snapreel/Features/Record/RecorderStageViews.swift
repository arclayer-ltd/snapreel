import SwiftUI

// MARK: - Camera

/// The viewfinder with countdown, paused veil, speaker notes and the mid-recording flip.
struct RecorderCameraStage: View {
    @EnvironmentObject private var model: RecorderModel
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ZStack {
            if model.primer != .none {
                RecorderPermissionPrimer()
            } else {
                viewfinder
                overlays
            }
        }
    }

    private var viewfinder: some View {
        ZStack {
            Color.srInkDeep
            if let still = model.preset?.cameraStill {
                // Overlay on a clear view so the filled image can't grow the stage past the screen.
                Color.clear
                    .overlay(
                        Image(uiImage: still)
                            .resizable()
                            .scaledToFill()
                    )
                    .clipped()
                    .accessibilityHidden(true)
            } else {
                switch model.cameraState {
                case .running, .starting:
                    RecorderCameraPreview(session: model.camera.session)
                        .accessibilityLabel("Camera preview")
                    if model.cameraState == .starting {
                        ProgressView().tint(.white)
                    }
                case .unavailable(let message):
                    EmptyStateView(systemImage: "video.slash.fill", title: "Camera unavailable",
                                   message: message, onDark: true)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var overlays: some View {
        ZStack {
            if model.stage == .paused {
                Color.black.opacity(0.45)
                    .allowsHitTesting(false)
                VStack(spacing: Space.xs) {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 44, weight: .semibold))
                    Text("Paused").font(.srHeadline)
                }
                .foregroundStyle(.white)
                .accessibilityElement(children: .combine)
            }
            if case .countdown(let remaining) = model.stage {
                RecorderCountdown(remaining: remaining)
            }
            VStack(spacing: 0) {
                Spacer().frame(height: 64)
                if model.speakerNotesVisible {
                    SpeakerNotesOverlay(text: settings.speakerNotes,
                                        isRunning: model.stage == .recording)
                        .padding(.horizontal, Space.s)
                }
                Spacer()
                if model.stage.isCapturing && model.canFlipWhileRecording {
                    HStack {
                        Spacer()
                        CircleIconButton(systemName: "arrow.triangle.2.circlepath.camera", label: "Flip camera",
                                         tone: .glass, size: 44) { model.flipCamera() }
                    }
                    .padding(Space.s)
                }
            }
        }
    }
}

/// Big number before the recording starts. Tap the record button again to cancel.
private struct RecorderCountdown: View {
    let remaining: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
            VStack(spacing: Space.s) {
                Text("\(remaining)")
                    .font(.system(size: 120, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .id(remaining)
                    .transition(reduceMotion ? .opacity : .scale(scale: 1.4).combined(with: .opacity))
                Text("Get ready")
                    .font(.srHeadline)
                    .foregroundStyle(Color.srOnDarkSecondary)
            }
        }
        .animation(Motion.standard, value: remaining)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recording starts in \(remaining)")
    }
}

// MARK: - Audio

/// Voice-only mode: a large timer and the live waveform.
struct RecorderAudioStage: View {
    @EnvironmentObject private var model: RecorderModel
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.srInkRaised, Color.srInk], startPoint: .top, endPoint: .bottom)
            if model.primer != .none {
                RecorderPermissionPrimer()
            } else {
                content
            }
        }
    }

    private var content: some View {
        VStack(spacing: Space.l) {
            Spacer().frame(height: 64)
            if model.speakerNotesVisible {
                SpeakerNotesOverlay(text: settings.speakerNotes, isRunning: model.stage == .recording)
                    .padding(.horizontal, Space.s)
            }
            Spacer(minLength: 0)
            VStack(spacing: Space.xs) {
                Text(Format.clock(model.elapsed))
                    .font(.system(size: 64, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .accessibilityLabel("Recording time \(Format.clock(model.elapsed))")
                Text(caption)
                    .font(.srSubheadline)
                    .foregroundStyle(Color.srOnDarkSecondary)
                    .multilineTextAlignment(.center)
            }
            RecorderWaveformView(meter: model.meter, isActive: model.stage == .recording)
                .frame(height: 120)
                .padding(.horizontal, Space.l)
            if case .countdown(let remaining) = model.stage {
                Text("Starting in \(remaining)…")
                    .font(.srHeadline)
                    .foregroundStyle(Color.srRedGlow)
            }
            Spacer(minLength: 0)
            Label("Stays on this iPhone", systemImage: "lock.fill")
                .font(.srFootnote)
                .foregroundStyle(Color.srOnDarkTertiary)
                .padding(.bottom, Space.l)
        }
    }

    private var caption: String {
        switch model.stage {
        case .recording: return "Recording your voice. You can lock your iPhone, it keeps going."
        case .paused: return "Paused"
        case .finishing: return "Finishing up…"
        default: return "Just your voice. Tap record when you're ready."
        }
    }
}

// MARK: - Permission primer

/// Explains camera and microphone use before iOS asks, or how to turn access back on.
struct RecorderPermissionPrimer: View {
    @EnvironmentObject private var model: RecorderModel

    var body: some View {
        VStack(spacing: Space.l) {
            Spacer()
            icons
            VStack(spacing: Space.s) {
                Text(title)
                    .font(.srTitle)
                    .foregroundStyle(.white)
                Text(message)
                    .font(.srCallout)
                    .foregroundStyle(Color.srOnDarkSecondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Space.xl)
            Spacer()
            VStack(spacing: Space.s) {
                if model.primer == .denied {
                    Button("Open Settings") { Permissions.openSettings() }
                        .buttonStyle(.srPrimary)
                    Button("Record your screen instead") { model.switchMode(to: .screen) }
                        .buttonStyle(.srTertiary)
                } else {
                    Button(model.mode == .camera ? "Allow camera and microphone" : "Allow microphone") {
                        Haptics.tap()
                        model.requestPermissions()
                    }
                    .buttonStyle(.srPrimary)
                }
            }
            .padding(.horizontal, Space.l)
            .padding(.bottom, Space.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.srInkRaised)
    }

    private var icons: some View {
        HStack(spacing: -10) {
            if model.mode == .camera {
                iconCircle(model.primer == .denied ? "video.slash.fill" : "video.fill")
            }
            iconCircle(model.primer == .denied ? "mic.slash.fill" : "mic.fill")
        }
        .accessibilityHidden(true)
    }

    private func iconCircle(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 26, weight: .semibold))
            .foregroundStyle(Color.srRed)
            .frame(width: 72, height: 72)
            .background(Circle().fill(Color.srInkControl))
            .overlay(Circle().strokeBorder(Color.srInkRaised, lineWidth: 4))
    }

    private var title: String {
        switch (model.mode, model.primer) {
        case (.camera, .denied): return "Camera access is off"
        case (_, .denied): return "Microphone access is off"
        case (.camera, _): return "Your camera and microphone"
        default: return "Your microphone"
        }
    }

    private var message: String {
        switch (model.mode, model.primer) {
        case (.camera, .denied):
            return "To record yourself, turn on Camera and Microphone for Snapreel in Settings, then come back."
        case (_, .denied):
            return "To record your voice, turn on Microphone for Snapreel in Settings, then come back."
        case (.camera, _):
            return "Snapreel uses them only while you record. Your recordings stay on this iPhone until you choose to send one."
        default:
            return "Snapreel listens only while you record. Your recordings stay on this iPhone until you choose to send one."
        }
    }
}

// MARK: - Speaker notes overlay

/// Your notes over the preview, scrolling slowly while you record. Drag to move through them.
/// Drawn over the preview only, so they are never in the video.
struct SpeakerNotesOverlay: View {
    let text: String
    let isRunning: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var dragStart: CGFloat?
    private let visibleHeight: CGFloat = 150

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            Label("Speaker notes", systemImage: "text.alignleft")
                .font(.srCaption)
                .foregroundStyle(Color.srOnDarkSecondary)
            notes
        }
        .padding(Space.s)
        .background(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(Color.black.opacity(0.55)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Speaker notes")
        .accessibilityValue(text)
    }

    private var maxOffset: CGFloat { max(0, contentHeight - visibleHeight + 24) }

    private var notes: some View {
        Text(text)
            .font(.system(.title3, design: .default, weight: .semibold))
            .foregroundStyle(.white)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { contentHeight = proxy.size.height }
                        .onChange(of: proxy.size.height) { height in contentHeight = height }
                }
            )
            .offset(y: -offset)
            .frame(height: visibleHeight, alignment: .top)
            .clipped()
            .mask(
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.08),
                    .init(color: .black, location: 0.85),
                    .init(color: .clear, location: 1),
                ], startPoint: .top, endPoint: .bottom)
            )
            .contentShape(Rectangle())
            .gesture(drag)
            .task(id: isRunning) {
                guard isRunning, !reduceMotion else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    if dragStart == nil && offset < maxOffset {
                        offset = min(maxOffset, offset + 1)
                    }
                }
            }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if dragStart == nil { dragStart = offset }
                let start = dragStart ?? offset
                offset = min(maxOffset, max(0, start - value.translation.height))
            }
            .onEnded { _ in
                dragStart = nil
            }
    }
}
