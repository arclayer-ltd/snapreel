import SwiftUI

/// The editor as the shell presents it, full screen over everything.
struct EditorScreen: View {
    @StateObject private var model: EditorModel
    @EnvironmentObject private var router: AppRouter

    init(videoID: UUID, library: Library) {
        _model = StateObject(wrappedValue: EditorModel(videoID: videoID, library: library))
    }

    var body: some View {
        EditorView(model: model,
                   onClose: { router.closeEditor() },
                   onOpen: { id in router.closeEditor(thenPlay: id) })
    }
}

/// Close on the left and a red Save on the right; the preview; time, play and undo/redo; the
/// timeline under a fixed playhead; and the tools along the bottom, which swap to a tool's
/// panel or to section actions when something is selected. Follows Light and Dark; only the
/// picture is dark.
struct EditorView: View {
    @ObservedObject var model: EditorModel
    let onClose: () -> Void
    let onOpen: (UUID) -> Void

    @EnvironmentObject private var library: Library
    @ObservedObject private var transcripts: TranscriptService = .shared
    @State private var pageOffset: CGFloat = 0
    @State private var isClosing = false
    @GestureState private var isSwiping = false
    @State private var shareTarget: Video?
    @State private var confirmsDiscard = false

    var body: some View {
        ZStack {
            Color.srStage.ignoresSafeArea()
            // Exactly as wide as the screen, whatever is in it: a row that was a little too wide used to
            // widen the whole page, and on iOS 16 dragging a shape then laid it out again for ever.
            GeometryReader { page in
                VStack(spacing: 0) {
                    // The top bar and transport hide while typing text so their buttons don't show
                    // through the text entry's backdrop (it has its own Cancel and Done).
                    topBar
                        .opacity(model.textEntry == nil ? 1 : 0)
                    EditorPreview(model: model)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    transport
                        .opacity(model.textEntry == nil ? 1 : 0)
                    EditorTimeline(model: model)
                        // The coach mark hangs over the bar below.
                        .zIndex(1)
                    EditorBottomBar(model: model)
                }
                .frame(width: page.size.width, height: page.size.height)
            }
            // The keyboard (text entry) covers the page instead of squeezing it.
            .ignoresSafeArea(.keyboard)
            // What is covered can't be reached with VoiceOver either.
            .accessibilityHidden(model.textEntry != nil || model.phase != .editing)
            if model.textEntry != nil {
                EditorTextEntry(model: model)
                    .transition(.opacity)
                    .zIndex(2)
            }
            phaseOverlay
                .zIndex(3)
        }
        // Text grows up to the first accessibility size; beyond it the controls, and the titles of the
        // sheets, would no longer fit an iPhone's width.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .offset(y: pageOffset)
        .onChange(of: isSwiping) { swiping in
            // The system took the swipe away halfway (a call, Control Centre): the page springs back.
            if !swiping, !isClosing, pageOffset != 0 { withAnimation(SwipeDismiss.springBack) { pageOffset = 0 } }
        }
        .animation(Motion.quick, value: model.tool)
        .animation(Motion.quick, value: model.selection)
        .sheet(item: $model.sheet) { sheet in
            sheetView(sheet)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        }
        .toast($model.toast, bottomInset: 170)
        .shareVideo($shareTarget)
        .task { await model.load() }
        .onDisappear { model.teardown() }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: Space.s) {
            CircleIconButton(systemName: "xmark", label: "Close editor", tone: .stage, size: 36) {
                requestClose()
            }
            Spacer(minLength: 0)
            Menu {
                Button {
                    model.revertToOriginal()
                } label: {
                    Label("Revert to original", systemImage: "arrow.uturn.backward")
                }
                .disabled(!model.isDirty)
                // Revert stays in the editor and can be undone; this ends the edit for good.
                Button(role: .destructive) {
                    confirmsDiscard = true
                } label: {
                    Label("Discard and close", systemImage: "trash")
                }
                .disabled(!model.isDirty)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.srStageText)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.srStageControl))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .accessibilityElement()
                    .accessibilityLabel("More")
            }
            .disabled(model.isRecordingVoice)
            .accessibilityLabel("More")
            .confirmationDialog("Discard your edits?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
                Button("Discard and close", role: .destructive) {
                    model.discardDraft()
                    close()
                }
                Button("Keep editing", role: .cancel) {}
            } message: {
                Text("The draft is thrown away and the editor closes. Your recording isn't changed.")
            }
            Button {
                Haptics.tap()
                model.pause()
                model.sheet = .export
            } label: {
                Text("Save")
            }
            .buttonStyle(.srPrimaryCompact)
            .disabled(model.isRecordingVoice || model.isPreparing || model.loadFailed)
            .accessibilityHint("Saves the edit as a new recording")
        }
        .padding(.horizontal, Space.m)
        .frame(height: 52)
        .contentShape(Rectangle())
        .gesture(swipeDown)
    }

    private var swipeDown: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .updating($isSwiping) { _, swiping, _ in swiping = true }
            .onChanged { value in
                guard !isClosing else { return }
                pageOffset = SwipeDismiss.isDownward(value) ? value.translation.height : 0
            }
            .onEnded { value in
                if SwipeDismiss.isDownward(value) && SwipeDismiss.commits(value) {
                    requestClose()
                } else {
                    withAnimation(SwipeDismiss.springBack) { pageOffset = 0 }
                }
            }
    }

    private func requestClose() {
        guard !isClosing else { return }
        // X always closes: a take being recorded stops first, whatever else is going on.
        if model.isRecordingVoice { model.stopVoice() }
        if model.textEntry != nil { model.commitTextEntry(leaving: true) }
        model.pause()
        switch model.phase {
        case .rendering, .restorePrompt:
            // A save carries on in the library; an unanswered draft stays as it was.
            close()
            return
        case .editing, .cancelled:
            break
        }
        if model.isDirty {
            withAnimation(SwipeDismiss.springBack) { pageOffset = 0 }
            model.sheet = .discard
        } else {
            model.keepDraft()
            close()
        }
    }

    private func close() {
        guard !isClosing else { return }
        isClosing = true
        withAnimation(SwipeDismiss.slideAway) { pageOffset = SwipeDismiss.offscreen }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            onClose()
        }
    }

    /// Closes after the sheet on screen has gone.
    private func closeAfterSheet() {
        model.sheet = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            close()
        }
    }

    // MARK: - Transport

    private var transport: some View {
        ZStack {
            HStack(spacing: Space.xs) {
                EditorTimeLabel(model: model, seconds: model.clock.seconds)
                Spacer(minLength: 0)
                historyButton("arrow.uturn.backward", label: "Undo", enabled: model.canUndo) { model.undo() }
                historyButton("arrow.uturn.forward", label: "Redo", enabled: model.canRedo) { model.redo() }
            }
            Button {
                Haptics.tap()
                model.togglePlay()
            } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.srStageText)
                    .frame(width: 56, height: 46)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle())
            .disabled(model.isRecordingVoice || model.isPreparing)
            .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
        }
        .padding(.leading, Space.m)
        .padding(.trailing, Space.xs)
        .frame(height: 46)
    }

    private func historyButton(_ systemImage: String, label: String, enabled: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(enabled ? Color.srStageText : Color.srStageTextTertiary.opacity(0.6))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!enabled || model.isRecordingVoice)
        .accessibilityLabel(label)
    }

    // MARK: - Sheets

    @ViewBuilder
    private func sheetView(_ sheet: EditorSheet) -> some View {
        switch sheet {
        case .transcript:
            EditorTranscriptSheet(model: model, transcripts: transcripts)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        case .speed:
            EditorSpeedSheet(model: model)
                .presentationDetents([.height(model.selectedSegment == nil ? 300 : 360), .large])
                .presentationDragIndicator(.visible)
        case .export:
            EditorExportSheet(model: model)
                .presentationDetents([.height(520), .large])
                .presentationDragIndicator(.visible)
        case .discard:
            EditorDiscardSheet(onKeepDraft: {
                model.keepDraft()
                closeAfterSheet()
            }, onDiscard: {
                model.discardDraft()
                closeAfterSheet()
            }, onKeepEditing: {
                model.sheet = nil
            })
            .presentationDetents([.height(330), .large])
            .presentationDragIndicator(.visible)
        case .captionWords:
            EditorCaptionWordsSheet(model: model)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        case .emoji:
            EmojiPickerSheet(title: "Emoji", onPick: { emoji in
                model.sheet = nil
                model.addSticker(.emoji, emoji: emoji)
            }, onClose: { model.sheet = nil })
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Full-screen states

    @ViewBuilder
    private var phaseOverlay: some View {
        switch model.phase {
        case .editing:
            EmptyView()
        case .restorePrompt:
            EditorRestorePrompt(date: model.draftDate, onContinue: {
                withAnimation(Motion.standard) { model.continueDraft() }
            }, onStartOver: {
                withAnimation(Motion.standard) { model.startOver() }
            })
            .transition(.opacity)
        case .rendering(let id):
            EditorRenderingView(model: model, videoID: id,
                                onOpen: { onOpen(id) },
                                onShare: { shareTarget = library.video(id) },
                                onDone: { close() })
            .contentShape(Rectangle())
            .gesture(swipeDown)
            .transition(.opacity)
        case .cancelled:
            EditorCancelledView { withAnimation(Motion.standard) { model.backToEditing() } }
                .transition(.opacity)
        }
    }
}

/// "0:12 / 9:00": follows whole seconds, so it isn't drawn again while nothing changes.
private struct EditorTimeLabel: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var seconds: EditorSeconds

    var body: some View {
        let now = Double(seconds.whole)
        Text("\(Format.clock(now)) / \(Format.clock(model.duration))")
            .font(.srTimerSmall)
            .foregroundStyle(Color.srStageTextSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            // Never under the play button in the middle.
            .frame(maxWidth: 118, alignment: .leading)
            .accessibilityLabel("\(Format.clock(now)) of \(Format.clock(model.duration))")
            .accessibilityIdentifier("editor.time")
    }
}

// MARK: - Bottom bar

/// The tools, or what replaces them: section actions, a tool's panel, or a confirmation.
struct EditorBottomBar: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.srStageLine).frame(height: 0.5)
            content
                .frame(maxWidth: .infinity)
        }
        .background(Color.srStage.ignoresSafeArea(edges: .bottom))
    }

    @ViewBuilder
    private var content: some View {
        if model.confirmsSectionDelete, let segment = model.selectedSegment {
            EditorDeleteSectionConfirm(model: model, segment: segment)
        } else if model.selectedSegment != nil {
            EditorSectionBar(model: model)
        } else if let tool = model.tool {
            EditorToolPanel(model: model, tool: tool)
                // Starts scrolled to the top, and typed state never leaks between tools.
                .id(tool)
        } else {
            EditorToolBar(model: model)
        }
    }
}

