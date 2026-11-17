import SwiftUI

/// The player's "…" sheet: edit title, save to Photos, share, watch later, stats, delete.
/// Delete asks first, inside the same sheet.
struct PlayerActionsSheet: View {
    enum Action {
        case editTitle
        case saveToPhotos
        case share
        case toggleWatchLater
        case stats
        case delete
    }

    let video: Video
    let onChoose: @MainActor (Action) -> Void
    let onClose: @MainActor () -> Void

    @State private var confirmingDelete: Bool

    init(video: Video, startsConfirmingDelete: Bool = false,
         onChoose: @escaping @MainActor (Action) -> Void,
         onClose: @escaping @MainActor () -> Void) {
        self.video = video
        self.onChoose = onChoose
        self.onClose = onClose
        _confirmingDelete = State(initialValue: startsConfirmingDelete)
    }

    var body: some View {
        ZStack {
            Color.srInkRaised.ignoresSafeArea()
            if confirmingDelete {
                deleteConfirmation
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                menu
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
    }

    // MARK: - Menu

    private var menu: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, Space.gutter)
                .padding(.top, Space.l)
                .padding(.bottom, Space.m)
            Rectangle().fill(Color.srInkLine).frame(height: 0.5)
            ScrollView {
                VStack(spacing: 0) {
                    ActionRow(systemImage: "pencil", title: "Edit title") { onChoose(.editTitle) }
                    ActionRow(systemImage: "square.and.arrow.down", title: "Save to Photos",
                              subtitle: video.isAudioOnly ? "Audio recordings can't go to Photos. Share the file instead." : nil) {
                        onChoose(.saveToPhotos)
                    }
                    ActionRow(systemImage: "square.and.arrow.up", title: "Share",
                              subtitle: "Send the file with AirDrop, Messages, Mail or any app") {
                        onChoose(.share)
                    }
                    ActionRow(systemImage: video.isInWatchLater ? "clock.badge.checkmark" : "clock",
                              title: video.isInWatchLater ? "Remove from Watch later" : "Add to Watch later") {
                        onChoose(.toggleWatchLater)
                    }
                    ActionRow(systemImage: "chart.bar", title: "Stats",
                              subtitle: "Plays, shares and how far you got") {
                        onChoose(.stats)
                    }
                    Rectangle().fill(Color.srInkLine).frame(height: 0.5).padding(.vertical, Space.xs)
                    ActionRow(systemImage: "trash", title: "Delete recording", isDestructive: true) {
                        Haptics.warning()
                        withAnimation(Motion.standard) { confirmingDelete = true }
                    }
                }
                .padding(.vertical, Space.xs)
            }
        }
    }

    private var header: some View {
        HStack(spacing: Space.s) {
            VideoThumbnail(video: video, cornerRadius: Radius.s, showsDuration: false)
                .frame(width: 88)
            VStack(alignment: .leading, spacing: 3) {
                Text(video.title)
                    .font(.srHeadline)
                    .foregroundStyle(Color.srOnDark)
                    .lineLimit(2)
                Text("\(Format.clock(video.duration)) · \(Format.date(video.createdAt))")
                    .font(.srFootnote)
                    .foregroundStyle(Color.srOnDarkSecondary)
            }
            Spacer(minLength: Space.xs)
            CircleIconButton(systemName: "xmark", label: "Close", tone: .dark, size: 32) { onClose() }
        }
    }

    // MARK: - Delete

    private var deleteConfirmation: some View {
        VStack(spacing: Space.m) {
            Spacer(minLength: Space.l)
            ZStack {
                Circle().fill(Color.srRed.opacity(0.16))
                Image(systemName: "trash.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.srRed)
            }
            .frame(width: 64, height: 64)
            VStack(spacing: Space.xs) {
                Text("Delete this recording?")
                    .font(.srTitle)
                    .foregroundStyle(Color.srOnDark)
                Text("This removes the video, its notes and transcript from this iPhone.")
                    .font(.srSubheadline)
                    .foregroundStyle(Color.srOnDarkSecondary)
                Text("\u{201C}\(video.title)\u{201D}")
                    .font(.srFootnote)
                    .foregroundStyle(Color.srOnDarkTertiary)
                    .lineLimit(1)
                    .padding(.top, Space.xxs)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Space.m)
            VStack(spacing: Space.s) {
                Button("Delete recording") { onChoose(.delete) }
                    .buttonStyle(.srPrimary)
                Button("Keep it") {
                    withAnimation(Motion.standard) { confirmingDelete = false }
                }
                .buttonStyle(.srSecondary)
            }
        }
        .padding(.horizontal, Space.gutter)
        .padding(.bottom, Space.l)
    }
}

private struct ActionRow: View {
    let systemImage: String
    let title: String
    var subtitle: String? = nil
    var isDestructive = false
    let action: @MainActor () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: Space.s) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isDestructive ? Color.srRed : Color.srOnDark)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isDestructive ? Color.srRed.opacity(0.16) : Color.srInkControl)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.srBody)
                        .foregroundStyle(isDestructive ? Color.srRedGlow : Color.srOnDark)
                    if let subtitle {
                        Text(subtitle)
                            .font(.srFootnote)
                            .foregroundStyle(Color.srOnDarkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.vertical, Space.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
    }
}
