import AVFoundation
import SwiftUI
import UIKit

/// The picture at the top of the editor: the edited video (the only dark area on the page),
/// with text, shapes and captions drawn over it where they will be saved, and the crop box
/// while the crop tool is open. A voice recording shows its sound instead.
struct EditorPreview: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        GeometryReader { proxy in
            let area = CGRect(origin: .zero, size: proxy.size).insetBy(dx: Space.m, dy: Space.xs)
            if model.hasPicture {
                let fullFrame = model.tool == .crop
                let picture = fullFrame ? model.geometry.displaySize(model.pictureSize) : model.outputPictureSize
                let rect = Self.fit(picture, in: area)
                ZStack(alignment: .topLeading) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { tapOutside() }
                    pictureView(fullFrame: fullFrame)
                        .frame(width: rect.width, height: rect.height)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .offset(x: rect.minX, y: rect.minY)
                        .onTapGesture { tapOutside() }
                    if fullFrame {
                        EditorCropOverlay(model: model, size: rect.size)
                            .frame(width: rect.width, height: rect.height)
                            .offset(x: rect.minX, y: rect.minY)
                    } else if !model.isTrimmingSection {
                        EditorCanvas(model: model, moment: model.moment, size: rect.size)
                            .frame(width: rect.width, height: rect.height)
                            .offset(x: rect.minX, y: rect.minY)
                    }
                    if model.isPreparing || model.loadFailed {
                        EditorLoadingCard(failed: model.loadFailed)
                            .frame(width: area.width, height: area.height)
                            .offset(x: area.minX, y: area.minY)
                            .allowsHitTesting(false)
                    }
                }
                // Two fingers anywhere on the picture resize and turn the selected text or shape; a
                // small one is too small to pinch itself.
                .simultaneousGesture(EditorPinchGesture.gesture(model: model), including: model.selection.isPinchable ? .all : .subviews)
            } else {
                EditorSoundArtwork(model: model)
                    .frame(width: area.width, height: area.height)
                    .offset(x: area.minX, y: area.minY)
                    .onTapGesture { model.togglePlay() }
            }
        }
    }

    @ViewBuilder
    private func pictureView(fullFrame: Bool) -> some View {
        ZStack {
            Color.black
            if let still = model.stillImage(fullFrame: fullFrame) {
                Image(uiImage: still)
                    .resizable()
                    .scaledToFit()
                    .allowsHitTesting(false)
            }
            if !model.isStatic {
                EditorStageRepresentable(playback: model.playback)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Video")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(model.isPlaying ? "Pauses" : "Plays")
        .accessibilityAction { model.togglePlay() }
    }

    private func tapOutside() {
        switch model.selection {
        case .text, .sticker, .blur:
            withAnimation(Motion.quick) { model.selection = nil }
        default:
            model.togglePlay()
        }
    }

    static func fit(_ size: CGSize, in area: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0, area.width > 0, area.height > 0 else { return area }
        let scale = min(area.width / size.width, area.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: area.midX - fitted.width / 2, y: area.midY - fitted.height / 2,
                      width: fitted.width, height: fitted.height)
    }
}

/// Opening, or why it couldn't.
private struct EditorLoadingCard: View {
    let failed: Bool

    var body: some View {
        VStack(spacing: Space.s) {
            if failed {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.srStageRed)
                Text("This recording can't be opened for editing. Close the editor and play it to check it.")
                    .font(.srSubheadline)
                    .multilineTextAlignment(.center)
            } else {
                ProgressView()
                Text("Opening…")
                    .font(.srFootnote)
            }
        }
        .foregroundStyle(Color.srStageText)
        .padding(Space.m)
        .background(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(Color.srStageRaised))
        .frame(maxWidth: 280, maxHeight: .infinity)
    }
}

extension Optional where Wrapped == EditorSelection {
    var isPinchable: Bool {
        switch self {
        case .text?, .sticker?: return true
        default: return false
        }
    }
}

/// Pinch and twist for the selected text or shape, from anywhere on the picture.
enum EditorPinchGesture {
    @MainActor
    static func gesture(model: EditorModel) -> some Gesture {
        MagnificationGesture(minimumScaleDelta: 0.02)
            .simultaneously(with: RotationGesture(minimumAngleDelta: .degrees(3)))
            .onChanged { value in model.pinch(scale: value.first.map(Double.init), degrees: value.second?.degrees) }
            .onEnded { _ in model.endPinch() }
    }
}

