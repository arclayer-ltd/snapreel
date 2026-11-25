import AVFoundation
import CoreMedia
import ImageIO
import ReplayKit

/// Writes ReplayKit samples straight into a movie file in the App Group.
///
/// Pictures are never buffered: each frame is either appended at once or dropped, which keeps the
/// extension well under its memory limit (about 50 MB). Sound waits for the writer for up to a
/// second and a half (under half a megabyte), and any sound that is lost becomes silence of the
/// same length, so it stays in step with the picture (`SoundTimeline`). The movie is written with
/// fragments every two seconds, so even if the extension is stopped by the system the file stays
/// readable up to the last fragment. Every method is safe to call from any queue.
///
/// Tracks: one H.264 video track, app audio as one AAC track and the microphone as a second AAC
/// track. The app mixes the two audio tracks into one when it imports the recording.
final class BroadcastWriter {
    enum Outcome {
        /// A complete movie.
        case written(URL)
        /// The writer failed, but a partial (fragmented) movie exists that may still play.
        case partial(URL)
        /// No video frame arrived, or the file could not be created.
        case nothingRecorded
    }

    private let lock = NSLock()
    private let url: URL
    private let quality: String?

    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var appAudioInput: AVAssetWriterInput?
    private var micAudioInput: AVAssetWriterInput?

    private var outcome: Outcome?
    private var isPaused = false
    private var resumePending = false
    /// Time removed from every sample after a pause, so the movie has no gap.
    private var timeOffset = CMTime.zero
    private var sessionStart = CMTime.invalid
    /// Latest end time appended to any track, in movie time.
    private var lastAppendedEnd = CMTime.invalid
    private var lastVideoTime = CMTime.invalid
    private var appSound = SoundTrack()
    private var micSound = SoundTrack()
    private var videoFrameCount = 0
    private var hasMicAudio = false

    init(url: URL, quality: String?) {
        self.url = url
        self.quality = quality
    }

    /// True once at least one microphone sample arrived (the person turned the mic on).
    var microphoneHeard: Bool {
        lock.lock()
        defer { lock.unlock() }
        return hasMicAudio
    }

    func pause() {
        lock.lock()
        isPaused = true
        lock.unlock()
    }

    func resume() {
        lock.lock()
        if isPaused {
            isPaused = false
            resumePending = true
        }
        lock.unlock()
    }

    func append(_ sample: CMSampleBuffer, type: RPSampleBufferType) {
        lock.lock()
        defer { lock.unlock() }
        guard outcome == nil, !isPaused, CMSampleBufferDataIsReady(sample) else { return }
        if type == .audioMic { hasMicAudio = true }

        let sourceTime = CMSampleBufferGetPresentationTimeStamp(sample)
        guard sourceTime.isValid else { return }

        if writer == nil {
            // The movie starts with the first frame; earlier audio is dropped.
            guard type == .video, startWriting(with: sample, at: sourceTime) else { return }
        }
        guard let writer, writer.status == .writing else { return }

        if resumePending {
            resumePending = false
            if lastAppendedEnd.isValid {
                let gap = CMTimeSubtract(CMTimeSubtract(sourceTime, timeOffset), lastAppendedEnd)
                if CMTimeCompare(gap, .zero) > 0 {
                    timeOffset = CMTimeAdd(timeOffset, gap)
                }
            }
        }

        let adjusted: CMSampleBuffer
        if CMTimeCompare(timeOffset, .zero) == 0 {
            adjusted = sample
        } else if let copy = BroadcastSampleTiming.retimed(sample, by: timeOffset) {
            adjusted = copy
        } else {
            return
        }
        let time = CMSampleBufferGetPresentationTimeStamp(adjusted)
        guard sessionStart.isValid, CMTimeCompare(time, sessionStart) >= 0 else { return }
        let duration = CMSampleBufferGetDuration(adjusted)
        let end = duration.isValid ? CMTimeAdd(time, duration) : time

        switch type {
        case .video:
            guard let input = videoInput, input.isReadyForMoreMediaData else { return }
            if lastVideoTime.isValid && CMTimeCompare(time, lastVideoTime) <= 0 { return }
            if input.append(adjusted) {
                lastVideoTime = time
                videoFrameCount += 1
                noteAppended(end: end)
            }
        case .audioApp:
            appendSound(adjusted, to: appAudioInput, track: &appSound)
        case .audioMic:
            appendSound(adjusted, to: micAudioInput, track: &micSound)
        @unknown default:
            return
        }
    }

