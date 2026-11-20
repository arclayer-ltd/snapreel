import SwiftUI

// MARK: - Cut by transcript

/// The transcript as sentence blocks: tap one to cut it from the video, tap again to bring it
/// back. "Remove filler words" opens a review of the ums and uhs it found.
struct EditorTranscriptSheet: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var transcripts: TranscriptService
    @State private var reviewsFillers: Bool
    @State private var chosenFillers: Set<String>?

    init(model: EditorModel, transcripts: TranscriptService, reviewsFillers: Bool = false) {
        self.model = model
        self.transcripts = transcripts
        _reviewsFillers = State(initialValue: reviewsFillers || EditorDebugState.opensFillerReview)
    }

    var body: some View {
        VStack(spacing: 0) {
            if reviewsFillers {
                fillerReview
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                sentences
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .background(Color.srStageRaised.ignoresSafeArea())
        .animation(Motion.standard, value: reviewsFillers)
    }

    // MARK: Sentences

    private var sentences: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Cut by transcript", trailingTitle: "Done", trailingAction: { model.sheet = nil }, onStage: true)
            switch model.transcriptPhase {
            case .ready:
                if let transcript = model.transcript {
                    readyList(transcript)
                }
            case .notStarted:
                EditorEmptyMessage(icon: "text.alignleft", title: "Make a transcript first",
                                   detail: "Snapreel listens to the recording on this iPhone and writes down what's said. Then you can cut sentences by tapping them.") {
                    Button("Make a transcript") { model.requestTranscript() }
                        .buttonStyle(.srPrimary)
                }
            case .working:
                EditorEmptyMessage(icon: "waveform", title: "Making the transcript…",
                                   detail: "This takes about a quarter of the recording's length. You can keep this open.") {
                    ProgressView(value: model.transcriptPhaseOverride != nil ? 0.4 : transcripts.progress)
                        .tint(Color.srRed)
                        .frame(maxWidth: 240)
                }
            case .unavailable(let reason):
                EditorEmptyMessage(icon: "speaker.slash",
                                   title: reason == .noSpeech ? "No speech found" : "No transcript for this recording",
                                   detail: reason == .permissionDenied
                                       ? "Speech recognition is off for Snapreel. Turn it on in Settings to cut by transcript."
                                       : "Cutting by transcript needs someone talking. Trim on the timeline instead.") {
                    if reason == .permissionDenied {
                        Button("Open Settings") { Permissions.openSettings() }
                            .buttonStyle(.srSecondary)
                    }
                }
            }
        }
    }

    private func readyList(_ transcript: Transcript) -> some View {
        let removed = transcript.segments.filter { model.isRemoved($0) }
        let fillers = model.fillers
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s) {
                    if !fillers.isEmpty {
                        Button {
                            Haptics.tap()
                            chosenFillers = Set(fillers.map(\.id))
                            reviewsFillers = true
                        } label: {
                            HStack(spacing: Space.xs) {
                                Image(systemName: "wand.and.stars")
                                Text("Remove filler words (\(fillers.count))")
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .font(.srSubheadlineStrong)
                            .foregroundStyle(Color.srStageRed)
                            .padding(.horizontal, Space.m)
                            .frame(height: 46)
                            .background(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).fill(Color.srRedSoft))
                        }
                        .buttonStyle(PressScaleStyle(scale: 0.98))
                    }
                    Text("Tap a sentence to cut it. Tap it again to bring it back.")
                        .font(.srFootnote)
                        .foregroundStyle(Color.srStageTextSecondary)
                    ForEach(paragraphs(transcript), id: \.first?.id) { paragraph in
                        if let first = paragraph.first {
                            Text(Format.clock(first.start))
                                .font(.srTimerSmall)
                                .foregroundStyle(Color.srStageTextTertiary)
                                .padding(.top, Space.xs)
                        }
                        ForEach(paragraph) { segment in
                            sentence(segment)
                        }
                    }
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.l)
            }
            footer(removed: removed)
        }
    }

    /// Sentences grouped where there is a pause, like paragraphs.
    private func paragraphs(_ transcript: Transcript) -> [[TranscriptSegment]] {
        var groups: [[TranscriptSegment]] = []
        for segment in transcript.segments {
            if let last = groups.last?.last, segment.start - (last.start + last.duration) < 2.5, groups[groups.count - 1].count < 4 {
                groups[groups.count - 1].append(segment)
            } else {
                groups.append([segment])
            }
        }
        return groups
    }

    private func sentence(_ segment: TranscriptSegment) -> some View {
        let removed = model.isRemoved(segment)
        return Button {
            model.toggleSentence(segment)
        } label: {
            HStack(alignment: .top, spacing: Space.xs) {
                Text(segment.text)
                    .font(.srCallout.weight(.semibold))
                    .strikethrough(removed, color: Color.srStageRed)
                    .foregroundStyle(removed ? Color.srStageTextTertiary : Color.srStageText)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                if removed {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(Color.srStageRed)
                        .font(.system(size: 16))
                }
            }
            .padding(.horizontal, Space.s)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                .fill(removed ? Color.srStageRaised : Color.srStageControl))
            .overlay(RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                .strokeBorder(removed ? Color.srStageLine : Color.clear, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
        .accessibilityLabel(segment.text)
        .accessibilityValue(removed ? "Cut" : "Kept")
        .accessibilityHint(removed ? "Brings the sentence back" : "Cuts the sentence from the video")
    }

    private func footer(removed: [TranscriptSegment]) -> some View {
        let removedSeconds = removed.reduce(0) { $0 + $1.duration }
        return HStack {
            if removed.isEmpty {
                Text("Nothing cut yet")
            } else {
                Text("\(removed.count) \(removed.count == 1 ? "sentence" : "sentences") cut · \(Format.clock(removedSeconds)) shorter")
            }
            Spacer(minLength: 0)
            Text("New length \(Format.clock(model.duration))")
        }
        .font(.srFootnote.weight(.semibold))
        .foregroundStyle(Color.srStageTextSecondary)
        .padding(.horizontal, Space.gutter)
        .frame(height: 48)
        .background(Color.srStageRaised.overlay(alignment: .top) { Rectangle().fill(Color.srStageLine).frame(height: 0.5) })
    }

    // MARK: Filler review

    private var fillerReview: some View {
        let fillers = model.fillers
        let chosen = chosenFillers ?? Set(fillers.map(\.id))
        return VStack(spacing: 0) {
            SheetHeader(title: "Filler words", leadingTitle: "Back",
                        leadingAction: { reviewsFillers = false }, onStage: true)
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s) {
                    Text("These sound like ums and uhs. Untick any you want to keep.")
                        .font(.srFootnote)
                        .foregroundStyle(Color.srStageTextSecondary)
                    VStack(spacing: 0) {
                        ForEach(fillers) { filler in
                            fillerRow(filler, isOn: chosen.contains(filler.id)) {
                                var next = chosen
                                if next.contains(filler.id) { next.remove(filler.id) } else { next.insert(filler.id) }
                                chosenFillers = next
                            }
                            if filler.id != fillers.last?.id {
                                Rectangle().fill(Color.srStageLine).frame(height: 0.5).padding(.leading, 44)
                            }
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(Color.srStageGroup))
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.l)
            }
            Button(chosen.isEmpty ? "Choose words to remove" : "Remove \(chosen.count) \(chosen.count == 1 ? "word" : "words")") {
                model.removeFillers(fillers.filter { chosen.contains($0.id) })
                reviewsFillers = false
            }
            .buttonStyle(.srPrimary)
            .disabled(chosen.isEmpty)
            .padding(.horizontal, Space.gutter)
            .padding(.vertical, Space.s)
        }
    }

    private func fillerRow(_ filler: EditFiller, isOn: Bool, toggle: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            toggle()
        } label: {
            HStack(spacing: Space.s) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isOn ? Color.srRed : Color.srStageTextTertiary)
                    .frame(width: 28)
                (Text(filler.before.isEmpty ? "" : "…\(filler.before) ")
                    .foregroundColor(Color.srStageTextSecondary)
                 + Text(filler.text).bold().foregroundColor(Color.srStageText)
                 + Text(filler.after.isEmpty ? "" : " \(filler.after)…")
                    .foregroundColor(Color.srStageTextSecondary))
                    .font(.srSubheadline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Text(Format.clock(filler.start))
                    .font(.srTimerSmall)
                    .foregroundStyle(Color.srStageTextTertiary)
            }
            .padding(.horizontal, Space.s)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Icon, title, a line and an action, centred in a sheet.
struct EditorEmptyMessage<Action: View>: View {
    let icon: String
    let title: String
    let detail: String
    @ViewBuilder let action: () -> Action

    var body: some View {
        VStack(spacing: Space.m) {
            Spacer(minLength: Space.xl)
            ZStack {
                Circle().fill(Color.srRedSoft)
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.srStageRed)
            }
            .frame(width: 64, height: 64)
            VStack(spacing: Space.xs) {
                Text(title)
                    .font(.srTitle3)
                    .foregroundStyle(Color.srStageText)
                Text(detail)
                    .font(.srSubheadline)
                    .foregroundStyle(Color.srStageTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            action()
            Spacer(minLength: Space.xl)
        }
        .padding(.horizontal, Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Speed

struct EditorSpeedSheet: View {
    @ObservedObject var model: EditorModel
    @State private var wholeVideo: Bool

    static let speeds: [Double] = [0.5, 1, 1.25, 1.5, 2]

    init(model: EditorModel) {
        self.model = model
        _wholeVideo = State(initialValue: model.selectedSegment == nil)
    }

    var body: some View {
        VStack(spacing: Space.m) {
            SheetHeader(title: "Speed", trailingTitle: "Done", trailingAction: { model.sheet = nil }, onStage: true)
            if model.selectedSegment != nil {
                PillSwitch(options: [true, false], selection: $wholeVideo,
                           title: { $0 ? "Whole video" : "This part" })
            }
            HStack(spacing: Space.xs) {
                ForEach(Self.speeds, id: \.self) { speed in
                    let selected = abs(current - speed) < 0.001
                    Button {
                        model.setSpeed(speed, wholeVideo: wholeVideo)
                    } label: {
                        Text(EditorText.speed(speed))
                            .font(.system(.callout, design: .rounded).weight(.bold))
                            .foregroundStyle(selected ? Color.srOnInverse : Color.srStageText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                                .fill(selected ? Color.srInverse : Color.srStageControl))
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityLabel("\(EditorText.speed(speed)) speed")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, Space.gutter)
            VStack(spacing: 4) {
                Text("New length \(Format.clock(model.duration))")
                    .font(.srSubheadlineStrong)
                    .foregroundStyle(Color.srStageText)
                Text("Voices keep their normal pitch.")
                    .font(.srFootnote)
                    .foregroundStyle(Color.srStageTextTertiary)
            }
            Spacer(minLength: 0)
        }
        .background(Color.srStageRaised.ignoresSafeArea())
    }

    private var current: Double {
        if !wholeVideo, let segment = model.selectedSegment { return segment.speed }
        let speeds = Set(model.recipe.segments.map(\.speed))
        return speeds.count == 1 ? (speeds.first ?? 1) : -1
    }
}

// MARK: - Export

/// 720p / 1080p / Original, with the estimated size and whether the iPhone has room.
struct EditorExportSheet: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        let quality = model.recipe.quality
        let bytes = model.estimatedBytes(quality)
        let room = model.hasRoom(for: quality)
        VStack(spacing: Space.m) {
            SheetHeader(title: "Save as a new recording", leadingTitle: "Cancel",
                        leadingAction: { model.sheet = nil }, onStage: true)
            if model.hasPicture {
                VStack(spacing: Space.xs) {
                    PillSwitch(options: ExportQuality.allCases,
                               selection: Binding(get: { model.recipe.quality }, set: { model.setQuality($0) }),
                               title: { $0.label })
                    Text(quality.helper)
                        .font(.srFootnote)
                        .foregroundStyle(Color.srStageTextSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Space.gutter)
            }
            VStack(spacing: 0) {
                row("Length", Format.clock(model.duration))
                if model.hasPicture {
                    let size = model.recipe.renderSize(source: model.pictureSize, quality: quality)
                    row("Picture", "\(Int(size.width)) × \(Int(size.height))")
                }
                row("Estimated size", "About \(Format.bytes(bytes))")
                row("Free on this iPhone", Format.bytes(max(0, model.availableBytes)), warns: !room)
            }
            .padding(.horizontal, Space.m)
            .background(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(Color.srStageGroup))
            .padding(.horizontal, Space.gutter)
            if !room {
                HStack(alignment: .top, spacing: Space.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.srStageRed)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Not enough space")
                            .font(.srSubheadlineStrong)
                            .foregroundStyle(Color.srStageText)
                        Text(model.hasPicture && quality != .hd720
                             ? "Free up space in Settings › General › iPhone Storage, or choose 720p for a smaller file."
                             : "Free up space in Settings › General › iPhone Storage, then try again.")
                            .font(.srFootnote)
                            .foregroundStyle(Color.srStageTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(Space.s)
                .background(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).fill(Color.srRedSoft))
                .padding(.horizontal, Space.gutter)
            } else {
                Text("Your original stays as it is. The edit is added to your library with an \u{201C}Edited\u{201D} badge.")
                    .font(.srFootnote)
                    .foregroundStyle(Color.srStageTextTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Space.gutter)
            }
            Spacer(minLength: 0)
            Button("Save") { model.startExport() }
                .buttonStyle(.srPrimary)
                .disabled(!room)
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.s)
        }
        .background(Color.srStageRaised.ignoresSafeArea())
    }

    private func row(_ title: String, _ value: String, warns: Bool = false) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(Color.srStageTextSecondary)
            Spacer(minLength: Space.s)
            Text(value)
                .foregroundStyle(warns ? Color.srStageRed : Color.srStageText)
                .fontWeight(.semibold)
        }
        .font(.srSubheadline)
        .frame(height: 42)
    }
}

// MARK: - Leave the editor

struct EditorDiscardSheet: View {
    let onKeepDraft: () -> Void
    let onDiscard: () -> Void
    let onKeepEditing: () -> Void

    var body: some View {
        VStack(spacing: Space.m) {
            VStack(spacing: Space.xs) {
                Text("Leave the editor?")
                    .font(.srTitle3)
                    .foregroundStyle(Color.srStageText)
                Text("Keep your edits as a draft to finish later, or throw them away. Your recording isn't changed either way.")
                    .font(.srSubheadline)
                    .foregroundStyle(Color.srStageTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, Space.l)
            VStack(spacing: Space.s) {
                Button("Keep draft") { onKeepDraft() }
                    .buttonStyle(.srPrimary)
                Button("Discard changes") { onDiscard() }
                    .buttonStyle(.srDestructive)
                Button("Keep editing") { onKeepEditing() }
                    .buttonStyle(.srTertiary)
            }
        }
        .padding(.horizontal, Space.gutter)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.srStageRaised.ignoresSafeArea())
    }
}

// MARK: - Caption words

struct EditorCaptionWordsSheet: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Edit captions", trailingTitle: "Done", trailingAction: { model.sheet = nil }, onStage: true)
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s) {
                    Text("Fix any word the transcript got wrong, or hide a line.")
                        .font(.srFootnote)
                        .foregroundStyle(Color.srStageTextSecondary)
                    ForEach(model.captionLines) { line in
                        EditorCaptionLineRow(line: line,
                                             onCommit: { model.editCaption(line.id, text: $0) },
                                             onToggle: { model.toggleCaptionHidden(line.id) })
                    }
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.l)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color.srStageRaised.ignoresSafeArea())
    }
}

