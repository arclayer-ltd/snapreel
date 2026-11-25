import Combine
import SwiftUI
import UIKit

/// The timeline under the preview: a time ruler, the filmstrip of kept sections and a row per
/// kind of overlay, scrolling under a fixed playhead in the middle. Drag to scrub (it keeps
/// rolling after a flick), pinch to zoom, tap a section to select it (its handles trim it), tap a
/// chip to select that overlay.
///
/// It is a UIKit scroll view: scrolling moves finished layers and draws nothing, so it stays
/// smooth on an iPhone X whatever the recording's length, and gestures that are interrupted (a
/// call, a second finger) always end properly, which SwiftUI's don't on iOS 16.
struct EditorTimeline: View {
    @ObservedObject var model: EditorModel

    static let rulerHeight: CGFloat = 20
    static let stripHeight: CGFloat = 52
    static let rowHeight: CGFloat = 32
    static let rowSpacing: CGFloat = 6
    static let topPadding: CGFloat = 2

    var body: some View {
        let state = EditorTimelineState(model: model)
        EditorTimelineRepresentable(model: model, state: state)
            .frame(height: Self.height(rows: state.rows.count))
            .overlay(alignment: .top) {
                if model.showsTrimCoach && model.phase == .editing && model.tool == nil && model.selection == nil {
                    EditorTrimCoach { model.dismissTrimCoach() }
                        .offset(y: Self.rulerHeight + Self.stripHeight + 8)
                        .transition(.opacity)
                }
            }
    }

    static func height(rows: Int) -> CGFloat {
        topPadding + rulerHeight + rowSpacing + stripHeight + CGFloat(rows) * (rowHeight + rowSpacing) + 6
    }
}

enum EditorTimelineRow: Hashable { case text, shapes, captions, voice }

/// Everything the timeline shows, except where the playhead is.
struct EditorTimelineState: Equatable {
    struct Chip: Equatable {
        var id: String
        var selection: EditorSelection?
        var target: TrimTarget?
        var start: Double
        var end: Double
        var label: String
        var icon: String?
        var faded = false
        var caption = false
        var levels: [Float]?
        var lead = 0.0
    }

    struct Handle: Equatable {
        var target: TrimTarget
        var edge: TrimEdge
        /// Output seconds.
        var time: Double
        var row: EditorTimelineRow?
        var bubble: String?
        /// VoiceOver.
        var value: String
    }

    var segments: [EditSegment]
    /// Sections from this one on are drawn this much later (a start handle being dragged).
    var shiftIndex = Int.max
    var shift = 0.0
    var selectedSegment: UUID?
    var handles: [Handle] = []
    var rows: [EditorTimelineRow]
    var chips: [EditorTimelineRow: [Chip]] = [:]
    var selection: EditorSelection?
    var recordingStart: Double?
    var take: ClosedRange<Double>?
    var emptyCaptions: String?
    var pps: CGFloat
    var duration: Double
    var hasPicture: Bool
    var isLocked: Bool
    var isDragging: Bool
    var tile: CGFloat
    var sourceLevels: [Float]?
    /// The rows invite their first item.
    var invitesText: Bool
    var invitesVoice: Bool

    @MainActor
    init(model: EditorModel) {
        let recipe = model.recipe
        segments = recipe.segments
        pps = max(0.2, model.pointsPerSecond)
        duration = model.duration
        hasPicture = model.hasPicture
        isLocked = model.isRecordingVoice
        isDragging = model.trimDrag != nil
        selection = model.selection
        sourceLevels = model.hasPicture ? nil : model.levels["source"]
        let size = model.pictureSize
        tile = min(92, max(36, EditorTimeline.stripHeight * size.width / max(1, size.height)))
        if let moved = model.trimShift {
            shiftIndex = moved.index
            shift = moved.seconds
        }

        // While a tool is open only its own row shows, so the picture keeps the room.
        var rows: [EditorTimelineRow] = []
        let hasShapes = !recipe.stickers.isEmpty || !recipe.blurs.isEmpty
        switch model.tool {
        case nil:
            if hasPicture {
                rows.append(.text)
                if hasShapes { rows.append(.shapes) }
                if recipe.captions != nil { rows.append(.captions) }
            }
            rows.append(.voice)
        case .text: rows = [.text]
        case .shapes, .blur: rows = hasShapes ? [.shapes] : []
        case .captions: rows = recipe.captions != nil ? [.captions] : []
        case .voice, .sound: rows = [.voice]
        case .trim, .crop, .thumbnail, .transcript, .speed: rows = []
        }
        self.rows = rows

        chips[.text] = recipe.texts.map {
            Chip(id: $0.id.uuidString, selection: .text($0.id), target: .text($0.id), start: $0.start, end: $0.end,
                 label: $0.text, icon: "textformat")
        }
        chips[.shapes] = recipe.stickers.map {
            Chip(id: $0.id.uuidString, selection: .sticker($0.id), target: .sticker($0.id), start: $0.start, end: $0.end,
                 label: $0.kind == .emoji ? ($0.emoji ?? "") : $0.kind.label, icon: $0.kind == .emoji ? nil : $0.kind.systemImage)
        } + recipe.blurs.map {
            Chip(id: $0.id.uuidString, selection: .blur($0.id), target: .blur($0.id), start: $0.start, end: $0.end,
                 label: "Blur", icon: "drop.fill")
        }
        if rows.contains(.captions) {
            let lines = model.captionLines
            chips[.captions] = lines.map {
                Chip(id: $0.id, start: $0.start, end: $0.end, label: $0.text, faded: $0.isHidden, caption: true)
            }
            if lines.isEmpty { emptyCaptions = model.transcriptPhase == .working ? "Making captions…" : "No speech for captions" }
        }
        chips[.voice] = recipe.voiceClips.map {
            Chip(id: $0.id.uuidString, selection: .voice($0.id), start: $0.start, end: $0.start + $0.duration, label: "Voice-over",
                 levels: model.levels[$0.fileName] ?? [], lead: $0.lead ?? 0)
        }
        switch model.voice {
        case .recording(let start): recordingStart = start
        case .review(let take): self.take = take.start...(take.start + max(0.1, take.duration))
        default: break
        }
        invitesText = recipe.texts.isEmpty
        invitesVoice = recipe.voiceClips.isEmpty && recordingStart == nil && take == nil

        // Handles: of the selected section or overlay, or of the clip's two ends in Trim.
        let bubble = model.trimDrag.map { ($0, model.trimBubble) }
        func handle(_ target: TrimTarget, _ edge: TrimEdge, _ time: Double, row: EditorTimelineRow? = nil) -> Handle {
            let text: String? = bubble.flatMap { $0.0.target == target && $0.0.edge == edge ? $0.1 : nil }
            return Handle(target: target, edge: edge, time: time, row: row, bubble: text, value: EditorText.precise(time))
        }
        func sectionHandles(_ index: Int, start: Bool, end: Bool) -> [Handle] {
            let segment = segments[index]
            let from = recipe.outputStart(ofSegment: index) + (index >= shiftIndex ? shift : 0)
            var result: [Handle] = []
            if start { result.append(handle(.segment(segment.id), .start, from)) }
            if end { result.append(handle(.segment(segment.id), .end, from + segment.outputLength)) }
            return result
        }
        if !isLocked {
            switch model.selection {
            case .segment(let id):
                selectedSegment = id
                if let index = recipe.segmentIndex(id) { handles = sectionHandles(index, start: true, end: true) }
            case .text(let id):
                if let item = recipe.texts.first(where: { $0.id == id }) {
                    handles = [handle(.text(id), .start, item.start, row: .text), handle(.text(id), .end, item.end, row: .text)]
                }
            case .sticker(let id):
                if let item = recipe.stickers.first(where: { $0.id == id }) {
                    handles = [handle(.sticker(id), .start, item.start, row: .shapes), handle(.sticker(id), .end, item.end, row: .shapes)]
                }
            case .blur(let id):
                if let item = recipe.blurs.first(where: { $0.id == id }) {
                    handles = [handle(.blur(id), .start, item.start, row: .shapes), handle(.blur(id), .end, item.end, row: .shapes)]
                }
            case .voice:
                break
            case nil:
                let trimming = model.tool == .trim || (model.showsTrimCoach && model.tool == nil && model.phase == .editing)
                if trimming, !segments.isEmpty {
                    if segments.count == 1 {
                        handles = sectionHandles(0, start: true, end: true)
                    } else {
                        handles = sectionHandles(0, start: true, end: false)
                            + sectionHandles(segments.count - 1, start: false, end: true)
                    }
                }
            }
        }
    }
}

