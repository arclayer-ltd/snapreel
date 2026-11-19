import AVFoundation
import AVKit
import SwiftUI
import UIKit

/// A small Snapreel tile that floats over other apps while the screen is being recorded, so
/// there's a way to stop without hunting for the red pill. iOS only lets an app show something
/// over other apps through picture in picture, so the tile is a picture-in-picture window:
/// it can be dragged anywhere, pushed off the side to tuck it away, or closed with its ✕.
/// Tapping it shows the picture-in-picture controls: the pause sign stops the recording and
/// the arrow brings Snapreel back. Like everything else on screen, it is in the recording.
///
/// The tile starts by itself when the person leaves Snapreel during a recording, as long as
/// the recorder's "Snapreel is recording your screen" page (which shows the tile) is open.
@MainActor
final class ScreenRecordingFloater {
    static let shared = ScreenRecordingFloater()

    static var isSupported: Bool {
        #if DEBUG
        if AppEnvironment.shared.debugScreenID != nil { return true }
        #endif
        return AVPictureInPictureController.isPictureInPictureSupported()
    }

    /// What the floating window shows.
    let displayLayer = AVSampleBufferDisplayLayer()
    /// The same picture as an image, for the in-app preview.
    let tileImage: UIImage = ScreenRecordingFloater.drawTile()

    private let bridge = FloaterPictureInPictureBridge()
    private var controller: AVPictureInPictureController?
    private var isArmed = false
    private var floatingSince: Date?
    private var finishedObserver: BroadcastSignalObserver?
    private var activeObserver: NSObjectProtocol?

    private init() {
        displayLayer.videoGravity = .resizeAspect
        bridge.floater = self
    }

    /// Puts the tile in the layer (debug screens use this on its own, without floating).
    func renderTile() {
        guard let sample = Self.sampleBuffer(from: tileImage) else { return }
        if displayLayer.status == .failed { displayLayer.flush() }
        displayLayer.enqueue(sample)
    }

