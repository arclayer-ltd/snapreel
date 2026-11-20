import AVFoundation
import UIKit

/// Makes the three files a share link needs from a recording (docs/pro/API.md, "Storage
/// layout"):
/// - `video.mp4`: H.264 and AAC laid out for streaming, at most 1280 (Free) or 1920 (Pro) on
///   the long side. A recording that is already H.264 and small enough is only repackaged.
///   Recordings are fragmented .mov files, which some browsers won't stream.
/// - `poster.jpg`: a frame, 1280 on the long side.
/// - `preview.mp4`: 3 seconds, silent, 480 px wide, for email and link previews.
/// Voice recordings have no picture, so their poster and preview are a drawn card.
enum WebExport {
    enum Failure: LocalizedError {
        case cannotRead
        case cannotExport(String?)
        case tooLarge

        var errorDescription: String? {
            switch self {
            case .cannotRead: return "Snapreel couldn't read this recording."
            case .cannotExport(let reason): return reason ?? "Snapreel couldn't prepare the video for the web."
            case .tooLarge: return "This video is over 2 GB, the most a link can hold."
            }
        }
    }

    // MARK: Video

    /// Writes the web copy of `source` to `destination` (an .mp4).
    static func exportVideo(from source: URL, to destination: URL, maxLongSide: Int) async throws {
        try? FileManager.default.removeItem(at: destination)
        let asset = AVURLAsset(url: source)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = videoTracks.first else {
            try await exportAudio(asset, to: destination)
            return
        }
        let natural = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let formats = try await track.load(.formatDescriptions)
        let duration = try await asset.load(.duration)
        let shown = CGRect(origin: .zero, size: natural).applying(transform).size
        let width = abs(shown.width), height = abs(shown.height)
        let isH264 = formats.first.map { CMFormatDescriptionGetMediaSubType($0) == kCMVideoCodecType_H264 } ?? false

        if isH264 && max(width, height) <= CGFloat(maxLongSide) + 1 {
            // Already web-sized: repackage into a streamable MP4 without re-encoding.
            if (try? await run(asset, preset: AVAssetExportPresetPassthrough, to: destination)) != nil { return }
            try? FileManager.default.removeItem(at: destination)
        }

        let scale = min(1, CGFloat(maxLongSide) / max(width, height, 1))
        let render = CGSize(width: even(width * scale), height: even(height * scale))
        let composition = AVMutableVideoComposition()
        composition.renderSize = render
        composition.frameDuration = CMTime(value: 1, timescale: 30)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setTransform(transform.concatenating(CGAffineTransform(scaleX: scale, y: scale)), at: .zero)
        instruction.layerInstructions = [layer]
        composition.instructions = [instruction]
        try await run(asset, preset: AVAssetExportPresetHighestQuality, to: destination, videoComposition: composition)
    }

    /// Voice recordings: the AAC track in an MP4, so the watch page's player can play it.
    private static func exportAudio(_ asset: AVAsset, to destination: URL) async throws {
        if (try? await run(asset, preset: AVAssetExportPresetPassthrough, to: destination)) != nil { return }
        try? FileManager.default.removeItem(at: destination)
        // Not AAC already: encode it. M4A is an MP4 file, so it keeps the .mp4 name.
        let m4a = destination.deletingPathExtension().appendingPathExtension("m4a")
        try? FileManager.default.removeItem(at: m4a)
        try await run(asset, preset: AVAssetExportPresetAppleM4A, to: m4a, fileType: .m4a)
        try FileManager.default.moveItem(at: m4a, to: destination)
    }

    // MARK: Poster

    /// A frame of the video (or the drawn card for a voice recording) as a JPEG, 1280 on the
    /// long side. Returns the image, which the preview reuses for voice recordings.
    @discardableResult
    static func writePoster(from source: URL, isAudio: Bool, title: String, duration: Double,
                            to destination: URL) async throws -> UIImage {
        let image: UIImage
        if isAudio {
            image = audioCard(title: title, duration: duration, size: CGSize(width: 1280, height: 720))
        } else {
            image = try await MediaInspector.thumbnail(for: source, at: min(1, duration / 2), maxDimension: 1280)
        }
        guard let data = image.jpegData(compressionQuality: 0.85) else { throw Failure.cannotExport(nil) }
        try data.write(to: destination, options: .atomic)
        return image
    }

    // MARK: Preview

    /// The first 3 seconds, silent, 480 px wide. Voice recordings get 3 seconds of `card`.
    static func writePreview(from source: URL, isAudio: Bool, card: UIImage, to destination: URL) async throws {
        try? FileManager.default.removeItem(at: destination)
        if isAudio {
            try await StillClip.write(card, seconds: 3, width: 480, to: destination)
            return
        }
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            try await StillClip.write(card, seconds: 3, width: 480, to: destination)
            return
        }
        let duration = try await asset.load(.duration)
        let natural = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let length = CMTime(seconds: min(3, max(0.5, duration.seconds)), preferredTimescale: 600)

        let composition = AVMutableComposition()
        guard let silent = composition.addMutableTrack(withMediaType: .video,
                                                       preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw Failure.cannotRead
        }
        try silent.insertTimeRange(CMTimeRange(start: .zero, duration: length), of: track, at: .zero)
        silent.preferredTransform = transform

