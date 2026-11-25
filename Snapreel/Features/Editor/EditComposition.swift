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
    /// Average frames a second of the picture. Screen recordings are uneven (about 37 on average,
    /// on a 60 a second clock); camera ones are an even 30.
    let frameRate: Float
    /// Bits a second of the stored picture, 0 when unknown.
    let videoBitRate: Double
    let codec: CMVideoCodecType
    /// HLG or PQ: turned into ordinary colours when the picture is drawn again.
    let isHDR: Bool

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
        var frameRate: Float = 30
        var bitRate: Float = 0
        var codec: CMVideoCodecType = kCMVideoCodecType_H264
        var isHDR = false
        if let track = videoTracks.first {
            naturalSize = try await track.load(.naturalSize)
            transform = try await track.load(.preferredTransform)
            videoRange = try await track.load(.timeRange)
            frameRate = try await track.load(.nominalFrameRate)
            bitRate = try await track.load(.estimatedDataRate)
            isHDR = try await track.load(.mediaCharacteristics).contains(.containsHDRVideo)
            if let format = try await track.load(.formatDescriptions).first {
                codec = CMFormatDescriptionGetMediaSubType(format)
            }
        }
        let turned = CGRect(origin: .zero, size: naturalSize).applying(transform)
        return EditSource(url: url, asset: asset, videoTrack: videoTracks.first, videoRange: videoRange,
                          audioTracks: audible, audioRanges: ranges,
                          duration: duration.isFinite ? duration : 0,
                          naturalSize: naturalSize, transform: transform,
                          uprightSize: CGSize(width: abs(turned.width), height: abs(turned.height)),
                          orientation: Self.orientation(of: transform), frameRate: frameRate,
                          videoBitRate: bitRate.isFinite ? Double(bitRate) : 0, codec: codec, isHDR: isHDR)
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

/// A picture to burn in over the edited video (text, shape, caption).
struct EditOverlayImage {
    let image: CIImage
    /// Output seconds.
    let start: Double
    let end: Double
    /// Normalised centre in the output picture (top-left origin).
    let center: CGPoint
}

/// What the preview shows besides the edit itself.
struct EditPreviewOptions {
    /// The whole picture, for the crop tool.
    var fullFrame = false
    /// The sound without noise reduction (before/after).
    var originalSound = false
}

struct EditBuild {
    let composition: AVMutableComposition
    let audioMix: AVAudioMix?
    /// The edited recording's picture and sound tracks (nil when it has none).
    let videoTrackID: CMPersistentTrackID?
    let audioTrackIDs: [CMPersistentTrackID]
    let voiceTrackIDs: [CMPersistentTrackID]
    let duration: CMTime
}

enum EditCompositionBuilder {
    /// Fine enough for 60 a second pictures and for cuts between frames, so cuts never add up to a
    /// drift between what the recipe says and what plays.
    static let timescale: CMTimeScale = 90_000
    /// How much of the last picture is held when the sound goes on after it.
    private static let heldFrame = CMTime(value: 1, timescale: 60)

    static func build(recipe: EditRecipe, source: EditSource, editFolder: URL, cleanedAudio: URL?,
                      originalSound: Bool) async throws -> EditBuild {
        let composition = AVMutableComposition()
        let videoOut = source.videoTrack != nil
            ? composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
            : nil

        // A track knows its file only as long as someone holds the file.
        var held: [AVAsset] = [source.asset]
        defer { withExtendedLifetime(held) {} }

        // The recording's sound, or its cleaned-up copy (same clock as the recording).
        var audioSources = Array(zip(source.audioTracks, source.audioRanges))
        if recipe.audio.reducesNoise, !originalSound, let cleanedAudio,
           FileManager.default.fileExists(atPath: cleanedAudio.path) {
            let cleaned = AVURLAsset(url: cleanedAudio)
            if let track = try? await cleaned.loadTracks(withMediaType: .audio).first,
               let range = try? await track.load(.timeRange) {
                held.append(cleaned)
                audioSources = [(track, range)]
            }
        }
        let audioOut = audioSources.compactMap { _ in
            composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        }

        let placements = placements(recipe: recipe, source: source)
        for placement in placements {
            if let videoOut, let videoIn = source.videoTrack {
                try insertPicture(placement, of: videoIn, available: source.videoRange, into: videoOut)
            }
            for (index, pair) in audioSources.enumerated() where index < audioOut.count {
                try insert(placement, of: pair.0, available: pair.1, into: audioOut[index])
            }
        }
        videoOut?.preferredTransform = source.transform
        let total = placements.last.map { $0.at + $0.length } ?? .zero

        // Narration, mixed over the recording.
        var voiceOut: [AVMutableCompositionTrack] = []
        for clip in recipe.voiceClips {
            let url = editFolder.appendingPathComponent(clip.fileName)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let asset = AVURLAsset(url: url)
            held.append(asset)
            guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
                  let available = try? await track.load(.timeRange) else { continue }
            let at = CMTime(seconds: clip.start, preferredTimescale: timescale)
            guard at < total else { continue }
            let lead = CMTime(seconds: max(0, clip.lead ?? 0), preferredTimescale: timescale)
            let length = CMTimeMinimum(CMTimeMinimum(available.duration - lead,
                                                     CMTime(seconds: clip.duration, preferredTimescale: timescale)),
                                       total - at)
            guard length > .zero,
                  let out = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            try out.insertTimeRange(CMTimeRange(start: available.start + lead, duration: length), of: track, at: at)
            voiceOut.append(out)
        }

        // A track with nothing in it (all the kept sections are past the end of a short sound)
        // makes playing and saving fail.
        let filledAudio = audioOut.filter { !$0.segments.isEmpty }
        for track in audioOut where track.segments.isEmpty { composition.removeTrack(track) }

        return EditBuild(composition: composition,
                         audioMix: audioMix(recipe: recipe, original: filledAudio.map(\.trackID),
                                            voice: voiceOut.map(\.trackID), total: total),
                         videoTrackID: videoOut?.trackID,
                         audioTrackIDs: filledAudio.map(\.trackID),
                         voiceTrackIDs: voiceOut.map(\.trackID),
                         duration: total)
    }

