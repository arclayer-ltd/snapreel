import AVFoundation
import SwiftUI
import UIKit

/// What the camera engine reports when the session is (re)configured.
struct RecorderCameraSetup {
    var isAvailable: Bool
    var side: CameraSide
    /// The other camera supports the current quality, so it can be switched to mid-recording.
    var canFlipWhileRecording: Bool
    var message: String?
}

/// How a camera recording ended.
enum RecorderCaptureResult {
    case finished(URL)
    /// The writer stopped early (for example the disk filled) but a readable part was kept.
    case partial(URL)
    case failed(String, outOfSpace: Bool)
}

/// Camera capture and movie writing, off the main actor.
/// Session changes run on `sessionQueue`; frames, sound and the movie writer run on `dataQueue`.
/// Results come back through `@Sendable` callbacks; callers hop to the main actor themselves.
final class RecorderCameraEngine: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate,
                                  AVCaptureAudioDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "co.arclayer.snapreel.camera.session")
    private let dataQueue = DispatchQueue(label: "co.arclayer.snapreel.camera.data")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()

    // sessionQueue only
    private var cameraInput: AVCaptureDeviceInput?
    private var microphoneInput: AVCaptureDeviceInput?
    private var outputsAdded = false

    // dataQueue only
    private var movie: RecorderMovieWriter?

    // MARK: - Session

    /// Sets up (or changes) the session and starts it. `keepPreset` holds the current quality
    /// while a recording is running (used when flipping mid-recording).
    func configure(side: CameraSide, quality: RecordingQuality, mirrorsFront: Bool, microphone: Bool,
                   keepPreset: Bool = false,
                   completion: @escaping @Sendable (RecorderCameraSetup) -> Void) {
        sessionQueue.async {
            let setup = self.applyConfiguration(side: side, quality: quality, mirrorsFront: mirrorsFront,
                                                microphone: microphone, keepPreset: keepPreset)
            if setup.isAvailable && !self.session.isRunning {
                self.session.startRunning()
            }
            completion(setup)
        }
    }

    func stopRunning() {
        sessionQueue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    private func applyConfiguration(side: CameraSide, quality: RecordingQuality, mirrorsFront: Bool,
                                    microphone: Bool, keepPreset: Bool) -> RecorderCameraSetup {
        let position: AVCaptureDevice.Position = side == .front ? .front : .back
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            return RecorderCameraSetup(isAvailable: false, side: side, canFlipWhileRecording: false,
                                       message: "This iPhone's camera isn't available right now.")
        }
        let currentPreset = session.sessionPreset
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        if cameraInput?.device.uniqueID != device.uniqueID {
            if let cameraInput { session.removeInput(cameraInput) }
            cameraInput = nil
            guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
                return RecorderCameraSetup(isAvailable: false, side: side, canFlipWhileRecording: false,
                                           message: "Snapreel couldn't open the camera. Close other apps using it and try again.")
            }
            session.addInput(input)
            cameraInput = input
        }

        if microphone, microphoneInput == nil,
           let mic = AVCaptureDevice.default(for: .audio),
           let input = try? AVCaptureDeviceInput(device: mic),
           session.canAddInput(input) {
            session.addInput(input)
            microphoneInput = input
        } else if !microphone, let microphoneInput {
            session.removeInput(microphoneInput)
            self.microphoneInput = nil
        }

        if !outputsAdded {
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: dataQueue)
            if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
            audioOutput.setSampleBufferDelegate(self, queue: dataQueue)
            if session.canAddOutput(audioOutput) { session.addOutput(audioOutput) }
            outputsAdded = true
        }

        if keepPreset, session.canSetSessionPreset(currentPreset) {
            session.sessionPreset = currentPreset
        } else {
            let preset = Self.presets(for: quality).first { session.canSetSessionPreset($0) } ?? .high
            if session.sessionPreset != preset { session.sessionPreset = preset }
        }

        if let connection = videoOutput.connection(with: .video) {
            if #available(iOS 17, *) {
                if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            } else if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = side == .front && mirrorsFront
            }
        }

        let otherPosition: AVCaptureDevice.Position = side == .front ? .back : .front
        let other = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: otherPosition)
        let canFlip = other?.supportsSessionPreset(session.sessionPreset) ?? false
        return RecorderCameraSetup(isAvailable: true, side: side, canFlipWhileRecording: canFlip, message: nil)
    }

    private static func presets(for quality: RecordingQuality) -> [AVCaptureSession.Preset] {
        switch quality {
        case .max: return [.hd4K3840x2160, .hd1920x1080, .hd1280x720]
        case .high: return [.hd1920x1080, .hd1280x720]
        case .standard: return [.hd1280x720]
        }
    }

    // MARK: - Recording

    func startRecording(to url: URL, quality: RecordingQuality, includesAudio: Bool) {
        dataQueue.async {
            self.movie = RecorderMovieWriter(url: url, quality: quality, includesAudio: includesAudio)
        }
    }

    func pauseRecording() {
        dataQueue.async { self.movie?.pause() }
    }

    func resumeRecording() {
        dataQueue.async { self.movie?.resume() }
    }

    func stopRecording(completion: @escaping @Sendable (RecorderCaptureResult) -> Void) {
        dataQueue.async {
            guard let movie = self.movie else {
                completion(.failed("Nothing was recorded.", outOfSpace: false))
                return
            }
            self.movie = nil
            movie.finish(completion: completion)
        }
    }

    /// Throws the current recording away and deletes its file.
    func cancelRecording() {
        dataQueue.async {
            self.movie?.cancel()
            self.movie = nil
        }
    }

    // MARK: - Samples (dataQueue)

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let movie else { return }
        if output === videoOutput {
            movie.append(sampleBuffer, isVideo: true)
        } else if output === audioOutput {
            movie.append(sampleBuffer, isVideo: false)
        }
    }
}

