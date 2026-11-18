import ReplayKit
import SwiftUI
import UIKit

/// Screen mode: first-time tutorial, the broadcast step, the can't-record explainer, or the
/// recording in progress.
struct RecorderScreenStage: View {
    @EnvironmentObject private var model: RecorderModel

    var body: some View {
        ZStack {
            Color.srInkRaised
            switch model.screenStep {
            case .tutorial: ScreenTutorialView()
            case .broadcast: BroadcastStepView()
            case .unavailable: ScreenUnavailableView()
            case .inProgress: ScreenRecordingProgressView()
            }
        }
        .animation(Motion.standard, value: model.screenStep)
    }
}

// MARK: - Tutorial

private struct TutorialCard: Identifiable {
    let id: Int
    let title: String
    let message: String
}

private let tutorialCards: [TutorialCard] = [
    TutorialCard(id: 0, title: "Start a screen recording",
                 message: "Tap the record button below, pick Snapreel, then Start Broadcast. Turn on Microphone in that sheet to add your voice."),
    TutorialCard(id: 1, title: "Stop when you're done",
                 message: "Tap the red pill at the top of your screen, or come back to Snapreel and tap Stop."),
    TutorialCard(id: 2, title: "Name it and send it",
                 message: "Back in Snapreel you can give it a title and share the file. The notification brings you straight here."),
]

/// Three swipeable cards with illustrations drawn in Snapreel's own style.
struct ScreenTutorialView: View {
    @EnvironmentObject private var model: RecorderModel

    var body: some View {
        VStack(spacing: Space.m) {
            HStack {
                Spacer()
                Text("Screen recording · \(model.tutorialPage + 1) of \(tutorialCards.count)")
                    .font(.srFootnote)
                    .foregroundStyle(Color.srOnDarkTertiary)
                Spacer()
            }
            .padding(.top, 70)
            TabView(selection: $model.tutorialPage) {
                ForEach(tutorialCards) { card in
                    page(card).tag(card.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            controls
        }
    }

    private var isLastCard: Bool { model.tutorialPage >= tutorialCards.count - 1 }

    /// Page dots, Skip, and a labelled Next / Got it.
    private var controls: some View {
        HStack {
            dots
            Spacer()
            if !isLastCard {
                Button("Skip") { model.finishTutorial() }
                    .font(.srSubheadlineStrong)
                    .foregroundStyle(Color.srOnDarkSecondary)
                    .padding(.trailing, Space.s)
            }
            Button {
                if isLastCard {
                    model.finishTutorial()
                } else {
                    Haptics.selection()
                    withAnimation(Motion.standard) { model.tutorialPage += 1 }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(isLastCard ? "Got it" : "Next")
                    Image(systemName: isLastCard ? "checkmark" : "arrow.right")
                        .font(.system(size: 13, weight: .bold))
                }
            }
            .buttonStyle(.srPrimaryCompact)
        }
        .padding(.horizontal, Space.l)
        .padding(.bottom, Space.m)
        .animation(Motion.quick, value: isLastCard)
    }

    private func page(_ card: TutorialCard) -> some View {
        VStack(spacing: Space.l) {
            TutorialIllustration(step: card.id)
                .frame(width: 240, height: 190)
                .accessibilityHidden(true)
            VStack(spacing: Space.xs) {
                Text(card.title)
                    .font(.srTitle)
                    .foregroundStyle(.white)
                Text(card.message)
                    .font(.srCallout)
                    .foregroundStyle(Color.srOnDarkSecondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Space.xl)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var dots: some View {
        HStack(spacing: 8) {
            ForEach(tutorialCards) { card in
                Capsule()
                    .fill(card.id == model.tutorialPage ? Color.srRed : Color.white.opacity(0.25))
                    .frame(width: card.id == model.tutorialPage ? 20 : 7, height: 7)
            }
        }
        .animation(Motion.quick, value: model.tutorialPage)
        .accessibilityHidden(true)
    }
}

/// Phone sketches for the three tutorial cards.
private struct TutorialIllustration: View {
    let step: Int

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(Color.srInk)
                .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 3))
                .frame(width: 150, height: 230)
            switch step {
            case 0: StartSketch()
            case 1: StopSketch()
            default: ShareSketch()
            }
        }
        .frame(width: 240, height: 190, alignment: .top)
        .clipped()
    }
}

/// The system sheet: Snapreel chosen, a red start button, the microphone toggle.
private struct StartSketch: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "record.circle")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.85))
            HStack(spacing: 6) {
                Image("BrandMark").resizable().scaledToFit().frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                Text("Snapreel").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                    .lineLimit(1).fixedSize()
                Spacer(minLength: 2)
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.srRed)
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.08)))
            Capsule().fill(Color.srRed).frame(height: 26)
                .overlay(Capsule().fill(Color.white.opacity(0.9)).frame(width: 48, height: 5))
            HStack {
                ZStack {
                    Circle().fill(Color.white.opacity(0.14)).frame(width: 30, height: 30)
                    Image(systemName: "mic.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                }
                .overlay(Circle().strokeBorder(Color.srRedGlow, lineWidth: 2).frame(width: 38, height: 38))
                Spacer()
            }
        }
        .padding(10)
        .frame(width: 140)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.srInkControl))
        .padding(.top, 36)
    }
}

