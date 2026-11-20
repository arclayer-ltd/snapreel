import AVFoundation
import CoreImage
import UIKit

/// Facts about the source recording, loaded once per editor and reused by every rebuild.
struct EditSource {
    let url: URL
    let asset: AVURLAsset
    let videoTrack: AVAssetTrack?
    let videoRange: CMTimeRange
    let audioTracks: [AVAssetTrack]
    let audioRanges: [CMTimeRange]
    let duration: Double
    /// Pixel size as stored.
    let naturalSize: CGSize
    let transform: CGAffineTransform
    /// Pixel size as shown (turned upright).
    let uprightSize: CGSize
    let orientation: CGImagePropertyOrientation

    var hasVideo: Bool { videoTrack != nil }

    static func load(_ url: URL) async throws -> EditSource {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let duration = try await asset.load(.duration).seconds
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        var audible: [AVAssetTrack] = []
        var ranges: [CMTimeRange] = []
        for track in audioTracks {
            let range = try await track.load(.timeRange)
            if range.duration.seconds > 0.05 {
                audible.append(track)
                ranges.append(range)
            }
        }
        var naturalSize = CGSize.zero
        var transform = CGAffineTransform.identity
        var videoRange = CMTimeRange(start: .zero, duration: CMTime(seconds: max(duration, 0), preferredTimescale: 600))
        if let track = videoTracks.first {
            naturalSize = try await track.load(.naturalSize)
            transform = try await track.load(.preferredTransform)
            videoRange = try await track.load(.timeRange)
        }
        let turned = CGRect(origin: .zero, size: naturalSize).applying(transform)
        return EditSource(url: url, asset: asset, videoTrack: videoTracks.first, videoRange: videoRange,
                          audioTracks: audible, audioRanges: ranges,
                          duration: duration.isFinite ? duration : 0,
                          naturalSize: naturalSize, transform: transform,
                          uprightSize: CGSize(width: abs(turned.width), height: abs(turned.height)),
                          orientation: Self.orientation(of: transform))
    }

    /// The EXIF-style orientation that turns the stored picture upright.
    static func orientation(of t: CGAffineTransform) -> CGImagePropertyOrientation {
        let angle = (atan2(t.b, t.a) * 180 / .pi).rounded()
        let mirrored = t.a * t.d - t.b * t.c < 0
        switch (Int(angle), mirrored) {
        case (90, false): return .right
        case (-90, false): return .left
        case (180, false), (-180, false): return .down
        case (90, true): return .leftMirrored
        case (-90, true): return .rightMirrored
        case (180, true), (-180, true): return .upMirrored
        case (0, true): return .downMirrored
        default: return .up
        }
    }
}

/// A picture to burn in over the edited video (text, shape, caption), made once per export.
struct EditOverlayImage {
    let image: CIImage
    /// Output seconds.
    let start: Double
    let end: Double
    /// Normalised centre in the output picture (top-left origin).
    let center: CGPoint
}

/// What a build is for.
enum EditBuildPurpose {
    /// The editor's player. `fullFrame` shows the whole picture for the crop tool;
    /// `originalSound` plays the sound without noise reduction (before/after).
    case preview(fullFrame: Bool, originalSound: Bool)
    /// The new recording, with its overlays burned in.
    case export(quality: ExportQuality, overlays: [EditOverlayImage])
}

struct EditBuild {
    let composition: AVMutableComposition
    let audioMix: AVAudioMix?
    let videoComposition: AVVideoComposition?
    let renderSize: CGSize
    let duration: Double
}

enum EditCompositionBuilder {
    /// Longest side of the preview picture; full quality is only needed on export.
    static let previewShortSide: CGFloat = 720