/// A voice recording's stand-in for the picture: its sound, following the appearance.
struct EditorSoundArtwork: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var clock: EditorClock

    init(model: EditorModel) {
        self.model = model
        self.clock = model.clock
    }

    var body: some View {
        VStack(spacing: Space.m) {
            HStack(alignment: .center, spacing: 4) {
                ForEach(0..<32, id: \.self) { index in
                    let progress = model.duration > 0 ? clock.time / model.duration : 0
                    let played = Double(index) / 32 <= progress
                    Capsule()
                        .fill(played ? Color.srRed : Color.srStageTextTertiary.opacity(0.5))
                        .frame(width: 4, height: 70 * level(index))
                }
            }
            .frame(height: 80)
            Text(Format.clock(clock.time))
                .font(.srStat)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(Color.srStageText)
            Text(model.isPlaying ? "Tap to pause" : "Tap to play")
                .font(.srFootnote)
                .foregroundStyle(Color.srStageTextTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(Color.srStageRaised))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Voice recording, \(Format.clock(clock.time)) of \(Format.clock(model.duration))")
    }

    /// The recording's own loudness, kept sections only; a pattern until it has been read.
    private func level(_ index: Int) -> CGFloat {
        if let levels = model.levels["source"], !levels.isEmpty {
            let from = model.recipe.sourceTime(forOutput: model.duration * Double(index) / 32)
            let to = model.recipe.sourceTime(forOutput: model.duration * Double(index + 1) / 32)
            let a = min(levels.count - 1, max(0, Int(from * EditorLevels.perSecond)))
            let b = min(levels.count, max(a + 1, Int(to * EditorLevels.perSecond)))
            return 0.08 + 0.92 * CGFloat(levels[a..<max(a + 1, b)].max() ?? 0)
        }
        let x = Double(index) + Double(abs(model.source.id.hashValue % 11))
        return CGFloat(0.2 + 0.6 * abs(sin(x * 0.8)) * abs(cos(x * 0.27)))
    }
}

// MARK: - Overlays on the picture

/// Text, shapes, blur boxes and the caption at the playhead, in picture coordinates.
struct EditorCanvas: View {
    @ObservedObject var model: EditorModel
    /// Changes only when something appears or goes, so playing costs nothing here.
    @ObservedObject var moment: EditorMomentStore
    let size: CGSize

    var body: some View {
        let shown = moment.value.overlays
        ZStack(alignment: .topLeading) {
            Color.clear.allowsHitTesting(false)
            if let captions = model.recipe.captions, let caption = moment.value.caption {
                EditCaptionOverlayView(text: caption, style: captions.style, frame: size)
                    .position(x: EditCaptionOverlayView.center.x * size.width, y: EditCaptionOverlayView.center.y * size.height)
                    .allowsHitTesting(false)
            }
            ForEach(model.recipe.blurs) { blur in
                if model.selection == .blur(blur.id) || (model.tool == .blur && shown.contains(blur.id)) {
                    EditorBlurBox(model: model, blur: blur, size: size, isSelected: model.selection == .blur(blur.id))
                }
            }
            ForEach(model.recipe.stickers) { item in
                if model.selection == .sticker(item.id) || shown.contains(item.id) {
                    EditorMovable(isSelected: model.selection == .sticker(item.id), center: item.center, size: size,
                                  label: item.kind == .emoji ? (item.emoji ?? "Emoji") : item.kind.label,
                                  onSelect: { model.selectOverlay(.sticker(item.id)) },
                                  onChange: { center in model.liveMove(.sticker(item.id), center: center) },
                                  onEnd: { model.endLiveChange() },
                                  onDelete: { model.deleteSticker(item.id) },
                                  onEdit: nil) {
                        EditStickerOverlayView(item: item, frame: size)
                    }
                }
            }
            ForEach(model.recipe.texts) { item in
                if model.selection == .text(item.id) || shown.contains(item.id) {
                    EditorMovable(isSelected: model.selection == .text(item.id), center: item.center, size: size,
                                  label: item.text,
                                  onSelect: { model.selectOverlay(.text(item.id)) },
                                  onChange: { center in model.liveMove(.text(item.id), center: center) },
                                  onEnd: { model.endLiveChange() },
                                  onDelete: { model.deleteText(item.id) },
                                  onEdit: { model.editText(item) }) {
                        EditTextOverlayView(item: item, frame: size)
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height)
        // Laid out in picture units, so the person's text size must not change them.
        .dynamicTypeSize(.large)
    }
}

/// Drag to move (two fingers anywhere on the picture resize and turn it); a selected item shows
/// its outline and a delete button, and tapping selected text again edits it.
struct EditorMovable<Content: View>: View {
    let isSelected: Bool
    let center: CGPoint
    let size: CGSize
    let label: String
    let onSelect: () -> Void
    let onChange: (CGPoint) -> Void
    let onEnd: () -> Void
    let onDelete: () -> Void
    let onEdit: (() -> Void)?
    @ViewBuilder let content: () -> Content

    @State private var startCenter: CGPoint?
    /// Resets by itself, also when the system takes the touch away (a call, a second gesture).
    @GestureState private var isDragging = false

    var body: some View {
        content()
            .padding(6)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.white, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .shadow(color: .black.opacity(0.5), radius: 1)
                }
            }
            // At least a fingertip to grab, however small the item.
            .background(Color.clear.frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()))
            .contentShape(Rectangle().inset(by: -8))
            .onTapGesture {
                Haptics.selection()
                if isSelected, let onEdit { onEdit() } else { onSelect() }
            }
            .gesture(drag)
            .overlay(alignment: .topLeading) {
                if isSelected {
                    corner("xmark", label: "Delete") { onDelete() }
                        .offset(x: -22, y: -22)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isSelected, let onEdit {
                    corner("pencil", label: "Edit text") { onEdit() }
                        .offset(x: 22, y: -22)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(label)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { onSelect() }
            .position(x: center.x * size.width, y: center.y * size.height)
            .onChange(of: isDragging) { dragging in
                if !dragging { finish() }
            }
    }

    private func corner(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.srInk)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white))
                .shadow(color: .black.opacity(0.3), radius: 2)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }

