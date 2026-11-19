import SwiftUI

/// The Notes tab: your reactions as a strip of chips, then your notes in time order. Every
/// time stamp is a button that jumps there and plays.
struct NotesPanel: View {
    let notes: [VideoNote]
    let reactions: [VideoReaction]
    let onSeek: @MainActor (Double) -> Void
    let onEdit: @MainActor (VideoNote) -> Void
    let onDelete: @MainActor (VideoNote) -> Void
    let onDeleteReaction: @MainActor (VideoReaction) -> Void
    let onAddNote: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if !reactions.isEmpty {
                reactionStrip
            }
            if notes.isEmpty {
                EmptyStateView(systemImage: "note.text",
                               title: "No notes yet",
                               message: "Pause on a moment that matters and write it down. Each note keeps its time, so one tap brings you straight back.",
                               actionTitle: "Add a note",
                               action: { onAddNote() },
                               onStage: true)
                    .padding(.vertical, Space.l)
            } else {
                ForEach(notes) { note in
                    NoteRow(note: note,
                            onSeek: { onSeek(note.time) },
                            onEdit: { onEdit(note) },
                            onDelete: { onDelete(note) })
                }
            }
        }
    }

    private var reactionStrip: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("Reactions")
                .font(.srCaption)
                .foregroundStyle(Color.srStageTextTertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.xs) {
                    ForEach(reactions) { reaction in
                        ReactionChip(reaction: reaction,
                                     onSeek: { onSeek(reaction.time) },
                                     onDelete: { onDeleteReaction(reaction) })
                    }
                }
            }
        }
    }
}

private struct ReactionChip: View {
    let reaction: VideoReaction
    let onSeek: @MainActor () -> Void
    let onDelete: @MainActor () -> Void

    var body: some View {
        Button {
            onSeek()
        } label: {
            HStack(spacing: 6) {
                Text(reaction.emoji).font(.system(size: 17))
                Text(Format.stamp(reaction.time))
                    .font(.srTimerSmall)
                    .foregroundStyle(Color.srStageTextSecondary)
            }
            .padding(.horizontal, Space.s)
            .frame(height: 34)
            .background(Capsule().fill(Color.srStageRaised))
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Remove reaction", systemImage: "trash")
            }
        }
        .accessibilityLabel("\(EmojiCatalog.name(for: reaction.emoji)) at \(Format.stamp(reaction.time))")
        .accessibilityHint("Plays from here")
        .accessibilityAction(named: "Remove reaction") { onDelete() }
    }
}

private struct NoteRow: View {
    let note: VideoNote
    let onSeek: @MainActor () -> Void
    let onEdit: @MainActor () -> Void
    let onDelete: @MainActor () -> Void

    private var isEdited: Bool { note.updatedAt.timeIntervalSince(note.createdAt) > 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.xs) {
                stampButton
                Text(isEdited ? "Edited · \(Format.age(note.updatedAt))" : Format.age(note.createdAt))
                    .font(.srFootnote)
                    .foregroundStyle(Color.srStageTextTertiary)
                Spacer(minLength: Space.xs)
                Menu {
                    menuItems
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.srStageTextSecondary)
                        .frame(width: 32, height: 28)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Note options")
            }
            Text(note.text)
                .font(.srBody)
                .foregroundStyle(Color.srStageText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Space.m)
        .background(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(Color.srStageRaised))
        .contextMenu { menuItems }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Note at \(Format.stamp(note.time)). \(note.text)")
        .accessibilityAction(named: "Play from here") { onSeek() }
        .accessibilityAction(named: "Edit note") { onEdit() }
        .accessibilityAction(named: "Delete note") { onDelete() }
    }

    private var stampButton: some View {
        Button {
            onSeek()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "play.fill")
                    .font(.system(size: 9, weight: .bold))
                Text("Note at \(Format.stamp(note.time))")
                    .font(.srCaption)
            }
            .foregroundStyle(Color.srStageRed)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.srRed.opacity(0.16)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
    }

    @ViewBuilder private var menuItems: some View {
        Button {
            onSeek()
        } label: {
            Label("Play from here", systemImage: "play")
        }
        Button {
            onEdit()
        } label: {
            Label("Edit note", systemImage: "pencil")
        }
        Button(role: .destructive) {
            onDelete()
        } label: {
            Label("Delete note", systemImage: "trash")
        }
    }
}

/// Six quick reactions, more reactions, and the add-note button, docked at the bottom.
struct ReactionDock: View {
    let onReact: @MainActor (String) -> Void
    let onMore: @MainActor () -> Void
    let onAddNote: @MainActor () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(EmojiCatalog.quick, id: \.self) { emoji in
                Button {
                    onReact(emoji)
                } label: {
                    Text(emoji)
                        .font(.system(size: 26))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleStyle(scale: 0.8))
                .accessibilityLabel("React with \(EmojiCatalog.name(for: emoji))")
            }
            Button {
                Haptics.tap()
                onMore()
            } label: {
                Image(systemName: "face.smiling")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Color.srStageTextSecondary)
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.srStageText)
                            .background(Circle().fill(Color.srStage))
                            .offset(x: 4, y: -3)
                    }
                    .frame(width: 44, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel("More reactions")
            Rectangle()
                .fill(Color.srStageLine)
                .frame(width: 1, height: 26)
                .padding(.horizontal, Space.xxs)
            Button {
                Haptics.tap()
                onAddNote()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.srRed))
                    .contentShape(Circle())
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel("Add a note at this moment")
        }
        .padding(.horizontal, Space.s)
        .padding(.top, Space.xxs)
        .padding(.bottom, Space.xxs)
        .background(
            Color.srStage
                .overlay(alignment: .top) { Rectangle().fill(Color.srStageLine).frame(height: 0.5) }
                .ignoresSafeArea(edges: .bottom)
        )
    }
}