    /// Where each kept section of the recording lands in the edit. Positions come from the
    /// recipe's own clock, so rounding never adds up over many cuts.
    static func placements(recipe: EditRecipe, source: EditSource) -> [Placement] {
        var result: [Placement] = []
        var outputSeconds = 0.0
        for segment in recipe.playedSegments {
            let speed = max(0.25, min(4, segment.speed))
            let start = CMTime(seconds: max(0, segment.start), preferredTimescale: timescale)
            let end = CMTime(seconds: min(segment.end, max(source.duration, 0)), preferredTimescale: timescale)
            guard end > start else { continue }
            let at = CMTime(seconds: outputSeconds, preferredTimescale: timescale)
            outputSeconds += (end - start).seconds / speed
            result.append(Placement(range: CMTimeRange(start: start, end: end), at: at,
                                    length: CMTime(seconds: outputSeconds, preferredTimescale: timescale) - at,
                                    stretches: abs(speed - 1) > 0.001))
        }
        return result
    }

    /// Where a kept section lands in the edit.
    struct Placement {
        /// In the recording.
        let range: CMTimeRange
        /// In the edit.
        let at: CMTime
        let length: CMTime
        /// Played faster or slower.
        let stretches: Bool

        /// The edit's time for a moment of the recording inside `range`.
        func output(_ time: CMTime) -> CMTime {
            if time <= range.start { return at }
            if time >= range.end { return at + length }
            if range.duration == length { return at + (time - range.start) }
            return at + CMTimeMultiplyByFloat64(length, multiplier: (time - range.start).seconds / range.duration.seconds)
        }

        /// The moment of the recording shown at `time` of the edit.
        func source(_ time: CMTime) -> CMTime {
            if time <= at { return range.start }
            if time >= at + length { return range.end }
            return range.start + CMTimeMultiplyByFloat64(range.duration, multiplier: (time - at).seconds / max(length.seconds, 0.000_01))
        }
    }

    private static func insert(_ placement: Placement, of track: AVAssetTrack, available: CMTimeRange,
                               into out: AVMutableCompositionTrack) throws {
        let clipped = placement.range.intersection(available)
        guard clipped.duration > .zero else { return }
        try insert(clipped, of: track, from: placement.output(clipped.start), to: placement.output(clipped.end),
                   stretches: placement.stretches, into: out)
    }

    /// `range` of `track` from `from` to `to` in the edit, played faster or slower to fit.
    ///
    /// Two things here would be heard: inserting a hair before the end of what is there already
    /// splits it, and stretching a section by a rounding error runs all of its sound through the
    /// pitch corrector. So sections that follow each other are joined end to end, and only a real
    /// change of speed stretches.
    private static func insert(_ range: CMTimeRange, of track: AVAssetTrack, from: CMTime, to: CMTime, stretches: Bool,
                               into out: AVMutableCompositionTrack) throws {
        guard to > from, range.duration > .zero else { return }
        let end = out.segments.isEmpty ? CMTime.zero : out.timeRange.end
        let at = (from - end).seconds < 0.02 ? end : from
        try out.insertTimeRange(range, of: track, at: at)
        guard stretches else { return }
        let length = CMTimeMaximum(to - at, CMTime(value: 1, timescale: timescale))
        if length != range.duration {
            out.scaleTimeRange(CMTimeRange(start: at, duration: range.duration), toDuration: length)
        }
    }