/// The main tools in one scrolling row.
struct EditorToolBar: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(model.tools) { tool in
                    EditorToolButton(title: tool.title, systemImage: tool.systemImage) {
                        model.open(tool)
                    }
                }
            }
            .padding(.horizontal, Space.xs)
        }
        .frame(height: 76)
    }
}

struct EditorToolButton: View {
    let title: String
    let systemImage: String
    var isOn = false
    var isDestructive = false
    var enabled = true
    let action: () -> Void

    // Grows with the text size up to what one row of tools holds; holding a tool shows it large.
    @ScaledMetric(relativeTo: .caption2) private var labelSize: CGFloat = 11
    @ScaledMetric(relativeTo: .caption2) private var iconSize: CGFloat = 20
    @ScaledMetric(relativeTo: .caption2) private var width: CGFloat = 66

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: min(iconSize, 24), weight: .medium))
                    .frame(height: min(iconSize, 24) + 4)
                Text(title)
                    .font(.system(size: min(labelSize, 15), weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .accessibilityShowsLargeContentViewer {
                Label(title, systemImage: systemImage)
            }
            .foregroundStyle(isOn ? Color.srStageRed : (isDestructive ? Color.srStageRed : Color.srStageText))
            .frame(width: min(width, 84), height: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Section actions: back, Split, Delete, Speed.
struct EditorSectionBar: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        HStack(spacing: 0) {
            Button {
                Haptics.tap()
                model.selection = nil
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.srStageText)
                    .frame(width: 48, height: 64)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Back to tools")
            Rectangle().fill(Color.srStageLine).frame(width: 0.5, height: 36)
            EditorToolButton(title: "Split", systemImage: "scissors") { model.splitAtPlayhead() }
            EditorToolButton(title: "Delete", systemImage: "trash", isDestructive: true) {
                if model.recipe.segments.count > 1 {
                    Haptics.warning()
                    model.confirmsSectionDelete = true
                } else {
                    model.deleteSelectedSegment()
                }
            }
            EditorToolButton(title: "Speed", systemImage: "speedometer") { model.sheet = .speed }
            Spacer(minLength: 0)
            if let segment = model.selectedSegment, let index = model.recipe.segmentIndex(segment.id) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Part \(index + 1) of \(model.recipe.segments.count)")
                        .font(.srCaption)
                        .foregroundStyle(Color.srStageText)
                    Text(EditorText.length(segment.outputLength))
                        .font(.srTimerSmall)
                        .foregroundStyle(Color.srStageTextTertiary)
                }
                .padding(.trailing, Space.m)
            }
        }
        .frame(height: 76)
    }
}