    /// Finishes the movie. Blocks until the file is closed (at most 10 seconds). Safe to call
    /// more than once; later calls return the first outcome.
    func finish() -> Outcome {
        lock.lock()
        defer { lock.unlock() }
        if let outcome { return outcome }

        let result: Outcome
        if let writer {
            result = close(writer)
        } else {
            result = .nothingRecorded
        }
        outcome = result
        return result
    }

    // MARK: - Sound (called with the lock held)

    /// One sound track's clock and the buffers waiting for the writer.
    private struct SoundTrack {
        var timeline = SoundTimeline()
        var waiting: [CMSampleBuffer] = []
        /// About 1.5 s of ReplayKit's buffers (1024 frames each, 23 ms).
        static let mostWaiting = 64
    }

    private func appendSound(_ sample: CMSampleBuffer, to input: AVAssetWriterInput?, track: inout SoundTrack) {
        guard let input else { return }
        drain(&track, into: input)
        if track.waiting.isEmpty, input.isReadyForMoreMediaData {
            write(sample, to: input, track: &track)
            return
        }
        // Not ready: keep a copy for a moment. When too much is waiting the oldest goes, and the
        // silence written in its place keeps the rest in step.
        if track.waiting.count >= SoundTrack.mostWaiting { track.waiting.removeFirst() }
        if let copy = SoundBuffer.copy(sample) { track.waiting.append(copy) }
    }

    private func drain(_ track: inout SoundTrack, into input: AVAssetWriterInput) {
        while !track.waiting.isEmpty, input.isReadyForMoreMediaData {
            write(track.waiting.removeFirst(), to: input, track: &track)
        }
    }

    private func write(_ sample: CMSampleBuffer, to input: AVAssetWriterInput, track: inout SoundTrack) {
        let time = CMSampleBufferGetPresentationTimeStamp(sample)
        guard let rate = SoundBuffer.sampleRate(of: sample) else {
            // Not plain PCM (never seen from ReplayKit): as it is.
            if input.append(sample) { noteAppended(end: time) }
            return
        }
        switch track.timeline.step(forBufferAt: time.seconds) {
        case .drop:
            return
        case .append:
            break
        case .fill(let gap):
            var left = Int((gap * rate).rounded())
            while left > 0 {
                // If the writer fills up on the way, this buffer is lost too and the next one's
                // gap includes it.
                let piece = min(left, SoundBuffer.pieceFrames)
                guard input.isReadyForMoreMediaData, let end = track.timeline.end else { return }
                let start = CMTime(seconds: end, preferredTimescale: CMTimeScale(rate))
                guard let silence = SoundBuffer.silence(like: sample, frames: piece, at: start),
                      input.append(silence) else { return }
                track.timeline.appended(seconds: Double(piece) / rate, at: end)
                left -= piece
            }
            guard input.isReadyForMoreMediaData else { return }
        }
        if input.append(sample) {
            let frames = CMSampleBufferGetNumSamples(sample)
            track.timeline.appended(seconds: Double(frames) / rate, at: time.seconds)
            noteAppended(end: CMTimeAdd(time, CMTime(value: CMTimeValue(frames), timescale: CMTimeScale(rate))))
        }
    }

    // MARK: - Private (called with the lock held)

    private func noteAppended(end: CMTime) {
        if !lastAppendedEnd.isValid || CMTimeCompare(end, lastAppendedEnd) > 0 {
            lastAppendedEnd = end
        }
    }

