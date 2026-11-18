import SwiftUI

/// Write a note stamped with the moment the sheet opened ("Note at 0:14"), or edit one.
/// Playback stays paused while it's open.
struct NoteComposerSheet: View {
    enum Mode {
        case new(time: Double)
        case edit(VideoNote)
    }

    let mode: Mode
    let onSave: @MainActor (String) -> Void
    let onDelete: @MainActor () -> Void
    let onCancel: @MainActor () -> Void

    @State private var text: String
    @FocusState private var focused: Bool
    private let limit = 500

    init(mode: Mode,
         onSave: @escaping @MainActor (String) -> Void,
         onDelete: @escaping @MainActor () -> Void = {},
         onCancel: @escaping @MainActor () -> Void) {
        self.mode = mode
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        switch mode {
        case .new:
            var draft = ""
            #if DEBUG
            draft = NoteComposerDebug.draft ?? ""
            #endif
            _text = State(initialValue: draft)
        case .edit(let note): _text = State(initialValue: note.text)
        }
    }

    private var time: Double {
        switch mode {
        case .new(let time): return time
        case .edit(let note): return note.time
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSave: Bool {
        guard !trimmed.isEmpty else { return false }
        if case .edit(let note) = mode { return trimmed != note.text }
        return true
    }

    var body: some View {
        VStack(spacing: Space.s) {
            header
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
            field
            if isEditing { editActions }
            Spacer(minLength: 0)
        }
        .padding(.top, Space.xs)
        .background(Color.srInkRaised.ignoresSafeArea())
        .onAppear { focused = true }
    }

    private var header: some View {
        ZStack {
            VStack(spacing: 2) {
                Text(isEditing ? "Edit note at \(Format.stamp(time))" : "Note at \(Format.stamp(time))")
                    .font(.srHeadline)
                    .foregroundStyle(Color.srOnDark)
                Text(isEditing ? "Saved on this iPhone" : "Playback is paused")
                    .font(.srCaption)
                    .foregroundStyle(Color.srOnDarkTertiary)
            }
            HStack {
                CircleIconButton(systemName: "xmark", label: "Cancel", tone: .dark, size: 32) {
                    onCancel()
                }
                Spacer()
            }
        }
        .padding(.horizontal, Space.gutter)
    }

    private var field: some View {
        HStack(alignment: .bottom, spacing: Space.xs) {
            TextField(isEditing ? "Your note" : "What stands out at this moment?", text: $text, axis: .vertical)
                .font(.srBody)
                .foregroundStyle(Color.srOnDark)
                .lineLimit(1...5)
                .focused($focused)
                .submitLabel(.done)
                .onChange(of: text) { value in
                    if value.count > limit { text = String(value.prefix(limit)) }
                }
                .padding(.vertical, 6)
            if !isEditing {
                Button {
                    save()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(canSave ? Color.srRed : Color.srInkLine))
                }
                .buttonStyle(PressScaleStyle())
                .disabled(!canSave)
                .accessibilityLabel("Add note")
            }
        }
        .padding(.leading, Space.m)
        .padding(.trailing, isEditing ? Space.m : Space.xs)
        .padding(.vertical, Space.xs)
        .background(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(Color.srInkControl))
        .padding(.horizontal, Space.gutter)
    }

    private var editActions: some View {
        HStack {
            Button(role: .destructive) {
                Haptics.warning()
                onDelete()
            } label: {
                Label("Delete note", systemImage: "trash")
                    .font(.srSubheadlineStrong)
                    .foregroundStyle(Color.srRedGlow)
            }
            .buttonStyle(.plain)
            Spacer()
            Button("Save") { save() }
                .buttonStyle(.srPrimaryCompact)
                .disabled(!canSave)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.xxs)
    }

    private func save() {
        guard canSave else { return }
        Haptics.success()
        onSave(trimmed)
    }
}

#if DEBUG
/// Lets a debug entry open the composer with text already typed.
enum NoteComposerDebug {
    @MainActor static var draft: String? = nil
}
#endif