/// "Delete this part?" in place of the section actions.
struct EditorDeleteSectionConfirm: View {
    @ObservedObject var model: EditorModel
    let segment: EditSegment

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.xs) {
                Image(systemName: "trash.fill")
                    .foregroundStyle(Color.srStageRed)
                Text("Delete this \(EditorText.length(segment.outputLength)) part?")
                    .font(.srHeadline)
                    .foregroundStyle(Color.srStageText)
            }
            Text("What comes after it moves up. Undo brings it back.")
                .font(.srFootnote)
                .foregroundStyle(Color.srStageTextSecondary)
            HStack(spacing: Space.s) {
                Button("Keep it") { model.confirmsSectionDelete = false }
                    .buttonStyle(.srSecondaryCompact)
                Button("Delete part") { model.deleteSelectedSegment() }
                    .buttonStyle(.srPrimaryCompact)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, Space.gutter)
        .padding(.vertical, Space.s)
    }
}

// MARK: - Full-screen states

/// "Pick up where you left off?"
struct EditorRestorePrompt: View {
    let date: Date?
    let onContinue: () -> Void
    let onStartOver: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: Space.m) {
                ZStack {
                    Circle().fill(Color.srRedSoft)
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color.srStageRed)
                }
                .frame(width: 60, height: 60)
                VStack(spacing: Space.xs) {
                    Text("Pick up where you left off?")
                        .font(.srTitle3)
                        .foregroundStyle(Color.srStageText)
                    Text(date.map { "You have unsaved edits from \(Format.age($0).lowercased())." }
                         ?? "You have unsaved edits to this recording.")
                        .font(.srSubheadline)
                        .foregroundStyle(Color.srStageTextSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: Space.s) {
                    Button("Continue editing") { onContinue() }
                        .buttonStyle(.srPrimary)
                    Button("Start over") { onStartOver() }
                        .buttonStyle(.srSecondary)
                }
            }
            .padding(Space.l)
            .background(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(Color.srStageRaised))
            .padding(.horizontal, Space.l)
        }
    }
}