/// The red status pill being tapped, with a stop control below.
private struct StopSketch: View {
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                HStack(spacing: 4) {
                    Circle().fill(Color.white).frame(width: 6, height: 6)
                    Text("0:42").font(.system(size: 10, weight: .bold, design: .rounded)).monospacedDigit()
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .frame(height: 18)
                .background(Capsule().fill(Color.srRed))
                .overlay(
                    Circle().strokeBorder(Color.srRedGlow.opacity(0.7), lineWidth: 2)
                        .frame(width: 46, height: 46)
                )
                Spacer()
                RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.5)).frame(width: 18, height: 8)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.18)).frame(width: 90, height: 8)
                RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.12)).frame(width: 60, height: 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            ZStack {
                Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: 3).frame(width: 46, height: 46)
                RoundedRectangle(cornerRadius: 4).fill(Color.srRed).frame(width: 18, height: 18)
            }
        }
        .frame(width: 150)
    }
}

/// A "ready" notification arriving, then the title and share controls.
private struct ShareSketch: View {
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image("BrandMark").resizable().scaledToFit().frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.85)).frame(width: 80, height: 6)
                    RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.4)).frame(width: 110, height: 6)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(width: 196)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.srInkControl))
            .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
            .padding(.top, 22)
            HStack(spacing: 6) {
                Image(systemName: "character.cursor.ibeam").font(.system(size: 11, weight: .semibold))
                RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.5)).frame(width: 64, height: 6)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(width: 124, height: 28)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.1)))
            ZStack {
                Circle().fill(Color.srRed).frame(width: 42, height: 42)
                Image(systemName: "square.and.arrow.up").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
            }
        }
        .frame(width: 220)
    }
}

// MARK: - Broadcast step

/// What will be recorded, the microphone, privacy. The record button below opens the system
/// sheet (it is the broadcast picker).
struct BroadcastStepView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Spacer().frame(height: 52)
            VStack(alignment: .leading, spacing: Space.xs) {
                IconTile(systemName: "rectangle.inset.filled.on.rectangle", tint: .white,
                         background: Color.srRed, size: 44)
                    .padding(.bottom, Space.xxs)
                Text("Record your screen")
                    .font(.srDisplay)
                    .foregroundStyle(.white)
                Text("Snapreel records everything on this iPhone's screen until you stop, in any app.")
                    .font(.srCallout)
                    .foregroundStyle(Color.srOnDarkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: Space.m) {
                BroadcastPoint(systemImage: "bell.slash.fill",
                               title: "Notifications show up too",
                               message: "Turn on Do Not Disturb first if you'd rather keep them out.")
                BroadcastPoint(systemImage: settings.microphoneOnByDefault ? "mic.fill" : "mic.slash.fill",
                               title: settings.microphoneOnByDefault ? "Microphone: on by default" : "Microphone: off by default",
                               message: settings.microphoneOnByDefault
                                ? "Check Microphone is on in the next sheet so your voice is included."
                                : "Leave Microphone off in the next sheet to record screen and app sound only.")
                if DiskSpace.hasRoom(for: 300_000_000) {
                    BroadcastPoint(systemImage: "lock.fill",
                                   title: "Stays on this iPhone",
                                   message: "Nothing is uploaded. You decide who gets the file.")
                } else {
                    BroadcastPoint(systemImage: "externaldrive.fill.badge.exclamationmark",
                                   title: "Your iPhone is almost full",
                                   message: "\(Format.bytes(DiskSpace.available)) left. Snapreel stops a recording before the space runs out and keeps what it has.")
                }
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Label("Tap record below to start", systemImage: "arrow.down")
                    .font(.srFootnote)
                    .foregroundStyle(Color.srOnDarkTertiary)
                Spacer()
            }
            .padding(.bottom, Space.m)
        }
        .padding(.horizontal, Space.l)
    }
}