struct EditorTimelineRepresentable: UIViewRepresentable {
    let model: EditorModel
    let state: EditorTimelineState

    func makeUIView(context: Context) -> EditorTimelineView {
        let view = EditorTimelineView(model: model)
        view.apply(state)
        return view
    }

    func updateUIView(_ view: EditorTimelineView, context: Context) {
        view.apply(state)
    }

    static func dismantleUIView(_ view: EditorTimelineView, coordinator: ()) {
        view.stop()
    }
}

// MARK: - The view

/// Lets a drag that starts on one of its buttons scroll.
private final class EditorTimelineScroll: UIScrollView {
    override func touchesShouldCancel(in view: UIView) -> Bool { true }
}

/// The handles at the two ends of the clip stick out of it.
private final class EditorTimelineContent: UIView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { true }
}

final class EditorTimelineView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    private let model: EditorModel
    private var state: EditorTimelineState
    private let scroll = EditorTimelineScroll()
    private let content = EditorTimelineContent()
    private let ruler = EditorRulerView()
    private let playheadLine = UIView()
    private let playheadKnob = UIView()
    private let scrubber = EditorScrubElement()
    private let selectionBorder = UIView()
    private let lengthBadge = EditorBadgeLabel()
    private let addText = EditorAddRowButton(title: "Add text", systemImage: "plus")
    private let addVoice = EditorAddRowButton(title: "Voice-over", systemImage: "mic")
    private let captionsNote = EditorAddRowButton(title: "", systemImage: nil)
    private let liveTake = EditorWaveView()
    private var sectionViews: [UUID: EditorSectionView] = [:]
    private var chipViews: [String: EditorChipView] = [:]
    private var handleViews: [String: EditorHandleView] = [:]
    private var subscriptions: [AnyCancellable] = []

    /// The finger (or its momentum) moves the timeline; otherwise the playhead does.
    private var isUserScrolling = false
    private var isZooming = false
    private var zoomStart: CGFloat = 0
    private var handleDrag: (key: String, scrolled: CGFloat, touch: CGFloat)?
    private var edgeLink: CADisplayLink?
    /// Content width while a handle is dragged, so the timeline doesn't jump under the finger.
    private var heldWidth: CGFloat?
    private var prepared: ClosedRange<CGFloat>?
    private var wantTask: DispatchWorkItem?

    private var pps: CGFloat { state.pps }

    init(model: EditorModel) {
        self.model = model
        self.state = EditorTimelineState(model: model)
        super.init(frame: .zero)
        backgroundColor = UIColor(Color.srStage)
        clipsToBounds = true
        accessibilityIdentifier = "editor.timeline"

        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.alwaysBounceVertical = false
        scroll.bounces = false
        scroll.delaysContentTouches = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.scrollsToTop = false
        scroll.delegate = self
        scroll.isAccessibilityElement = false
        addSubview(scroll)
        scroll.addSubview(content)
        content.addSubview(ruler)

        selectionBorder.isUserInteractionEnabled = false
        selectionBorder.layer.cornerRadius = 6
        selectionBorder.layer.cornerCurve = .continuous
        selectionBorder.layer.borderWidth = 2.5
        selectionBorder.isHidden = true
        content.addSubview(selectionBorder)
        lengthBadge.isHidden = true
        content.addSubview(lengthBadge)
        for view in [addText, addVoice, captionsNote] as [UIView] { content.addSubview(view) }
        captionsNote.isUserInteractionEnabled = false
        liveTake.isUserInteractionEnabled = false
        liveTake.isLive = true
        liveTake.isHidden = true
        content.addSubview(liveTake)
        addText.addAction(UIAction { [weak self] _ in self?.tappedAddText() }, for: .touchUpInside)
        addVoice.addAction(UIAction { [weak self] _ in
            Haptics.tap()
            self?.model.open(.voice)
        }, for: .touchUpInside)

        playheadLine.isUserInteractionEnabled = false
        playheadKnob.isUserInteractionEnabled = false
        playheadLine.backgroundColor = UIColor(Color.srStageText)
        playheadKnob.backgroundColor = UIColor(Color.srRed)
        playheadKnob.layer.cornerRadius = 5.5
        addSubview(playheadLine)
        addSubview(playheadKnob)

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tap.delegate = self
        scroll.addGestureRecognizer(tap)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
        addGestureRecognizer(pinch)

        scrubber.model = model
        addSubview(scrubber)

        model.filmstrip.onUpdate = { [weak self] in self?.refreshTiles() }
        model.clock.$time
            .sink { [weak self] time in self?.follow(time) }
            .store(in: &subscriptions)
        updateColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func stop() {
        edgeLink?.invalidate()
        edgeLink = nil
        wantTask?.cancel()
        subscriptions = []
    }

    // MARK: - State

    func apply(_ next: EditorTimelineState) {
        guard next != state else { return }
        let zoomed = next.pps != state.pps
        let locked = next.isLocked
        let startedDrag = next.isDragging && !state.isDragging
        let endedDrag = !next.isDragging && state.isDragging
        if startedDrag { heldWidth = contentWidth(state) }
        if endedDrag { heldWidth = nil }
        state = next
        scroll.isScrollEnabled = !locked
        prepared = nil
        if bounds.width > 0 {
            layoutContent()
            if !isUserScrolling && handleDrag == nil { place(model.playhead) }
            refresh()
            if zoomed { scheduleTiles() }
        }
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        updateColors()
    }

    private func updateColors() {
        selectionBorder.layer.borderColor = UIColor(Color.srStageText).resolvedColor(with: traitCollection).cgColor
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        scroll.frame = bounds
        scroll.contentInset = UIEdgeInsets(top: 0, left: bounds.width / 2, bottom: 0, right: bounds.width / 2)
        let top = EditorTimeline.topPadding + EditorTimeline.rulerHeight
        playheadLine.frame = CGRect(x: bounds.midX - 1, y: top - 2, width: 2, height: bounds.height - top + 2)
        playheadKnob.frame = CGRect(x: bounds.midX - 5.5, y: top - 8, width: 11, height: 11)
        scrubber.frame = CGRect(x: 0, y: 0, width: bounds.width, height: top)
        prepared = nil
        layoutContent()
        if !isUserScrolling && handleDrag == nil { place(model.playhead) }
        refresh()
    }

    private func contentWidth(_ state: EditorTimelineState) -> CGFloat {
        max(1, CGFloat(state.duration + (state.shiftIndex == .max ? 0 : state.shift)) * state.pps)
    }

    private func layoutContent() {
        let size = CGSize(width: max(contentWidth(state), heldWidth ?? 0), height: bounds.height)
        if scroll.contentSize != size { scroll.contentSize = size }
        content.frame = CGRect(origin: .zero, size: size)
    }

    private static var stripTop: CGFloat { EditorTimeline.topPadding + EditorTimeline.rulerHeight + EditorTimeline.rowSpacing }

    private func rowTop(_ row: EditorTimelineRow) -> CGFloat? {
        guard let index = state.rows.firstIndex(of: row) else { return nil }
        return Self.stripTop + EditorTimeline.stripHeight + EditorTimeline.rowSpacing
            + CGFloat(index) * (EditorTimeline.rowHeight + EditorTimeline.rowSpacing)
    }

    private func offset(for time: Double) -> CGFloat { CGFloat(time) * pps - bounds.width / 2 }
    private var offsetTime: Double { Double((scroll.contentOffset.x + bounds.width / 2) / max(0.2, pps)) }

    private func place(_ time: Double) {
        let x = offset(for: time)
        if abs(scroll.contentOffset.x - x) > 0.05 { scroll.contentOffset = CGPoint(x: x, y: 0) }
    }

    private func follow(_ time: Double) {
        guard bounds.width > 0, !isUserScrolling, handleDrag == nil, !isZooming else { return }
        place(time)
        updateLiveTake(time)
    }

    /// The part on screen plus a screen each side is kept ready; moving inside it draws nothing.
    private var visible: ClosedRange<CGFloat> {
        let x = scroll.contentOffset.x
        return x...(x + bounds.width)
    }

    private func refresh() {
        guard bounds.width > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let margin = bounds.width
        let range = (visible.lowerBound - margin)...(visible.upperBound + margin)
        prepared = range
        ruler.frame = CGRect(x: 0, y: EditorTimeline.topPadding, width: max(1, scroll.contentSize.width), height: EditorTimeline.rulerHeight)
        ruler.show(range: range, pps: pps, duration: state.duration)
        refreshSections(range)
        refreshChips(range)
        refreshHandles()
        refreshSticky()
        updateLiveTake(model.playhead)
        scrubber.update()
        updateAccessibility()
        scheduleTiles()
    }

    private func sectionRects() -> [(segment: EditSegment, index: Int, rect: CGRect, start: Double)] {
        var result: [(segment: EditSegment, index: Int, rect: CGRect, start: Double)] = []
        var cursor = 0.0
        for (index, segment) in state.segments.enumerated() {
            let start = cursor + (index >= state.shiftIndex ? state.shift : 0)
            let rect = CGRect(x: CGFloat(start) * pps, y: Self.stripTop, width: max(2, CGFloat(segment.outputLength) * pps),
                              height: EditorTimeline.stripHeight)
            result.append((segment, index, rect, cursor))
            cursor += segment.outputLength
        }
        return result
    }

    private func refreshSections(_ range: ClosedRange<CGFloat>) {
        var seen = Set<UUID>()
        selectionBorder.isHidden = true
        lengthBadge.isHidden = true
        for (segment, index, rect, _) in sectionRects() where rect.maxX >= range.lowerBound && rect.minX <= range.upperBound {
            seen.insert(segment.id)
            let view = sectionViews[segment.id] ?? {
                let view = EditorSectionView()
                sectionViews[segment.id] = view
                content.insertSubview(view, aboveSubview: ruler)
                view.onActivate = { [weak self] in self?.activateSection(segment.id) }
                return view
            }()
            view.show(segment: segment, rect: rect, range: range, tile: state.tile, pps: pps, hasPicture: state.hasPicture,
                      levels: state.sourceLevels, filmstrip: model.filmstrip)
            view.accessibilityLabel = state.segments.count == 1 ? "Video clip" : "Part \(index + 1) of \(state.segments.count)"
            view.accessibilityValue = EditorText.length(segment.outputLength) + (segment.speed == 1 ? "" : ", \(EditorText.speed(segment.speed))")
            let selected = state.selectedSegment == segment.id
            view.accessibilityTraits = selected ? [.button, .selected] : .button
            if selected {
                selectionBorder.isHidden = false
                selectionBorder.frame = rect.intersection(CGRect(x: range.lowerBound, y: 0, width: range.upperBound - range.lowerBound,
                                                                 height: bounds.height))
                content.bringSubviewToFront(selectionBorder)
                lengthBadge.text = segment.speed == 1 ? EditorText.length(segment.outputLength)
                    : "\(EditorText.length(segment.outputLength)) · \(EditorText.speed(segment.speed))"
                lengthBadge.isHidden = false
                lengthBadge.sizeToFit()
                content.bringSubviewToFront(lengthBadge)
            }
        }
        for (id, view) in sectionViews where !seen.contains(id) {
            view.removeFromSuperview()
            sectionViews[id] = nil
        }
    }

    private func refreshChips(_ range: ClosedRange<CGFloat>) {
        var seen = Set<String>()
        for row in state.rows {
            guard let top = rowTop(row) else { continue }
            for chip in state.chips[row] ?? [] {
                let x = CGFloat(chip.start) * pps
                let width = max(10, CGFloat(chip.end - chip.start) * pps - (chip.caption ? 2 : 0))
                guard x + width >= range.lowerBound, x <= range.upperBound else { continue }
                seen.insert(chip.id)
                let view = chipViews[chip.id] ?? {
                    let view = EditorChipView()
                    chipViews[chip.id] = view
                    content.addSubview(view)
                    return view
                }()
                let left = max(x, range.lowerBound)
                let right = min(x + width, range.upperBound)
                view.frame = CGRect(x: left, y: top, width: max(8, right - left), height: EditorTimeline.rowHeight)
                let selected = chip.selection != nil && chip.selection == state.selection
                view.show(chip, selected: selected, pps: pps, hiddenSeconds: Double((left - x) / pps))
                view.labelInset = max(0, min(scroll.contentOffset.x - left, right - left - 40))
                view.onActivate = { [weak self] in self?.activate(chip, in: row) }
            }
        }
        for (id, view) in chipViews where !seen.contains(id) {
            view.removeFromSuperview()
            chipViews[id] = nil
        }
    }

    private func refreshHandles() {
        var seen = Set<String>()
        for handle in state.handles {
            let top: CGFloat
            let height: CGFloat
            if let row = handle.row {
                guard let rowY = rowTop(row) else { continue }
                top = rowY
                height = EditorTimeline.rowHeight
            } else {
                top = Self.stripTop
                height = EditorTimeline.stripHeight
            }
            let key = "\(handle.target)\(handle.edge)"
            seen.insert(key)
            let view = handleViews[key] ?? {
                let view = EditorHandleView()
                handleViews[key] = view
                content.addSubview(view)
                let pan = UIPanGestureRecognizer(target: self, action: #selector(draggedHandle(_:)))
                pan.maximumNumberOfTouches = 1
                view.addGestureRecognizer(pan)
                // A drag that starts on a handle trims; it never scrolls.
                scroll.panGestureRecognizer.require(toFail: pan)
                return view
            }()
            view.key = key
            view.target = handle.target
            view.edge = handle.edge
            view.place(x: CGFloat(handle.time) * pps, top: top, height: height)
            view.bubble = handle.bubble
            view.accessibilityLabel = handle.edge == .start ? "Start handle" : "End handle"
            view.accessibilityValue = handle.value
            view.onNudge = { [weak self] seconds in
                self?.model.nudge(handle.target, edge: handle.edge, by: seconds)
            }
            content.bringSubviewToFront(view)
        }
        for (key, view) in handleViews where !seen.contains(key) && handleDrag?.key != key {
            view.removeFromSuperview()
            handleViews[key] = nil
        }
    }

    /// What stays at the left edge while its row scrolls by: the invitations and the length badge.
    private func refreshSticky() {
        let left = scroll.contentOffset.x
        let start: CGFloat = 0
        let end = CGFloat(state.duration) * pps
        func placeRow(_ view: UIView, _ row: EditorTimelineRow, shown: Bool) {
            guard shown, let top = rowTop(row) else {
                view.isHidden = true
                return
            }
            view.isHidden = false
            let x = max(left + 8, start)
            let right = min(left + bounds.width - 8, max(end, x + 120))
            view.frame = CGRect(x: x, y: top, width: max(120, right - x), height: EditorTimeline.rowHeight)
        }
        placeRow(addText, .text, shown: state.invitesText)
        placeRow(addVoice, .voice, shown: state.invitesVoice)
        captionsNote.title = state.emptyCaptions ?? ""
        placeRow(captionsNote, .captions, shown: state.emptyCaptions != nil)
        addText.isEnabled = !state.isLocked
        addVoice.isEnabled = !state.isLocked
        if !lengthBadge.isHidden, !selectionBorder.isHidden {
            let rect = selectionBorder.frame
            lengthBadge.frame.origin = CGPoint(x: min(max(left + 8, rect.minX + 8), max(rect.minX + 8, rect.maxX - lengthBadge.frame.width - 8)),
                                               y: Self.stripTop + 4)
        }
    }

    private func updateLiveTake(_ time: Double) {
        let range: ClosedRange<Double>?
        if let start = state.recordingStart { range = start...max(start, time) } else { range = state.take }
        guard let range, let top = rowTop(.voice) else {
            liveTake.isHidden = true
            return
        }
        liveTake.isHidden = false
        let x = CGFloat(range.lowerBound) * pps
        liveTake.frame = CGRect(x: x, y: top, width: max(4, CGFloat(range.upperBound - range.lowerBound) * pps),
                                height: EditorTimeline.rowHeight)
        content.bringSubviewToFront(liveTake)
    }

    // MARK: - Filmstrip pictures

    /// Exact pictures for what is on screen, once the timeline has stopped moving.
    private func scheduleTiles() {
        guard state.hasPicture, !model.isStatic else { return }
        wantTask?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.wantTiles() }
        wantTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: task)
    }

    private func wantTiles() {
        guard bounds.width > 0 else { return }
        var times: [Double] = []
        var cell = 1.0
        let seen = (visible.lowerBound - 40)...(visible.upperBound + 40)
        for (segment, _, rect, _) in sectionRects() where rect.maxX >= seen.lowerBound && rect.minX <= seen.upperBound {
            cell = Double(state.tile / pps) * segment.speed
            times += EditorSectionView.cellTimes(segment: segment, rect: rect, range: seen, tile: state.tile, pps: pps).map(\.time)
            if times.count > 80 { break }
        }
        model.filmstrip.want(times, cell: cell)
    }

    private func refreshTiles() {
        guard let prepared else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (segment, _, rect, _) in sectionRects() {
            sectionViews[segment.id]?.show(segment: segment, rect: rect, range: prepared, tile: state.tile, pps: pps,
                                           hasPicture: state.hasPicture, levels: state.sourceLevels, filmstrip: model.filmstrip)
        }
        CATransaction.commit()
    }

    // MARK: - Scrubbing

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        isUserScrolling = true
        model.beginScrub()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if isUserScrolling, scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating {
            model.seek(to: offsetTime)
        }
        if let prepared, visible.lowerBound - bounds.width * 0.4 >= prepared.lowerBound || prepared.lowerBound < -bounds.width,
           visible.upperBound + bounds.width * 0.4 <= prepared.upperBound || prepared.upperBound > scroll.contentSize.width + bounds.width,
           visible.lowerBound >= prepared.lowerBound, visible.upperBound <= prepared.upperBound {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            refreshSticky()
            CATransaction.commit()
            if isUserScrolling { scheduleTiles() }
        } else {
            refresh()
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { endScrub() }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { endScrub() }

    private func endScrub() {
        guard isUserScrolling else { return }
        isUserScrolling = false
        model.endScrub()
        scheduleTiles()
    }

    // MARK: - Zoom

    @objc private func pinched(_ pinch: UIPinchGestureRecognizer) {
        switch pinch.state {
        case .began:
            isZooming = true
            zoomStart = pps
            // The first finger may have started a scrub: end it, or the two fight.
            scroll.panGestureRecognizer.isEnabled = false
            scroll.panGestureRecognizer.isEnabled = true
            endScrub()
            model.pause()
        case .changed:
            let limits = model.zoomRange(width: bounds.width)
            let next = min(limits.upperBound, max(limits.lowerBound, zoomStart * pinch.scale))
            guard abs(next - pps) > 0.01 else { return }
            model.pointsPerSecond = next
            // At once, not with the next SwiftUI update.
            var zoomed = state
            zoomed.pps = max(0.2, next)
            apply(zoomed)
            place(model.playhead)
        case .ended, .cancelled, .failed:
            isZooming = false
            place(model.playhead)
            scheduleTiles()
        default:
            break
        }
    }

    // MARK: - Taps

    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !(touch.view is UIControl) && !(touch.view is EditorHandleView)
    }

    @objc private func tapped(_ tap: UITapGestureRecognizer) {
        guard !state.isLocked else { return }
        let point = tap.location(in: content)
        if point.y >= Self.stripTop - 4, point.y <= Self.stripTop + EditorTimeline.stripHeight + 3 {
            for (_, _, rect, start) in sectionRects() where point.x >= rect.minX && point.x <= rect.maxX {
                Haptics.selection()
                model.toggleSegment(atOutput: start + Double((point.x - rect.minX) / pps))
                return
            }
            return
        }
        for row in state.rows {
            guard let top = rowTop(row), point.y >= top - 3, point.y <= top + EditorTimeline.rowHeight + 3 else { continue }
            // The one on top, with a little room around short ones.
            let chips = state.chips[row] ?? []
            let hit = chips.last { CGFloat($0.start) * pps <= point.x && point.x <= max(CGFloat($0.end) * pps, CGFloat($0.start) * pps + 10) }
                ?? chips.last { CGFloat($0.start) * pps - 12 <= point.x && point.x <= CGFloat($0.end) * pps + 12 }
            if let hit { activate(hit, in: row) }
            return
        }
    }

    private func activate(_ chip: EditorTimelineState.Chip, in row: EditorTimelineRow) {
        guard !state.isLocked else { return }
        Haptics.selection()
        if chip.caption {
            model.open(.captions)
            model.seek(to: chip.start + 0.01, exact: true)
        } else if let selection = chip.selection {
            if state.selection == selection { model.selection = nil } else { model.selectOverlay(selection) }
        }
    }

    private func activateSection(_ id: UUID) {
        guard let span = model.outputSpan(of: id) else { return }
        model.toggleSegment(atOutput: (span.lowerBound + span.upperBound) / 2)
    }

    private func tappedAddText() {
        Haptics.tap()
        model.open(.text)
        model.addText()
    }

    // MARK: - Trim handles

    @objc private func draggedHandle(_ pan: UIPanGestureRecognizer) {
        guard let view = pan.view as? EditorHandleView, let target = view.target else { return }
        switch pan.state {
        case .began:
            guard !state.isLocked else { return }
            Haptics.selection()
            handleDrag = (view.key, 0, pan.location(in: self).x)
            model.beginTrim(target, edge: view.edge)
            let link = CADisplayLink(target: DisplayLinkTarget { [weak self, weak pan] in
                if let pan { self?.scrollAtEdges(pan) }
            }, selector: #selector(DisplayLinkTarget.fire))
            link.add(to: .main, forMode: .common)
            edgeLink = link
        case .changed:
            updateHandle(pan)
        case .ended, .cancelled, .failed:
            edgeLink?.invalidate()
            edgeLink = nil
            guard handleDrag != nil else { return }
            updateHandle(pan)
            handleDrag = nil
            heldWidth = nil
            model.endTrim()
            // SwiftUI brings the new state; the timeline glides to the edge that was set.
            UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                self.place(self.model.playhead)
            }
        default:
            break
        }
    }

    private func updateHandle(_ pan: UIPanGestureRecognizer) {
        guard let drag = handleDrag else { return }
        handleDrag?.touch = pan.location(in: self).x
        model.updateTrim(offset: Double((pan.translation(in: self).x + drag.scrolled) / max(0.2, pps)))
    }

    /// Near the left or right edge the timeline rolls on, so a handle can travel minutes.
    private func scrollAtEdges(_ pan: UIPanGestureRecognizer) {
        guard let drag = handleDrag else { return }
        let zone: CGFloat = 56
        let x = drag.touch
        var speed: CGFloat = 0
        if x < zone { speed = -(zone - max(0, x)) / zone }
        if x > bounds.width - zone { speed = (zone - max(0, bounds.width - x)) / zone }
        guard speed != 0 else { return }
        let step = speed * abs(speed) * 14
        let least = -bounds.width / 2
        let most = max(least, scroll.contentSize.width - bounds.width / 2)
        let next = min(most, max(least, scroll.contentOffset.x + step))
        let moved = next - scroll.contentOffset.x
        guard abs(moved) > 0.01 else { return }
        scroll.contentOffset.x = next
        handleDrag?.scrolled += moved
        updateHandle(pan)
    }

    // MARK: - VoiceOver

    private func updateAccessibility() {
        guard UIAccessibility.isVoiceOverRunning || ProcessInfo.processInfo.arguments.contains("-uiTests") else { return }
        var elements: [Any] = [scrubber]
        elements += sectionViews.values.sorted { $0.frame.minX < $1.frame.minX } as [Any]
        elements += handleViews.values.sorted { $0.frame.minX < $1.frame.minX } as [Any]
        for row in state.rows {
            elements += (state.chips[row] ?? []).compactMap { chipViews[$0.id] } as [Any]
            if row == .text, !addText.isHidden { elements.append(addText) }
            if row == .voice, !addVoice.isHidden { elements.append(addVoice) }
        }
        accessibilityElements = elements
    }
}

