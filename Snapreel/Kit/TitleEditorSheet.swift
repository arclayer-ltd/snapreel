import SwiftUI

/// Edit a recording's title. Shared by review (B), the player (C) and library row actions (D).
/// Present with `.sheet(item:)` and `.presentationDetents([.height(220)])` or full height.
struct TitleEditorSheet: View {
    let initialTitle: String
    var heading = "Title"
    /// From the recorder or the player: stage colours, which follow the appearance like the rest.
    var onStage = false
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var text: String
    @FocusState private var focused: Bool
    private let limit = 120

    init(initialTitle: String, heading: String = "Title", onStage: Bool = false,
         onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.initialTitle = initialTitle
        self.heading = heading
        self.onStage = onStage
        self.onSave = onSave
        self.onCancel = onCancel
        _text = State(initialValue: initialTitle)
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: heading,
                        leadingTitle: "Cancel", leadingAction: onCancel,
                        trailingTitle: "Save", trailingEnabled: !trimmed.isEmpty,
                        trailingAction: save, onStage: onStage)
            HStack(spacing: Space.xs) {
                TextField("Give it a name people will recognise", text: $text, axis: .vertical)
                    .font(.srBody)
                    .foregroundStyle(onStage ? Color.srStageText : Color.srText)
                    .lineLimit(1...3)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(save)
                    .onChange(of: text) { value in
                        if value.count > limit { text = String(value.prefix(limit)) }
                        if value.contains("\n") { text = value.replacingOccurrences(of: "\n", with: " "); save() }
                    }
                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(onStage ? Color.srStageTextTertiary : Color.srTextTertiary)
                    }
                    .accessibilityLabel("Clear title")
                }
            }
            .padding(Space.m)
            .background(RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                .fill(onStage ? Color.srStageControl : Color.srFill))
            .padding(.horizontal, Space.gutter)
            HStack {
                Spacer()
                Text("\(text.count)/\(limit)")
                    .font(.srCaption)
                    .foregroundStyle(onStage ? Color.srStageTextTertiary : Color.srTextTertiary)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.xs)
            Spacer(minLength: 0)
        }
        .background((onStage ? Color.srStageRaised : Color.srSurface).ignoresSafeArea())
        .onAppear { focused = true }
    }

    private func save() {
        guard !trimmed.isEmpty else { return }
        Haptics.success()
        onSave(trimmed)
    }
}
