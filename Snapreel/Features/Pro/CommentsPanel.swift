import SwiftUI

/// The player's Comments tab for a shared recording: what viewers wrote on the watch page,
/// newest first, each pinned to its moment (tap to jump there), plus a count of their
/// reactions. You can delete any comment, and block its author from all your videos
/// (App Review guideline 1.2). Comments the server's word filter held come first, marked Held:
/// viewers can't see them until you approve them. Hosted in the player's UIKit scroller, so
/// everything comes in as values and callbacks.
struct CommentsPanel: View {
    let activity: CloudActivity?
    let failed: Bool
    let commentsAllowed: Bool
    let onSeek: @MainActor (Double) -> Void
    let onModerate: @MainActor (CloudComment) -> Void
    let onApprove: @MainActor (CloudComment) -> Void
    let onRetry: @MainActor () -> Void
    let onSettings: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if let activity {
                let held = activity.comments.filter(\.isHeld).count
                if held > 0 {
                    heldNote(held)
                }
                if !activity.reactions.isEmpty {
                    reactionSummary(activity.reactions)
                }
                if !commentsAllowed {
                    offNote
                }
                if activity.comments.isEmpty {
                    EmptyStateView(systemImage: "text.bubble",
                                   title: "No comments yet",
                                   message: "When people comment on the watch page, their comments show here, pinned to the moment they were watching.",
                                   onStage: true)
                        .padding(.vertical, Space.l)
                } else {
                    ForEach(threads(activity.comments), id: \.0.id) { thread in
                        CommentRow(comment: thread.0, onSeek: onSeek, onModerate: onModerate, onApprove: onApprove)
                        ForEach(thread.1) { reply in
                            CommentRow(comment: reply, isReply: true, onSeek: onSeek, onModerate: onModerate,
                                       onApprove: onApprove)
                        }
                    }
                }
            } else if failed {
                VStack(spacing: Space.s) {
                    Text("Comments didn't load.")
                        .font(.srSubheadline)
                        .foregroundStyle(Color.srStageTextSecondary)
                    Button("Try again") { onRetry() }
                        .buttonStyle(.srSecondaryCompact)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.xl)
            } else {
                HStack(spacing: Space.s) {
                    ProgressView()
                    Text("Loading comments…")
                        .font(.srSubheadline)
                        .foregroundStyle(Color.srStageTextSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.xl)
            }
        }
    }

    /// Top-level comments, held ones first, then newest first; each with its replies oldest first.
    private func threads(_ comments: [CloudComment]) -> [(CloudComment, [CloudComment])] {
        let roots = comments.filter { $0.parentId == nil }.sorted {
            $0.isHeld != $1.isHeld ? $0.isHeld : $0.createdAt > $1.createdAt
        }
        return roots.map { root in
            (root, comments.filter { $0.parentId == root.id }.sorted { $0.createdAt < $1.createdAt })
        }
    }

    private func reactionSummary(_ reactions: [CloudReaction]) -> some View {
        let counts = Dictionary(grouping: reactions, by: \.emoji).map { ($0.key, $0.value.count) }
            .sorted { $0.1 > $1.1 }
        return VStack(alignment: .leading, spacing: Space.xs) {
            Text(reactions.count == 1 ? "1 reaction from viewers" : "\(reactions.count) reactions from viewers")
                .font(.srFootnote)
                .foregroundStyle(Color.srStageTextSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.xs) {
                    ForEach(counts, id: \.0) { item in
                        HStack(spacing: 4) {
                            Text(item.0)
                            Text("\(item.1)")
                                .font(.srSubheadlineStrong.monospacedDigit())
                                .foregroundStyle(Color.srStageText)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(Capsule().fill(Color.srStageControl))
                        .overlay(Capsule().strokeBorder(ViewerMarkerStyle.ring, lineWidth: 1.5))
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func heldNote(_ count: Int) -> some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: "eye.slash")
                .foregroundStyle(Color.srStageTextSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(count == 1 ? "1 comment is waiting for you" : "\(count) comments are waiting for you")
                    .font(.srSubheadlineStrong)
                    .foregroundStyle(Color.srStageText)
                Text(count == 1
                     ? "It contains words on Snapreel's filter list, so viewers can't see it until you approve it."
                     : "They contain words on Snapreel's filter list, so viewers can't see them until you approve them.")
                    .font(.srFootnote)
                    .foregroundStyle(Color.srStageTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s)
        .background(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).fill(Color.srStageRaised))
        .accessibilityElement(children: .combine)
    }

    private var offNote: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "text.bubble")
                .foregroundStyle(Color.srStageTextSecondary)
            Text("Comments are off for this link.")
                .font(.srFootnote)
                .foregroundStyle(Color.srStageTextSecondary)
            Spacer()
            Button("Link settings") { onSettings() }
                .font(.srFootnote.weight(.semibold))
                .foregroundStyle(Color.srStageRed)
        }
        .padding(Space.s)
        .background(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).fill(Color.srStageRaised))
    }
}

