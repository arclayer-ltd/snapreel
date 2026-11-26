import SwiftUI

/// A tool's panel in place of the tool bar. Each has a title and a Done button that goes back
/// to the tools; the preview and the timeline stay in view above it.
struct EditorToolPanel: View {
    @ObservedObject var model: EditorModel
    let tool: EditorTool

    var body: some View {
        VStack(spacing: 0) {
            header
            // A tall panel (large text, small screen) scrolls; the picture always keeps some room.
            EditorPanelHeight(limit: UIScreen.main.bounds.height * 0.4) {
                switch tool {
                case .trim: EditorTrimPanel(model: model)
                case .crop: EditorCropPanel(model: model)
                case .text: EditorTextPanel(model: model)
                case .shapes: EditorShapesPanel(model: model)
                case .captions: EditorCaptionsPanel(model: model)
                case .voice: EditorVoicePanel(model: model)
                case .sound: EditorSoundPanel(model: model)
                case .blur: EditorBlurPanel(model: model)
                case .thumbnail: EditorThumbnailPanel(model: model)
                case .transcript, .speed: EmptyView()
                }
            }
            .padding(.bottom, Space.xs)
        }
    }

    private var header: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: tool.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.srStageRed)
            Text(tool.title)
                .font(.srHeadline)
                .foregroundStyle(Color.srStageText)
            Spacer(minLength: 0)
            Button {
                Haptics.tap()
                withAnimation(Motion.quick) { model.closeTool() }
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.srOnInverse)
                    .opacity(model.isRecordingVoice ? 0.4 : 1)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.srInverse))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle())
            .disabled(model.isRecordingVoice)
            .accessibilityLabel("Done")
        }
        .padding(.leading, Space.gutter)
        .padding(.trailing, Space.xs)
        .frame(height: 46)
    }
}

/// Its content as it is, or scrolling when it is taller than `limit`.
struct EditorPanelHeight<Content: View>: View {
    let limit: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        EditorCappedHeight(limit: limit) {
            ViewThatFits(in: .vertical) {
                content()
                ScrollView(.vertical) { content() }
            }
        }
    }
}

/// As tall as its content wants, at most `limit`.
private struct EditorCappedHeight: Layout {
    let limit: CGFloat

    private func height(_ width: CGFloat?, _ subviews: Subviews) -> CGSize {
        let wanted = subviews.first?.sizeThatFits(ProposedViewSize(width: width, height: nil)) ?? .zero
        return CGSize(width: width ?? wanted.width, height: min(wanted.height, limit))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        height(proposal.width, subviews)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

/// Text that names the playhead's time, drawn again only when the second changes.
struct EditorPlayheadText: View {
    @ObservedObject var seconds: EditorSeconds
    let text: (String) -> String

    init(_ model: EditorModel, _ text: @escaping (String) -> String) {
        self.seconds = model.clock.seconds
        self.text = text
    }

    var body: some View { Text(text(Format.clock(Double(seconds.whole)))) }
}

/// A small helper line under a panel's controls.
struct EditorHint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.srFootnote)
            .foregroundStyle(Color.srStageTextTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.gutter)
    }
}

/// A rounded action in a panel.
struct EditorPanelButton: View {
    let title: String
    let systemImage: String
    var prominent = false
    var isDestructive = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Label(title, systemImage: systemImage)
                .font(.srSubheadlineStrong)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(prominent ? Color.white : (isDestructive ? Color.srStageRed : Color.srStageText))
                .padding(.horizontal, Space.m)
                .frame(minHeight: 40)
                .background(Capsule().fill(prominent ? Color.srRed : Color.srStageControl))
                .padding(.vertical, 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .layoutPriority(1)
    }
}

/// Start–end of an overlay, on one line.
struct EditorSpanLabel: View {
    let start: Double
    let end: Double

