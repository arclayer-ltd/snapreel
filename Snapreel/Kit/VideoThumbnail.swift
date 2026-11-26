import SwiftUI
import UIKit

/// In-memory cache of decoded thumbnails, loaded off the main thread.
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSURL, UIImage>()

    init() { cache.countLimit = 200 }

    func cached(_ url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }

    func load(_ url: URL) async -> UIImage? {
        if let hit = cached(url) { return hit }
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return nil }
            return image.preparingForDisplay() ?? image
        }.value
        if let image { cache.setObject(image, forKey: url as NSURL) }
        return image
    }

    func remove(_ url: URL) { cache.removeObject(forKey: url as NSURL) }
    func removeAll() { cache.removeAllObjects() }
}

/// A video's thumbnail with its duration badge. Portrait recordings sit centred on a blurred
/// copy of themselves so every card keeps the same 16:9 shape. Audio recordings show a waveform.
struct VideoThumbnail: View {
    let video: Video
    var cornerRadius: CGFloat = Radius.m
    var showsDuration = true
    var aspectRatio: CGFloat = 16 / 9

    @EnvironmentObject private var library: Library
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.srInkRaised
            content
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .overlay(alignment: .bottomTrailing) {
            if showsDuration { badge.padding(Space.xs) }
        }
        .overlay { stateOverlay }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: video.thumbnailFileName) {
            guard let url = library.thumbnailURL(for: video) else { image = nil; return }
            image = ThumbnailCache.shared.cached(url)
            if image == nil { image = await ThumbnailCache.shared.load(url) }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private var content: some View {
        if let image {
            GeometryReader { proxy in
                let portrait = image.size.height > image.size.width
                ZStack {
                    if portrait {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .blur(radius: 18)
                            .overlay(Color.black.opacity(0.35))
                            .clipped()
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(height: proxy.size.height)
                            .shadow(color: .black.opacity(0.35), radius: 8)
                    } else {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        } else if video.kind == .audio || (video.isAudioOnly && video.state.isReady) {
            // A video still being written has no picture size yet: that isn't a sound recording.
            AudioArtwork(seed: video.id.hashValue)
        } else {
            Image(systemName: video.kind.systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.srOnDarkTertiary)
        }
    }

    private var badge: some View {
        HStack(spacing: 3) {
            if video.kind == .audio {
                Image(systemName: "waveform").font(.system(size: 9, weight: .bold))
            }
            Text(Format.clock(video.duration))
        }
        .font(.srTimerSmall)
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.black.opacity(0.62)))
        // Hidden from VoiceOver with the picture; at the largest text it would cover the thumbnail.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    @ViewBuilder private var stateOverlay: some View {
        switch video.state {
        case .ready:
            EmptyView()
        case .saving:
            ZStack {
                Color.black.opacity(0.45)
                VStack(spacing: Space.xs) {
                    SpinningRing(lineWidth: 3)
                        .frame(width: 30, height: 30)
                    Text("Saving").font(.srCaption).foregroundStyle(.white)
                        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                }
            }
        case .failed:
            ZStack {
                Color.black.opacity(0.55)
                VStack(spacing: Space.xxs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.srRedGlow)
                    Text("Not saved").font(.srCaption).foregroundStyle(.white)
                        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                }
            }
        }
    }
}

/// Stand-in artwork for audio recordings: a red waveform on ink.
struct AudioArtwork: View {
    var seed: Int = 0

    var body: some View {
        GeometryReader { proxy in
            let count = 28
            let barWidth = proxy.size.width * 0.6 / CGFloat(count)
            HStack(alignment: .center, spacing: barWidth * 0.6) {
                ForEach(0..<count, id: \.self) { index in
                    Capsule()
                        .fill(Color.srRed.opacity(index % 3 == 0 ? 1 : 0.7))
                        .frame(width: barWidth, height: proxy.size.height * height(index))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(
            LinearGradient(colors: [Color.srInkRaised, Color.srInk], startPoint: .top, endPoint: .bottom)
        )
    }

    private func height(_ index: Int) -> CGFloat {
        // Deterministic, speech-like envelope.
        let x = Double(index) + Double(abs(seed % 17))
        let value = 0.25 + 0.35 * abs(sin(x * 0.9)) + 0.2 * abs(sin(x * 0.37 + 1.3))
        return CGFloat(min(0.78, value))
    }
}

/// A ring that turns while something without a measurable progress is under way (saving).
struct SpinningRing: View {
    var lineWidth: CGFloat = 4
    var tint: Color = .srRed
    var track: Color = Color.white.opacity(0.25)
    @State private var isTurning = false

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(isTurning ? 270 : -90))
                .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: isTurning)
        }
        .onAppear { isTurning = true }
    }
}

/// Circular progress indicator in the accent colour.
struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 4
    var tint: Color = .srRed
    var track: Color = Color.white.opacity(0.25)

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(max(0.02, min(1, progress))))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.2), value: progress)
        }
    }
}
