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
                    } else {
                        EditorCanvas(model: model, size: rect.size)
                            .frame(width: rect.width, height: rect.height)
                            .offset(x: rect.minX, y: rect.minY)
                    }
                }
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
            }
            if !model.isStatic {
                EditorPlayerView(player: model.player)
            }
        }
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

/// The player's video layer.
struct EditorPlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> EditorPlayerLayerView {
        let view = EditorPlayerLayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: EditorPlayerLayerView, context: Context) {
        if uiView.playerLayer.player !== player { uiView.playerLayer.player = player }
    }
}

final class EditorPlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

/// A voice recording's stand-in for the picture: its sound, following the appearance.
struct EditorSoundArtwork: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        VStack(spacing: Space.m) {
            HStack(alignment: .center, spacing: 4) {
                ForEach(0..<32, id: \.self) { index in
                    let progress = model.duration > 0 ? model.playhead / model.duration : 0
                    let played = Double(index) / 32 <= progress
                    Capsule()
                        .fill(played ? Color.srRed : Color.srStageTextTertiary.opacity(0.5))
                        .frame(width: 4, height: 70 * level(index))
                }
            }
            .frame(height: 80)
            Text(Format.clock(model.playhead))
                .font(.srStat)
                .foregroundStyle(Color.srStageText)
            Text(model.isPlaying ? "Tap to pause" : "Tap to play")
                .font(.srFootnote)
                .foregroundStyle(Color.srStageTextTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(Color.srStageRaised))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Voice recording, \(Format.clock(model.playhead)) of \(Format.clock(model.duration))")
    }

    private func level(_ index: Int) -> CGFloat {
        let x = Double(index) + Double(abs(model.source.id.hashValue % 11))
        return CGFloat(0.2 + 0.6 * abs(sin(x * 0.8)) * abs(cos(x * 0.27)))
    }
}

// MARK: - Overlays on the picture

/// Text, shapes, blur boxes and the caption at the playhead, in picture coordinates.
struct EditorCanvas: View {
    @ObservedObject var model: EditorModel
    let size: CGSize

    var body: some View {
        let t = model.playhead
        ZStack(alignment: .topLeading) {
            Color.clear.allowsHitTesting(false)
            if let captions = model.recipe.captions,
               let line = model.captionLines.first(where: { !$0.isHidden && t >= $0.start && t <= $0.end }) {
                EditCaptionOverlayView(text: line.text, style: captions.style, frame: size)
                    .position(x: EditCaptionOverlayView.center.x * size.width, y: EditCaptionOverlayView.center.y * size.height)
                    .allowsHitTesting(false)
            }
            ForEach(model.recipe.blurs) { blur in
                if model.selection == .blur(blur.id) || (model.tool == .blur && t >= blur.start && t <= blur.end) {
                    EditorBlurBox(model: model, blur: blur, size: size, isSelected: model.selection == .blur(blur.id))
                }
            }
            ForEach(model.recipe.stickers) { item in
                if model.selection == .sticker(item.id) || (t >= item.start && t <= item.end) {
                    EditorMovable(isSelected: model.selection == .sticker(item.id), center: item.center, size: size,
                                  scale: item.scale, rotation: item.rotation, allowsRotation: item.kind != .circle,
                                  onSelect: { model.selectOverlay(.sticker(item.id)) },
                                  onChange: { center, scale, rotation in
                                      model.liveMove(.sticker(item.id), center: center, scale: scale, rotation: rotation)
                                  },
                                  onEnd: { model.endLiveChange() },
                                  onDelete: { model.deleteSticker(item.id) },
                                  onEdit: nil) {
                        EditStickerOverlayView(item: item, frame: size)
                    }
                }
            }
            ForEach(model.recipe.texts) { item in
                if model.selection == .text(item.id) || (t >= item.start && t <= item.end) {
                    EditorMovable(isSelected: model.selection == .text(item.id), center: item.center, size: size,
                                  scale: item.scale, rotation: 0, allowsRotation: false,
                                  onSelect: { model.selectOverlay(.text(item.id)) },
                                  onChange: { center, scale, _ in
                                      model.liveMove(.text(item.id), center: center, scale: scale)
                                  },
                                  onEnd: { model.endLiveChange() },
                                  onDelete: { model.deleteText(item.id) },
                                  onEdit: { model.editText(item) }) {
                        EditTextOverlayView(item: item, frame: size)
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

/// Drag to move, pinch to resize, twist to turn; a selected item shows its outline and a
/// delete button.
struct EditorMovable<Content: View>: View {
    let isSelected: Bool
    let center: CGPoint
    let size: CGSize
    let scale: Double
    let rotation: Double
    let allowsRotation: Bool
    let onSelect: () -> Void
    let onChange: (CGPoint?, Double?, Double?) -> Void
    let onEnd: () -> Void
    let onDelete: () -> Void
    let onEdit: (() -> Void)?
    @ViewBuilder let content: () -> Content

    @State private var startCenter: CGPoint?
    @State private var startScale: Double?
    @State private var startRotation: Double?

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
            .overlay(alignment: .topLeading) {
                if isSelected {
                    Button {
                        Haptics.tap()
                        onDelete()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.srInk)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.white))
                            .shadow(color: .black.opacity(0.3), radius: 2)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .offset(x: -18, y: -18)
                    .accessibilityLabel("Delete")
                }
            }
            .overlay(alignment: .topTrailing) {
                if isSelected, let onEdit {
                    Button {
                        Haptics.tap()
                        onEdit()
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.srInk)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.white))
                            .shadow(color: .black.opacity(0.3), radius: 2)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .offset(x: 18, y: -18)
                    .accessibilityLabel("Edit text")
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { onEdit?() }
            .onTapGesture {
                Haptics.selection()
                onSelect()
            }
            .gesture(drag.simultaneously(with: pinch.simultaneously(with: twist)))
            .position(x: center.x * size.width, y: center.y * size.height)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if startCenter == nil {
                    startCenter = center
                    if !isSelected { onSelect() }
                }
                let origin = startCenter ?? center
                onChange(CGPoint(x: origin.x + value.translation.width / max(1, size.width),
                                 y: origin.y + value.translation.height / max(1, size.height)), nil, nil)
            }
            .onEnded { _ in
                startCenter = nil
                onEnd()
            }
    }

    private var pinch: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if startScale == nil { startScale = scale }
                onChange(nil, (startScale ?? scale) * Double(value), nil)
            }
            .onEnded { _ in
                startScale = nil
                onEnd()
            }
    }

