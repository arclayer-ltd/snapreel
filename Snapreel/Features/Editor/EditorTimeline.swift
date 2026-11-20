import SwiftUI

/// The timeline under the preview: a time ruler, the filmstrip of kept sections and a row per
/// kind of overlay, scrolling under a fixed playhead in the middle. Drag to scrub, pinch to
/// zoom, tap a section to select it (its handles trim it), tap a chip to select that overlay.
struct EditorTimeline: View {
    @ObservedObject var model: EditorModel

    @State private var scrubStart: Double?
    @State private var zoomStart: CGFloat?

    static let rulerHeight: CGFloat = 20
    static let stripHeight: CGFloat = 52
    static let rowHeight: CGFloat = 30
    static let rowSpacing: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let pps = max(1, model.pointsPerSecond)
            let origin = width / 2 - CGFloat(model.playhead) * pps
            ZStack(alignment: .topLeading) {
                Color.srStage
                VStack(alignment: .leading, spacing: Self.rowSpacing) {
                    EditorRuler(origin: origin, pps: pps, duration: model.duration)
                        .frame(height: Self.rulerHeight)
                    filmstrip(width: width, origin: origin, pps: pps)
                        .frame(height: Self.stripHeight)
                    ForEach(rows, id: \.self) { row in
                        trackRow(row, width: width, origin: origin, pps: pps)
                            .frame(height: Self.rowHeight)
                    }
                }
                .padding(.top, 2)
                playheadLine(width: width)
                if model.showsTrimCoach && model.phase == .editing && model.tool == nil && model.selection == nil {
                    EditorTrimCoach { model.dismissTrimCoach() }
                        .frame(width: width)
                        .offset(y: Self.rulerHeight + Self.stripHeight + 8)
                        .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
            .gesture(scrub(pps: pps))
            .simultaneousGesture(zoom(width: width))
        }
        .frame(height: height)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Timeline")
    }

    // MARK: - Rows

    enum Row: Hashable { case text, shapes, captions, voice }

    private var rows: [Row] {
        var result: [Row] = []
        if model.hasPicture {
            result.append(.text)
            if !model.recipe.stickers.isEmpty || !model.recipe.blurs.isEmpty { result.append(.shapes) }
            if model.recipe.captions != nil { result.append(.captions) }
        }
        result.append(.voice)
        return result
    }

    private var height: CGFloat {
        2 + Self.rulerHeight + Self.stripHeight + CGFloat(rows.count) * (Self.rowHeight + Self.rowSpacing)
            + Self.rowSpacing + 6
    }

    // MARK: - Filmstrip

    private func filmstrip(width: CGFloat, origin: CGFloat, pps: CGFloat) -> some View {
        let layout = sectionLayout(origin: origin, pps: pps)
        return ZStack(alignment: .topLeading) {
            EditorFilmstrip(model: model, sections: layout, width: width)
                .gesture(SpatialTapGesture().onEnded { value in
                    guard let hit = layout.first(where: { $0.rect.minX <= value.location.x && value.location.x <= $0.rect.maxX }) else { return }
                    Haptics.selection()
                    let t = hit.outputStart + Double((value.location.x - hit.rect.minX) / pps)
                    model.toggleSegment(atOutput: t)
                })
            ForEach(layout) { section in
                if showsHandles(for: section) {
                    sectionChrome(section, width: width)
                }
            }
        }
    }

    /// Where each kept section is drawn this frame.
    struct SectionRect: Identifiable {
        let id: UUID
        let index: Int
        let rect: CGRect
        let outputStart: Double
        let outputLength: Double
        let speed: Double
    }