    var body: some View {
        Text("\(EditorText.precise(start))–\(EditorText.precise(end))")
            .font(.srTimerSmall)
            .foregroundStyle(Color.srStageTextTertiary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

// MARK: - Trim

struct EditorTrimPanel: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        VStack(spacing: Space.s) {
            HStack(spacing: Space.s) {
                fact("Start", EditorText.precise(model.recipe.segments.first?.start ?? 0))
                fact("End", EditorText.precise(model.recipe.segments.last?.end ?? 0))
                fact("Length", EditorText.precise(model.duration))
            }
            .padding(.horizontal, Space.gutter)
            // The quick way on a long recording: no handle to drag across minutes of it.
            HStack(spacing: Space.xs) {
                action("Start here", "arrow.right.to.line", hint: "Cuts everything before the playhead") { model.cutToPlayhead(.start) }
                action("Split", "scissors", hint: "Splits the clip at the playhead") { model.splitAtPlayhead() }
                action("End here", "arrow.left.to.line", hint: "Cuts everything after the playhead") { model.cutToPlayhead(.end) }
            }
            .padding(.horizontal, Space.gutter)
            EditorHint(text: "Drag the handles, or move the playhead and cut there. Split, then tap a part to delete it or change its speed.")
        }
    }

    private func action(_ title: String, _ systemImage: String, hint: String, _ body: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            body()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(height: 20)
                Text(title)
                    .font(.srSubheadlineStrong)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(Color.srStageText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.xs)
            .background(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).fill(Color.srStageControl))
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityHint(hint)
    }

    private func fact(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.srCaption)
                .foregroundStyle(Color.srStageTextTertiary)
            Text(value)
                .font(.srTimer)
                .foregroundStyle(Color.srStageText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s)
        .padding(.vertical, Space.xs)
        .background(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).fill(Color.srStageRaised))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Crop

struct EditorCropPanel: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        VStack(spacing: Space.s) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.xs) {
                    ForEach(EditAspect.allCases) { aspect in
                        aspectButton(aspect)
                    }
                }
                .padding(.horizontal, Space.gutter)
            }
            HStack(spacing: Space.s) {
                EditorPanelButton(title: "Rotate", systemImage: "rotate.right") { model.rotate() }
                EditorPanelButton(title: "Flip", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right") {
                    model.flip()
                }
                Spacer(minLength: 0)
                Button { model.resetCrop() } label: {
                    Text("Reset")
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                    .font(.srSubheadlineStrong)
                    .foregroundStyle(Color.srStageTextSecondary)
                    .disabled(model.recipe.crop.isFullFrame && model.recipe.quarterTurns == 0 && !model.recipe.flipped)
            }
            .padding(.horizontal, Space.gutter)
        }
    }

    private func aspectButton(_ aspect: EditAspect) -> some View {
        let selected = model.recipe.crop.aspect == aspect
        return Button {
            model.setAspect(aspect)
        } label: {
            VStack(spacing: 5) {
                aspectIcon(aspect)
                    .frame(width: 26, height: 26)
                Text(aspect.label)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(selected ? Color.srStageRed : Color.srStageText)
            .frame(width: 58, height: 58)
            .background(RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                .fill(selected ? Color.srRedSoft : Color.srStageControl))
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(aspect == .free ? "Free crop" : "Crop \(aspect.label)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The shape drawn in its own proportions.
    @ViewBuilder
    private func aspectIcon(_ aspect: EditAspect) -> some View {
        switch aspect {
        case .original:
            Image(systemName: "rectangle.dashed").font(.system(size: 18, weight: .semibold))
        case .free:
            Image(systemName: "crop").font(.system(size: 18, weight: .semibold))
        default:
            let ratio = aspect.ratio ?? 1
            let width: CGFloat = ratio >= 1 ? 24 : 24 * ratio
            let height: CGFloat = ratio >= 1 ? 24 / ratio : 24
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(lineWidth: 2)
                .frame(width: width, height: height)
        }
    }
}

// MARK: - Text

struct EditorTextPanel: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        if let item = model.selectedText {
            VStack(spacing: Space.s) {
                EditorTextStyleRow(style: item.style, color: item.color,
                                   onStyle: { style in model.updateText(item.id) { $0.style = style } },
                                   onColor: { color in model.updateText(item.id) { $0.color = color } })
                EditorHint(text: "Drag it to move it, drag the white corner to resize it, tap it to change the words.")
                HStack(spacing: Space.s) {
                    EditorPanelButton(title: "Edit", systemImage: "pencil") { model.editText(item) }
                    EditorPanelButton(title: "Delete", systemImage: "trash", isDestructive: true) { model.deleteText(item.id) }
                    Spacer(minLength: 0)
                    EditorSpanLabel(start: item.start, end: item.end)
                }
                .padding(.horizontal, Space.gutter)
            }
        } else {
            VStack(spacing: Space.s) {
                HStack {
                    EditorPanelButton(title: "Add text", systemImage: "plus", prominent: true) { model.addText() }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Space.gutter)
                EditorHint(text: model.recipe.texts.isEmpty
                           ? "Text starts at the playhead and shows for 3 seconds. Drag its ends on the timeline to change that."
                           : "Tap a text on the video or the timeline to change it. Drag to move, pinch to resize.")
            }
        }
    }
}

// MARK: - Shapes and emoji

struct EditorShapesPanel: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        VStack(spacing: Space.s) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.xs) {
                    ForEach(EditStickerKind.allCases) { kind in
                        Button {
                            if kind == .emoji {
                                Haptics.tap()
                                model.sheet = .emoji
                            } else {
                                model.addSticker(kind)
                            }
                        } label: {
                            VStack(spacing: 5) {
                                Image(systemName: kind.systemImage)
                                    .font(.system(size: 20, weight: .semibold))
                                    .frame(height: 24)
                                Text(kind.label)
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(Color.srStageText)
                            .frame(width: 66, height: 58)
                            .background(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).fill(Color.srStageControl))
                        }
                        .buttonStyle(PressScaleStyle())
                        .accessibilityLabel("Add \(kind.label.lowercased())")
                    }
                }
                .padding(.horizontal, Space.gutter)
            }
            if let item = model.selectedSticker {
                HStack(spacing: Space.s) {
                    if item.kind != .emoji {
                        EditorColorDots(selected: item.color) { color in
                            model.updateSticker(item.id) { $0.color = color }
                        }
                    }
                    Spacer(minLength: 0)
                    CircleIconButton(systemName: "trash", label: "Delete", tone: .stage, size: 44) {
                        model.deleteSticker(item.id)
                    }
                }
                .padding(.horizontal, Space.gutter)
                EditorHint(text: item.kind == .circle || item.kind == .emoji
                           ? "Drag it to move it. Drag the white corner to make it larger or smaller."
                           : "Drag it to move it. Drag the white corner to resize and turn it. Drag its bar on the timeline to move it in time.")
            } else {
                EditorHint(text: "Point at what matters in a screen recording. Drag to place, pinch to resize, twist to turn.")
            }
        }
    }
}

