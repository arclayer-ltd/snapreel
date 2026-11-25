import AVFoundation
import UIKit

/// The pieces of making a share link's files (docs/pro/API.md, "Storage layout") that `WebPreparer` puts together:
/// the poster, the preview, sound, and Apple's exporter for anything the fast way can't do. Voice recordings have no
/// picture, so their poster and preview are a drawn card.
enum WebExport {
    enum Failure: LocalizedError {
        case cannotRead
        case cannotExport(String?)
        case tooLarge
        case gone

        var errorDescription: String? {
            switch self {
            case .cannotRead: return "Snapreel couldn't read this recording."
            case .cannotExport(let reason): return reason ?? "Snapreel couldn't prepare the video for the web."
            case .tooLarge: return "This video is over 2 GB, the most a link can hold."
            case .gone: return "This recording isn't on this iPhone any more."
            }
        }
    }

    /// Preparing stopped because Snapreel left the screen; what is done is kept.
    struct Interrupted: Error {}

    /// Hardware encoding taken away (Snapreel left the screen, a call came in).
    static func isInterruption(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == AVFoundationErrorDomain,
           ns.code == AVError.operationInterrupted.rawValue || ns.code == AVError.sessionWasInterrupted.rawValue
            || ns.code == AVError.mediaServicesWereReset.rawValue { return true }
        // VideoToolbox: invalid session, not available now.
        if ns.domain == NSOSStatusErrorDomain, ns.code == -12903 || ns.code == -12915 || ns.code == -16408 { return true }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error { return isInterruption(underlying) }
        return false
    }

    /// The transform that shows a picture upright at the origin, scaled.
    static func upright(_ transform: CGAffineTransform, size: CGSize, scale: Double) -> CGAffineTransform {
        let shown = CGRect(origin: .zero, size: size).applying(transform)
        return transform.concatenating(CGAffineTransform(translationX: -shown.minX, y: -shown.minY))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
    }

    // MARK: Sound

    /// Voice recordings: the AAC track in an MP4, so the watch page's player can play it.
    static func exportAudio(_ asset: AVAsset, to destination: URL) async throws {
        try? FileManager.default.removeItem(at: destination)
        if (try? await run(asset, preset: AVAssetExportPresetPassthrough, to: destination)) != nil,
           MediaInspector.fileSize(destination) > 0 { return }
        try? FileManager.default.removeItem(at: destination)
        // Not AAC already: encode it. M4A is an MP4 file, so it keeps the .mp4 name.
        let m4a = destination.deletingPathExtension().appendingPathExtension("m4a")
        try? FileManager.default.removeItem(at: m4a)
        try await run(asset, preset: AVAssetExportPresetAppleM4A, to: m4a, fileType: .m4a)
        try FileManager.default.moveItem(at: m4a, to: destination)
    }