private struct CommentRow: View {
    let comment: CloudComment
    var isReply = false
    let onSeek: @MainActor (Double) -> Void
    let onModerate: @MainActor (CloudComment) -> Void
    let onApprove: @MainActor (CloudComment) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            ZStack {
                Circle().fill(comment.isOwner ? Color.srRed : ViewerMarkerStyle.fill)
                Text(String(comment.authorName.prefix(1)).uppercased())
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(comment.isOwner ? Color.white : Color.srStageText)
            }
            .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(comment.isOwner ? "You" : comment.authorName)
                        .font(.srSubheadlineStrong)
                        .foregroundStyle(Color.srStageText)
                        .lineLimit(1)
                    Text("· \(Format.age(comment.createdAt))")
                        .font(.srFootnote)
                        .foregroundStyle(Color.srStageTextTertiary)
                        .lineLimit(1)
                    if comment.isHeld {
                        Text("Held")
                            .font(.srCaption.weight(.semibold))
                            .foregroundStyle(Color.srStageTextSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .overlay(Capsule().strokeBorder(Color.srStageTextTertiary, lineWidth: 1))
                    }
                }
                if comment.isHeld {
                    Text("Only you can see this until you approve it.")
                        .font(.srFootnote)
                        .foregroundStyle(Color.srStageTextSecondary)
                }
                Text(comment.body)
                    .font(.srCallout)
                    .foregroundStyle(Color.srStageText)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if let at = comment.atS {
                    Button {
                        onSeek(at)
                    } label: {
                        Label(Format.stamp(at), systemImage: "play.fill")
                            .font(.srCaption.monospacedDigit())
                            .foregroundStyle(Color.srStageRed)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.srRed.opacity(0.14)))
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityLabel("Play from \(Format.stamp(at))")
                }
                if comment.isHeld {
                    Button {
                        Haptics.tap()
                        onApprove(comment)
                    } label: {
                        Label("Approve", systemImage: "checkmark")
                    }
                    .buttonStyle(.srSecondaryCompact)
                    .accessibilityLabel("Approve comment by \(comment.authorName)")
                }
            }
            Spacer(minLength: 0)
            if !comment.isOwner {
                Button {
                    Haptics.tap()
                    onModerate(comment)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.srStageTextSecondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete or block, comment by \(comment.authorName)")
            }
        }
        .padding(Space.s)
        .background(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(Color.srStageRaised))
        .padding(.leading, isReply ? Space.xl : 0)
    }
}

/// How viewers' reactions and comments are told apart from yours: a soft blue-grey disc with a
/// white ring, where yours are plain emoji.
enum ViewerMarkerStyle {
    static var fill: Color { Color(light: 0xDCE3F0, dark: 0x34405A) }
    static var ring: Color { Color(light: 0x7A8CB3, dark: 0x9FB3DB) }
}
