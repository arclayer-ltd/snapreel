import AVFoundation
import SwiftUI

// MARK: - Mode chooser

/// "What do you want to record?" Shown when the recorder opens without a mode (the tab bar's
/// record button, "Start a recording"), so the camera never switches on before the person has
/// asked for it. The last mode used is marked so a repeat take is one tap.
struct RecorderModeChooser: View {
    @EnvironmentObject private var model: RecorderModel
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(spacing: Space.l) {
            Spacer(minLength: 56)
            VStack(spacing: Space.xs) {
                Text("What do you want to record?")
                    .font(.srTitle)
                    .foregroundStyle(.white)
                Text("Nothing turns on until you pick one.")
                    .font(.srCallout)
                    .foregroundStyle(Color.srOnDarkSecondary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, Space.l)
            VStack(spacing: Space.s) {
                ForEach(RecordMode.allCases) { mode in
                    option(mode)
                }
            }
            .padding(.horizontal, Space.m)
            Spacer(minLength: Space.m)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(colors: [Color.srInkRaised, Color.srInk], startPoint: .top, endPoint: .bottom)
        )
    }

    private func option(_ mode: RecordMode) -> some View {
        Button {
            model.chooseMode(mode)
        } label: {
            HStack(spacing: Space.s) {
                Image(systemName: Self.symbol(mode))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.srRedGlow)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Color.srRed.opacity(0.16)))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Space.xs) {
                        Text(mode.label)
                            .font(.srHeadline)
                            .foregroundStyle(.white)
                        if mode == settings.lastRecordMode {
                            Text("Last used")
                                .font(.srCaption)
                                .foregroundStyle(Color.srOnDarkSecondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.white.opacity(0.1)))
                        }
                    }
                    Text(Self.detail(mode))
                        .font(.srSubheadline)
                        .foregroundStyle(Color.srOnDarkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.xs)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.srOnDarkTertiary)
            }
            .padding(Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(Color.srInkControl))
            .contentShape(RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
        }
        .buttonStyle(PressScaleStyle(scale: 0.97))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(mode.label). \(Self.detail(mode))")
        .accessibilityAddTraits(.isButton)
    }

    static func symbol(_ mode: RecordMode) -> String {
        switch mode {
        case .camera: return "video.fill"
        case .screen: return "rectangle.inset.filled.on.rectangle"
        case .audio: return "waveform"
        }
    }

    static func detail(_ mode: RecordMode) -> String {
        switch mode {
        case .camera: return "Talk to the front or back camera."
        case .screen: return "Show anything on your iPhone, with your voice."
        case .audio: return "Just your voice."
        }
    }
}

/// Under the chooser, in place of the record button and the mode switch.
struct RecorderChooserFooter: View {
    @EnvironmentObject private var model: RecorderModel

    var body: some View {
        VStack(spacing: Space.s) {
            Button {
                Haptics.tap()
                model.showsPhotoPicker = true
            } label: {
                Label("Import a video from Photos", systemImage: "photo.on.rectangle")
                    .font(.srSubheadlineStrong)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Space.m)
                    .frame(height: 44)
                    .background(Capsule().fill(Color.srInkControl))
            }
            .buttonStyle(PressScaleStyle())
            Text("Pick one above to start")
                .font(.srFootnote)
                .foregroundStyle(Color.srOnDarkTertiary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 92 + 40 + Space.s)
    }
}

// MARK: - Minimised recording

/// The bar above the tab bar while a voice recording carries on with the recorder swiped
/// away. Tap it to bring the recorder back; pause, resume or stop from here.
struct MinimizedRecordingBar: View {
    @ObservedObject var model: RecorderModel
    @EnvironmentObject private var router: AppRouter

    private var isPaused: Bool { model.stage == .paused }

    var body: some View {
        HStack(spacing: Space.s) {
            RecordingPulse(isLive: model.stage == .recording)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(isPaused ? "Recording paused" : "Recording your voice")
                    .font(.srSubheadlineStrong)
                    .foregroundStyle(Color.srOnDark)
                    .lineLimit(1)
                Text(Format.clock(model.elapsed))
                    .font(.srTimerSmall)
                    .foregroundStyle(Color.srOnDarkSecondary)
            }
            Spacer(minLength: Space.xxs)
            Button {
                Haptics.tap()
                model.togglePause()
            } label: {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel(isPaused ? "Resume recording" : "Pause recording")
            Button {
                model.recordTapped()
                router.expandRecorder()
            } label: {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 14, height: 14)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.srRed))
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel("Stop recording")
        }
        .padding(.leading, Space.xs)
        .padding(.trailing, Space.xs)
        .padding(.vertical, Space.xs)
        .background(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(Color.srInk))
        .clipShape(RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
        .shadow(color: Color.black.opacity(0.22), radius: 14, y: 6)
        .contentShape(RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
        .onTapGesture {
            Haptics.tap()
            router.expandRecorder()
        }
        // The recorder's own event handlers are off screen while minimised.
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { note in
            model.audioInterrupted(note)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recording your voice, \(Format.clock(model.elapsed))")
        .accessibilityAction(named: "Open recorder") { router.expandRecorder() }
    }
}

/// A red dot with a soft ring that breathes while recording.
private struct RecordingPulse: View {
    let isLive: Bool
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.srRed.opacity(0.25))
                .scaleEffect(isLive && expanded && !reduceMotion ? 1 : 0.6)
            Circle()
                .fill(isLive ? Color.srRed : Color.srOnDarkTertiary)
                .frame(width: 14, height: 14)
        }
        .animation(isLive && !reduceMotion ? Animation.easeInOut(duration: 0.9).repeatForever(autoreverses: true) : Animation.default,
                   value: expanded)
        .onAppear { expanded = true }
        .accessibilityHidden(true)
    }
}