    static func build(recipe: EditRecipe, source: EditSource, editFolder: URL, cleanedAudio: URL?,
                      purpose: EditBuildPurpose) async throws -> EditBuild {
        let composition = AVMutableComposition()
        let timescale: CMTimeScale = 600
        let videoOut = source.videoTrack != nil
            ? composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
            : nil

        // The recording's sound, or its cleaned-up copy (same clock as the recording).
        var audioSources = Array(zip(source.audioTracks, source.audioRanges))
        var playsOriginalSound = false
        if case .preview(_, let original) = purpose { playsOriginalSound = original }
        if recipe.audio.reducesNoise, !playsOriginalSound, let cleanedAudio,
           FileManager.default.fileExists(atPath: cleanedAudio.path) {
            let cleaned = AVURLAsset(url: cleanedAudio)
            if let track = try await cleaned.loadTracks(withMediaType: .audio).first {
                let range = try await track.load(.timeRange)
                audioSources = [(track, range)]
            }
        }
        let audioOut = audioSources.compactMap { _ in
            composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        }

        var cursor = CMTime.zero
        for segment in recipe.segments {
            let start = CMTime(seconds: max(0, segment.start), preferredTimescale: timescale)
            let end = CMTime(seconds: min(segment.end, source.duration), preferredTimescale: timescale)
            guard end > start else { continue }
            let range = CMTimeRange(start: start, end: end)
            if let videoOut, let videoIn = source.videoTrack {
                let clipped = range.intersection(source.videoRange)
                if clipped.duration > .zero {
                    try videoOut.insertTimeRange(clipped, of: videoIn, at: cursor + (clipped.start - range.start))
                }
            }
            for (index, pair) in audioSources.enumerated() where index < audioOut.count {
                let clipped = range.intersection(pair.1)
                if clipped.duration > .zero {
                    try audioOut[index].insertTimeRange(clipped, of: pair.0, at: cursor + (clipped.start - range.start))
                }
            }
            let speed = max(0.25, min(4, segment.speed))
            let scaled = CMTimeMultiplyByFloat64(range.duration, multiplier: 1 / speed)
            if abs(speed - 1) > 0.001 {
                composition.scaleTimeRange(CMTimeRange(start: cursor, duration: range.duration), toDuration: scaled)
            }
            cursor = cursor + scaled
        }
        videoOut?.preferredTransform = source.transform
        let total = cursor

        // Narration, mixed over the recording.
        var voiceOut: [AVMutableCompositionTrack] = []
        for clip in recipe.voiceClips {
            let url = editFolder.appendingPathComponent(clip.fileName)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let asset = AVURLAsset(url: url)
            guard let track = try await asset.loadTracks(withMediaType: .audio).first else { continue }
            let available = try await track.load(.timeRange)
            let at = CMTime(seconds: clip.start, preferredTimescale: timescale)
            guard at < total else { continue }
            let length = CMTimeMinimum(CMTimeMinimum(available.duration, CMTime(seconds: clip.duration, preferredTimescale: timescale)),
                                       total - at)
            guard length > .zero,
                  let out = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            try out.insertTimeRange(CMTimeRange(start: available.start, duration: length), of: track, at: at)
            voiceOut.append(out)
        }

        let mix = audioMix(recipe: recipe, original: audioOut, voice: voiceOut, total: total)

        // Picture.
        var videoComposition: AVVideoComposition?
        var renderSize = CGSize.zero
        if videoOut != nil {
            switch purpose {
            case .preview(let fullFrame, _):
                let needsPipeline = fullFrame ? (recipe.quarterTurns != 0 || recipe.flipped)
                    : (!recipe.crop.isFullFrame || recipe.quarterTurns != 0 || recipe.flipped || !recipe.blurs.isEmpty)
                var shown = recipe
                if fullFrame { shown.crop = EditCrop() }
                renderSize = shown.renderSize(source: source.uprightSize, quality: .hd720)
                if needsPipeline {
                    let pipeline = EditFramePipeline(recipe: shown, source: source, renderSize: renderSize,
                                                     showsBlur: !fullFrame, overlays: [])
                    videoComposition = makeVideoComposition(composition, pipeline: pipeline, renderSize: renderSize)
                }
            case .export(let quality, let overlays):
                renderSize = recipe.renderSize(source: source.uprightSize, quality: quality)
                let pipeline = EditFramePipeline(recipe: recipe, source: source, renderSize: renderSize,
                                                 showsBlur: true, overlays: overlays)
                videoComposition = makeVideoComposition(composition, pipeline: pipeline, renderSize: renderSize)
            }
        }
        return EditBuild(composition: composition, audioMix: mix, videoComposition: videoComposition,
                         renderSize: renderSize, duration: total.seconds)
    }