// MARK: - Pieces

/// VoiceOver's way to scrub: swipe up or down to move a second (five when the video is long).
private final class EditorScrubElement: UIView {
    weak var model: EditorModel?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityLabel = "Timeline"
        accessibilityTraits = .adjustable
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update() {}

    override var accessibilityValue: String? {
        get {
            MainActor.assumeIsolated {
                model.map { "\(Format.clock($0.playhead)) of \(Format.clock($0.duration))" }
            }
        }
        set {}
    }

    override func accessibilityIncrement() { move(1) }
    override func accessibilityDecrement() { move(-1) }

    private func move(_ direction: Double) {
        MainActor.assumeIsolated {
            guard let model, !model.isRecordingVoice else { return }
            model.pause()
            model.seek(to: model.playhead + direction * (model.duration > 120 ? 5 : 1), exact: true)
        }
    }
}

/// Seconds along the top, spaced so labels never crowd.
final class EditorRulerView: UIView {
    private var labels: [UILabel] = []
    private var dots: [UIView] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    static func step(pps: CGFloat) -> Double {
        let steps: [Double] = [0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600]
        return steps.first { CGFloat($0) * pps >= 56 } ?? 600
    }

    func show(range: ClosedRange<CGFloat>, pps: CGFloat, duration: Double) {
        let step = Self.step(pps: pps)
        var index = max(0, Int(floor(Double(range.lowerBound / pps) / step)))
        var used = 0
        while Double(index) * step <= duration + 0.001 {
            let t = Double(index) * step
            let x = CGFloat(t) * pps
            if x > range.upperBound { break }
            let label = label(used)
            label.text = step < 1 ? EditorText.precise(t) : Format.clock(t)
            label.sizeToFit()
            label.center = CGPoint(x: x, y: bounds.midY - 1)
            label.isHidden = false
            let dot = dots[used]
            dot.isHidden = t + step / 2 > duration
            dot.frame = CGRect(x: x + CGFloat(step / 2) * pps - 1.5, y: bounds.midY - 2.5, width: 3, height: 3)
            used += 1
            index += 1
        }
        for rest in used..<max(used, labels.count) {
            labels[rest].isHidden = true
            dots[rest].isHidden = true
        }
    }

