import SwiftUI
import UIKit
import UserNotifications

/// The stops of the guided tour. Steps 1–4 spotlight a tab bar item.
enum TourStep: Int, CaseIterable, Hashable {
    case intro
    case home
    case library
    case record
    case notifications

    /// The tab bar item this step points at.
    var tab: AppTab? {
        switch self {
        case .intro: return nil
        case .home: return .home
        case .library: return .library
        case .record: return .record
        case .notifications: return .notifications
        }
    }

    /// 1...4 for the spotlight steps.
    var number: Int { rawValue }
    static let stepCount = 4

    var title: String {
        switch self {
        case .intro: return "Let's show you around"
        case .home: return "Pick up where you left off"
        case .library: return "Everything in one place"
        case .record: return "Record in one tap"
        case .notifications: return "Know when it's ready"
        }
    }

    var message: String {
        switch self {
        case .intro:
            return "Four quick stops, then you're ready to make your first recording."
        case .home:
            return "Home brings together your newest recordings, your Watch later list and what you watched recently."
        case .library:
            return "Library keeps every recording you make. Sort them into folders, add tags and find them fast."
        case .record:
            return "The red button records your screen, your camera or just your voice. Each recording saves straight to this iPhone."
        case .notifications:
            return "We'll tell you when a recording is saved, a transcript is ready or space is running low. Nothing else."
        }
    }

    var character: CharacterClip? {
        switch self {
        case .intro: return .tour
        case .notifications: return .notify
        default: return nil
        }
    }

    var next: TourStep? { TourStep(rawValue: rawValue + 1) }
}

#if DEBUG
/// Lets a debug entry open the tour at a given step (the shell builds the overlay itself).
enum TourDebug {
    @MainActor static var start: TourStep? = nil
    /// Starts the notification permission request on appear, so the system alert shows.
    @MainActor static var requestsPermission = false
}
#endif

/// Four-step tour over the real tab shell, shown once after onboarding. The shell is dimmed,
/// the current tab bar item is spotlit, and a card above the bar explains it. The last step
/// asks for notification permission, then calls `onFinish` either way.
/// `targets` are the tab bar items' frames in the overlay's full-screen coordinates.
struct GuidedTourOverlay: View {
    let targets: [AppTab: CGRect]
    let onFinish: @MainActor () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: TourStep
    @State private var isRequesting = false
    @State private var notificationsAlreadyOn = false
    @State private var notificationsDenied = false

    init(targets: [AppTab: CGRect], initialStep: TourStep = .intro, onFinish: @escaping @MainActor () -> Void) {
        self.targets = targets
        self.onFinish = onFinish
        _step = State(initialValue: initialStep)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                dimming(size: proxy.size)
                spotlightButton
                cardLayer(size: proxy.size)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .onAppear { applyDebugStart() }
        .task(id: step) { await refreshNotificationState() }
    }

    // MARK: Spotlight

    private var stepAnimation: Animation? {
        reduceMotion ? Animation.easeOut(duration: 0.2) : Motion.standard
    }

    private func dimming(size: CGSize) -> some View {
        SpotlightShape(hole: hole, cornerRadius: holeRadius)
            .fill(Color.black.opacity(0.6), style: FillStyle(eoFill: true))
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .onTapGesture {}
            .animation(stepAnimation, value: step)
            .accessibilityHidden(true)
    }

    /// Tapping the lit-up item moves on (except on the permission step, which needs a choice).
    @ViewBuilder private var spotlightButton: some View {
        if step.tab != nil, step != .notifications, hole.width > 0 {
            ZStack {
                if !reduceMotion {
                    PulseRing(cornerRadius: holeRadius)
                }
            }
            .frame(width: hole.width, height: hole.height)
            .contentShape(Rectangle())
            .onTapGesture { advance() }
            .offset(x: hole.minX, y: hole.minY)
            .accessibilityHidden(true)
        }
    }

    /// The hole around the current target. Before the first stop it is a point on Home, so it
    /// opens out from there.
    private var hole: CGRect {
        let tab: AppTab = step.tab ?? .home
        guard let frame = targets[tab] else { return .zero }
        if step == .intro {
            return CGRect(x: frame.midX, y: frame.midY, width: 0, height: 0)
        }
        if tab == .record {
            // The record button draws 10 pt above its layout frame (see SnapreelTabBar).
            let diameter: CGFloat = 70
            return CGRect(x: frame.midX - diameter / 2, y: frame.midY - 10 - diameter / 2,
                          width: diameter, height: diameter)
        }
        let width = min(frame.width, 72)
        let height = frame.height + 8
        return CGRect(x: frame.midX - width / 2, y: frame.midY - height / 2, width: width, height: height)
    }

    private var holeRadius: CGFloat {
        step.tab == .record ? 35 : 16
    }

    // MARK: Card

    /// Top of the tab bar artwork (the raised record button), in overlay coordinates.
    private func barTop(size: CGSize) -> CGFloat {
        guard let top = targets.values.map(\.minY).min() else { return size.height - 110 }
        return top - 10
    }