    private static func makeVideoComposition(_ composition: AVMutableComposition, pipeline: EditFramePipeline,
                                             renderSize: CGSize) -> AVVideoComposition {
        let videoComposition = AVMutableVideoComposition(asset: composition, applyingCIFiltersWithHandler: { request in
            let frame = pipeline.render(request.sourceImage, at: request.compositionTime.seconds)
            request.finish(with: frame, context: pipeline.context)
        })
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        return videoComposition
    }

    private static func audioMix(recipe: EditRecipe, original: [AVMutableCompositionTrack],
                                 voice: [AVMutableCompositionTrack], total: CMTime) -> AVAudioMix? {
        guard !original.isEmpty || !voice.isEmpty else { return nil }
        let fade = CMTime(seconds: min(EditAudio.fadeLength, total.seconds / 3), preferredTimescale: 600)
        var parameters: [AVMutableAudioMixInputParameters] = []
        let level = recipe.audio.muted ? 0 : Float(max(0, min(1, recipe.audio.volume)))
        for track in original {
            let input = AVMutableAudioMixInputParameters(track: track)
            input.audioTimePitchAlgorithm = .spectral
            if recipe.audio.fadeIn && level > 0 && fade > .zero {
                input.setVolumeRamp(fromStartVolume: 0, toEndVolume: level, timeRange: CMTimeRange(start: .zero, duration: fade))
            } else {
                input.setVolume(level, at: .zero)
            }
            if recipe.audio.fadeOut && level > 0 && fade > .zero && total > fade {
                input.setVolumeRamp(fromStartVolume: level, toEndVolume: 0,
                                    timeRange: CMTimeRange(start: total - fade, duration: fade))
            }
            parameters.append(input)
        }
        let voiceLevel = Float(max(0, min(1, recipe.audio.voiceVolume)))
        for track in voice {
            let input = AVMutableAudioMixInputParameters(track: track)
            input.audioTimePitchAlgorithm = .spectral
            input.setVolume(voiceLevel, at: .zero)
            parameters.append(input)
        }
        let mix = AVMutableAudioMix()
        mix.inputParameters = parameters
        return mix
    }
}

// MARK: - Frames

/// Turns one source frame into one edited frame: upright, cropped, flipped and turned, blurred,
/// scaled to the render size, with the overlays on top. Runs on AVFoundation's queue; holds
/// only values that never change after it is made.
final class EditFramePipeline {
    let context = CIContext(options: [.cacheIntermediates: false])
    private let recipe: EditRecipe
    private let naturalSize: CGSize
    private let orientation: CGImagePropertyOrientation
    private let renderSize: CGSize
    private let showsBlur: Bool
    private let overlays: [EditOverlayImage]
    private let background: CIImage

    convenience init(recipe: EditRecipe, source: EditSource, renderSize: CGSize, showsBlur: Bool, overlays: [EditOverlayImage]) {
        self.init(recipe: recipe, naturalSize: source.naturalSize, orientation: source.orientation,
                  renderSize: renderSize, showsBlur: showsBlur, overlays: overlays)
    }