// MARK: - Captions

struct EditorCaptionsPanel: View {
    @ObservedObject var model: EditorModel
    @ObservedObject private var transcripts: TranscriptService = .shared

    var body: some View {
        switch model.transcriptPhase {
        case .notStarted:
            message(icon: "captions.bubble", title: "Captions come from the transcript",
                    detail: "Snapreel makes it on this iPhone. Nothing is uploaded.") {
                EditorPanelButton(title: "Make a transcript", systemImage: "text.alignleft", prominent: true) {
                    model.requestTranscript()
                }
            }
        case .working:
            message(icon: "waveform", title: "Making captions…",
                    detail: "Listening to the recording on this iPhone. This takes about a quarter of its length.") {
                ProgressView(value: model.transcriptPhaseOverride != nil ? 0.45 : transcripts.progress)
                    .tint(Color.srRed)
                    .frame(maxWidth: 220)
            }
        case .unavailable(let reason):
            message(icon: "speaker.slash", title: reason == .noSpeech ? "No speech found" : "No transcript for this one",
                    detail: reason == .noSpeech
                        ? "Captions need someone talking. You can still add text."
                        : "Captions need a transcript, and this recording couldn't get one.") {
                EditorPanelButton(title: "Add text instead", systemImage: "textformat") {
                    model.open(.text)
                }
            }
        case .ready:
            if let captions = model.recipe.captions {
                VStack(spacing: Space.s) {
                    HStack(spacing: Space.xs) {
                        ForEach(EditCaptionStyle.allCases) { style in
                            styleTile(style, selected: captions.style == style)
                        }
                    }
                    .padding(.horizontal, Space.gutter)
                    HStack(spacing: Space.s) {
                        EditorPanelButton(title: "Edit words", systemImage: "pencil") { model.sheet = .captionWords }
                        EditorPanelButton(title: "Remove", systemImage: "trash", isDestructive: true) { model.removeCaptions() }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Space.gutter)
                }
            } else {
                message(icon: "captions.bubble", title: "Add captions from your transcript",
                        detail: "Timed to your voice and saved into the video. You can fix any word.") {
                    EditorPanelButton(title: "Add captions", systemImage: "plus", prominent: true) { model.addCaptions() }
                }
            }
        }
    }