    private func sectionLayout(origin: CGFloat, pps: CGFloat) -> [SectionRect] {
        var result: [SectionRect] = []
        var cursor = 0.0
        let shift = model.trimShift
        for (index, segment) in model.recipe.segments.enumerated() {
            var x = origin + CGFloat(cursor) * pps
            if let shift, index >= shift.index { x += CGFloat(shift.seconds) * pps }
            let w = max(2, CGFloat(segment.outputLength) * pps)
            result.append(SectionRect(id: segment.id, index: index,
                                      rect: CGRect(x: x, y: 0, width: w, height: Self.stripHeight),
                                      outputStart: cursor, outputLength: segment.outputLength, speed: segment.speed))
            cursor += segment.outputLength
        }
        return result
    }

    private func showsHandles(for section: SectionRect) -> Bool {
        if model.selection == .segment(section.id) { return true }
        guard model.selection == nil else { return false }
        let first = section.index == 0
        let last = section.index == model.recipe.segments.count - 1
        if model.tool == .trim || (model.showsTrimCoach && model.tool == nil && model.phase == .editing) {
            return first || last
        }
        return false
    }

    /// Border, handles and length badge of a selected section (or the clip's ends in Trim).
    @ViewBuilder
    private func sectionChrome(_ section: SectionRect, width: CGFloat) -> some View {
        let selected = model.selection == .segment(section.id)
        let first = section.index == 0
        let last = section.index == model.recipe.segments.count - 1
        let visible = section.rect.intersection(CGRect(x: -40, y: 0, width: width + 80, height: Self.stripHeight))
        if selected, !visible.isNull {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.srStageText, lineWidth: 2.5)
                .frame(width: visible.width, height: Self.stripHeight)
                .offset(x: visible.minX)
                .allowsHitTesting(false)
            Text(section.speed == 1 ? EditorText.length(section.outputLength)
                 : "\(EditorText.length(section.outputLength)) · \(EditorText.speed(section.speed))")
                .font(.srTimerSmall)
                .foregroundStyle(Color.srOnInverse)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.srInverse))
                .offset(x: max(8, visible.minX + 8), y: 4)
                .allowsHitTesting(false)
        }
        if selected || first {
            EditorTrimHandle(edge: .start, bubble: bubble(for: section.id, edge: .start)) { phase, offset in
                drag(.segment(section.id), edge: .start, phase: phase, offset: offset)
            }
            .offset(x: section.rect.minX - EditorTrimHandle.width)
        }
        if selected || last {
            EditorTrimHandle(edge: .end, bubble: bubble(for: section.id, edge: .end)) { phase, offset in
                drag(.segment(section.id), edge: .end, phase: phase, offset: offset)
            }
            .offset(x: section.rect.maxX)
        }
    }

    private func bubble(for id: UUID, edge: TrimEdge) -> String? {
        guard let drag = model.trimDrag, drag.target == .segment(id), drag.edge == edge else { return nil }
        return model.trimBubble
    }

    private func drag(_ target: TrimTarget, edge: TrimEdge, phase: EditorTrimHandle.Phase, offset: CGFloat) {
        let pps = max(1, model.pointsPerSecond)
        switch phase {
        case .began:
            model.beginTrim(target, edge: edge)
        case .changed:
            model.updateTrim(offset: Double(offset / pps))
        case .ended:
            model.endTrim()
        }
    }

    // MARK: - Track rows

    @ViewBuilder
    private func trackRow(_ row: Row, width: CGFloat, origin: CGFloat, pps: CGFloat) -> some View {
        let clipStart = origin
        let clipEnd = origin + CGFloat(model.duration) * pps
        switch row {
        case .text:
            if model.recipe.texts.isEmpty {
                EditorAddRow(title: "Add text", systemImage: "plus", start: clipStart, end: clipEnd, width: width) {
                    model.open(.text)
                    model.addText()
                }
            } else {
                chips(textChips, width: width, origin: origin, pps: pps)
            }
        case .shapes:
            chips(shapeChips, width: width, origin: origin, pps: pps)
        case .captions:
            captionChips(width: width, origin: origin, pps: pps)
        case .voice:
            voiceRow(width: width, origin: origin, pps: pps, clipStart: clipStart, clipEnd: clipEnd)
        }
    }

    private var textChips: [ChipItem] {
        model.recipe.texts.map { item -> ChipItem in
            ChipItem(id: item.id, selection: .text(item.id), target: .text(item.id),
                     start: item.start, end: item.end, label: item.text, icon: "textformat")
        }
    }

    private var shapeChips: [ChipItem] {
        var items: [ChipItem] = []
        for item in model.recipe.stickers {
            let label: String = item.kind == .emoji ? (item.emoji ?? "") : item.kind.label
            let icon: String? = item.kind == .emoji ? nil : item.kind.systemImage
            items.append(ChipItem(id: item.id, selection: .sticker(item.id), target: .sticker(item.id),
                                  start: item.start, end: item.end, label: label, icon: icon))
        }
        for item in model.recipe.blurs {
            items.append(ChipItem(id: item.id, selection: .blur(item.id), target: .blur(item.id),
                                  start: item.start, end: item.end, label: "Blur", icon: "drop.fill"))
        }
        return items
    }

    struct ChipItem: Identifiable {
        let id: UUID
        let selection: EditorSelection
        let target: TrimTarget
        let start: Double
        let end: Double
        let label: String
        let icon: String?
    }

    private func chips(_ items: [ChipItem], width: CGFloat, origin: CGFloat, pps: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Color.clear
            ForEach(items) { item in
                let rect = CGRect(x: origin + CGFloat(item.start) * pps, y: 0,
                                  width: max(10, CGFloat(item.end - item.start) * pps), height: Self.rowHeight)
                let visible = rect.intersection(CGRect(x: -30, y: 0, width: width + 60, height: Self.rowHeight))
                let selected = model.selection == item.selection
                if !visible.isNull {
                    EditorChip(label: item.label, icon: item.icon, selected: selected)
                        .frame(width: visible.width, height: Self.rowHeight)
                        .offset(x: visible.minX)
                        .onTapGesture {
                            Haptics.selection()
                            if selected { model.selection = nil } else { model.selectOverlay(item.selection) }
                        }
                }
                if selected {
                    EditorTrimHandle(edge: .start, height: Self.rowHeight, bubble: chipBubble(item.target, .start)) { phase, offset in
                        drag(item.target, edge: .start, phase: phase, offset: offset)
                    }
                    .offset(x: rect.minX - EditorTrimHandle.width)
                    EditorTrimHandle(edge: .end, height: Self.rowHeight, bubble: chipBubble(item.target, .end)) { phase, offset in
                        drag(item.target, edge: .end, phase: phase, offset: offset)
                    }
                    .offset(x: rect.maxX)
                }
            }
        }
    }

    private func chipBubble(_ target: TrimTarget, _ edge: TrimEdge) -> String? {
        guard let drag = model.trimDrag, drag.target == target, drag.edge == edge else { return nil }
        return model.trimBubble
    }

    private func captionChips(width: CGFloat, origin: CGFloat, pps: CGFloat) -> some View {
        let lines = model.captionLines
        return ZStack(alignment: .leading) {
            Color.clear
            if lines.isEmpty {
                Text(model.transcriptPhase == .working ? "Making captions…" : "No speech for captions")
                    .font(.srCaption)
                    .foregroundStyle(Color.srStageTextTertiary)
                    .padding(.horizontal, Space.s)
                    .frame(height: Self.rowHeight)
                    .background(Capsule().strokeBorder(Color.srStageLine, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    .offset(x: max(8, origin))
            }
            ForEach(lines) { line in
                let rect = CGRect(x: origin + CGFloat(line.start) * pps, y: 0,
                                  width: max(8, CGFloat(line.end - line.start) * pps - 2), height: Self.rowHeight)
                let visible = rect.intersection(CGRect(x: -30, y: 0, width: width + 60, height: Self.rowHeight))
                if !visible.isNull {
                    EditorChip(label: line.text, icon: nil, selected: false, faded: line.isHidden)
                        .frame(width: visible.width, height: Self.rowHeight)
                        .offset(x: visible.minX)
                        .onTapGesture {
                            model.open(.captions)
                            model.seek(to: line.start + 0.01, exact: true)
                        }
                }
            }
        }
    }

    @ViewBuilder
    private func voiceRow(width: CGFloat, origin: CGFloat, pps: CGFloat, clipStart: CGFloat, clipEnd: CGFloat) -> some View {
        let clips = model.recipe.voiceClips
        let recording: (Double, Double)? = {
            switch model.voice {
            case .recording(let start): return (start, max(start, model.playhead))
            case .review(let take): return (take.start, take.start + take.duration)
            default: return nil
            }
        }()
        if clips.isEmpty && recording == nil {
            EditorAddRow(title: "Voice-over", systemImage: "mic", start: clipStart, end: clipEnd, width: width) {
                model.open(.voice)
            }
        } else {
            ZStack(alignment: .leading) {
                Color.clear
                ForEach(clips) { clip in
                    let rect = CGRect(x: origin + CGFloat(clip.start) * pps, y: 0,
                                      width: max(8, CGFloat(clip.duration) * pps), height: Self.rowHeight)
                    let visible = rect.intersection(CGRect(x: -30, y: 0, width: width + 60, height: Self.rowHeight))
                    let selected = model.selection == .voice(clip.id)
                    if !visible.isNull {
                        EditorVoiceChip(seed: clip.fileName.hashValue, selected: selected, live: false)
                            .frame(width: visible.width, height: Self.rowHeight)
                            .offset(x: visible.minX)
                            .onTapGesture {
                                Haptics.selection()
                                if selected { model.selection = nil } else { model.selectOverlay(.voice(clip.id)) }
                            }
                    }
                }
                if let recording {
                    let rect = CGRect(x: origin + CGFloat(recording.0) * pps, y: 0,
                                      width: max(4, CGFloat(recording.1 - recording.0) * pps), height: Self.rowHeight)
                    let visible = rect.intersection(CGRect(x: -30, y: 0, width: width + 60, height: Self.rowHeight))
                    if !visible.isNull {
                        EditorVoiceChip(seed: 7, selected: false, live: true)
                            .frame(width: visible.width, height: Self.rowHeight)
                            .offset(x: visible.minX)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    // MARK: - Playhead and gestures

    private func playheadLine(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            Circle()
                .fill(Color.srRed)
                .frame(width: 11, height: 11)
            Rectangle()
                .fill(Color.srStageText)
                .frame(width: 2)
        }
        .frame(width: 12)
        .offset(x: width / 2 - 6, y: Self.rulerHeight - 6)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func scrub(pps: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard model.trimDrag == nil else { return }
                if scrubStart == nil {
                    model.pause()
                    model.dismissTrimCoach()
                    scrubStart = model.playhead
                }
                model.seek(to: (scrubStart ?? 0) - Double(value.translation.width / pps))
            }
            .onEnded { _ in
                if scrubStart != nil { model.seek(to: model.playhead, exact: true) }
                scrubStart = nil
            }
    }

    private func zoom(width: CGFloat) -> some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                if zoomStart == nil { zoomStart = model.pointsPerSecond }
                let minimum = max(2, width * 0.6 / CGFloat(max(model.duration, 0.5)))
                model.pointsPerSecond = min(240, max(minimum, (zoomStart ?? 40) * scale))
            }
            .onEnded { _ in zoomStart = nil }
    }
}

// MARK: - Pieces

/// Seconds along the top, spaced so labels never crowd.
struct EditorRuler: View {
    let origin: CGFloat
    let pps: CGFloat
    let duration: Double

    var body: some View {
        Canvas { context, size in
            let steps: [Double] = [0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600]
            let step = steps.first { CGFloat($0) * pps >= 56 } ?? 600
            let first = max(0, floor(Double((-origin) / pps) / step) * step)
            var t = first
            while t <= duration + 0.001 {
                let x = origin + CGFloat(t) * pps
                if x > size.width + 40 { break }
                let label = Text(Format.clock(t)).font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundColor(Color.srStageTextTertiary)
                context.draw(label, at: CGPoint(x: x, y: size.height / 2 - 1), anchor: .center)
                let half = x + CGFloat(step / 2) * pps
                if t + step / 2 <= duration {
                    let dot = Path(ellipseIn: CGRect(x: half - 1.5, y: size.height / 2 - 2.5, width: 3, height: 3))
                    context.fill(dot, with: .color(Color.srStageTextTertiary.opacity(0.6)))
                }
                t += step
            }
        }
        .allowsHitTesting(false)
    }
}

/// Frames of the kept sections, drawn only where they are on screen.
struct EditorFilmstrip: View {
    @ObservedObject var model: EditorModel
    let sections: [EditorTimeline.SectionRect]
    let width: CGFloat

    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 36
            for section in sections {
                let rect = section.rect.insetBy(dx: 1, dy: 0)
                guard rect.maxX > -cell, rect.minX < size.width + cell else { continue }
                let shape = Path(roundedRect: rect, cornerRadius: 6)
                context.drawLayer { layer in
                    layer.clip(to: shape)
                    layer.fill(shape, with: .color(model.hasPicture ? Color.srInkRaised : Color.srStageControl))
                    if model.hasPicture {
                        var x = max(rect.minX, floor((0 - rect.minX) / cell) * cell + rect.minX)
                        while x < min(rect.maxX, size.width + cell) {
                            let t = section.outputStart + Double((x + cell / 2 - rect.minX) / max(1, model.pointsPerSecond))
                            let source = model.recipe.sourceTime(forOutput: min(t, section.outputStart + section.outputLength))
                            if let image = model.filmImage(atSource: source) {
                                let resolved = layer.resolve(Image(uiImage: image))
                                let imageSize = image.size
                                let scale = max(cell / max(1, imageSize.width), size.height / max(1, imageSize.height))
                                let drawn = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
                                let cellRect = CGRect(x: x, y: 0, width: cell, height: size.height)
                                layer.drawLayer { cellLayer in
                                    cellLayer.clip(to: Path(cellRect))
                                    cellLayer.draw(resolved, in: CGRect(x: x + (cell - drawn.width) / 2,
                                                                       y: (size.height - drawn.height) / 2,
                                                                       width: drawn.width, height: drawn.height))
                                }
                            }
                            x += cell
                        }
                    } else {
                        // A voice recording: a waveform-like strip.
                        var x = max(rect.minX, 0)
                        var index = Int(x / 5)
                        while x < min(rect.maxX, size.width) {
                            let level = 0.25 + 0.55 * abs(sin(Double(index) * 0.7)) * abs(cos(Double(index) * 0.23))
                            let h = size.height * CGFloat(level)
                            layer.fill(Path(roundedRect: CGRect(x: x, y: (size.height - h) / 2, width: 3, height: h), cornerRadius: 1.5),
                                       with: .color(Color.srStageTextSecondary.opacity(0.7)))
                            x += 5
                            index += 1
                        }
                    }
                    if section.speed != 1 {
                        let badge = Text(EditorText.speed(section.speed)).font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                        layer.fill(Path(roundedRect: CGRect(x: max(rect.minX, 0) + 4, y: size.height - 18, width: 34, height: 14),
                                        cornerRadius: 7), with: .color(Color.black.opacity(0.6)))
                        layer.draw(badge, at: CGPoint(x: max(rect.minX, 0) + 21, y: size.height - 11), anchor: .center)
                    }
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(model.recipe.segments.count == 1 ? "Video clip" : "\(model.recipe.segments.count) sections")
        .accessibilityHint("Tap to select a section")
    }
}

/// The grip at either end of a selected section or overlay; drag it to trim.
struct EditorTrimHandle: View {
    enum Phase { case began, changed, ended }

    static let width: CGFloat = 16

    let edge: TrimEdge
    var height: CGFloat = EditorTimeline.stripHeight
    var bubble: String?
    let onDrag: (Phase, CGFloat) -> Void

    @State private var dragging = false

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.srStageText)
            .overlay(
                Capsule().fill(Color.srStage).frame(width: 3, height: height * 0.36)
            )
            .frame(width: Self.width, height: height)
            .overlay(alignment: .top) {
                if let bubble {
                    Text(bubble)
                        .font(.srTimerSmall)
                        .foregroundStyle(Color.srOnInverse)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.srInverse))
                        .fixedSize()
                        .offset(y: -24)
                }
            }
            .contentShape(Rectangle().inset(by: -8))
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if !dragging {
                            dragging = true
                            Haptics.selection()
                            onDrag(.began, 0)
                        }
                        onDrag(.changed, value.translation.width)
                    }
                    .onEnded { _ in
                        dragging = false
                        onDrag(.ended, 0)
                    }
            )
            .accessibilityLabel(edge == .start ? "Start handle" : "End handle")
            .accessibilityHint("Drag to trim")
    }
}