    init(recipe: EditRecipe, naturalSize: CGSize, orientation: CGImagePropertyOrientation, renderSize: CGSize,
         showsBlur: Bool, overlays: [EditOverlayImage]) {
        self.recipe = recipe
        self.naturalSize = naturalSize
        self.orientation = orientation
        self.renderSize = renderSize
        self.showsBlur = showsBlur
        self.overlays = overlays
        self.background = CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: CGRect(origin: .zero, size: renderSize))
    }

    func render(_ source: CIImage, at time: Double) -> CIImage {
        var image = source.movedToOrigin()

        // Upright. Whether AVFoundation already applied the track's turn shows in the size.
        if orientation != .up {
            let stored = abs(image.extent.width - naturalSize.width) < 2 && abs(image.extent.height - naturalSize.height) < 2
            let sideways: [CGImagePropertyOrientation] = [.left, .right, .leftMirrored, .rightMirrored]
            let turnsSides = sideways.contains(orientation)
            if stored && (turnsSides ? naturalSize.width != naturalSize.height : true) {
                image = image.oriented(orientation).movedToOrigin()
            }
        }

        // Crop (normalised, top-left origin; Core Image counts from the bottom).
        let crop = recipe.crop.rect
        if !recipe.crop.isFullFrame {
            let width = image.extent.width, height = image.extent.height
            let rect = CGRect(x: crop.minX * width, y: (1 - crop.maxY) * height,
                              width: crop.width * width, height: crop.height * height).integral
            image = image.cropped(to: rect).movedToOrigin()
        }

        // Mirror, then quarter turns clockwise.
        if recipe.flipped { image = image.oriented(.upMirrored).movedToOrigin() }
        switch ((recipe.quarterTurns % 4) + 4) % 4 {
        case 1: image = image.oriented(.right).movedToOrigin()
        case 2: image = image.oriented(.down).movedToOrigin()
        case 3: image = image.oriented(.left).movedToOrigin()
        default: break
        }

        // Blurred rectangles.
        if showsBlur {
            let width = image.extent.width, height = image.extent.height
            let sigma = max(6, min(width, height) * 0.03)
            for blur in recipe.blurs where time >= blur.start && time <= blur.end {
                let rect = CGRect(x: blur.rect.minX * width, y: (1 - blur.rect.maxY) * height,
                                  width: blur.rect.width * width, height: blur.rect.height * height)
                let blurred = image.clampedToExtent()
                    .applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: max(8, sigma * 0.8)])
                    .applyingGaussianBlur(sigma: sigma)
                    .cropped(to: rect)
                image = blurred.composited(over: image)
            }
        }

        // Render size.
        let sx = renderSize.width / max(1, image.extent.width)
        let sy = renderSize.height / max(1, image.extent.height)
        image = image.transformed(by: CGAffineTransform(scaleX: sx, y: sy))

        // Overlays.
        for overlay in overlays where time >= overlay.start && time <= overlay.end {
            let size = overlay.image.extent.size
            let x = overlay.center.x * renderSize.width - size.width / 2
            let y = (1 - overlay.center.y) * renderSize.height - size.height / 2
            image = overlay.image.movedToOrigin().transformed(by: CGAffineTransform(translationX: x, y: y))
                .composited(over: image)
        }

        return image.composited(over: background).cropped(to: CGRect(origin: .zero, size: renderSize))
    }
}

extension CIImage {
    /// The same picture with its extent starting at 0,0.
    func movedToOrigin() -> CIImage {
        let origin = extent.origin
        guard origin != .zero, origin.x.isFinite, origin.y.isFinite else { return self }
        return transformed(by: CGAffineTransform(translationX: -origin.x, y: -origin.y))
    }
}

// MARK: - Display geometry

/// Maps normalised points and rects between the upright source picture and the turned,
/// mirrored picture the person sees (crop tool).
struct EditFrameGeometry {
    var quarterTurns: Int
    var flipped: Bool

    private var turns: Int { ((quarterTurns % 4) + 4) % 4 }

    /// Upright source → shown.
    func toDisplay(_ point: CGPoint) -> CGPoint {
        var p = point
        if flipped { p.x = 1 - p.x }
        for _ in 0..<turns { p = CGPoint(x: 1 - p.y, y: p.x) }
        return p
    }

    /// Shown → upright source.
    func toSource(_ point: CGPoint) -> CGPoint {
        var p = point
        for _ in 0..<turns { p = CGPoint(x: p.y, y: 1 - p.x) }
        if flipped { p.x = 1 - p.x }
        return p
    }

    func toDisplay(_ rect: CGRect) -> CGRect { mapped(rect, toDisplay) }
    func toSource(_ rect: CGRect) -> CGRect { mapped(rect, toSource) }

    /// Pixel size as shown.
    func displaySize(_ upright: CGSize) -> CGSize {
        turns % 2 == 0 ? upright : CGSize(width: upright.height, height: upright.width)
    }

    private func mapped(_ rect: CGRect, _ transform: (CGPoint) -> CGPoint) -> CGRect {
        let a = transform(CGPoint(x: rect.minX, y: rect.minY))
        let b = transform(CGPoint(x: rect.maxX, y: rect.maxY))
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}
