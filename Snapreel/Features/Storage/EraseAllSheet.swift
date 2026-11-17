import SwiftUI

/// What "Delete all my data" removes, counted before anything happens.
struct EraseSummary {
    var recordings: Int
    var recordingBytes: Int64
    var folders: Int
    var notes: Int
    var reactions: Int
    var transcripts: Int
    var notifications: Int

    @MainActor
    init(library: Library) {
        recordings = library.videos.count
        recordingBytes = library.totalVideoBytes
        folders = library.folders.count
        notes = library.notes.count
        reactions = library.reactions.count
        transcripts = library.transcripts.count
        notifications = library.notifications.count
    }
}

/// Settings › Storage › Delete all my data: says exactly what goes and what stays, asks for a
/// tick plus a tap (no typing), shows progress, then "All data deleted".
@MainActor
struct EraseAllSheet: View {
    let step: StorageView.EraseStep
    let summary: EraseSummary
    /// Bytes of recordings that were removed, for the done message.
    let freedBytes: Int64
    let onErase: @MainActor () -> Void
    let onCancel: @MainActor () -> Void
    let onDone: @MainActor () -> Void

    @State private var understood = false

    var body: some View {
        ZStack {
            Color.srCanvas.ignoresSafeArea()
            switch step {
            case .confirm:
                confirmContent
                    .transition(.opacity)
            case .erasing:
                erasingContent
                    .transition(.opacity)
            case .done:
                doneContent
                    .transition(.opacity)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(step == .erasing ? .hidden : .visible)
        .interactiveDismissDisabled(step == .erasing)
    }

    // MARK: Confirm

    private var confirmContent: some View {
        ScrollView {
            VStack(spacing: Space.l) {
                badge(systemImage: "trash.fill")
                VStack(spacing: Space.xs) {
                    Text("Delete all your data?")
                        .font(.srDisplay)
                        .foregroundStyle(Color.srText)
                    Text("Everything below is removed from this iPhone. It can't be undone, and Snapreel keeps no copy anywhere else.")
                        .font(.srSubheadline)
                        .foregroundStyle(Color.srTextSecondary)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                removedList
                keptNote
                understandToggle
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.xxl)
            .padding(.bottom, Space.l)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { confirmButtons }
    }

    private var removedList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("What's deleted")
                .font(.srSubheadlineStrong)
                .foregroundStyle(Color.srTextSecondary)
                .padding(.horizontal, Space.m)
                .padding(.top, Space.s)
                .padding(.bottom, Space.xxs)
            removedRow("video.fill", recordingsLine)
            divider
            removedRow("folder.fill", count(summary.folders, "folder", "folders"))
            divider
            removedRow("note.text", count(summary.notes, "note", "notes"))
            divider
            removedRow("face.smiling", count(summary.reactions, "reaction", "reactions"))
            divider
            removedRow("text.quote", count(summary.transcripts, "transcript", "transcripts"))
            divider
            removedRow("bell.fill", count(summary.notifications, "notification", "notifications"))
        }
        .srCard()
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.srLine)
            .frame(height: 0.5)
            .padding(.leading, Space.m + 28 + Space.s)
    }

    private func removedRow(_ systemImage: String, _ text: String) -> some View {
        HStack(spacing: Space.s) {
            IconTile(systemName: systemImage, size: 28)
            Text(text)
                .font(.srBody)
                .foregroundStyle(Color.srText)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.xs)
    }

    private var recordingsLine: String {
        let base = count(summary.recordings, "recording", "recordings")
        return summary.recordings > 0 ? "\(base) \u{00B7} \(Format.bytes(summary.recordingBytes))" : base
    }

    private var keptNote: some View {
        HStack(alignment: .top, spacing: Space.s) {
            IconTile(systemName: "gearshape.fill", tint: .srTextSecondary, background: .srFill, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("What stays")
                    .font(.srSubheadlineStrong)
                    .foregroundStyle(Color.srText)
                Text("Your settings: which alerts you get, recording defaults and playback speed. Videos you already saved to Photos or sent to someone stay where they are.")
                    .font(.srFootnote)
                    .foregroundStyle(Color.srTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.m)
        .srCard()
        .accessibilityElement(children: .combine)
    }

    private var understandToggle: some View {
        Button {
            Haptics.selection()
            withAnimation(Motion.quick) { understood.toggle() }
        } label: {
            HStack(alignment: .top, spacing: Space.s) {
                Image(systemName: understood ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(understood ? Color.srRed : Color.srTextTertiary)
                Text("I understand my recordings can't be recovered")
                    .font(.srBody)
                    .foregroundStyle(Color.srText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(Space.m)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .srCard()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(understood ? .isSelected : [])
        .accessibilityHint("Needed before you can delete everything")
    }

    private var confirmButtons: some View {
        VStack(spacing: Space.xs) {
            Button {
                Haptics.warning()
                onErase()
            } label: {
                Label("Delete everything", systemImage: "trash")
            }
            .buttonStyle(.srPrimary)
            .disabled(!understood)
            Button("Cancel") { onCancel() }
                .buttonStyle(.srTertiary)
                .frame(height: 44)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.s)
        .padding(.bottom, Space.xs)
        .background(Color.srCanvas.ignoresSafeArea(edges: .bottom))
    }

    // MARK: Erasing

    private var erasingContent: some View {
        VStack(spacing: Space.m) {
            ProgressView()
                .scaleEffect(1.4)
                .tint(Color.srRed)
                .frame(height: 44)
            Text("Deleting your data\u{2026}")
                .font(.srTitle3)
                .foregroundStyle(Color.srText)
            Text("This only takes a moment.")
                .font(.srSubheadline)
                .foregroundStyle(Color.srTextSecondary)
        }
        .padding(.horizontal, Space.xxl)
        .accessibilityElement(children: .combine)
    }

    // MARK: Done

    private var doneContent: some View {
        VStack(spacing: Space.l) {
            Spacer(minLength: 0)
            badge(systemImage: "checkmark")
            VStack(spacing: Space.xs) {
                Text("All data deleted")
                    .font(.srDisplay)
                    .foregroundStyle(Color.srText)
                Text("Snapreel is empty and ready for your next recording. Your settings are just as you left them.")
                    .font(.srSubheadline)
                    .foregroundStyle(Color.srTextSecondary)
                if freedBytes > 0 {
                    Text("\(Format.bytes(freedBytes)) freed on this iPhone")
                        .font(.srSubheadlineStrong)
                        .foregroundStyle(Color.srText)
                        .padding(.top, Space.xxs)
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            Button("Back to library") {
                Haptics.tap()
                onDone()
            }
            .buttonStyle(.srPrimary)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.xxl)
        .padding(.bottom, Space.m)
    }

    // MARK: Helpers

    private func badge(systemImage: String) -> some View {
        ZStack {
            Circle().fill(Color.srRedSoft)
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Color.srRed)
        }
        .frame(width: 76, height: 76)
        .accessibilityHidden(true)
    }

    private func count(_ value: Int, _ one: String, _ many: String) -> String {
        switch value {
        case 0: return "No \(many)"
        case 1: return "1 \(one)"
        default: return "\(value) \(many)"
        }
    }
}
