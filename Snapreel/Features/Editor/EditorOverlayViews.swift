import CoreImage
import SwiftUI

// Text, shapes and captions are drawn by the same SwiftUI views in the live preview (in points,
// over the player) and in the exported file (rendered once to pictures with `ImageRenderer`, in
// pixels), so what the person places is exactly what is saved. Every size is in units of 1/100
// of the picture's shorter side.

enum EditOverlayMetrics {
    static func unit(_ frame: CGSize) -> CGFloat { max(1, min(frame.width, frame.height) / 100) }
}

struct EditTextOverlayView: View {
    let item: EditText
    /// The picture's size, in points (preview) or pixels (export).
    let frame: CGSize

    var body: some View {
        let unit = EditOverlayMetrics.unit(frame)
        let fontSize = 6.5 * unit * CGFloat(item.scale)
        let label = Text(item.text.isEmpty ? " " : item.text)
            .font(.system(size: fontSize, weight: .bold))
            .multilineTextAlignment(.center)
            .lineLimit(6)

        switch item.style {
        case .plain:
            label
                .foregroundStyle(item.color.color)
                .shadow(color: .black.opacity(item.color == .black ? 0 : 0.45), radius: unit * 0.6, y: unit * 0.2)
                .padding(unit)
                .frame(maxWidth: frame.width * 0.9)
                .fixedSize(horizontal: false, vertical: true)
        case .box:
            label
                .foregroundStyle(item.color.contrasting)
                .padding(.horizontal, fontSize * 0.45)
                .padding(.vertical, fontSize * 0.2)
                .background(RoundedRectangle(cornerRadius: fontSize * 0.3, style: .continuous).fill(item.color.color))
                .frame(maxWidth: frame.width * 0.9)
                .fixedSize(horizontal: false, vertical: true)
        case .outline:
            let edge: Color = item.color == .black ? .white : Color(hex: 0x13141B)
            let width = max(1, fontSize * 0.07)
            label
                .foregroundStyle(item.color.color)
                .shadow(color: edge, radius: 0, x: width, y: 0)
                .shadow(color: edge, radius: 0, x: -width, y: 0)
                .shadow(color: edge, radius: 0, x: 0, y: width)
                .shadow(color: edge, radius: 0, x: 0, y: -width)
                .padding(unit)
                .frame(maxWidth: frame.width * 0.9)
                .fixedSize(horizontal: false, vertical: true)
        case .bar:
            label
                .foregroundStyle(item.color == .black ? Color.white : item.color.color)
                .padding(.horizontal, unit * 3)
                .padding(.vertical, fontSize * 0.35)
                .frame(width: frame.width)
                .background(Color(hex: 0x13141B).opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct EditStickerOverlayView: View {
    let item: EditSticker
    let frame: CGSize

    var body: some View {
        let unit = EditOverlayMetrics.unit(frame)
        let size = baseSize(unit: unit)
        let diagonal = (size.width * size.width + size.height * size.height).squareRoot()
        shape(unit: unit, size: size)
            .frame(width: size.width, height: size.height)
            .rotationEffect(.degrees(item.rotation))
            .frame(width: item.rotation == 0 ? size.width : diagonal,
                   height: item.rotation == 0 ? size.height : diagonal)
    }

    private func baseSize(unit: CGFloat) -> CGSize {
        let s = CGFloat(item.scale)
        switch item.kind {
        case .arrow: return CGSize(width: 26 * unit * s, height: 11 * unit * s)
        case .circle: return CGSize(width: 26 * unit * s, height: 26 * unit * s)
        case .box: return CGSize(width: 34 * unit * s, height: 22 * unit * s)
        case .highlight: return CGSize(width: 38 * unit * s, height: 9 * unit * s)
        case .emoji: return CGSize(width: 16 * unit * s, height: 16 * unit * s)
        }
    }

    @ViewBuilder
    private func shape(unit: CGFloat, size: CGSize) -> some View {
        let line = max(2, 1.4 * unit * CGFloat(item.scale))
        switch item.kind {
        case .arrow:
            EditArrowShape()
                .fill(item.color.color)
                .shadow(color: .black.opacity(0.35), radius: unit * 0.5, y: unit * 0.2)
        case .circle:
            Ellipse()
                .strokeBorder(item.color.color, lineWidth: line)
                .shadow(color: .black.opacity(0.3), radius: unit * 0.4)
        case .box:
            RoundedRectangle(cornerRadius: unit * 1.2, style: .continuous)
                .strokeBorder(item.color.color, lineWidth: line)
                .shadow(color: .black.opacity(0.3), radius: unit * 0.4)
        case .highlight:
            RoundedRectangle(cornerRadius: unit, style: .continuous)
                .fill(item.color.color.opacity(0.38))
        case .emoji:
            Text(item.emoji ?? "👍")
                .font(.system(size: size.height * 0.86))
                .fixedSize()
        }
    }
}

/// A right-pointing arrow filling its rect.
struct EditArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        let shaft = rect.height * 0.32
        let head = rect.width * 0.36
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY - shaft / 2))
        path.addLine(to: CGPoint(x: rect.maxX - head, y: rect.midY - shaft / 2))
        path.addLine(to: CGPoint(x: rect.maxX - head, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - head, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - head, y: rect.midY + shaft / 2))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY + shaft / 2))
        path.closeSubpath()
        return path
    }
}