    private func message<Action: View>(icon: String, title: String, detail: String,
                                       @ViewBuilder action: () -> Action) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .top, spacing: Space.s) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.srStageRed)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.srRedSoft))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.srSubheadlineStrong)
                        .foregroundStyle(Color.srStageText)
                    Text(detail)
                        .font(.srFootnote)
                        .foregroundStyle(Color.srStageTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            action()
                .padding(.leading, 48)
        }
        .padding(.horizontal, Space.gutter)
    }

    private func styleTile(_ style: EditCaptionStyle, selected: Bool) -> some View {
        Button {
            model.setCaptionStyle(style)
        } label: {
            VStack(spacing: 6) {
                EditCaptionStyleSample(style: style)
                    .frame(height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(style.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(selected ? Color.srStageRed : Color.srStageText)
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                .strokeBorder(selected ? Color.srRed : Color.srStageLine, lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(PressScaleStyle())
        .frame(maxWidth: .infinity)
        .accessibilityLabel("\(style.label) captions")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Voice-over

struct EditorVoicePanel: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        switch model.voice {
        case .primer:
            prompt(icon: "mic.fill", title: "Talk over your video",
                   detail: "Snapreel needs the microphone to record your voice. It stays on this iPhone.") {
                EditorPanelButton(title: "Allow microphone", systemImage: "mic", prominent: true) { model.requestMicrophone() }
            }
        case .denied:
            prompt(icon: "mic.slash.fill", title: "The microphone is off for Snapreel",
                   detail: "Turn it on in Settings to record a voice-over.") {
                EditorPanelButton(title: "Open Settings", systemImage: "gearshape") { Permissions.openSettings() }
            }
        case .ready:
            if case .voice(let id) = model.selection, let clip = model.recipe.voiceClips.first(where: { $0.id == id }) {
                selectedClip(clip)
            } else {
                ready
            }
        case .countdown(let count):
            HStack(spacing: Space.m) {
                Text("\(count)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.srStageRed)
                    .frame(width: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Get ready…")
                        .font(.srHeadline)
                        .foregroundStyle(Color.srStageText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    EditorPlayheadText(model) { "Recording starts at \($0)." }
                        .font(.srFootnote)
                        .foregroundStyle(Color.srStageTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button("Cancel") { model.cancelCountdown() }
                    .buttonStyle(.srSecondaryCompact)
            }
            .padding(.horizontal, Space.gutter)
            .frame(minHeight: 84)
        case .recording:
            HStack(spacing: Space.m) {
                Button {
                    model.stopRecording()
                } label: {
                    RecordButtonShape(isRecording: true, diameter: 64)
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel("Stop recording")
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Circle().fill(Color.srRed).frame(width: 8, height: 8)
                        EditorPlayheadText(model) { _ in "Recording · \(Format.clock(model.recordingElapsed))" }
                            .font(.srTimer)
                            .foregroundStyle(Color.srStageText)
                    }
                    EditorLevelMeter(level: model.voiceLevel)
                        .frame(height: 16)
                    Text("The video plays muted while you talk.")
                        .font(.srFootnote)
                        .foregroundStyle(Color.srStageTextTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.gutter)
            .frame(minHeight: 96)
        case .review(let take):
            VStack(alignment: .leading, spacing: Space.s) {
                HStack(spacing: Space.xs) {
                    Image(systemName: "waveform")
                        .foregroundStyle(Color.srStageRed)
                    Text("New take · \(EditorText.length(take.duration)) from \(Format.clock(take.start))")
                        .font(.srSubheadlineStrong)
                        .foregroundStyle(Color.srStageText)
                }
                HStack(spacing: Space.s) {
                    CircleIconButton(systemName: model.isPlaying ? "stop.fill" : "play.fill",
                                     label: model.isPlaying ? "Stop" : "Play the take", tone: .stage, size: 44) {
                        model.playTake(take)
                    }
                    EditorPanelButton(title: "Re-record", systemImage: "arrow.counterclockwise") { model.rerecord(take) }
                    Spacer(minLength: 0)
                    EditorPanelButton(title: "Use take", systemImage: "checkmark", prominent: true) { model.keepTake(take) }
                }
            }
            .padding(.horizontal, Space.gutter)
        }
    }

    private var ready: some View {
        HStack(spacing: Space.m) {
            Button {
                model.startCountdown()
            } label: {
                RecordButtonShape(isRecording: false, diameter: 64)
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel("Record voice-over")
            VStack(alignment: .leading, spacing: 3) {
                EditorPlayheadText(model) { "Record from \($0)" }
                    .font(.srHeadline)
                    .foregroundStyle(Color.srStageText)
                Text("Move the playhead to where you want to start. The video plays muted while you talk.")
                    .font(.srFootnote)
                    .foregroundStyle(Color.srStageTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.vertical, Space.xs)
    }

    private func selectedClip(_ clip: EditVoiceClip) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Voice-over · \(EditorText.length(clip.duration)) from \(Format.clock(clip.start))")
                .font(.srSubheadlineStrong)
                .foregroundStyle(Color.srStageText)
            HStack(spacing: Space.s) {
                EditorPanelButton(title: "Record another", systemImage: "mic") {
                    model.selection = nil
                }
                EditorPanelButton(title: "Delete", systemImage: "trash", isDestructive: true) { model.deleteVoiceClip(clip.id) }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, Space.gutter)
    }

    private func prompt<Action: View>(icon: String, title: String, detail: String,
                                      @ViewBuilder action: () -> Action) -> some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.srStageRed)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.srRedSoft))
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(title)
                    .font(.srSubheadlineStrong)
                    .foregroundStyle(Color.srStageText)
                Text(detail)
                    .font(.srFootnote)
                    .foregroundStyle(Color.srStageTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                action()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.gutter)
    }
}

struct EditorLevelMeter: View {
    let level: Float

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 3) {
                ForEach(0..<20, id: \.self) { index in
                    Capsule()
                        .fill(Float(index) / 20 < level ? Color.srRed : Color.srStageControl)
                        .frame(width: max(2, (proxy.size.width - 57) / 20))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Sound

struct EditorSoundPanel: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        let audio = model.recipe.audio
        VStack(spacing: Space.s) {
            HStack(spacing: Space.s) {
                Button {
                    model.toggleMute()
                } label: {
                    Image(systemName: audio.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(audio.muted ? Color.srStageRed : Color.srStageText)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.srStageControl))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(audio.muted ? "Unmute recording" : "Mute recording")
                VStack(alignment: .leading, spacing: 0) {
                    Text("Recording's sound")
                        .font(.srCaption)
                        .foregroundStyle(Color.srStageTextSecondary)
                    Slider(value: Binding(get: { model.recipe.audio.volume },
                                          set: { model.setVolume($0, live: true) }),
                           in: 0...1, onEditingChanged: { editing in if !editing { model.endLiveChange() } })
                        .tint(Color.srRed)
                        .disabled(audio.muted)
                        .accessibilityLabel("Recording's sound")
                }
                Text(audio.muted ? "Off" : "\(Int((audio.volume * 100).rounded()))%")
                    .font(.srTimerSmall)
                    .foregroundStyle(Color.srStageTextSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: 44, alignment: .trailing)
            }
            if !model.recipe.voiceClips.isEmpty {
                HStack(spacing: Space.s) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.srStageText)
                        .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Voice-over")
                            .font(.srCaption)
                            .foregroundStyle(Color.srStageTextSecondary)
                        Slider(value: Binding(get: { model.recipe.audio.voiceVolume },
                                              set: { model.setVoiceVolume($0, live: true) }),
                               in: 0...1, onEditingChanged: { editing in if !editing { model.endLiveChange() } })
                            .tint(Color.srRed)
                            .accessibilityLabel("Voice-over volume")
                    }
                    Text("\(Int((audio.voiceVolume * 100).rounded()))%")
                        .font(.srTimerSmall)
                        .foregroundStyle(Color.srStageTextSecondary)
                        .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: 44, alignment: .trailing)
                }
            }
            HStack(spacing: Space.xs) {
                toggleChip("Fade in", on: audio.fadeIn) { model.toggleFadeIn() }
                toggleChip("Fade out", on: audio.fadeOut) { model.toggleFadeOut() }
                Spacer(minLength: 0)
            }
            noiseRow(audio)
        }
        .padding(.horizontal, Space.gutter)
    }

    private func toggleChip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                Text(title)
            }
            .font(.srSubheadlineStrong)
            .foregroundStyle(on ? Color.srOnInverse : Color.srStageText)
            .padding(.horizontal, Space.s)
            .frame(minHeight: 36)
            .background(Capsule().fill(on ? Color.srInverse : Color.srStageControl))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder
    private func noiseRow(_ audio: EditAudio) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Toggle(isOn: Binding(get: { audio.reducesNoise }, set: { model.setNoiseReduction($0) })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Reduce background noise")
                        .font(.srSubheadlineStrong)
                        .foregroundStyle(Color.srStageText)
                    Text(noiseDetail(audio))
                        .font(.srFootnote)
                        .foregroundStyle(Color.srStageTextTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Color.srRed)
            if case .working(let progress) = model.noise {
                ProgressView(value: progress)
                    .tint(Color.srRed)
            }
            if audio.reducesNoise && model.noise == .ready {
                PillSwitch(options: [true, false], selection: Binding(get: { model.hearsOriginalSound },
                                                                      set: { model.setHearsOriginal($0) }),
                           title: { $0 ? "Before" : "After" })
            }
        }
        .padding(Space.s)
        .background(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).fill(Color.srStageRaised))
    }

    private func noiseDetail(_ audio: EditAudio) -> String {
        switch model.noise {
        case .working: return "Cleaning up the sound on this iPhone…"
        case .failed: return "This recording's sound couldn't be cleaned up."
        case .ready where audio.reducesNoise: return "Hum, hiss and room noise turned down."
        default: return "Turns down hum, hiss and room noise between words."
        }
    }
}