    private func cardLayer(size: CGSize) -> some View {
        let bottomGap = size.height - barTop(size: size) + 28
        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            card(width: size.width - Space.m * 2)
                .padding(.horizontal, Space.m)
                .padding(.bottom, max(bottomGap, Space.xl))
        }
        .frame(width: size.width, height: size.height)
    }

    private func card(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if let clip = step.character {
                characterPanel(clip)
            }
            if step == .intro {
                Label("Takes about 20 seconds", systemImage: "clock")
                    .font(.srCaption)
                    .foregroundStyle(Color.srTextSecondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(step.title)
                    .font(.srTitle)
                    .foregroundStyle(Color.srText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(step.message)
                    .font(.srSubheadline)
                    .foregroundStyle(Color.srTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            footer
        }
        .padding(Space.l)
        .frame(width: width, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(Color.srSurface)
        )
        .overlay(alignment: .bottomLeading) { pointer(cardWidth: width) }
        .shadow(color: Color.black.opacity(0.25), radius: 24, y: 10)
        .animation(stepAnimation, value: step)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private func characterPanel(_ clip: CharacterClip) -> some View {
        let side: CGFloat = clip == .tour ? 196 : 176
        return ZStack {
            clip.background
            CharacterView(clip: clip, cornerRadius: 0)
                .frame(width: side, height: side)
        }
        .frame(maxWidth: .infinity)
        .frame(height: side * 0.76)
        .clipShape(RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
        .id(clip)
        .transition(.opacity)
    }

    /// Small arrow under the card pointing at the lit-up item.
    @ViewBuilder private func pointer(cardWidth: CGFloat) -> some View {
        if let tab = step.tab, let frame = targets[tab] {
            let x = min(max(frame.midX - Space.m, 28), cardWidth - 28)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.srSurface)
                .frame(width: 18, height: 18)
                .rotationEffect(.degrees(45))
                .offset(x: x - 9, y: 8)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var footer: some View {
        switch step {
        case .intro:
            HStack {
                Button("Skip") { finish(success: false) }
                    .font(.srSubheadlineStrong)
                    .foregroundStyle(Color.srTextSecondary)
                    .accessibilityHint("Skips the tour")
                Spacer()
                Button("Show me around") { advance() }
                    .buttonStyle(.srPrimaryCompact)
            }
            .padding(.top, Space.xxs)
        case .home, .library, .record:
            HStack {
                TourProgress(current: step.number, total: TourStep.stepCount)
                Spacer()
                Button("Next") { advance() }
                    .buttonStyle(.srPrimaryCompact)
            }
            .padding(.top, Space.xxs)
        case .notifications:
            notificationFooter
        }
    }

    private var notificationFooter: some View {
        VStack(spacing: Space.s) {
            TourProgress(current: step.number, total: TourStep.stepCount)
                .frame(maxWidth: .infinity, alignment: .leading)
            if notificationsAlreadyOn {
                Button("Finish") { finish(success: true) }
                    .buttonStyle(.srPrimary)
            } else if notificationsDenied {
                Button("Turn on in Settings") {
                    Permissions.openSettings()
                    finish(success: false)
                }
                .buttonStyle(.srPrimary)
                Button("Not now") { finish(success: false) }
                    .buttonStyle(.srTertiary)
            } else {
                Button {
                    requestNotifications()
                } label: {
                    HStack(spacing: Space.xs) {
                        if isRequesting {
                            ProgressView().tint(.white)
                        }
                        Text("Turn on notifications")
                    }
                }
                .buttonStyle(.srPrimary)
                .disabled(isRequesting)
                Button("Not now") { finish(success: false) }
                    .buttonStyle(.srTertiary)
                    .disabled(isRequesting)
            }
        }
        .padding(.top, Space.xxs)
    }

    // MARK: Actions

    private func advance() {
        guard let next = step.next else { return }
        Haptics.selection()
        withAnimation(stepAnimation) { step = next }
        UIAccessibility.post(notification: .screenChanged, argument: nil)
    }

    private func requestNotifications() {
        guard !isRequesting else { return }
        isRequesting = true
        Task { @MainActor in
            let allowed = await Notifier.shared.requestAuthorization()
            isRequesting = false
            finish(success: allowed)
        }
    }

    private func finish(success: Bool) {
        if success { Haptics.success() } else { Haptics.tap() }
        onFinish()
    }

    @MainActor
    private func refreshNotificationState() async {
        guard step == .notifications else { return }
        let status = await Notifier.shared.authorizationStatus()
        notificationsAlreadyOn = status == .authorized || status == .provisional || status == .ephemeral
        notificationsDenied = status == .denied
    }

    private func applyDebugStart() {
        #if DEBUG
        guard let start = TourDebug.start else { return }
        TourDebug.start = nil
        step = start
        if TourDebug.requestsPermission {
            TourDebug.requestsPermission = false
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 800_000_000)
                requestNotifications()
            }
        }
        #endif
    }
}

// MARK: - Pieces

/// The dimmed layer with a rounded hole cut out. The hole animates between targets.
struct SpotlightShape: Shape {
    var hole: CGRect
    var cornerRadius: CGFloat

    var animatableData: AnimatablePair<CGRect.AnimatableData, CGFloat> {
        get { AnimatablePair(hole.animatableData, cornerRadius) }
        set {
            hole.animatableData = newValue.first
            cornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        if hole.width > 0.5, hole.height > 0.5 {
            let radius = min(cornerRadius, min(hole.width, hole.height) / 2)
            path.addRoundedRect(in: hole, cornerSize: CGSize(width: radius, height: radius), style: .continuous)
        }
        return path
    }
}

/// A soft ring that keeps expanding out of the spotlight to draw the eye.
struct PulseRing: View {
    let cornerRadius: CGFloat
    @State private var expanded = false

    init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(Color.white.opacity(0.9), lineWidth: 2)
            .scaleEffect(expanded ? 1.28 : 1)
            .opacity(expanded ? 0 : 0.8)
            .onAppear {
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                    expanded = true
                }
            }
    }
}

/// "Step 2 of 4" as four short bars.
struct TourProgress: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(1...max(total, 1), id: \.self) { index in
                Capsule()
                    .fill(index <= current ? Color.srRed : Color.srFill)
                    .frame(width: 18, height: 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current) of \(total)")
    }
}