    private var twist: some Gesture {
        RotationGesture()
            .onChanged { angle in
                guard allowsRotation else { return }
                if startRotation == nil { startRotation = rotation }
                onChange(nil, nil, (startRotation ?? rotation) + angle.degrees)
            }
            .onEnded { _ in
                startRotation = nil
                onEnd()
            }
    }
}

/// A blur rectangle being placed: drag to move, the corner to resize.
struct EditorBlurBox: View {
    @ObservedObject var model: EditorModel
    let blur: EditBlur
    let size: CGSize
    let isSelected: Bool

    @State private var startRect: CGRect?

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
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
                    .offset(x: 20, y: 20)
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
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .offset(x: -18, y: -18)
                .accessibilityLabel("Delete blur")
            }
        }
        .position(x: rect.midX, y: rect.midY)
    }

    private var move: some Gesture {
        DragGesture(minimumDistance: 2)
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
            .onEnded { _ in
                startRect = nil
                model.endLiveChange()
            }
    }

    private var resize: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if startRect == nil { startRect = blur.rect }
                guard let start = startRect else { return }
                var next = start
                next.size.width = start.width + value.translation.width / max(1, size.width)
                next.size.height = start.height + value.translation.height / max(1, size.height)
                model.liveMove(.blur(blur.id), rect: next)
            }
            .onEnded { _ in
                startRect = nil
                model.endLiveChange()
            }
    }
}

// MARK: - Crop

/// The crop box over the whole picture: drag inside to move it, drag a corner to resize it
/// (a fixed shape keeps its shape), pinch to scale it.
struct EditorCropOverlay: View {
    @ObservedObject var model: EditorModel
    let size: CGSize

    @State private var startRect: CGRect?

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
                Rectangle().strokeBorder(Color.white, lineWidth: 2)
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
                .stroke(Color.white.opacity(0.45), lineWidth: 0.75)
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
        .simultaneousGesture(pinch)
        .accessibilityElement()
        .accessibilityLabel("Crop box")
        .accessibilityHint("Drag to move, drag a corner to resize")
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

    private func cornerHandle(_ corner: Corner) -> some View {
        let length: CGFloat = 18
        return Path { path in
            switch corner {
            case .topLeft:
                path.move(to: CGPoint(x: 0, y: length)); path.addLine(to: .zero); path.addLine(to: CGPoint(x: length, y: 0))
            case .topRight:
                path.move(to: CGPoint(x: -length, y: 0)); path.addLine(to: .zero); path.addLine(to: CGPoint(x: 0, y: length))
            case .bottomLeft:
                path.move(to: CGPoint(x: 0, y: -length)); path.addLine(to: .zero); path.addLine(to: CGPoint(x: length, y: 0))
            case .bottomRight:
                path.move(to: CGPoint(x: -length, y: 0)); path.addLine(to: .zero); path.addLine(to: CGPoint(x: 0, y: -length))
            }
        }
        .offsetBy(dx: 22, dy: 22)
        .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }

    private var move: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if startRect == nil { startRect = displayRect }
                guard let start = startRect else { return }
                var next = start
                next.origin.x = min(max(0, start.minX + value.translation.width / max(1, size.width)), 1 - start.width)
                next.origin.y = min(max(0, start.minY + value.translation.height / max(1, size.height)), 1 - start.height)
                model.setDisplayCrop(next, live: true)
            }
            .onEnded { _ in
                startRect = nil
                model.endLiveChange()
            }
    }

    private func resize(_ corner: Corner) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if startRect == nil {
                    startRect = displayRect
                    if model.recipe.crop.aspect == .original { model.liveChange { $0.crop.aspect = .free } }
                }
                guard let start = startRect else { return }
                let dx = value.translation.width / max(1, size.width)
                let dy = value.translation.height / max(1, size.height)
                model.setDisplayCrop(resized(start, corner: corner, dx: dx, dy: dy), live: true)
            }
            .onEnded { _ in
                startRect = nil
                model.endLiveChange()
            }
    }

    private var pinch: some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                if startRect == nil { startRect = displayRect }
                guard let start = startRect else { return }
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
            .onEnded { _ in
                startRect = nil
                model.endLiveChange()
            }
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