    private func label(_ index: Int) -> UILabel {
        while labels.count <= index {
            let label = UILabel()
            label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
            label.textColor = UIColor(Color.srStageTextTertiary)
            addSubview(label)
            labels.append(label)
            let dot = UIView()
            dot.backgroundColor = UIColor(Color.srStageTextTertiary).withAlphaComponent(0.6)
            dot.layer.cornerRadius = 1.5
            addSubview(dot)
            dots.append(dot)
        }
        return labels[index]
    }
}

/// One kept section: its pictures, or its sound for a voice recording. Only the part near the
/// screen exists.
final class EditorSectionView: UIView {
    private var tiles: [Int: CALayer] = [:]
    private let wave = EditorWaveView()
    private let speedBadge = EditorBadgeLabel()
    var onActivate: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = true
        layer.cornerRadius = 6
        layer.cornerCurve = .continuous
        isAccessibilityElement = true
        accessibilityHint = "Selects this part"
        wave.isHidden = true
        wave.backgroundColor = .clear
        addSubview(wave)
        speedBadge.isHidden = true
        addSubview(speedBadge)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func accessibilityActivate() -> Bool {
        onActivate?()
        return true
    }

    /// The cells of a section inside `range`: their place and the moment of the recording they show.
    static func cellTimes(segment: EditSegment, rect: CGRect, range: ClosedRange<CGFloat>, tile: CGFloat,
                          pps: CGFloat) -> [(index: Int, time: Double)] {
        let from = max(rect.minX, range.lowerBound), to = min(rect.maxX, range.upperBound)
        guard to > from else { return [] }
        let first = Int(floor((from - rect.minX) / tile))
        let last = Int(floor((to - rect.minX - 0.01) / tile))
        guard last >= first else { return [] }
        return (first...last).map { index in
            let middle = (CGFloat(index) + 0.5) * tile
            let time = segment.start + Double(middle / pps) * segment.speed
            return (index, min(max(segment.start, time), max(segment.start, segment.end - 0.02)))
        }
    }