/// Writes camera frames and microphone sound into a movie, with pause and resume done by
/// dropping samples while paused and shifting later timestamps back by the paused time.
/// Used only on the camera engine's data queue.
final class RecorderMovieWriter {
    let url: URL
    private let quality: RecordingQuality
    private let includesAudio: Bool

    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var isPaused = false
    private var resumePending = false
    private var timeOffset = CMTime.zero
    private var sessionStart = CMTime.invalid
    private var lastAppendedEnd = CMTime.invalid
    private var lastVideoTime = CMTime.invalid
    private var lastAudioEnd = CMTime.invalid
    private var frameCount = 0
    private var failed = false

    init(url: URL, quality: RecordingQuality, includesAudio: Bool) {
        self.url = url
        self.quality = quality
        self.includesAudio = includesAudio
    }

    func pause() {
        isPaused = true
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        resumePending = true
    }

    func append(_ sample: CMSampleBuffer, isVideo: Bool) {
        guard !isPaused, !failed, CMSampleBufferDataIsReady(sample) else { return }
        let sourceTime = CMSampleBufferGetPresentationTimeStamp(sample)
        guard sourceTime.isValid else { return }

        if writer == nil {
            guard isVideo, start(with: sample, at: sourceTime) else { return }
        }
        guard let writer else { return }
        guard writer.status == .writing else {
            if writer.status == .failed { failed = true }
            return
        }

        if resumePending {
            resumePending = false
            if lastAppendedEnd.isValid {
                let gap = CMTimeSubtract(CMTimeSubtract(sourceTime, timeOffset), lastAppendedEnd)
                if CMTimeCompare(gap, .zero) > 0 { timeOffset = CMTimeAdd(timeOffset, gap) }
            }
        }

        let adjusted: CMSampleBuffer
        if CMTimeCompare(timeOffset, .zero) == 0 {
            adjusted = sample
        } else if let copy = RecorderSampleTiming.retimed(sample, by: timeOffset) {
            adjusted = copy
        } else {
            return
        }
        let time = CMSampleBufferGetPresentationTimeStamp(adjusted)
        guard CMTimeCompare(time, sessionStart) >= 0 else { return }
        let duration = CMSampleBufferGetDuration(adjusted)
        let end = duration.isValid ? CMTimeAdd(time, duration) : time

        if isVideo {
            guard let input = videoInput, input.isReadyForMoreMediaData else { return }
            if lastVideoTime.isValid && CMTimeCompare(time, lastVideoTime) <= 0 { return }
            if input.append(adjusted) {
                lastVideoTime = time
                frameCount += 1
                noteAppended(end)
            } else if writer.status == .failed {
                failed = true
            }
        } else {
            guard let input = audioInput, input.isReadyForMoreMediaData else { return }
            if lastAudioEnd.isValid && CMTimeCompare(time, lastAudioEnd) < 0 { return }
            if input.append(adjusted) {
                lastAudioEnd = end
                noteAppended(end)
            } else if writer.status == .failed {
                failed = true
            }
        }
    }