struct EditCaptionOverlayView: View {
    let text: String
    let style: EditCaptionStyle
    let frame: CGSize

    /// Captions sit low in the picture, centred.
    static let center = CGPoint(x: 0.5, y: 0.84)

    var body: some View {
        let unit = EditOverlayMetrics.unit(frame)
        let fontSize = 5 * unit
        let label = Text(text)
            .font(.system(size: fontSize, weight: .semibold))
            .multilineTextAlignment(.center)
            .lineLimit(3)
        switch style {
        case .classic:
            label
                .foregroundStyle(Color.white)
                .shadow(color: .black.opacity(0.9), radius: 0, x: 0, y: max(1, unit * 0.25))
                .shadow(color: .black.opacity(0.6), radius: unit * 0.8)
                .padding(unit)
                .frame(maxWidth: frame.width * 0.88)
                .fixedSize(horizontal: false, vertical: true)
        case .box:
            label
                .foregroundStyle(Color.white)
                .padding(.horizontal, fontSize * 0.5)
                .padding(.vertical, fontSize * 0.25)
                .background(RoundedRectangle(cornerRadius: fontSize * 0.3, style: .continuous)
                    .fill(Color.black.opacity(0.72)))
                .frame(maxWidth: frame.width * 0.88)
                .fixedSize(horizontal: false, vertical: true)
        case .bar:
            label
                .foregroundStyle(Color(hex: 0x13141B))
                .padding(.horizontal, unit * 3)
                .padding(.vertical, fontSize * 0.4)
                .frame(width: frame.width)
                .background(Color.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Export

/// Renders the overlays once, as pictures the frame pipeline places over each frame.
@MainActor
enum EditOverlayRasterizer {
    static func images(recipe: EditRecipe, transcript: Transcript?, size: CGSize) -> [EditOverlayImage] {
        var result: [EditOverlayImage] = []
        for item in recipe.texts {
            if let image = rasterize(EditTextOverlayView(item: item, frame: size), width: size.width) {
                result.append(EditOverlayImage(image: image, start: item.start, end: item.end, center: item.center))
            }
        }
        for item in recipe.stickers {
            if let image = rasterize(EditStickerOverlayView(item: item, frame: size), width: size.width) {
                result.append(EditOverlayImage(image: image, start: item.start, end: item.end, center: item.center))
            }
        }
        if let captions = recipe.captions {
            for line in recipe.captionLines(from: transcript) where !line.isHidden {
                let view = EditCaptionOverlayView(text: line.text, style: captions.style, frame: size)
                if let image = rasterize(view, width: size.width) {
                    result.append(EditOverlayImage(image: image, start: line.start, end: line.end,
                                                   center: EditCaptionOverlayView.center))
                }
            }
        }
        return result
    }

    private static func rasterize<V: View>(_ view: V, width: CGFloat) -> CIImage? {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
        renderer.scale = 1
        renderer.isOpaque = false
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        guard let image = renderer.cgImage else { return nil }
        return CIImage(cgImage: image)
    }
}