    func show(segment: EditSegment, rect: CGRect, range: ClosedRange<CGFloat>, tile: CGFloat, pps: CGFloat, hasPicture: Bool,
              levels: [Float]?, filmstrip: EditorFilmstrip) {
        // A point of space each side between sections.
        let left = max(rect.minX + 1, range.lowerBound), right = min(rect.maxX - 1, range.upperBound)
        frame = CGRect(x: left, y: rect.minY, width: max(1, right - left), height: rect.height)
        backgroundColor = UIColor(hasPicture ? Color.srInkRaised : Color.srStageControl)
        wave.isHidden = hasPicture
        if hasPicture {
            var seen = Set<Int>()
            let cell = Double(tile / pps) * segment.speed
            for (index, time) in Self.cellTimes(segment: segment, rect: rect, range: range, tile: tile, pps: pps) {
                seen.insert(index)
                let layer = tiles[index] ?? {
                    let layer = CALayer()
                    layer.contentsGravity = .resizeAspectFill
                    layer.masksToBounds = true
                    layer.contentsScale = UIScreen.main.scale
                    tiles[index] = layer
                    self.layer.insertSublayer(layer, at: 0)
                    return layer
                }()
                layer.frame = CGRect(x: rect.minX + CGFloat(index) * tile - left, y: 0, width: tile, height: rect.height)
                let image = filmstrip.image(at: time, cell: cell)
                if let image, (layer.contents as AnyObject?) !== image { layer.contents = image }
            }
            for (index, layer) in tiles where !seen.contains(index) {
                layer.removeFromSuperlayer()
                tiles[index] = nil
            }
        } else {
            wave.frame = bounds
            wave.show(levels: levels ?? [], from: segment.start + Double((left - rect.minX) / pps) * segment.speed,
                      secondsPerPoint: segment.speed / Double(pps))
        }
        speedBadge.isHidden = segment.speed == 1 || rect.width < 46
        if !speedBadge.isHidden {
            speedBadge.text = EditorText.speed(segment.speed)
            speedBadge.sizeToFit()
            speedBadge.frame.origin = CGPoint(x: 4, y: rect.height - speedBadge.frame.height - 4)
        }
    }
}