/// An overlay on its track.
struct EditorChip: View {
    let label: String
    let icon: String?
    let selected: Bool
    var faded = false

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
            }
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(faded ? Color.srStageTextTertiary : Color.srStageText)
        .padding(.horizontal, 7)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.srStageControl))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(selected ? Color.srStageText : Color.clear, lineWidth: 2))
        .padding(.horizontal, 1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A voice-over on its track (or the take being recorded).
struct EditorVoiceChip: View {
    let seed: Int
    let selected: Bool
    let live: Bool

    var body: some View {
        Canvas { context, size in
            var x: CGFloat = 6
            var index = abs(seed % 13)
            while x < size.width - 4 {
                let level = 0.3 + 0.6 * abs(sin(Double(index) * 0.9)) * abs(cos(Double(index) * 0.31))
                let h = (size.height - 10) * CGFloat(level)
                context.fill(Path(roundedRect: CGRect(x: x, y: (size.height - h) / 2, width: 2, height: h), cornerRadius: 1),
                             with: .color(live ? Color.white : Color.srStageTextSecondary))
                x += 4
                index += 1
            }
        }
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(live ? Color.srRed : Color.srStageControl))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(selected ? Color.srStageText : Color.clear, lineWidth: 2))
        .padding(.horizontal, 1)
        .accessibilityLabel(live ? "Recording voice-over" : "Voice-over")
    }
}