    private func close(_ writer: AVAssetWriter) -> Outcome {
        guard writer.status == .writing else {
            return keepPartialIfAny()
        }
        guard videoFrameCount > 0 else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            return .nothingRecorded
        }
        if let appAudioInput { drain(&appSound, into: appAudioInput) }
        if let micAudioInput { drain(&micSound, into: micAudioInput) }
        videoInput?.markAsFinished()
        appAudioInput?.markAsFinished()
        micAudioInput?.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting {
            done.signal()
        }
        if done.wait(timeout: .now() + 10) == .timedOut {
            return keepPartialIfAny()
        }
        return writer.status == .completed ? .written(url) : keepPartialIfAny()
    }

    private func keepPartialIfAny() -> Outcome {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return size > 100_000 ? .partial(url) : .nothingRecorded
    }

    private func startWriting(with sample: CMSampleBuffer, at time: CMTime) -> Bool {
        guard let image = CMSampleBufferGetImageBuffer(sample) else { return false }
        let sourceWidth = CVPixelBufferGetWidth(image)
        let sourceHeight = CVPixelBufferGetHeight(image)
        guard sourceWidth > 0, sourceHeight > 0 else { return false }
        let size = Self.outputSize(width: sourceWidth, height: sourceHeight, quality: quality)

        try? FileManager.default.removeItem(at: url)
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return false }
        writer.movieFragmentInterval = CMTime(seconds: 2, preferredTimescale: 600)

        let video = AVAssetWriterInput(mediaType: .video,
                                       outputSettings: Self.videoSettings(width: size.width, height: size.height))
        video.expectsMediaDataInRealTime = true
        video.transform = Self.transform(for: Self.orientation(of: sample), width: size.width, height: size.height)
        guard writer.canAdd(video) else { return false }
        writer.add(video)

        let appAudio = AVAssetWriterInput(mediaType: .audio, outputSettings: Self.audioSettings(channels: 2))
        appAudio.expectsMediaDataInRealTime = true
        if writer.canAdd(appAudio) {
            writer.add(appAudio)
            appAudioInput = appAudio
        }
        let micAudio = AVAssetWriterInput(mediaType: .audio, outputSettings: Self.audioSettings(channels: 1))
        micAudio.expectsMediaDataInRealTime = true
        if writer.canAdd(micAudio) {
            writer.add(micAudio)
            micAudioInput = micAudio
        }

        guard writer.startWriting() else {
            try? FileManager.default.removeItem(at: url)
            appAudioInput = nil
            micAudioInput = nil
            return false
        }
        writer.startSession(atSourceTime: time)
        self.writer = writer
        videoInput = video
        sessionStart = time
        return true
    }

    // MARK: - Settings

    /// The phone's screen scaled to the chosen quality (shorter side 720 or 1080 pixels, or the
    /// full screen for 4K), rounded to even numbers for the encoder.
    static func outputSize(width: Int, height: Int, quality: String?) -> (width: Int, height: Int) {
        let shorter = Double(min(width, height))
        let target: Double
        switch quality ?? "" {
        case "720p": target = 720
        case "4K": target = shorter
        default: target = 1080
        }
        let scale = min(1, target / max(shorter, 1))
        func even(_ value: Int) -> Int {
            max(2, Int((Double(value) * scale / 2).rounded()) * 2)
        }
        return (even(width), even(height))
    }

    private static func videoSettings(width: Int, height: Int) -> [String: Any] {
        let pixels = Double(width * height)
        // About 2.6 bits per pixel per second: sharp text without huge files.
        let bitRate = Int(min(14_000_000, max(2_500_000, pixels * 2.6)))
        let compression: [String: Any] = [
            AVVideoAverageBitRateKey: bitRate,
            AVVideoExpectedSourceFrameRateKey: 30,
            AVVideoMaxKeyFrameIntervalKey: 60,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            AVVideoAllowFrameReorderingKey: false,
        ]
        return [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspect,
            AVVideoCompressionPropertiesKey: compression,
        ]
    }

    private static func audioSettings(channels: Int) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: channels == 2 ? 128_000 : 96_000,
        ]
    }

    private static func orientation(of sample: CMSampleBuffer) -> CGImagePropertyOrientation {
        guard let value = CMGetAttachment(sample, key: RPVideoSampleOrientationKey as CFString, attachmentModeOut: nil) as? NSNumber,
              let orientation = CGImagePropertyOrientation(rawValue: value.uint32Value) else {
            return .up
        }
        return orientation
    }

    /// ReplayKit always delivers the screen in the phone's portrait pixel layout and says how the
    /// content is turned. The track transform turns it upright when played, and moves the turned
    /// picture back to the origin: Apple's players do that by themselves, but apps that place the
    /// picture with the transform as it is (some share extensions and editors) draw it off screen
    /// without it. It is set from the first frame: turning the phone during a recording keeps the
    /// starting orientation.
    static func transform(for orientation: CGImagePropertyOrientation, width: Int, height: Int) -> CGAffineTransform {
        // Exact quarter turns: `rotationAngle` leaves tiny remainders that some readers reject.
        switch orientation {
        case .right, .rightMirrored:
            return CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: CGFloat(height), ty: 0)
        case .left, .leftMirrored:
            return CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: CGFloat(width))
        case .down, .downMirrored:
            return CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: CGFloat(width), ty: CGFloat(height))
        default:
            return .identity
        }
    }
}

/// Moves a sample's timestamps earlier by `offset` without copying its media data.
enum BroadcastSampleTiming {
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
