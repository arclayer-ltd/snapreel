import SwiftUI

/// One feed row: kind icon (with the unread dot), title, body, age and what a tap does, plus the
/// recording's thumbnail when the row is about one.
struct NotificationRow: View {
    let item: AppNotification
    /// The recording the row points at, if it still exists.
    let video: Video?

    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            icon
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(item.isRead ? Font.srBody : Font.srHeadline)
                    .foregroundStyle(Color.srText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.body)
                    .font(.srSubheadline)
                    .foregroundStyle(Color.srTextSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                meta
                    .padding(.top, 2)
            }
            Spacer(minLength: Space.xs)
            if let video {
                VideoThumbnail(video: video, cornerRadius: Radius.s, showsDuration: false)
                    .frame(width: 76)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityHint(spokenHint)
    }

    private var icon: some View {
        IconTile(systemName: item.kind.systemImage,
                 tint: item.isRead ? Color.srTextSecondary : Color.srRed,
                 background: item.isRead ? Color.srFill : Color.srRedSoft,
                 size: 40)
            .overlay(alignment: .topTrailing) {
                if !item.isRead {
                    UnreadDot(size: 11)
                        .offset(x: 3, y: -3)
                        .transition(.scale.combined(with: .opacity))
                }
            }
    }

    private var meta: some View {
        HStack(spacing: 4) {
            Text(Format.age(item.createdAt))
                .foregroundStyle(Color.srTextTertiary)
            if let action = actionLabel {
                Text("\u{00B7}")
                    .foregroundStyle(Color.srTextTertiary)
                Text(action)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.srRed)
            }
        }
        .font(.srFootnote)
    }

    /// What tapping the row does, when it isn't simply "watch".
    private var actionLabel: String? {
        switch item.kind {
        case .needsTitle: return video?.needsTitle == true ? "Add a title" : nil
        case .storageLow: return "See storage"
        case .recordingSaved, .importFinished, .transcriptReady:
            if let video, !video.state.isReady { return "Still saving" }
            return nil
        }
    }

    private var spokenLabel: String {
        let state = item.isRead ? "" : "Unread. "
        return "\(state)\(item.title). \(item.body). \(Format.age(item.createdAt))."
    }

    private var spokenHint: String {
        switch item.kind {
        case .storageLow: return "Opens Storage"
        case .needsTitle where video?.needsTitle == true: return "Lets you add a title"
        default: return video == nil ? "" : "Opens the recording"
        }
    }
}

/// "All · Recordings · Transcripts" chips, each with its unread count.
struct FeedFilterBar: View {
    @Binding var selection: FeedFilter
    let unreadCounts: [FeedFilter: Int]

    var body: some View {
        HStack(spacing: Space.xs) {
            ForEach(FeedFilter.allCases) { option in
                chip(option)
            }
            Spacer(minLength: 0)
        }
    }

    private func chip(_ option: FeedFilter) -> some View {
        let selected = option == selection
        let count = unreadCounts[option] ?? 0
        return Button {
            guard option != selection else { return }
            Haptics.selection()
            withAnimation(Motion.quick) { selection = option }
        } label: {
            HStack(spacing: 6) {
                Text(option.title)
                    .font(.srSubheadlineStrong)
                    .foregroundStyle(selected ? Color.white : Color.srText)
                if count > 0 {
                    Text("\(count)")
                        .font(.srTimerSmall)
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Capsule().fill(Color.srRed))
                }
            }
            .padding(.horizontal, Space.m)
            .frame(height: 36)
            .background(Capsule().fill(selected ? Color.srInk : Color.srSurface))
            .overlay(Capsule().strokeBorder(selected ? Color.clear : Color.srLine, lineWidth: 1))
            .contentShape(Capsule())
        }
        // Borderless so each chip takes its own taps inside a List row.
        .buttonStyle(.borderless)
        .accessibilityLabel(count > 0 ? "\(option.title), \(count) unread" : option.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