    /// A screen recording is running: float the tile as soon as the person leaves Snapreel.
    func arm() {
        guard Self.isSupported, !isArmed else { return }
        isArmed = true
        renderTile()
        let audio = AVAudioSession.sharedInstance()
        // Picture in picture needs an active playback session; mixing keeps other apps' sound.
        try? audio.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? audio.setActive(true)
        if controller == nil {
            let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: displayLayer,
                                                                    playbackDelegate: bridge)
            let controller = AVPictureInPictureController(contentSource: source)
            controller.delegate = bridge
            controller.requiresLinearPlayback = true
            self.controller = controller
        }
        controller?.canStartPictureInPictureAutomaticallyFromInline = true
        controller?.invalidatePlaybackState()
        finishedObserver = BroadcastSignalObserver(.finished) { [weak self] in
            Task { @MainActor in self?.disarm() }
        }
        activeObserver = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.appBecameActive() }
        }
    }

    /// The recording ended (or the floating button was turned off).
    func disarm() {
        guard isArmed else { return }
        isArmed = false
        controller?.canStartPictureInPictureAutomaticallyFromInline = false
        if controller?.isPictureInPictureActive == true { controller?.stopPictureInPicture() }
        floatingSince = nil
        finishedObserver = nil
        if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
        activeObserver = nil
    }

    /// Back in Snapreel: the recorder shows the recording, so the floating copy goes away. It
    /// comes back the next time the person leaves.
    private func appBecameActive() {
        let state = BroadcastStateStore.read()
        if state.status != .recording && state.status != .finishing {
            disarm()
        } else if controller?.isPictureInPictureActive == true {
            controller?.stopPictureInPicture()
        }
    }

    // MARK: - Picture-in-picture callbacks (main actor)

    fileprivate func floatingChanged(_ active: Bool) {
        floatingSince = active ? Date() : nil
    }

    /// The pause sign in the floating window: stop the recording.
    fileprivate func pauseTapped() {
        // Ignore the state changes iOS reports while the window is still appearing.
        guard let floatingSince, Date().timeIntervalSince(floatingSince) > 1 else {
            controller?.invalidatePlaybackState()
            return
        }
        Haptics.firm()
        BroadcastSignal.stopRequested.post()
        disarm()
    }

    // MARK: - Drawing

    /// 16:9, dark, with the record mark and how to stop.
    private static func drawTile() -> UIImage {
        let size = CGSize(width: 480, height: 270)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.srInk.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            // Record mark: red disc, white ring, red centre.
            let mark = CGRect(x: 40, y: 75, width: 120, height: 120)
            UIColor.srRed.setFill()
            UIBezierPath(ovalIn: mark).fill()
            UIColor.white.setStroke()
            let ring = UIBezierPath(ovalIn: mark.insetBy(dx: 22, dy: 22))
            ring.lineWidth = 9
            ring.stroke()
            UIColor.white.setFill()
            UIBezierPath(ovalIn: mark.insetBy(dx: 42, dy: 42)).fill()

            let title: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 46, weight: .bold),
                .foregroundColor: UIColor.white,
            ]
            let live: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 30, weight: .semibold),
                .foregroundColor: UIColor.srRed,
            ]
            let hint: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 25, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.72),
            ]
            NSAttributedString(string: "● Recording", attributes: live).draw(at: CGPoint(x: 190, y: 62))
            NSAttributedString(string: "Snapreel", attributes: title).draw(at: CGPoint(x: 190, y: 100))
            NSAttributedString(string: "Tap, then ❚❚ to stop", attributes: hint).draw(at: CGPoint(x: 190, y: 166))
        }
    }

    private static func sampleBuffer(from image: UIImage) -> CMSampleBuffer? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [CFString: Any],
        ]
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                                  attributes as CFDictionary, &pixelBuffer) == kCVReturnSuccess,
              let buffer = pixelBuffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        let drawn: Bool = {
            guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                              | CGBitmapInfo.byteOrder32Little.rawValue) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }()
        CVPixelBufferUnlockBaseAddress(buffer, [])
        guard drawn else { return nil }

        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer,
                                                           formatDescriptionOut: &format) == noErr,
              let format else { return nil }
        var timing = CMSampleTimingInfo(duration: .invalid,
                                        presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
                                        decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer,
                                                       formatDescription: format, sampleTiming: &timing,
                                                       sampleBufferOut: &sample) == noErr,
              let sample else { return nil }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let first = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(first,
                                 Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sample
    }
}

/// AVKit's callbacks for the floating tile. They may arrive off the main actor; anything that
/// changes state hops to it. The tile is "live" content that is always playing.
final class FloaterPictureInPictureBridge: NSObject, AVPictureInPictureControllerDelegate,
                                           AVPictureInPictureSampleBufferPlaybackDelegate {
    weak var floater: ScreenRecordingFloater?

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        guard !playing else { return }
        Task { @MainActor [weak self] in self?.floater?.pauseTapped() }
    }

    func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        // Live: no scrubber and no skip buttons.
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }

    func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        false
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    skipByInterval skipInterval: CMTime,
                                    completion completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor [weak self] in self?.floater?.floatingChanged(true) }
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor [weak self] in self?.floater?.floatingChanged(false) }
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        // The arrow in the floating window: iOS brings Snapreel forward, showing the recorder.
        completionHandler(true)
    }
}

/// Shows the floating tile's layer in the recorder, which is also where picture in picture
/// starts from when the person leaves Snapreel.
struct FloaterTileView: UIViewRepresentable {
    func makeUIView(context: Context) -> FloaterTileHost {
        FloaterTileHost()
    }

    func updateUIView(_ uiView: FloaterTileHost, context: Context) {}
}

final class FloaterTileHost: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        let tile = ScreenRecordingFloater.shared.displayLayer
        if tile.superlayer !== layer {
            tile.removeFromSuperlayer()
            layer.addSublayer(tile)
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let tile = ScreenRecordingFloater.shared.displayLayer
        if tile.superlayer === layer { tile.frame = bounds }
    }
}