    /// The picture, holding its first or last frame where the sound goes on without it (players do
    /// the same; without this the edit would turn black there).
    private static func insertPicture(_ placement: Placement, of track: AVAssetTrack, available: CMTimeRange,
                                      into out: AVMutableCompositionTrack) throws {
        let range = placement.range
        let frame = CMTimeMinimum(heldFrame, available.duration)
        if range.start < available.start {
            try insert(CMTimeRange(start: available.start, duration: frame), of: track, from: placement.at,
                       to: placement.output(CMTimeMinimum(available.start, range.end)), stretches: true, into: out)
        }
        try insert(placement, of: track, available: available, into: out)
        if range.end > available.end {
            try insert(CMTimeRange(start: available.end - frame, duration: frame), of: track,
                       from: placement.output(CMTimeMaximum(available.end, range.start)), to: placement.at + placement.length,
                       stretches: true, into: out)
        }
    }

    // MARK: - Sound

    /// Levels and fades. Made on its own, so changing the volume never rebuilds what is playing.
    static func audioMix(recipe: EditRecipe, build: EditBuild) -> AVAudioMix? {
        audioMix(recipe: recipe, original: build.audioTrackIDs, voice: build.voiceTrackIDs, total: build.duration)
    }

    private static func audioMix(recipe: EditRecipe, original: [CMPersistentTrackID], voice: [CMPersistentTrackID],
                                 total: CMTime) -> AVAudioMix? {
        guard !original.isEmpty || !voice.isEmpty else { return nil }
        let fade = CMTime(seconds: min(EditAudio.fadeLength, total.seconds / 3), preferredTimescale: timescale)
        var parameters: [AVMutableAudioMixInputParameters] = []
        let level = recipe.audio.muted ? 0 : Float(max(0, min(1, recipe.audio.volume)))
        for id in original {
            let input = AVMutableAudioMixInputParameters()
            input.trackID = id
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
        for id in voice {
            let input = AVMutableAudioMixInputParameters()
            input.trackID = id
            input.audioTimePitchAlgorithm = .spectral
            input.setVolume(voiceLevel, at: .zero)
            parameters.append(input)
        }
        let mix = AVMutableAudioMix()
        mix.inputParameters = parameters
        return mix
    }

    // MARK: - Picture

    /// The player's picture when the recording is shown cropped, turned, mirrored or blurred; nil
    /// when it plays as it is. Made on its own, so moving the crop never rebuilds what is playing.
    static func previewVideoComposition(recipe: EditRecipe, source: EditSource, build: EditBuild,
                                        fullFrame: Bool) -> AVVideoComposition? {
        guard let trackID = build.videoTrackID else { return nil }
        let turned = recipe.quarterTurns != 0 || recipe.flipped
        guard turned || (!fullFrame && (!recipe.crop.isFullFrame || !recipe.blurs.isEmpty)) else { return nil }
        var shown = recipe
        if fullFrame { shown.crop = EditCrop() }
        let size = shown.renderSize(source: source.uprightSize, quality: .hd720)
        let pipeline = EditFramePipeline(recipe: shown, source: source, renderSize: size, showsBlur: !fullFrame)
        let composition = AVMutableVideoComposition()
        composition.customVideoCompositorClass = EditCompositor.self
        composition.renderSize = size
        composition.frameDuration = CMTime(value: 1, timescale: source.frameRate > 31 ? 60 : 30)
        composition.instructions = [EditInstruction(timeRange: CMTimeRange(start: .zero, duration: build.duration),
                                                    trackID: trackID, pipeline: pipeline)]
        return composition
    }
}

/// The whole edit, drawn by one pipeline.
final class EditInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let trackID: CMPersistentTrackID
    let pipeline: EditFramePipeline

    init(timeRange: CMTimeRange, trackID: CMPersistentTrackID, pipeline: EditFramePipeline) {
        self.timeRange = timeRange
        self.trackID = trackID
        self.pipeline = pipeline
        self.requiredSourceTrackIDs = [NSNumber(value: trackID)]
    }
}

/// Draws the player's edited frames. It gets frames exactly as stored (unlike Core Image's own
/// compositor), so the turn is applied once, by the pipeline, for every orientation.
final class EditCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    let sourcePixelBufferAttributes: [String: any Sendable]? = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        kCVPixelBufferMetalCompatibilityKey as String: true,
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: String](),
    ]
    let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferMetalCompatibilityKey as String: true,
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: String](),
    ]
    private let queue = DispatchQueue(label: "co.arclayer.snapreel.edit-preview", qos: .userInteractive)
    private var lastFrame: CVPixelBuffer?
    private let lock = NSLock()
    private var cancelled = 0

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        lock.lock()
        let generation = cancelled
        lock.unlock()
        queue.async { [self] in
            autoreleasepool {
                lock.lock()
                let current = generation == cancelled
                lock.unlock()
                guard current else {
                    request.finishCancelledRequest()
                    return
                }
                guard let instruction = request.videoCompositionInstruction as? EditInstruction,
                      let output = request.renderContext.newPixelBuffer(),
                      let source = request.sourceFrame(byTrackID: instruction.trackID) ?? lastFrame else {
                    request.finish(with: AVError(.noImageAtTime))
                    return
                }
                lastFrame = source
                instruction.pipeline.render(source, at: request.compositionTime.seconds, into: output)
                request.finish(withComposedVideoFrame: output)
            }
        }
    }

    func cancelAllPendingVideoCompositionRequests() {
        lock.lock()
        cancelled += 1
        lock.unlock()
    }
}