/// The save was stopped.
struct EditorCancelledView: View {
    let onBack: () -> Void

    var body: some View {
        ZStack {
            Color.srStage.ignoresSafeArea()
            VStack(spacing: Space.m) {
                Spacer()
                ZStack {
                    Circle().fill(Color.srStageControl)
                    Image(systemName: "stop.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.srStageText)
                }
                .frame(width: 64, height: 64)
                Text("Saving stopped")
                    .font(.srTitle)
                    .foregroundStyle(Color.srStageText)
                Text("Nothing was added to your library. Your edits are still here.")
                    .font(.srSubheadline)
                    .foregroundStyle(Color.srStageTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Back to the editor") { onBack() }
                    .buttonStyle(.srPrimary)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.l)
        }
    }
}

// MARK: - Text entry

/// The keyboard is up: the text in its style over a dimmed page, with styles and colours just
/// above the keyboard.
struct EditorTextEntry: View {
    @ObservedObject var model: EditorModel
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.9).ignoresSafeArea()
                .accessibilityHidden(true)
                .onTapGesture { model.commitTextEntry(leaving: true) }
            VStack(spacing: 0) {
                HStack {
                    Button("Cancel") {
                        model.textEntry = nil
                        model.textEntryNeedsWords = false
                    }
                    .font(.srBody)
                    .foregroundStyle(Color.white.opacity(0.85))
                    .frame(minWidth: 44, minHeight: 44)
                    Spacer()
                    Button("Done") { model.commitTextEntry() }
                        .font(.srHeadline)
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, Space.m)
                        .frame(height: 36)
                        .background(Capsule().fill(Color.srRed))
                }
                .padding(.horizontal, Space.gutter)
                .frame(height: 56)
                Spacer(minLength: Space.m)
                field
                    .padding(.horizontal, Space.l)
                if model.textEntryNeedsWords {
                    Text("Type something first, or tap Cancel.")
                        .font(.srSubheadlineStrong)
                        .foregroundStyle(Color(hex: 0xFE6262))
                        .padding(.top, Space.s)
                        .transition(.opacity)
                        .accessibilityAddTraits(.isStaticText)
                }
                Spacer(minLength: Space.m)
                if let entry = model.textEntry {
                    EditorTextStyleRow(style: entry.style, color: entry.color, onDark: true,
                                       onStyle: { style in model.textEntry?.style = style },
                                       onColor: { color in model.textEntry?.color = color })
                        .padding(.bottom, Space.s)
                }
            }
        }
        // On iOS 16 a field that asks for the keyboard while it is still appearing doesn't always get it.
        .task {
            focused = true
            try? await Task.sleep(nanoseconds: 350_000_000)
            if !Task.isCancelled { focused = true }
        }
    }

    @ViewBuilder
    private var field: some View {
        if let entry = model.textEntry {
            let binding = Binding<String>(get: { model.textEntry?.text ?? "" },
                                          set: {
                                              model.textEntry?.text = $0
                                              if model.textEntryNeedsWords { model.textEntryNeedsWords = false }
                                          })
            TextField("Type something", text: binding, axis: .vertical)
                .font(.system(size: 30, weight: .bold))
                .multilineTextAlignment(.center)
                .lineLimit(1...5)
                .focused($focused)
                .foregroundStyle(foreground(entry))
                .tint(Color.srRed)
                .padding(.horizontal, entry.style == .box ? 14 : 4)
                .padding(.vertical, 6)
                .background(background(entry))
                .accessibilityLabel("Text")
        }
    }

    private func foreground(_ entry: EditText) -> Color {
        entry.style == .box ? entry.color.contrasting : entry.color.color
    }

    @ViewBuilder
    private func background(_ entry: EditText) -> some View {
        switch entry.style {
        case .box:
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(entry.color.color)
        case .bar:
            Rectangle().fill(Color(hex: 0x13141B).opacity(0.82))
        case .plain, .outline:
            Color.clear
        }
    }
}