/// A dashed row inviting the first item of its kind ("+ Add text", "+ Voice-over").
struct EditorAddRow: View {
    let title: String
    let systemImage: String
    let start: CGFloat
    let end: CGFloat
    let width: CGFloat
    let action: () -> Void

    var body: some View {
        let left = max(8, start)
        let right = min(width - 8, max(end, left + 120))
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .bold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.srStageTextSecondary)
            .padding(.horizontal, 10)
            .frame(width: max(120, right - left), height: EditorTimeline.rowHeight)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.srStageTextTertiary.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
        .offset(x: left)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// First open: how trimming works, once.
struct EditorTrimCoach: View {
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: "hand.draw.fill")
                .font(.system(size: 14, weight: .semibold))
            Text("Drag the handles to trim. Tap the clip to select a part.")
                .font(.srFootnote.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Got it")
        }
        .foregroundStyle(Color.white)
        .padding(.leading, Space.s)
        .padding(.trailing, Space.xxs)
        .padding(.vertical, Space.xs)
        .background(Capsule().fill(Color.srRed))
        .overlay(alignment: .top) {
            EditorCoachPointer()
                .fill(Color.srRed)
                .frame(width: 14, height: 8)
                .offset(y: -7)
        }
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .padding(.horizontal, Space.l)
        .frame(maxWidth: .infinity)
        .onTapGesture { dismiss() }
    }
}

private struct EditorCoachPointer: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
