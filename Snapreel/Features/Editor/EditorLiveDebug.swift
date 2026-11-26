#if DEBUG
import AVFoundation
import SwiftUI
import UIKit

extension DebugCatalog {
    /// The real editor, playing and saving, on a two-minute portrait recording made on first use.
    /// The UI tests (SnapreelUITests) drive it.
    static var editorLiveScreens: [DebugScreen] {
        [
            DebugScreen("edit.live", "Editor [playing a real recording]", fixture: .filled, wait: 12) { EditorLiveHost() },
        ]
    }
}

struct EditorLiveHost: View {
    @EnvironmentObject private var library: Library
    @State private var launch: EditorLaunch?
    @State private var closed = 0

    var body: some View {
        ZStack {
            Color.srCanvas.ignoresSafeArea()
            VStack(spacing: Space.m) {
                Text(closed == 0 ? "Making a recording…" : "Editor closed")
                if closed > 0, let id = EditorLiveClip.videoID {
                    Button("Open again") { launch = EditorLaunch(videoID: id) }
                        .buttonStyle(.srPrimary)
                    Text("\(library.edits(of: id).filter { $0.state.isReady }.count) saved")
                        .accessibilityIdentifier("live.saved")
                    Text(library.draft(for: id) == nil ? "No draft" : "Draft kept")
                        .accessibilityIdentifier("live.draft")
                }
            }
            .padding()
        }
        .fullScreenCover(item: $launch, onDismiss: { closed += 1 }) { item in
            EditorLiveEditor(videoID: item.videoID, library: library) { launch = nil }
        }
        .task {
            guard launch == nil, closed == 0, let id = await EditorLiveClip.add(to: library) else { return }
            UserDefaults.standard.set(!ProcessInfo.processInfo.arguments.contains("-trimCoach"), forKey: EditorModel.trimCoachKey)
            launch = EditorLaunch(videoID: id)
        }
    }
}

private struct EditorLiveEditor: View {
    @StateObject private var model: EditorModel
    let close: () -> Void

    init(videoID: UUID, library: Library, close: @escaping () -> Void) {
        _model = StateObject(wrappedValue: EditorModel(videoID: videoID, library: library))
        self.close = close
    }

    var body: some View {
        EditorView(model: model, onClose: close, onOpen: { _ in close() })
    }
}

/// A recording of a list scrolling, with the second written on it.
enum EditorLiveClip {
    static var videoID: UUID?

    @MainActor
    static func add(to library: Library) async -> UUID? {
        if let videoID { return videoID }
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let long = caches.appendingPathComponent("editor-live-2.mov")
        if !FileManager.default.fileExists(atPath: long.path) {
            let short = caches.appendingPathComponent("editor-live-short.mov")
            guard await write(short), await loop(short, times: 10, to: long) else { return nil }
        }
        let id = UUID()
        let name = id.uuidString + ".mov"
        do {
            try FileManager.default.copyItem(at: long, to: library.media.videoURL(name))
        } catch {
            return nil
        }
        guard let info = try? await MediaInspector.inspect(library.media.videoURL(name)) else { return nil }
        library.add(Video(id: id, title: "Live editor test", createdAt: Date(), kind: .screen, fileName: name, thumbnailFileName: nil,
                          duration: info.duration, fileSize: info.fileSize, pixelWidth: info.pixelWidth, pixelHeight: info.pixelHeight,
                          needsTitle: false, state: .ready, reviewedAt: Date()))
        let lines = (0..<20).map { index in
            TranscriptSegment(start: Double(index) * 6 + 0.5, duration: 4.5, text: "Line number \(index + 1), um, about the checkout page.")
        }
        library.saveTranscript(Transcript(videoID: id, localeIdentifier: "en-GB", segments: lines, createdAt: Date(), summary: nil))
        videoID = id
        return id
    }

    private static func write(_ url: URL) async -> Bool {
        try? FileManager.default.removeItem(at: url)
        let size = CGSize(width: 590, height: 1278)
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return false }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: size.width, AVVideoHeightKey: size.height,
            AVVideoCompressionPropertiesKey: [AVVideoAllowFrameReorderingKey: false, AVVideoMaxKeyFrameIntervalDurationKey: 2],
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width), kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        writer.add(input)
        guard writer.startWriting() else { return false }
        writer.startSession(atSourceTime: .zero)
        let frames = 360
        for frame in 0..<frames {
            while !input.isReadyForMoreMediaData { try? await Task.sleep(nanoseconds: 2_000_000) }
            guard let pool = adaptor.pixelBufferPool else { return false }
            var made: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made)
            guard let buffer = made else { return false }
            draw(frame, into: buffer, size: size)
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame * 20), timescale: 600))
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue(frames * 20), timescale: 600))
        await writer.finishWriting()
        return writer.status == .completed
    }

    private static func draw(_ frame: Int, into buffer: CVPixelBuffer, size: CGSize) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width), height: Int(size.height),
                                      bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) else { return }
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        UIColor(white: 0.96, alpha: 1).setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        for row in 0..<12 {
            let y = CGFloat(row) * 120 - CGFloat(frame % 120)
            UIColor(hue: CGFloat((row + frame / 120) % 12) / 12, saturation: 0.45, brightness: 0.85, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(x: 30, y: y, width: size.width - 60, height: 96), cornerRadius: 16).fill()
        }
        let text = "\(frame / 30)s" as NSString
        text.draw(at: CGPoint(x: 60, y: size.height / 2 - 80),
                  withAttributes: [.font: UIFont.boldSystemFont(ofSize: 160), .foregroundColor: UIColor.black])
        UIGraphicsPopContext()
    }

    private static func loop(_ url: URL, times: Int, to destination: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        let composition = AVMutableComposition()
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let range = try? await track.load(.timeRange),
              let out = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { return false }
        for index in 0..<times {
            try? out.insertTimeRange(range, of: track, at: CMTimeMultiply(range.duration, multiplier: Int32(index)))
        }
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else { return false }
        session.outputURL = destination
        session.outputFileType = .mov
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { continuation.resume() }
        }
        return session.status == .completed
    }
}
#endif