    // Measured on the screen, not on the item: an item that moves with the finger would measure
    // the drag against itself and shake.
    private var drag: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .updating($isDragging) { _, dragging, _ in dragging = true }
            .onChanged { value in
                if startCenter == nil {
                    startCenter = center
                    if !isSelected { onSelect() }
                }
                let origin = startCenter ?? center
                onChange(CGPoint(x: origin.x + value.translation.width / max(1, size.width),
                                 y: origin.y + value.translation.height / max(1, size.height)))
            }
            .onEnded { _ in finish() }
    }

    private func finish() {
        guard startCenter != nil else { return }
        startCenter = nil
        onEnd()
    }
}

/// A blur rectangle being placed: drag to move, the corner to resize.
struct EditorBlurBox: View {
    @ObservedObject var model: EditorModel
    let blur: EditBlur
    let size: CGSize
    let isSelected: Bool

    @State private var startRect: CGRect?
    @GestureState private var isDragging = false

    var body: some View {
        let rect = CGRect(x: blur.rect.minX * size.width, y: blur.rect.minY * size.height,
                          width: blur.rect.width * size.width, height: blur.rect.height * size.height)
        ZStack(alignment: .bottomTrailing) {
            Rectangle()
                .fill(model.isStatic ? Color.clear : Color.white.opacity(0.06))
                .overlay(Rectangle().strokeBorder(Color.white, style: StrokeStyle(lineWidth: 1.5, dash: isSelected ? [] : [5, 4])))
                .shadow(color: .black.opacity(0.4), radius: 1)
                .contentShape(Rectangle())
                .onTapGesture { model.selectOverlay(.blur(blur.id)) }
                .gesture(move)
            if isSelected {
                Circle()
                    .fill(Color.white)
                    .frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .frame(width: 46, height: 46)
                    .contentShape(Rectangle())
                    .offset(x: 23, y: 23)
                    .gesture(resize)
                    .accessibilityLabel("Resize blur")
            }
        }
        .frame(width: rect.width, height: rect.height)
        .overlay(alignment: .topLeading) {
            if isSelected {
                Button {
                    model.deleteBlur(blur.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.srInk)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.white))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .offset(x: -22, y: -22)
                .accessibilityLabel("Delete blur")
            }
        }
        .position(x: rect.midX, y: rect.midY)
        .onChange(of: isDragging) { dragging in
            if !dragging { finish() }
        }
    }

    private func finish() {
        guard startRect != nil else { return }
        startRect = nil
        model.endLiveChange()
    }

    private var move: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .updating($isDragging) { _, dragging, _ in dragging = true }
            .onChanged { value in
                if startRect == nil {
                    startRect = blur.rect
                    if !isSelected { model.selectOverlay(.blur(blur.id)) }
                }
                guard let start = startRect else { return }
                var next = start
                next.origin.x += value.translation.width / max(1, size.width)
                next.origin.y += value.translation.height / max(1, size.height)
                model.liveMove(.blur(blur.id), rect: next)
            }
            .onEnded { _ in finish() }
    }

    private var resize: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .updating($isDragging) { _, dragging, _ in dragging = true }
            .onChanged { value in
                if startRect == nil { startRect = blur.rect }
                guard let start = startRect else { return }
                var next = start
                next.size.width = start.width + value.translation.width / max(1, size.width)
                next.size.height = start.height + value.translation.height / max(1, size.height)
                model.liveMove(.blur(blur.id), rect: next)
            }
            .onEnded { _ in finish() }
    }
}