/// Style chips and colour dots, shared by the keyboard bar and the text panel.
struct EditorTextStyleRow: View {
    let style: EditTextStyle
    let color: EditColor
    var onDark = false
    let onStyle: (EditTextStyle) -> Void
    let onColor: (EditColor) -> Void

    var body: some View {
        VStack(spacing: Space.s) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.xs) {
                    ForEach(EditTextStyle.allCases) { option in
                        Button {
                            Haptics.selection()
                            onStyle(option)
                        } label: {
                            Text(option.label)
                                .font(.srSubheadlineStrong)
                                .foregroundStyle(option == style ? selectedText : text)
                                .padding(.horizontal, Space.s)
                                .frame(height: 36)
                                .background(Capsule().fill(option == style ? selectedFill : fill))
                                .frame(height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressScaleStyle())
                        .accessibilityAddTraits(option == style ? .isSelected : [])
                    }
                }
                .padding(.horizontal, Space.gutter)
            }
            EditorColorDots(selected: color, onDark: onDark, onPick: onColor)
        }
    }

    private var text: Color { onDark ? .white : .srStageText }
    private var fill: Color { onDark ? Color.white.opacity(0.16) : .srStageControl }
    private var selectedText: Color { onDark ? .srInk : .srOnInverse }
    private var selectedFill: Color { onDark ? .white : .srInverse }
}

struct EditorColorDots: View {
    let selected: EditColor
    var onDark = false
    let onPick: (EditColor) -> Void

    var body: some View {
        HStack(spacing: Space.xs) {
            ForEach(EditColor.allCases) { option in
                Button {
                    Haptics.selection()
                    onPick(option)
                } label: {
                    Circle()
                        .fill(option.color)
                        // A ring strong enough that the dot matching the panel (white in Light, black in
                        // Dark) still reads as a dot.
                        .overlay(Circle().strokeBorder(onDark ? Color.white.opacity(0.4) : Color.srStageTextTertiary.opacity(0.6),
                                                       lineWidth: 1))
                        .frame(width: 28, height: 28)
                        .padding(3)
                        .overlay(Circle().strokeBorder(option == selected ? (onDark ? Color.white : Color.srStageText) : .clear,
                                                       lineWidth: 2))
                        .frame(maxWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel(option.label)
                .accessibilityAddTraits(option == selected ? .isSelected : [])
            }
        }
    }
}
