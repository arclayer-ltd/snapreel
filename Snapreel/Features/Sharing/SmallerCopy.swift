import AVFoundation
import Foundation

/// A second, smaller file of the same recording, for apps and mail that refuse large ones.
struct SmallerCopyPlan: Equatable {
    var width: Int
    var height: Int
    var videoBitRate: Int
    var estimatedBytes: Int64

    static let audioBitRate = 96_000
    static let frameRate: Int32 = 30
    /// Messenger and most mail take up to 25 MB.
    static let aim: Double = 24_000_000

    /// Nil when there is nothing to gain: a voice recording, or a file that is already small.
    static func make(for video: Video) -> SmallerCopyPlan? {
        guard !video.isAudioOnly else { return nil }
        return make(width: video.pixelWidth, height: video.pixelHeight, duration: video.duration, bytes: video.fileSize)
    }

    static func make(width: Int, height: Int, duration: Double, bytes: Int64) -> SmallerCopyPlan? {
        guard width > 0, height > 0, duration > 1, bytes > 12_000_000 else { return nil }
        let wanted = aim / 1.03 * 8 / duration - Double(audioBitRate)
        let rate = min(2_500_000, max(450_000, wanted))
        let shortSide = rate >= 1_300_000 ? 720.0 : 540.0
        let scale = min(1, shortSide / Double(min(width, height)))
        func even(_ value: Int) -> Int { max(2, Int((Double(value) * scale / 2).rounded()) * 2) }
        let estimate = Int64((rate + Double(audioBitRate)) / 8 * duration * 1.03)
        guard estimate < bytes * 6 / 10 else { return nil }
        return SmallerCopyPlan(width: even(width), height: even(height), videoBitRate: Int(rate),
                               estimatedBytes: estimate)
    }
}

enum SmallerCopy {
    /// Encodes `source` at the plan's size into an MP4 that can be streamed. iOS only lets an app
    /// encode video while it is on screen, so leaving Snapreel interrupts it.
    static func write(_ source: URL, to destination: URL, plan: SmallerCopyPlan,
                      control: MovieRewriteControl) async throws {
        try? FileManager.default.removeItem(at: destination)
        do {
            try await encode(source, to: destination, plan: plan, control: control)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw MoviePump.explain(error, control: control)
        }
    }

    private static func encode(_ source: URL, to destination: URL, plan: SmallerCopyPlan,
                               control: MovieRewriteControl) async throws {
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw MovieRewriteError.unreadable
        }
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let duration = try await asset.load(.duration)
        let natural = try await track.load(.naturalSize)
        let transform = MoviePlan.upright(try await track.load(.preferredTransform), size: natural)
        let shown = CGRect(origin: .zero, size: natural).applying(transform).size

        // Upright, at the smaller size, 30 steady frames a second, standard colours (HDR included).
        let composition = AVMutableVideoComposition()
        composition.renderSize = CGSize(width: plan.width, height: plan.height)
        composition.frameDuration = CMTime(value: 1, timescale: SmallerCopyPlan.frameRate)
        composition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        let scale = CGAffineTransform(scaleX: CGFloat(plan.width) / max(abs(shown.width), 1),
                                      y: CGFloat(plan.height) / max(abs(shown.height), 1))
        layer.setTransform(transform.concatenating(scale), at: .zero)
        instruction.layerInstructions = [layer]
        composition.instructions = [instruction]

        let reader = try AVAssetReader(asset: asset)
        let pictures = AVAssetReaderVideoCompositionOutput(videoTracks: [track], videoSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        ])
        pictures.videoComposition = composition
        pictures.alwaysCopiesSampleData = false

        let writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        if let created = try? await asset.load(.creationDate) { writer.metadata = [created] }
        let compression: [String: Any] = [
            AVVideoAverageBitRateKey: plan.videoBitRate,
            AVVideoExpectedSourceFrameRateKey: SmallerCopyPlan.frameRate,
            AVVideoMaxKeyFrameIntervalKey: SmallerCopyPlan.frameRate * 3,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: plan.width,
            AVVideoHeightKey: plan.height,
            AVVideoCompressionPropertiesKey: compression,
        ])
        var lanes = [MoviePump.Lane(output: pictures, input: input)]
        if !audioTracks.isEmpty {
            let sound = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: SoundSettings.pcm)
            let encoded = AVAssetWriterInput(mediaType: .audio,
                                             outputSettings: SoundSettings.aac(bitRate: SmallerCopyPlan.audioBitRate))
            lanes.append(MoviePump.Lane(output: sound, input: encoded))
        }
        try await MoviePump.run(reader: reader, writer: writer, lanes: lanes, duration: duration.seconds,
                                control: control)
    }
}