private struct BroadcastPoint: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.srRedGlow)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.srInkControl))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.srSubheadlineStrong).foregroundStyle(.white)
                Text(message).font(.srFootnote).foregroundStyle(Color.srOnDarkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Unavailable

/// Screen recording can't start (AirPlay, CarPlay, mirroring, Screen Time) or the last one failed.
struct ScreenUnavailableView: View {
    @EnvironmentObject private var model: RecorderModel

    var body: some View {
        VStack(spacing: Space.l) {
            Spacer()
            Image(systemName: "rectangle.on.rectangle.slash")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color.srRed)
                .frame(width: 72, height: 72)
                .background(Circle().fill(Color.srInkControl))
                .accessibilityHidden(true)
            VStack(spacing: Space.xs) {
                Text(model.screenFailure == nil ? "Screen recording can't start right now" : "Screen recording stopped")
                    .font(.srTitle3)
                    .foregroundStyle(.white)
                Text(model.screenFailure ?? "iPhone doesn't record the screen while it's showing on another display, using AirPlay or CarPlay, or when Screen Time doesn't allow it.")
                    .font(.srSubheadline)
                    .foregroundStyle(Color.srOnDarkSecondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Space.l)
            if model.screenFailure == nil {
                VStack(alignment: .leading, spacing: Space.s) {
                    fix("airplayvideo", "Stop AirPlay or Screen Mirroring in Control Centre.")
                    fix("car.fill", "Disconnect from CarPlay.")
                    fix("hourglass", "In Settings › Screen Time › Content & Privacy Restrictions, allow Screen Recording.")
                }
                .padding(Space.m)
                .background(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(Color.srInkControl.opacity(0.6)))
                .padding(.horizontal, Space.l)
            }
            Button("Try again") { model.dismissScreenFailure() }
                .buttonStyle(.srSecondaryCompact)
            Spacer()
        }
    }

    private func fix(_ systemImage: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.srRedGlow)
                .frame(width: 22)
            Text(text)
                .font(.srFootnote)
                .foregroundStyle(Color.srOnDarkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - In progress

/// Shown when Snapreel is open while the screen is being recorded.
struct ScreenRecordingProgressView: View {
    @EnvironmentObject private var model: RecorderModel

    var body: some View {
        VStack(spacing: Space.l) {
            Spacer()
            TimelineView(.periodic(from: .now, by: 1)) { context in
                pill(now: context.date)
            }
            VStack(spacing: Space.xs) {
                Text(model.isStoppingBroadcast ? "Stopping…" : "Snapreel is recording your screen")
                    .font(.srTitle)
                    .foregroundStyle(.white)
                Text("Go to any app and show what you need to. When you're done, tap Stop below or the red pill at the top of the screen.")
                    .font(.srCallout)
                    .foregroundStyle(Color.srOnDarkSecondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Space.xl)
            microphone
            Spacer()
        }
    }

    private func pill(now: Date) -> some View {
        let seconds = model.broadcast.startedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
        return HStack(spacing: Space.xs) {
            Circle().fill(Color.white).frame(width: 9, height: 9)
            Text("Recording \(Format.clock(seconds))")
                .font(.srTimer)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Space.m)
        .frame(height: 38)
        .background(Capsule().fill(Color.srRed))
        .shadow(color: Color.srRed.opacity(0.45), radius: 14, y: 4)
        .accessibilityElement(children: .combine)
    }

    private var microphone: some View {
        let on = model.broadcast.microphoneEnabled
        return HStack(spacing: Space.xs) {
            Image(systemName: on ? "mic.fill" : "mic.slash.fill")
            Text(on ? "Microphone on" : "Microphone off. Your voice isn't being recorded.")
        }
        .font(.srFootnote)
        .foregroundStyle(on ? Color.white : Color.srOnDarkSecondary)
        .padding(.horizontal, Space.s)
        .padding(.vertical, Space.xs)
        .background(Capsule().fill(Color.srInkControl))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Broadcast picker

/// The system screen-broadcast button, made invisible and laid over Snapreel's own record
/// button: the tap goes straight to iOS, which shows its sheet with Snapreel preselected and a
/// microphone switch.
struct BroadcastPickerButton: UIViewRepresentable {
    var onTap: @MainActor () -> Void

    func makeUIView(context: Context) -> BroadcastPickerContainer {
        let view = BroadcastPickerContainer(frame: .zero)
        view.onTap = onTap
        return view
    }

    func updateUIView(_ uiView: BroadcastPickerContainer, context: Context) {
        uiView.onTap = onTap
    }
}

final class BroadcastPickerContainer: UIView {
    var onTap: (@MainActor () -> Void)?
    private let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 76, height: 76))
    private weak var hookedButton: UIButton?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        picker.preferredExtension = AppGroup.broadcastExtensionBundleID
        picker.showsMicrophoneButton = true
        picker.backgroundColor = .clear
        // Nearly transparent but still tappable (UIKit ignores views below 0.01).
        picker.alpha = 0.02
        addSubview(picker)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        picker.frame = bounds
        for case let button as UIButton in picker.subviews {
            button.frame = picker.bounds
            if hookedButton !== button {
                hookedButton = button
                button.addTarget(self, action: #selector(pickerTapped), for: .touchUpInside)
                button.accessibilityLabel = "Record screen"
                button.accessibilityHint = "Opens the screen recording sheet"
            }
        }
    }

    @objc private func pickerTapped() {
        onTap?()
    }
}