private struct EditorCaptionLineRow: View {
    let line: EditCaptionLine
    let onCommit: (String) -> Void
    let onToggle: () -> Void

    @State private var text: String
    @FocusState private var focused: Bool

    init(line: EditCaptionLine, onCommit: @escaping (String) -> Void, onToggle: @escaping () -> Void) {
        self.line = line
        self.onCommit = onCommit
        self.onToggle = onToggle
        _text = State(initialValue: line.text)
    }

    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            Text(Format.clock(line.start))
                .font(.srTimerSmall)
                .foregroundStyle(Color.srStageTextTertiary)
                .frame(width: 40, alignment: .leading)
                .padding(.top, 10)
            TextField("Caption", text: $text, axis: .vertical)
                .font(.srCallout)
                .foregroundStyle(line.isHidden ? Color.srStageTextTertiary : Color.srStageText)
                .strikethrough(line.isHidden)
                .focused($focused)
                .padding(.horizontal, Space.s)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).fill(Color.srStageControl))
                .onChange(of: focused) { isFocused in
                    if !isFocused && text != line.text { onCommit(text) }
                }
                .onSubmit { onCommit(text) }
            Button {
                Haptics.selection()
                onToggle()
            } label: {
                Image(systemName: line.isHidden ? "eye.slash" : "eye")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(line.isHidden ? Color.srStageTextTertiary : Color.srStageText)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel(line.isHidden ? "Show caption" : "Hide caption")
        }
    }
}