    func finish(completion: @escaping @Sendable (RecorderCaptureResult) -> Void) {
        let url = self.url
        guard let writer, frameCount > 0 else {
            self.writer?.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            completion(.failed("Nothing was recorded. Keep recording for a moment before you stop.", outOfSpace: false))
            return
        }
        guard writer.status == .writing else {
            completion(Self.leftover(at: url, error: writer.error))
            return
        }
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        writer.finishWriting {
            if writer.status == .completed {
                completion(.finished(url))
            } else {
                completion(Self.leftover(at: url, error: writer.error))
            }
        }
    }

    func cancel() {
        writer?.cancelWriting()
        writer = nil
        try? FileManager.default.removeItem(at: url)
    }

    /// A fragmented movie that failed to finish is still readable up to its last fragment.
    private static func leftover(at url: URL, error: Error?) -> RecorderCaptureResult {
        let outOfSpace = error.map { DiskSpace.isOutOfSpace($0) } ?? false
        if MediaInspector.fileSize(url) > 200_000 {
            return .partial(url)
        }
        try? FileManager.default.removeItem(at: url)
        return .failed(outOfSpace ? "Your iPhone ran out of space, so the recording couldn't be saved."
                                  : "The recording couldn't be finished. Try again.",
                       outOfSpace: outOfSpace)
    }

    private func noteAppended(_ end: CMTime) {
        if !lastAppendedEnd.isValid || CMTimeCompare(end, lastAppendedEnd) > 0 { lastAppendedEnd = end }
    }

    private func start(with sample: CMSampleBuffer, at time: CMTime) -> Bool {
        guard let image = CMSampleBufferGetImageBuffer(sample) else { return false }
        let width = CVPixelBufferGetWidth(image)
        let height = CVPixelBufferGetHeight(image)
        guard width > 0, height > 0 else { return false }

        try? FileManager.default.removeItem(at: url)
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else {
            failed = true
            return false
        }
        // Fragments keep the file readable if Snapreel is closed mid-recording.
        writer.movieFragmentInterval = CMTime(seconds: 4, preferredTimescale: 600)

        let pixels = Double(width * height)
        let bitRate = Int(min(40_000_000, max(3_000_000, pixels * 5.3)))
        let compression: [String: Any] = [
            AVVideoAverageBitRateKey: bitRate,
            AVVideoExpectedSourceFrameRateKey: 30,
            AVVideoMaxKeyFrameIntervalKey: 60,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        ]
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
            AVVideoCompressionPropertiesKey: compression,
        ]
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        video.expectsMediaDataInRealTime = true
        guard writer.canAdd(video) else {
            failed = true
            return false
        }
        writer.add(video)

        if includesAudio {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 96_000,
            ]
            let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audio.expectsMediaDataInRealTime = true
            if writer.canAdd(audio) {
                writer.add(audio)
                audioInput = audio
            }
        }

        guard writer.startWriting() else {
            failed = true
            try? FileManager.default.removeItem(at: url)
            return false
        }
        writer.startSession(atSourceTime: time)
        self.writer = writer
        videoInput = video
        sessionStart = time
        return true
    }
}

/// Moves a sample's timestamps earlier by `offset` without copying its media data.
enum RecorderSampleTiming {
    static func retimed(_ sample: CMSampleBuffer, by offset: CMTime) -> CMSampleBuffer? {
        var needed: CMItemCount = 0
        guard CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: 0, arrayToFill: nil,
                                                     entriesNeededOut: &needed) == 0, needed > 0 else {
            return nil
        }
        var timing = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: needed)
        var filled: CMItemCount = 0
        guard CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: needed, arrayToFill: &timing,
                                                     entriesNeededOut: &filled) == 0 else {
            return nil
        }
        for index in timing.indices {
            timing[index].presentationTimeStamp = CMTimeSubtract(timing[index].presentationTimeStamp, offset)
            if timing[index].decodeTimeStamp.isValid {
                timing[index].decodeTimeStamp = CMTimeSubtract(timing[index].decodeTimeStamp, offset)
            }
        }
        var copy: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault,
                                                           sampleBuffer: sample,
                                                           sampleTimingEntryCount: needed,
                                                           sampleTimingArray: timing,
                                                           sampleBufferOut: &copy)
        return status == 0 ? copy : nil
    }
}

/// Live camera preview. Not part of the recorded movie, so overlays (speaker notes) never end
/// up in the video.
struct RecorderCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> RecorderPreviewView {
        let view = RecorderPreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: RecorderPreviewView, context: Context) {}
}

final class RecorderPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        // layerClass guarantees the type.
        layer as! AVCaptureVideoPreviewLayer
    }
}