// MARK: - Frames

/// The editor's drawing contexts, made once: each costs tens of milliseconds and several
/// megabytes, which used to be paid on every change.
enum EditGraphics {
    /// Ordinary pictures: values go through as they are, which is fast and keeps the colours.
    static let context = CIContext(options: [.workingColorSpace: NSNull(), .cacheIntermediates: false,
                                             .name: "snapreel-edit"])
    /// HDR pictures, turned into ordinary colours.
    static let managedContext = CIContext(options: [.cacheIntermediates: false, .name: "snapreel-edit-hdr"])
    static let sdrSpace = CGColorSpace(name: CGColorSpace.itur_709) ?? CGColorSpaceCreateDeviceRGB()
}

/// Turns one stored frame into one edited frame: upright, cropped, mirrored and turned, blurred,
/// scaled to the render size, with the overlays on top. Holds only values that never change after
/// it is made, so any queue can use it.
final class EditFramePipeline {
    private let recipe: EditRecipe
    private let orientation: CGImagePropertyOrientation
    private let renderSize: CGSize
    private let showsBlur: Bool
    private let isHDR: Bool
    private let background: CIImage

    init(recipe: EditRecipe, source: EditSource, renderSize: CGSize, showsBlur: Bool) {
        self.recipe = recipe
        self.orientation = source.orientation
        self.isHDR = source.isHDR
        self.renderSize = renderSize
        self.showsBlur = showsBlur
        self.background = CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: CGRect(origin: .zero, size: renderSize))
    }

    /// For a picture that is already upright (the poster).
    init(recipe: EditRecipe, upright size: CGSize, showsBlur: Bool) {
        self.recipe = recipe
        self.orientation = .up
        self.isHDR = false
        self.renderSize = size
        self.showsBlur = showsBlur
        self.background = CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: CGRect(origin: .zero, size: size))
    }

    /// Draws the stored frame `source` as it looks at output time `time` into `output`.
    func render(_ source: CVPixelBuffer, at time: Double, overlays: [EditOverlayImage] = [], into output: CVPixelBuffer) {
        let bounds = CGRect(origin: .zero, size: renderSize)
        if isHDR {
            let image = CIImage(cvPixelBuffer: source, options: [.toneMapHDRtoSDR: true])
            EditGraphics.managedContext.render(draw(image, at: time, overlays: overlays), to: output, bounds: bounds,
                                               colorSpace: EditGraphics.sdrSpace)
        } else {
            let image = CIImage(cvPixelBuffer: source, options: [.colorSpace: NSNull()])
            EditGraphics.context.render(draw(image, at: time, overlays: overlays), to: output, bounds: bounds, colorSpace: nil)
            // Same colour labels as the recording, so players show the same colours.
            CVBufferPropagateAttachments(source, output)
        }
    }

    func draw(_ source: CIImage, at time: Double, overlays: [EditOverlayImage] = []) -> CIImage {
        var image = source.movedToOrigin()

        // Upright (frames arrive exactly as stored).
        if orientation != .up { image = image.oriented(orientation).movedToOrigin() }

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
            for blur in recipe.blurs where Self.isActive(blur.start, blur.end, at: time) {
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
        if abs(sx - 1) > 0.0001 || abs(sy - 1) > 0.0001 {
            image = image.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        }

        // Overlays.
        for overlay in overlays where Self.isActive(overlay.start, overlay.end, at: time) {
            let size = overlay.image.extent.size
            let x = overlay.center.x * renderSize.width - size.width / 2
            let y = (1 - overlay.center.y) * renderSize.height - size.height / 2
            image = overlay.image.movedToOrigin()
                .transformed(by: CGAffineTransform(translationX: x.rounded(), y: y.rounded()))
                .composited(over: image)
        }

        return image.composited(over: background).cropped(to: CGRect(origin: .zero, size: renderSize))
    }

    /// On screen at `time`: up to a frame early rather than late, so a blur never misses its first
    /// frame.
    static func isActive(_ start: Double, _ end: Double, at time: Double) -> Bool {
        time >= start - 0.012 && time < end - 0.004
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