// MARK: - Rendering

/// Saving the edit: progress with Cancel, then failure with Try again, or "Saved as a new
/// recording" with Open and Share. Follows the library row, so it shows the real state.
struct EditorRenderingView: View {
    @ObservedObject var model: EditorModel
    let videoID: UUID
    let onOpen: () -> Void
    let onShare: () -> Void
    let onDone: () -> Void

    @EnvironmentObject private var library: Library

    var body: some View {
        ZStack {
            Color.srStage.ignoresSafeArea()
            if let video = library.video(videoID) {
                content(video)
            } else {
                content(nil)
            }
        }
    }

    @ViewBuilder
    private func content(_ video: Video?) -> some View {
        VStack(spacing: Space.l) {
            Spacer(minLength: Space.l)
            preview(video)
            switch video?.state {
            case .ready?:
                done(video!)
            case .failed(let reason, _)?:
                failed(reason)
            case .saving(let progress)?:
                saving(progress)
            case nil:
                saving(0.02)
            }
        }
        .padding(.horizontal, Space.gutter)
        .padding(.bottom, Space.l)
    }

    private func preview(_ video: Video?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(Color.black)
            if let still = model.stillImage(fullFrame: false) {
                Image(uiImage: still)
                    .resizable()
                    .scaledToFit()
            } else if !model.hasPicture {
                Image(systemName: "waveform")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(Color.srRed)
            }
            if case .ready? = video?.state {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.white, Color.srRed)
                    .shadow(color: .black.opacity(0.3), radius: 6)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
    }