// MARK: - Blur

struct EditorBlurPanel: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        VStack(spacing: Space.s) {
            HStack(spacing: Space.s) {
                EditorPanelButton(title: "Add blur", systemImage: "plus", prominent: model.selectedBlur == nil) { model.addBlur() }
                if let blur = model.selectedBlur {
                    EditorPanelButton(title: "Delete", systemImage: "trash", isDestructive: true) { model.deleteBlur(blur.id) }
                }
                Spacer(minLength: 0)
                if let blur = model.selectedBlur {
                    EditorSpanLabel(start: blur.start, end: blur.end)
                }
            }
            .padding(.horizontal, Space.gutter)
            EditorHint(text: model.selectedBlur == nil
                       ? "Hide passwords, emails or faces. The blur covers a box you place, for as long as you choose."
                       : "Drag the box over what to hide and its corner to resize. Drag its ends on the timeline to time it.")
        }
    }
}

// MARK: - Thumbnail

struct EditorThumbnailPanel: View {
    @ObservedObject var model: EditorModel
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        Group {
            if textSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Space.s) {
                    text
                    button
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: Space.m) {
                    text
                    Spacer(minLength: 0)
                    button
                }
            }
        }
        .padding(.horizontal, Space.gutter)
        .padding(.vertical, Space.xs)
    }

    private var button: some View {
        EditorPanelButton(title: model.recipe.thumbnailTime == nil ? "Use this frame" : "Use this one",
                          systemImage: "photo", prominent: true) {
            model.chooseThumbnail()
        }
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let time = model.recipe.thumbnailTime {
                Label("Frame at \(EditorText.precise(time))", systemImage: "checkmark.circle.fill")
                    .font(.srSubheadlineStrong)
                    .foregroundStyle(Color.srStageText)
                    .labelStyle(EditorTintedIconLabel())
                Text("Your library shows this frame for the new recording.")
                    .font(.srFootnote)
                    .foregroundStyle(Color.srStageTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Scrub to the frame people should see")
                    .font(.srSubheadlineStrong)
                    .foregroundStyle(Color.srStageText)
                    .fixedSize(horizontal: false, vertical: true)
                Text("It becomes the picture on the recording's card in your library.")
                    .font(.srFootnote)
                    .foregroundStyle(Color.srStageTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A caption style shown on a small dark picture.
struct EditCaptionStyleSample: View {
    let style: EditCaptionStyle

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [Color(hex: 0x3A3D4A), Color(hex: 0x1C1E27)], startPoint: .top, endPoint: .bottom)
            sample
                .padding(.bottom, style == .bar ? 0 : 6)
        }
    }

    @ViewBuilder
    private var sample: some View {
        let text = Text("Hello there").font(.system(size: 11, weight: .semibold))
        switch style {
        case .classic:
            text
                .foregroundStyle(Color.white)
                .shadow(color: .black.opacity(0.9), radius: 0, x: 0, y: 1)
        case .box:
            text
                .foregroundStyle(Color.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Color.black.opacity(0.75)))
        case .bar:
            text
                .foregroundStyle(Color(hex: 0x13141B))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.92))
        }
    }
}

/// A label whose icon is the accent colour.
struct EditorTintedIconLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.foregroundStyle(Color.srStageRed)
            configuration.title
        }
    }
}
