import AVFoundation
import Foundation

/// Build 47's sound mix, kept to measure against (`LargeRecordingTests`). It always decodes and encodes
/// every sound track, silent or not.
enum LegacyAudioMixer {
    static func mix(_ source: URL, into destination: URL,
                    progress: @escaping @MainActor (Double) -> Void = { _ in }) async -> Bool {
        let asset = AVURLAsset(url: source)
        do {
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            var audible: [AVAssetTrack] = []
            for track in audioTracks {
                let range = try await track.load(.timeRange)
                if range.duration.seconds > 0.1 { audible.append(track) }
            }
            guard let videoTrack = videoTracks.first, audible.count > 1 else { return false }
            let duration = try await asset.load(.duration).seconds
            let transform = try await videoTrack.load(.preferredTransform)
            let formats = try await videoTrack.load(.formatDescriptions)
            return try await copy(asset: asset, video: videoTrack, audio: audible, transform: transform,
                                  videoFormat: formats.first, duration: duration,
                                  destination: destination, progress: progress)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            return false
        }
    }

    private static func copy(asset: AVURLAsset, video: AVAssetTrack, audio: [AVAssetTrack],
                             transform: CGAffineTransform, videoFormat: CMFormatDescription?,
                             duration: Double, destination: URL,
                             progress: @escaping @MainActor (Double) -> Void) async throws -> Bool {
        try? FileManager.default.removeItem(at: destination)
        let reader = try AVAssetReader(asset: asset)
        let videoOut = AVAssetReaderTrackOutput(track: video, outputSettings: nil)
        videoOut.alwaysCopiesSampleData = false
        let pcm: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let audioOut = AVAssetReaderAudioMixOutput(audioTracks: audio, audioSettings: pcm)
        audioOut.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOut), reader.canAdd(audioOut) else { return false }
        reader.add(videoOut)
        reader.add(audioOut)

        let writer = try AVAssetWriter(outputURL: destination, fileType: .mov)
        let videoIn = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: videoFormat)
        videoIn.transform = transform
        let aac: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 160_000,
        ]
        let audioIn = AVAssetWriterInput(mediaType: .audio, outputSettings: aac)
        guard writer.canAdd(videoIn), writer.canAdd(audioIn) else { return false }
        writer.add(videoIn)
        writer.add(audioIn)

        guard reader.startReading() else { return false }
        guard writer.startWriting() else {
            reader.cancelReading()
            return false
        }
        writer.startSession(atSourceTime: .zero)

        let total = max(duration, 0.1)
        let job = MixJob(reader: reader, writer: writer, videoOut: videoOut, videoIn: videoIn,
                         audioOut: audioOut, audioIn: audioIn)
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let succeeded = LegacyAudioMixer.copyLoop(job) { seconds in
                    let fraction = min(1, seconds / total)
                    Task { @MainActor in progress(fraction) }
                }
                continuation.resume(returning: succeeded)
            }
        }
    }

    /// The reader, writer and their tracks. Handed once to the copy loop, which is the only
    /// code that touches them afterwards, so passing them across queues is safe.
    private struct MixJob: @unchecked Sendable {
        let reader: AVAssetReader
        let writer: AVAssetWriter
        let videoOut: AVAssetReaderOutput
        let videoIn: AVAssetWriterInput
        let audioOut: AVAssetReaderOutput
        let audioIn: AVAssetWriterInput
    }

    /// Feeds both inputs in turn until both sources run out. Runs on a background queue.
    /// Gives up if the writer fails or nothing moves for 15 seconds.
    private static func copyLoop(_ job: MixJob, report: (Double) -> Void) -> Bool {
        let reader = job.reader
        let writer = job.writer
        let videoOut = job.videoOut
        let videoIn = job.videoIn
        let audioOut = job.audioOut
        let audioIn = job.audioIn
        var videoDone = false
        var audioDone = false
        var idleSpins = 0
        var lastReported = -1.0
        while !(videoDone && audioDone) {
            if writer.status != .writing || reader.status == .failed || reader.status == .cancelled { break }
            var moved = false
            if !videoDone && videoIn.isReadyForMoreMediaData {
                if let sample = videoOut.copyNextSampleBuffer() {
                    guard videoIn.append(sample) else { break }
                    moved = true
                    let seconds = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                    if seconds - lastReported >= 0.5 {
                        lastReported = seconds
                        report(seconds)
                    }
                } else {
                    videoIn.markAsFinished()
                    videoDone = true
                    moved = true
                }
            }
            if !audioDone && audioIn.isReadyForMoreMediaData {
                if let sample = audioOut.copyNextSampleBuffer() {
                    guard audioIn.append(sample) else { break }
                    moved = true
                } else {
                    audioIn.markAsFinished()
                    audioDone = true
                    moved = true
                }
            }
            if moved {
                idleSpins = 0
            } else {
                idleSpins += 1
                if idleSpins > 7_500 { break }
                usleep(2_000)
            }
        }
        guard videoDone, audioDone, reader.status == .completed, writer.status == .writing else {
            reader.cancelReading()
            writer.cancelWriting()
            return false
        }
        let finished = DispatchSemaphore(value: 0)
        writer.finishWriting {
            finished.signal()
        }
        finished.wait()
        return writer.status == .completed
    }
}