    private func saving(_ progress: Double) -> some View {
        VStack(spacing: Space.m) {
            VStack(spacing: Space.xs) {
                Text("Saving your edit")
                    .font(.srTitle)
                    .foregroundStyle(Color.srStageText)
                Text("As a new recording. Your original stays as it is.")
                    .font(.srSubheadline)
                    .foregroundStyle(Color.srStageTextSecondary)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: Space.xs) {
                ProgressView(value: min(1, max(0, progress)))
                    .tint(Color.srRed)
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.srTimerSmall)
                    .foregroundStyle(Color.srStageTextSecondary)
            }
            Text("You can leave the editor. Saving carries on in your library.")
                .font(.srFootnote)
                .foregroundStyle(Color.srStageTextTertiary)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
            Button("Cancel") { model.cancelExport(videoID) }
                .buttonStyle(.srSecondary)
        }
    }

    private func failed(_ reason: String) -> some View {
        VStack(spacing: Space.m) {
            VStack(spacing: Space.xs) {
                Text("Couldn't save the edit")
                    .font(.srTitle)
                    .foregroundStyle(Color.srStageText)
                Text(reason)
                    .font(.srSubheadline)
                    .foregroundStyle(Color.srStageTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            VStack(spacing: Space.s) {
                Button("Try again") { model.retryExport(videoID) }
                    .buttonStyle(.srPrimary)
                Button("Back to the editor") { model.cancelExport(videoID); model.backToEditing() }
                    .buttonStyle(.srSecondary)
            }
        }
    }

    private func done(_ video: Video) -> some View {
        VStack(spacing: Space.m) {
            VStack(spacing: Space.xs) {
                Text("Saved as a new recording")
                    .font(.srTitle)
                    .foregroundStyle(Color.srStageText)
                Text("\u{201C}\(video.title)\u{201D} · \(Format.clock(video.duration)) · \(Format.bytes(video.fileSize))")
                    .font(.srSubheadline)
                    .foregroundStyle(Color.srStageTextSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            VStack(spacing: Space.s) {
                Button("Open") { onOpen() }
                    .buttonStyle(.srPrimary)
                HStack(spacing: Space.s) {
                    Button {
                        onShare()
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.srSecondary)
                    Button("Done") { onDone() }
                        .buttonStyle(.srSecondary)
                }
            }
        }
    }
}

/// Debug-only switches for sheet states CI can't tap into.
enum EditorDebugState {
    static var opensFillerReview = false
}