    /// Mixes a video's sound down to one AAC track in its own file. Returns where it starts in the recording, in
    /// seconds, or nil when there is no sound in it.
    static func encodeSound(_ asset: AVAsset, tracks: [AVAssetTrack], to url: URL) async throws -> Double? {
        let cancelled = WebPreparer.CancelFlag()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (done: CheckedContinuation<Double?, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    do { done.resume(returning: try encodeSoundNow(asset, tracks: tracks, to: url, cancelled)) } catch { done.resume(throwing: error) }
                }
            }
        } onCancel: {
            cancelled.set()
        }
    }

    private static func encodeSoundNow(_ asset: AVAsset, tracks: [AVAssetTrack], to url: URL, _ cancelled: WebPreparer.CancelFlag) throws -> Double? {
        let part = url.appendingPathExtension("part")
        try? FileManager.default.removeItem(at: part)
        try? FileManager.default.removeItem(at: url)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw Failure.cannotRead }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? Failure.cannotRead }
        let writer = try AVAssetWriter(outputURL: part, fileType: .m4a)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128_000,
        ])
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { throw Failure.cannotExport(nil) }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? Failure.cannotExport(nil) }
        var offset: Double?
        while true {
            try cancelled.check()
            let more: Bool = try autoreleasepool {
                guard let buffer = output.copyNextSampleBuffer() else { return false }
                let time = CMSampleBufferGetPresentationTimeStamp(buffer)
                if offset == nil {
                    offset = time.seconds
                    writer.startSession(atSourceTime: time)
                }
                while !input.isReadyForMoreMediaData {
                    try cancelled.check()
                    guard writer.status == .writing else { throw writer.error ?? Failure.cannotExport(nil) }
                    usleep(1_500)
                }
                guard input.append(buffer) else { throw writer.error ?? Failure.cannotExport(nil) }
                return true
            }
            if !more { break }
        }
        guard reader.status == .completed else { throw reader.error ?? Failure.cannotRead }
        guard offset != nil else {
            writer.cancelWriting()
            return nil
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else { throw writer.error ?? Failure.cannotExport(nil) }
        try FileManager.default.moveItem(at: part, to: url)
        return offset
    }

    // MARK: Apple's exporter

    /// The whole web copy with `AVAssetExportSession`, kept under about `limit` bytes.
    static func exportWhole(_ asset: AVURLAsset, to destination: URL, maxLongSide: Int, limit: Int64,
                            progress: @escaping (Double) -> Void) async throws {
        try? FileManager.default.removeItem(at: destination)
        let preset = maxLongSide > 1_280 ? AVAssetExportPreset1920x1080 : AVAssetExportPreset1280x720
        try await run(asset, preset: preset, to: destination, limit: max(limit, 2_000_000), progress: progress)
    }

    /// Stands in for a poster or preview that couldn't be made.
    static func writeStandIn(_ kind: UploadJob.Part.Kind, to url: URL, title: String) {
        let card = audioCard(title: title, duration: 0, size: CGSize(width: 1_280, height: 720), caption: "Snapreel")
        switch kind {
        case .poster: try? card.jpegData(compressionQuality: 0.85)?.write(to: url, options: .atomic)
        case .preview: try? StillClip.writeSync(card, seconds: 3, width: 480, to: url)
        case .video: break
        }
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
    static func writePreview(from source: URL, isAudio: Bool, card: UIImage?, to destination: URL) async throws {
        try? FileManager.default.removeItem(at: destination)
        let asset = AVURLAsset(url: source)
        var track: AVAssetTrack?
        if !isAudio { track = try await asset.loadTracks(withMediaType: .video).first }
        guard let track else {
            guard let card else { return }
            try await StillClip.write(card, seconds: 3, width: 480, to: destination)
            return
        }
        let natural = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let duration = try await asset.load(.duration)
        let shown = CGRect(origin: .zero, size: natural).applying(transform).size
        let scale = 480 / max(abs(shown.width), 1)
        let size = CGSize(width: 480, height: even(abs(shown.height) * scale))
        let length = CMTime(seconds: min(3, max(0.5, duration.seconds)), preferredTimescale: 600)

        let composition = AVMutableVideoComposition()
        composition.renderSize = size
        composition.frameDuration = CMTime(value: 1, timescale: 24)
        composition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setTransform(upright(transform, size: natural, scale: scale), at: .zero)
        instruction.layerInstructions = [layer]
        composition.instructions = [instruction]

        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .utility).async {
                do {
                    try writeClip(asset, track, composition, size: size, length: length, to: destination)
                    done.resume()
                } catch {
                    try? FileManager.default.removeItem(at: destination)
                    done.resume(throwing: error)
                }
            }
        }
    }

    private static func writeClip(_ asset: AVAsset, _ track: AVAssetTrack, _ composition: AVVideoComposition,
                                  size: CGSize, length: CMTime, to url: URL) throws {
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: .zero, duration: length)
        let output = AVAssetReaderVideoCompositionOutput(videoTracks: [track], videoSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        ])
        output.videoComposition = composition
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw Failure.cannotRead }
        reader.add(output)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 700_000,
                AVVideoExpectedSourceFrameRateKey: 24,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264MainAutoLevel,
            ] as [String: Any],
        ])
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { throw Failure.cannotExport(nil) }
        writer.add(input)
        guard reader.startReading() else { throw reader.error ?? Failure.cannotRead }
        guard writer.startWriting() else { throw writer.error ?? Failure.cannotExport(nil) }
        writer.startSession(atSourceTime: .zero)
        var frames = 0
        while let frame = output.copyNextSampleBuffer() {
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing else { throw writer.error ?? Failure.cannotExport(nil) }
                usleep(1_500)
            }
            guard input.append(frame) else { throw writer.error ?? Failure.cannotExport(nil) }
            frames += 1
        }
        guard reader.status == .completed, frames > 0 else {
            writer.cancelWriting()
            throw reader.error ?? Failure.cannotRead
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else { throw writer.error ?? Failure.cannotExport(nil) }
    }

    // MARK: Drawing

    /// A voice recording's card: brand red with a waveform and the title.
    static func audioCard(title: String, duration: Double, size: CGSize, caption: String? = nil) -> UIImage {
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
            let caption = caption ?? "Voice recording · \(Format.clock(duration))"
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

    private static func run(_ asset: AVAsset, preset: String, to destination: URL, fileType: AVFileType = .mp4,
                            limit: Int64 = CloudConfig.maxFileBytes, progress: ((Double) -> Void)? = nil) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw Failure.cannotExport(nil)
        }
        guard session.supportedFileTypes.contains(fileType) else { throw Failure.cannotExport(nil) }
        session.outputURL = destination
        session.outputFileType = fileType
        session.shouldOptimizeForNetworkUse = true
        session.fileLengthLimit = limit
        // The session is only read again inside its own completion handler and the progress timer.
        let box = WebExportSessionBox(session: session)
        let ticker = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                progress?(Double(box.session.progress))
            }
        }
        defer { ticker.cancel() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                box.session.exportAsynchronously {
                    switch box.session.status {
                    case .completed: continuation.resume()
                    case .cancelled: continuation.resume(throwing: CancellationError())
                    default:
                        let error = box.session.error
                        if let error, DiskSpace.isOutOfSpace(error) {
                            continuation.resume(throwing: Failure.cannotExport("Your iPhone is too full to prepare the video."))
                        } else if let error, isInterruption(error) {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(throwing: Failure.cannotExport(nil))
                        }
                    }
                }
            }
        } onCancel: {
            box.session.cancelExport()
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

    static func writeSync(_ image: UIImage, seconds: Int, width: Int, to url: URL) throws {
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
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing else { throw writer.error ?? WebExport.Failure.cannotExport(nil) }
                usleep(2_000)
            }
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