        let shown = CGRect(origin: .zero, size: natural).applying(transform).size
        let width = abs(shown.width), height = abs(shown.height)
        let scale = 480 / max(width, 1)
        let video = AVMutableVideoComposition()
        video.renderSize = CGSize(width: 480, height: even(height * scale))
        video.frameDuration = CMTime(value: 1, timescale: 30)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: length)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: silent)
        layer.setTransform(transform.concatenating(CGAffineTransform(scaleX: scale, y: scale)), at: .zero)
        instruction.layerInstructions = [layer]
        video.instructions = [instruction]
        try await run(composition, preset: AVAssetExportPresetHighestQuality, to: destination, videoComposition: video)
    }

    // MARK: Drawing

    /// A voice recording's card: brand red with a waveform and the title.
    static func audioCard(title: String, duration: Double, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let colors = [UIColor(hex: 0xFE6262).cgColor, UIColor(hex: 0xD32434).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            }
            // Waveform across the middle.
            let bars = 48
            let barWidth = size.width * 0.6 / CGFloat(bars * 2)
            let left = size.width * 0.2
            cg.setFillColor(UIColor.white.withAlphaComponent(0.92).cgColor)
            for index in 0..<bars {
                let wave = abs(sin(Double(index) * 0.55)) * 0.7 + abs(sin(Double(index) * 0.17)) * 0.3
                let barHeight = size.height * 0.08 + size.height * 0.3 * CGFloat(wave)
                let x = left + CGFloat(index) * barWidth * 2
                let rect = CGRect(x: x, y: size.height * 0.42 - barHeight / 2, width: barWidth, height: barHeight)
                cg.addPath(UIBezierPath(roundedRect: rect, cornerRadius: barWidth / 2).cgPath)
            }
            cg.fillPath()
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byTruncatingTail
            let titleFont = UIFont.systemFont(ofSize: size.height * 0.07, weight: .bold)
            (title as NSString).draw(in: CGRect(x: size.width * 0.08, y: size.height * 0.7,
                                                width: size.width * 0.84, height: titleFont.lineHeight * 1.2),
                                     withAttributes: [.font: titleFont, .foregroundColor: UIColor.white,
                                                      .paragraphStyle: paragraph])
            let caption = "Voice recording · \(Format.clock(duration))"
            let captionFont = UIFont.systemFont(ofSize: size.height * 0.04, weight: .semibold)
            (caption as NSString).draw(in: CGRect(x: 0, y: size.height * 0.81, width: size.width,
                                                  height: captionFont.lineHeight * 1.2),
                                       withAttributes: [.font: captionFont,
                                                        .foregroundColor: UIColor.white.withAlphaComponent(0.8),
                                                        .paragraphStyle: paragraph])
        }
    }

    // MARK: Export session

    private static func even(_ value: CGFloat) -> CGFloat {
        max(2, (value / 2).rounded() * 2)
    }

    private static func run(_ asset: AVAsset, preset: String, to destination: URL,
                            fileType: AVFileType = .mp4, videoComposition: AVVideoComposition? = nil) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw Failure.cannotExport(nil)
        }
        guard session.supportedFileTypes.contains(fileType) else { throw Failure.cannotExport(nil) }
        session.outputURL = destination
        session.outputFileType = fileType
        session.shouldOptimizeForNetworkUse = true
        session.fileLengthLimit = CloudConfig.maxFileBytes
        if let videoComposition { session.videoComposition = videoComposition }
        // The session is only read again inside its own completion handler.
        let box = WebExportSessionBox(session: session)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            box.session.exportAsynchronously {
                if box.session.status == .completed {
                    continuation.resume()
                } else {
                    let error = box.session.error
                    if let error, DiskSpace.isOutOfSpace(error) {
                        continuation.resume(throwing: Failure.cannotExport("Your iPhone is too full to prepare the video."))
                    } else {
                        continuation.resume(throwing: Failure.cannotExport(nil))
                    }
                }
            }
        }
    }
}

/// Carries an export session into its own completion handler, the only other place it is read.
private struct WebExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession
}

/// Writes a still image as a short silent H.264 clip (a voice recording's preview).
enum StillClip {
    static func write(_ image: UIImage, seconds: Int, width: Int, to url: URL) async throws {
        try await Task.detached(priority: .utility) {
            try writeSync(image, seconds: seconds, width: width, to: url)
        }.value
    }

    private static func writeSync(_ image: UIImage, seconds: Int, width: Int, to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        guard let cgImage = image.cgImage else { throw WebExport.Failure.cannotRead }
        let height = max(2, Int((CGFloat(width) * image.size.height / max(1, image.size.width) / 2).rounded()) * 2)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        guard writer.canAdd(input) else { throw WebExport.Failure.cannotExport(nil) }
        writer.add(input)
        writer.shouldOptimizeForNetworkUse = true
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        let fps: Int32 = 10
        for index in 0...(Int(fps) * seconds) {
            while !input.isReadyForMoreMediaData { usleep(2_000) }
            guard let pool = adaptor.pixelBufferPool else { break }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { continue }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
                                       bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                       space: CGColorSpaceCreateDeviceRGB(),
                                       bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: fps))
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else { throw WebExport.Failure.cannotExport(nil) }
    }
}
