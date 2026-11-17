import SwiftUI

/// Session D. Edit a recording's tags: current tags as removable chips, a field where return (or
/// a comma) adds a tag, and suggestions from tags used on other recordings.
/// The player (session C) can present it too: `TagEditorSheet(videoID:initialTags:onDone:)`.
struct TagEditorSheet: View {
    let videoID: UUID
    let onDone: @MainActor () -> Void

    @EnvironmentObject private var library: Library
    @EnvironmentObject private var router: AppRouter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tags: [String]
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    private static let limit = 30

    init(videoID: UUID, initialTags: [String], onDone: @escaping @MainActor () -> Void) {
        self.videoID = videoID
        self.onDone = onDone
        _tags = State(initialValue: initialTags)
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Tags",
                        leadingTitle: "Cancel", leadingAction: { onDone() },
                        trailingTitle: "Done", trailingAction: { save() })
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    field
                    currentSection
                    suggestionsSection
                }
                .padding(.horizontal, Space.gutter)
                .padding(.top, Space.xs)
                .padding(.bottom, Space.xxl)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color.srSurface.ignoresSafeArea())
        .onChange(of: draft) { value in
            if value.contains(",") { addPieces(of: value) }
        }
    }

    // MARK: Sections

    private var field: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.xs) {
                Image(systemName: "number")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.srTextTertiary)
                TextField("Add a tag", text: $draft)
                    .font(.srBody)
                    .foregroundStyle(Color.srText)
                    .focused($fieldFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { addDraft() }
                if !cleanedDraft.isEmpty {
                    Button("Add") { addDraft() }
                        .font(.srSubheadlineStrong)
                        .foregroundStyle(Color.srRed)
                }
            }
            .padding(.horizontal, Space.m)
            .frame(height: 50)
            .background(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).fill(Color.srFill))
            Text("Press return to add. Tags help you find recordings in Search.")
                .font(.srFootnote)
                .foregroundStyle(Color.srTextSecondary)
        }
    }

    private var currentSection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("On this recording")
                .font(.srHeadline)
                .foregroundStyle(Color.srText)
            if tags.isEmpty {
                Text("No tags yet. Try a project, a person or a topic you'd search for later.")
                    .font(.srSubheadline)
                    .foregroundStyle(Color.srTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                BrowseChipFlow {
                    ForEach(tags, id: \.self) { tag in
                        BrowseTagChip(text: tag, style: .removable) {
                            remove(tag)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var suggestionsSection: some View {
        let suggestions = self.suggestions
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: Space.s) {
                Text(cleanedDraft.isEmpty ? "Used on other recordings" : "Matching tags")
                    .font(.srHeadline)
                    .foregroundStyle(Color.srText)
                BrowseChipFlow {
                    ForEach(suggestions, id: \.self) { tag in
                        BrowseTagChip(text: tag, style: .suggestion) {
                            add(tag)
                            draft = ""
                        }
                    }
                }
            }
        }
    }

    // MARK: Data

    private var cleanedDraft: String { Self.clean(draft) }

    private var suggestions: [String] {
        let query = cleanedDraft
        return library.allTags.filter { tag in
            !contains(tag) && (query.isEmpty || tag.range(of: query, options: BrowseMatch.options) != nil)
        }
    }

    private func contains(_ tag: String) -> Bool {
        tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
    }

    static func clean(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasPrefix("#") { text.removeFirst() }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(text.prefix(limit))
    }

    private func add(_ tag: String) {
        let cleaned = Self.clean(tag)
        guard !cleaned.isEmpty else { return }
        guard !contains(cleaned) else {
            Haptics.warning()
            return
        }
        Haptics.selection()
        withAnimation(reduceMotion ? nil : Motion.quick) {
            tags.append(cleaned)
        }
    }

    private func addDraft() {
        let pending = draft
        draft = ""
        add(pending)
        Task { @MainActor in
            fieldFocused = true
        }
    }

    /// Typing or pasting "design, review" adds both.
    private func addPieces(of value: String) {
        let pieces = value.components(separatedBy: ",")
        draft = pieces.last ?? ""
        for piece in pieces.dropLast() {
            add(piece)
        }
    }

    private func remove(_ tag: String) {
        withAnimation(reduceMotion ? nil : Motion.quick) {
            tags.removeAll { $0 == tag }
        }
    }

    private func save() {
        var updated = tags
        let pending = cleanedDraft
        if !pending.isEmpty && !contains(pending) {
            updated.append(pending)
        }
        let before = library.video(videoID)?.tags ?? []
        if updated != before {
            library.setTags(updated, for: videoID)
            Haptics.success()
            router.showToast(updated.isEmpty ? "Tags removed" : "Tags saved", systemImage: "number")
        }
        onDone()
    }
}