/// Sound as bars. Without levels yet, a flat line.
final class EditorWaveView: UIView {
    private var levels: [Float] = []
    private var from = 0.0
    private var secondsPerPoint = 0.1
    var isLive = false {
        didSet {
            backgroundColor = isLive ? UIColor(Color.srRed) : .clear
            layer.cornerRadius = isLive ? 6 : 0
            accessibilityLabel = "Recording voice-over"
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        layer.cornerCurve = .continuous
        clipsToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(levels: [Float], from: Double, secondsPerPoint: Double) {
        guard levels != self.levels || from != self.from || secondsPerPoint != self.secondsPerPoint else { return }
        self.levels = levels
        self.from = from
        self.secondsPerPoint = secondsPerPoint
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let color = isLive ? UIColor.white : UIColor(Color.srStageTextSecondary).resolvedColor(with: traitCollection)
        context.setFillColor(color.withAlphaComponent(0.8).cgColor)
        let spacing: CGFloat = 4
        var x = spacing / 2
        while x < bounds.width {
            var level: CGFloat = isLive ? 0.35 : 0.08
            if !levels.isEmpty {
                let a = Int((from + Double(x) * secondsPerPoint) * EditorLevels.perSecond)
                let b = max(a + 1, Int((from + Double(x + spacing) * secondsPerPoint) * EditorLevels.perSecond))
                if a >= 0, a < levels.count { level = CGFloat(levels[a..<min(b, levels.count)].max() ?? 0) } else { level = 0 }
            }
            let height = max(2, (bounds.height - 10) * level)
            context.fill(CGRect(x: x, y: (bounds.height - height) / 2, width: 2, height: height))
            x += spacing
        }
    }
}

/// A small dark pill with a number.
final class EditorBadgeLabel: UILabel {
    override init(frame: CGRect) {
        super.init(frame: frame)
        font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        textColor = UIColor(Color.srOnInverse)
        backgroundColor = UIColor(Color.srInverse)
        textAlignment = .center
        clipsToBounds = true
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let text = super.sizeThatFits(size)
        return CGSize(width: ceil(text.width) + 12, height: ceil(text.height) + 4)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }
}

/// The grip at either end of a selected section or overlay. 44 points to touch, 16 to see.
final class EditorHandleView: UIView {
    static let barWidth: CGFloat = 16
    private static let touchWidth: CGFloat = 46
    var key = ""
    var target: TrimTarget?
    var edge: TrimEdge = .start
    var onNudge: ((Double) -> Void)?
    private let bar = UIView()
    private let grip = UIView()
    private let bubbleLabel = EditorBadgeLabel()

    var bubble: String? {
        didSet {
            bubbleLabel.isHidden = bubble == nil
            guard let bubble else { return }
            bubbleLabel.text = bubble
            bubbleLabel.sizeToFit()
            setNeedsLayout()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        bar.backgroundColor = UIColor(Color.srStageText)
        bar.layer.cornerRadius = 4
        bar.layer.cornerCurve = .continuous
        bar.isUserInteractionEnabled = false
        grip.backgroundColor = UIColor(Color.srStage)
        grip.layer.cornerRadius = 1.5
        grip.isUserInteractionEnabled = false
        bubbleLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        bubbleLabel.isHidden = true
        addSubview(bar)
        bar.addSubview(grip)
        addSubview(bubbleLabel)
        isAccessibilityElement = true
        accessibilityTraits = .adjustable
        accessibilityHint = "Swipe up or down to trim by a tenth of a second"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var barHeight: CGFloat = 52

    /// `x` is the edge it moves: the bar sits just outside it.
    func place(x: CGFloat, top: CGFloat, height: CGFloat) {
        barHeight = height
        let touchHeight = max(46, height)
        let y = top + height / 2 - touchHeight / 2
        // Eight points reach inside, the rest outside, so two handles of a short part never overlap much.
        frame = CGRect(x: edge == .start ? x + 8 - Self.touchWidth : x - 8, y: y, width: Self.touchWidth, height: touchHeight)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let x = edge == .start ? bounds.width - 8 - Self.barWidth : 8
        bar.frame = CGRect(x: x, y: (bounds.height - barHeight) / 2, width: Self.barWidth, height: barHeight)
        grip.frame = CGRect(x: Self.barWidth / 2 - 1.5, y: barHeight * 0.32, width: 3, height: barHeight * 0.36)
        bubbleLabel.center = CGPoint(x: bar.frame.midX, y: bar.frame.minY - 14)
    }

    override func accessibilityIncrement() { onNudge?(0.1) }
    override func accessibilityDecrement() { onNudge?(-0.1) }
}

/// An overlay, a caption or a voice-over on its track.
final class EditorChipView: UIView {
    private let icon = UIImageView()
    private let label = UILabel()
    private let wave = EditorWaveView()
    private var isSelectedChip = false
    var onActivate: (() -> Void)?
    /// Keeps the label in view while a long chip's start is off screen.
    var labelInset: CGFloat = 0 {
        didSet { if labelInset != oldValue { setNeedsLayout() } }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.cornerRadius = 6
        layer.cornerCurve = .continuous
        clipsToBounds = true
        backgroundColor = UIColor(Color.srStageControl)
        icon.contentMode = .scaleAspectFit
        icon.tintColor = UIColor(Color.srStageText)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        addSubview(wave)
        addSubview(icon)
        addSubview(label)
        isAccessibilityElement = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(_ chip: EditorTimelineState.Chip, selected: Bool, pps: CGFloat, hiddenSeconds: Double) {
        let isVoice = chip.levels != nil
        label.isHidden = isVoice
        wave.isHidden = !isVoice
        if isVoice {
            wave.show(levels: chip.levels ?? [], from: chip.lead + hiddenSeconds, secondsPerPoint: 1 / Double(pps))
        } else {
            label.text = chip.label
            label.textColor = UIColor(chip.faded ? Color.srStageTextTertiary : Color.srStageText)
        }
        icon.image = chip.icon.flatMap { UIImage(systemName: $0, withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .bold)) }
        icon.isHidden = chip.icon == nil
        isSelectedChip = selected
        updateBorder()
        accessibilityLabel = isVoice ? "Voice-over" : chip.label
        accessibilityValue = "\(Format.clock(chip.start)) to \(Format.clock(chip.end))"
        accessibilityTraits = selected ? [.button, .selected] : .button
        setNeedsLayout()
    }

    private func updateBorder() {
        layer.borderWidth = isSelectedChip ? 2 : 0
        layer.borderColor = UIColor(Color.srStageText).resolvedColor(with: traitCollection).cgColor
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        updateBorder()
        wave.setNeedsDisplay()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        wave.frame = bounds.insetBy(dx: 4, dy: 0)
        var x = 7 + labelInset
        if !icon.isHidden {
            icon.frame = CGRect(x: x, y: bounds.midY - 7, width: 14, height: 14)
            x += 18
        }
        label.frame = CGRect(x: x, y: 0, width: max(0, bounds.width - x - 6), height: bounds.height)
    }

    override func accessibilityActivate() -> Bool {
        onActivate?()
        return true
    }
}

/// A dashed row inviting the first item of its kind ("+ Add text", "+ Voice-over").
final class EditorAddRowButton: UIControl {
    private let dash = CAShapeLayer()
    private let icon = UIImageView()
    private let label = UILabel()

    var title: String {
        get { label.text ?? "" }
        set {
            label.text = newValue
            accessibilityLabel = newValue
        }
    }

    init(title: String, systemImage: String?) {
        super.init(frame: .zero)
        dash.fillColor = nil
        dash.lineWidth = 1
        dash.lineDashPattern = [4, 3]
        layer.addSublayer(dash)
        icon.image = systemImage.flatMap { UIImage(systemName: $0, withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)) }
        icon.tintColor = UIColor(Color.srStageTextSecondary)
        icon.contentMode = .center
        icon.isHidden = systemImage == nil
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = UIColor(Color.srStageTextSecondary)
        addSubview(icon)
        addSubview(label)
        isAccessibilityElement = true
        accessibilityTraits = .button
        self.title = title
        updateColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isHighlighted: Bool { didSet { alpha = isHighlighted ? 0.6 : 1 } }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        updateColors()
    }

    private func updateColors() {
        dash.strokeColor = UIColor(Color.srStageTextTertiary).resolvedColor(with: traitCollection).withAlphaComponent(0.7).cgColor
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dash.frame = bounds
        dash.path = UIBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 6).cgPath
        CATransaction.commit()
        var x: CGFloat = 10
        if !icon.isHidden {
            icon.frame = CGRect(x: x, y: 0, width: 14, height: bounds.height)
            x += 19
        }
        label.frame = CGRect(x: x, y: 0, width: max(0, bounds.width - x - 8), height: bounds.height)
    }

    /// The rows are 32 points high; the touch area takes the gaps around them too.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: 0, dy: -6).contains(point)
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
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .padding(.vertical, -10)
            .padding(.trailing, -6)
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