// MARK: - Crop

/// The crop box over the whole picture: drag inside to move it, drag a corner to resize it
/// (a fixed shape keeps its shape), pinch to scale it.
struct EditorCropOverlay: View {
    @ObservedObject var model: EditorModel
    let size: CGSize

    @State private var startRect: CGRect?
    @State private var isPinching = false
    @GestureState private var isDragging = false
    @GestureState private var isScaling = false

    private var displayRect: CGRect { model.geometry.toDisplay(model.recipe.crop.rect) }
    private var shownPixels: CGSize { model.geometry.displaySize(model.pictureSize) }

    var body: some View {
        let crop = displayRect
        let frame = CGRect(x: crop.minX * size.width, y: crop.minY * size.height,
                           width: crop.width * size.width, height: crop.height * size.height)
        ZStack(alignment: .topLeading) {
            // Dim outside the crop.
            Path { path in
                path.addRect(CGRect(origin: .zero, size: size))
                path.addRect(frame)
            }
            .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)
            // Box, thirds and corners.
            ZStack {
                Rectangle()
                    .strokeBorder(Color.white, lineWidth: 2)
                    .shadow(color: .black.opacity(0.55), radius: 1.5)
                Path { path in
                    for i in 1...2 {
                        let x = frame.width * CGFloat(i) / 3
                        let y = frame.height * CGFloat(i) / 3
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: frame.height))
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: frame.width, y: y))
                    }
                }
                .stroke(Color.white.opacity(0.6), lineWidth: 0.75)
                .shadow(color: .black.opacity(0.45), radius: 1)
            }
            .frame(width: frame.width, height: frame.height)
            .contentShape(Rectangle())
            .gesture(move)
            .offset(x: frame.minX, y: frame.minY)
            ForEach(Corner.allCases, id: \.self) { corner in
                cornerHandle(corner)
                    .position(corner.point(in: frame))
                    .gesture(resize(corner))
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle().inset(by: -22))
        .simultaneousGesture(pinch)
        .onChange(of: isDragging) { dragging in
            if !dragging, !isPinching { finish() }
        }
        .onChange(of: isScaling) { scaling in
            if !scaling { finish() }
        }
        .accessibilityElement()
        .accessibilityLabel("Crop box")
        .accessibilityValue("\(Int((displayRect.width * 100).rounded())) by \(Int((displayRect.height * 100).rounded())) percent of the picture")
        .accessibilityHint("Drag to move, drag a corner to resize. The shapes below set it for you.")
    }

    private func finish() {
        guard startRect != nil else { return }
        startRect = nil
        isPinching = false
        model.endLiveChange()
    }

    enum Corner: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight

        func point(in rect: CGRect) -> CGPoint {
            switch self {
            case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
            case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
            case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
            case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
            }
        }
    }

    /// An L at the corner: drawn for the top-left and turned for the others.
    private func cornerHandle(_ corner: Corner) -> some View {
        let degrees: Double
        switch corner {
        case .topLeft: degrees = 0
        case .topRight: degrees = 90
        case .bottomRight: degrees = 180
        case .bottomLeft: degrees = 270
        }
        return ZStack(alignment: .topLeading) {
            Capsule().fill(Color.white).frame(width: 20, height: 4)
            Capsule().fill(Color.white).frame(width: 4, height: 20)
        }
        .frame(width: 20, height: 20, alignment: .topLeading)
        .offset(x: 8, y: 8)
        .frame(width: 44, height: 44)
        .rotationEffect(.degrees(degrees))
        .shadow(color: .black.opacity(0.5), radius: 1.5)
        .contentShape(Rectangle())
    }

    private var move: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .updating($isDragging) { _, dragging, _ in dragging = true }
            .onChanged { value in
                guard !isPinching else { return }
                if startRect == nil { startRect = displayRect }
                guard let start = startRect else { return }
                var next = start
                next.origin.x = min(max(0, start.minX + value.translation.width / max(1, size.width)), 1 - start.width)
                next.origin.y = min(max(0, start.minY + value.translation.height / max(1, size.height)), 1 - start.height)
                model.setDisplayCrop(next, live: true)
            }
            .onEnded { _ in if !isPinching { finish() } }
    }

    private func resize(_ corner: Corner) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .updating($isDragging) { _, dragging, _ in dragging = true }
            .onChanged { value in
                guard !isPinching else { return }
                if startRect == nil {
                    startRect = displayRect
                    if model.recipe.crop.aspect == .original { model.liveChange { $0.crop.aspect = .free } }
                }
                guard let start = startRect else { return }
                let dx = value.translation.width / max(1, size.width)
                let dy = value.translation.height / max(1, size.height)
                model.setDisplayCrop(resized(start, corner: corner, dx: dx, dy: dy), live: true)
            }
            .onEnded { _ in if !isPinching { finish() } }
    }

    private var pinch: some Gesture {
        MagnificationGesture()
            .updating($isScaling) { _, scaling, _ in scaling = true }
            .onChanged { scale in
                if !isPinching {
                    // Takes over from the one-finger move that started first.
                    isPinching = true
                    startRect = displayRect
                    model.beginLiveChange()
                }
                guard let start = startRect else { return }
                if model.recipe.crop.aspect == .original { model.liveChange { $0.crop.aspect = .free } }
                let width = min(1, max(0.1, start.width * scale))
                let height = min(1, max(0.1, start.height * scale))
                let ratio = model.recipe.crop.aspect.ratio
                var next = CGRect(x: start.midX - width / 2, y: start.midY - height / 2, width: width, height: height)
                if ratio != nil, width >= 1 || height >= 1 {
                    // Keep the shape when one side reaches the edge.
                    let factor = min(1 / max(start.width, 0.01), 1 / max(start.height, 0.01), scale)
                    next = CGRect(x: start.midX - start.width * factor / 2, y: start.midY - start.height * factor / 2,
                                  width: start.width * factor, height: start.height * factor)
                }
                next.origin.x = min(max(0, next.minX), 1 - next.width)
                next.origin.y = min(max(0, next.minY), 1 - next.height)
                model.setDisplayCrop(next, live: true)
            }
            .onEnded { _ in finish() }
    }

    /// The crop with one corner moved, kept inside the picture and, for a fixed shape, in shape.
    private func resized(_ start: CGRect, corner: Corner, dx: CGFloat, dy: CGFloat) -> CGRect {
        let minimum: CGFloat = 0.1
        let anchorX = (corner == .topLeft || corner == .bottomLeft) ? start.maxX : start.minX
        let anchorY = (corner == .topLeft || corner == .topRight) ? start.maxY : start.minY
        let movingX = (corner == .topLeft || corner == .bottomLeft) ? start.minX + dx : start.maxX + dx
        let movingY = (corner == .topLeft || corner == .topRight) ? start.minY + dy : start.maxY + dy
        var width = min(max(minimum, abs(anchorX - min(max(0, movingX), 1))), 1)
        var height = min(max(minimum, abs(anchorY - min(max(0, movingY), 1))), 1)
        if let ratio = model.recipe.crop.aspect.ratio {
            // Normalised height for this width at the shape's pixel ratio.
            let pixels = shownPixels
            height = width * pixels.width / (ratio * max(1, pixels.height))

            let maxHeight = (corner == .topLeft || corner == .topRight) ? anchorY : 1 - anchorY
            let maxWidth = (corner == .topLeft || corner == .bottomLeft) ? anchorX : 1 - anchorX
            if height > maxHeight {
                height = maxHeight
                width = height * ratio * max(1, pixels.height) / max(1, pixels.width)
            }
            if width > maxWidth {
                width = maxWidth
                height = width * pixels.width / (ratio * max(1, pixels.height))
            }
        }
        let x = (corner == .topLeft || corner == .bottomLeft) ? anchorX - width : anchorX
        let y = (corner == .topLeft || corner == .topRight) ? anchorY - height : anchorY
        return CGRect(x: max(0, x), y: max(0, y), width: width, height: height)
    }
}
