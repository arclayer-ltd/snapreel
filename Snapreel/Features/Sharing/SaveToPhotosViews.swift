import SwiftUI

// MARK: - Question sheet

/// The small sheet for the save-to-Photos stages that ask something: the permission
/// explanation, access off, audio-only and failures. Sized to its content.
@MainActor
struct PhotosQuestionSheet: View {
    let stage: PhotosSaveStage
    let video: Video
    let onPrimary: @MainActor () -> Void
    let onSecondary: @MainActor () -> Void

    @State private var contentHeight: CGFloat = 420
    @State private var bottomSafeArea: CGFloat = 0

    var body: some View {
        ScrollView {
            content
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { contentHeight = proxy.size.height }
                            .onChange(of: proxy.size.height) { newHeight in contentHeight = newHeight }
                    }
                )
        }
        .background(
            GeometryReader { proxy in
                Color.clear.onAppear { bottomSafeArea = proxy.safeAreaInsets.bottom }
            }
        )
        .background(Color.srSurface.ignoresSafeArea())
        .presentationDetents([.height(contentHeight + bottomSafeArea)])
        .presentationDragIndicator(.visible)
    }

    private var content: some View {
        VStack(spacing: Space.l) {
            symbol
            VStack(spacing: Space.xs) {
                Text(copy.title)
                    .font(.srTitle3)
                    .foregroundStyle(Color.srText)
                Text(copy.message)
                    .font(.srSubheadline)
                    .foregroundStyle(Color.srTextSecondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            PhotosVideoChip(video: video)
            if let note = copy.note {
                Label {
                    Text(note)
                } icon: {
                    Image(systemName: "lock.fill")
                }
                .font(.srFootnote)
                .foregroundStyle(Color.srTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            buttons
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.xxl)
        .padding(.bottom, Space.m)
    }

    private var symbol: some View {
        ZStack {
            Circle().fill(Color.srRedSoft)
            Image(systemName: copy.systemImage)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.srRed)
        }
        .frame(width: 64, height: 64)
        .accessibilityHidden(true)
    }

    private var buttons: some View {
        VStack(spacing: Space.xs) {
            Button(copy.primary) {
                Haptics.tap()
                onPrimary()
            }
            .buttonStyle(.srPrimary)
            if let secondary = copy.secondary {
                Button(secondary) { onSecondary() }
                    .buttonStyle(.srTertiary)
                    .frame(height: 44)
            }
        }
    }

    // MARK: Copy

    private struct Copy {
        var systemImage: String
        var title: String
        var message: String
        var note: String? = nil
        var primary: String
        var secondary: String?
    }

    private var spaceMessage: String {
        let free = DiskSpace.available
        let needs = "Photos needs about \(Format.bytes(video.fileSize)) to keep its own copy"
        let has = free > 0 ? ", and this iPhone has \(Format.bytes(free)) free" : ""
        return "\(needs)\(has). Free up some space, or delete recordings you no longer need, then try again."
    }

    private var quotedTitle: String { "\u{201C}\(video.title)\u{201D}" }

    private var copy: Copy {
        switch stage {
        case .permission, .preparing, .saving, .saved:
            return Copy(systemImage: "photo.on.rectangle",
                        title: "Save to your Photos",
                        message: "Next, your iPhone will ask if Snapreel can add to Photos. Choose Allow to keep a copy of \(quotedTitle) there.",
                        note: "Snapreel can only add what you choose. It can't see or change anything already in your library.",
                        primary: "Continue",
                        secondary: "Not now")
        case .denied:
            return Copy(systemImage: "hand.raised.fill",
                        title: "Photos access is off",
                        message: "To save recordings to Photos, open Settings, tap Photos and choose Add Photos Only.",
                        primary: "Open Settings",
                        secondary: "Not now")
        case .audioOnly:
            return Copy(systemImage: "waveform",
                        title: "Audio can't go to Photos",
                        message: "Photos only keeps pictures and videos. Share \(quotedTitle) instead to save it to Files, send it in Messages or open it in another app.",
                        primary: "Share instead",
                        secondary: "Close")
        case .failed(.outOfSpace):
            return Copy(systemImage: "externaldrive.fill.badge.exclamationmark",
                        title: "Not enough space",
                        message: spaceMessage,
                        primary: "Try again",
                        secondary: "Close")
        case .failed(.missingFile):
            return Copy(systemImage: "questionmark.folder",
                        title: "Recording not found",
                        message: "The file for this recording is no longer on this iPhone, so there's nothing to save.",
                        primary: "Close",
                        secondary: nil)
        case .failed(.other(let reason)):
            return Copy(systemImage: "exclamationmark.triangle.fill",
                        title: "Couldn't save to Photos",
                        message: reason,
                        primary: "Try again",
                        secondary: "Close")
        }
    }
}

/// Which recording a sheet is about: thumbnail, title, size and length.
struct PhotosVideoChip: View {
    let video: Video

    var body: some View {
        HStack(spacing: Space.s) {
            VideoThumbnail(video: video, cornerRadius: Radius.s, showsDuration: false)
                .frame(width: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text(video.title)
                    .font(.srSubheadlineStrong)
                    .foregroundStyle(Color.srText)
                    .lineLimit(2)
                Text("\(Format.bytes(video.fileSize)) · \(Format.clock(video.duration))")
                    .font(.srFootnote)
                    .foregroundStyle(Color.srTextSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s)
        .background(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).fill(Color.srCanvas))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Status card

/// Floating card along the bottom edge while a recording is prepared, shared or saved: what is
/// happening, for which recording, how far it is and one button. Follows the appearance like the
/// screen under it, with a hairline and a shadow so it lifts off lists and the player alike.
@MainActor
struct SharingStatusCard: View {
    let video: Video
    let title: String
    let detail: String
    /// 0...1; nil while there is nothing to measure.
    var progress: Double?
    /// A bar under the text: filled to `progress`, or moving when there is none.
    var showsBar = false
    var isDone = false
    var actionTitle: String?
    var actionHint: String?
    var action: (@MainActor () -> Void)?

    static func detail(progress: Double?, of video: Video) -> String {
        guard let progress else { return video.title }
        return "\(Int((min(1, max(0, progress)) * 100).rounded(.down)))% \u{00B7} \(video.title)"
    }

    var body: some View {
        VStack(spacing: Space.s) {
            HStack(spacing: Space.s) {
                thumbnail
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.srSubheadlineStrong)
                        .foregroundStyle(Color.srText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(detail)
                        .font(.srFootnote.monospacedDigit())
                        .foregroundStyle(Color.srTextSecondary)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
                .accessibilityValue(detail)
                Spacer(minLength: Space.xs)
                if let actionTitle, let action {
                    actionButton(actionTitle, action)
                }
            }
            if showsBar { SharingProgressBar(progress: progress) }
        }
        .padding(Space.s)
        .frame(maxWidth: 440)
        .background(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(Color.srSurface))
        .overlay(RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
            .strokeBorder(Color.srLine, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.22), radius: 18, x: 0, y: 8)
    }

    private var thumbnail: some View {
        VideoThumbnail(video: video, cornerRadius: Radius.s, showsDuration: false)
            .frame(width: 52)
            .overlay(alignment: .bottomTrailing) {
                if isDone {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.white, Color.srRed)
                        .offset(x: 5, y: 5)
                        .transition(.scale.combined(with: .opacity))
                }
            }
    }

    private func actionButton(_ label: String, _ action: @escaping @MainActor () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text(label)
                .font(.srSubheadlineStrong)
                .foregroundStyle(isDone ? Color.srOnInverse : Color.srText)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, Space.s)
                .frame(height: 34)
                .background(Capsule().fill(isDone ? Color.srInverse : Color.srFill))
                // A full-size target around the small capsule.
                .padding(.vertical, 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityHint(actionHint ?? "")
    }
}

/// A thin bar: filled to `progress`, or a piece moving along it when the end isn't known.
struct SharingProgressBar: View {
    let progress: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isMoving = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.srFill)
                if let progress {
                    Capsule().fill(Color.srRed)
                        .frame(width: max(4, proxy.size.width * CGFloat(min(1, max(0, progress)))))
                        .animation(.linear(duration: 0.2), value: progress)
                } else {
                    Capsule().fill(Color.srRed.opacity(reduceMotion ? 0.5 : 1))
                        .frame(width: proxy.size.width * (reduceMotion ? 1 : 0.3))
                        .offset(x: reduceMotion ? 0 : (isMoving ? proxy.size.width * 0.7 : 0))
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                                   value: isMoving)
                }
            }
        }
        .frame(height: 4)
        .onAppear { isMoving = true }
        .accessibilityHidden(true)
    }
}

/// Slides a status card up from the bottom edge of a screen.
struct SharingCardOverlay<Card: View>: View {
    let isPresented: Bool
    let bottomInset: CGFloat
    @ViewBuilder let card: () -> Card
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            if isPresented {
                card()
                    .padding(.horizontal, Space.gutter)
                    .padding(.bottom, bottomInset)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : Motion.standard, value: isPresented)
    }
}
