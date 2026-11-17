import AVFoundation
import Foundation

/// A finished capture or import waiting in `library.media.staging`.
struct RecordingSaveRequest {
    var id: UUID
    var kind: RecordingKind
    var createdAt: Date
    /// File name inside the staging folder; it keeps this name in the videos folder.
    var fileName: String
}

/// Moves recordings into the library. A `Video` row exists from the first moment (state
/// `.saving`), so a save interrupted by Snapreel closing shows up next launch and is finished
/// by `PendingImports.resumeInterruptedSaves`. Failures become `.failed` with a plain reason.
@MainActor
final class RecordingSaver {
    static let shared = RecordingSaver()

    /// Key of the "still needs a title" reminder for a video.
    static func reminderKey(_ id: UUID) -> String { "needs-title-\(id.uuidString)" }

    private var inFlight = Set<UUID>()
    /// Staging files the recorder is writing right now; never treated as leftovers.
    var activeCaptureFiles = Set<String>()

    func isProcessing(_ id: UUID) -> Bool { inFlight.contains(id) }

    /// Adds the row and starts saving.
    func begin(_ request: RecordingSaveRequest, library: Library) {
        let staged = library.media.staging.appendingPathComponent(request.fileName)
        let video = Video(id: request.id,
                          title: Format.defaultTitle(for: request.kind, at: request.createdAt),
                          createdAt: request.createdAt,
                          kind: request.kind,
                          fileName: request.fileName,
                          thumbnailFileName: nil,
                          duration: 0,
                          fileSize: MediaInspector.fileSize(staged),
                          pixelWidth: 0,
                          pixelHeight: 0,
                          needsTitle: true,
                          state: .saving(progress: 0.05))
        library.add(video)
        process(request.id, library: library)
    }

    /// Saving failed earlier (or was interrupted): try again from wherever the file is.
    func retry(_ id: UUID, library: Library) {
        guard library.video(id) != nil else { return }
        library.update(id) { $0.state = .saving(progress: 0.05) }
        process(id, library: library)
    }

    /// Continues a save found in `.saving` state after a relaunch.
    func resume(_ id: UUID, library: Library) {
        process(id, library: library)
    }

    /// Deletes a recording that is being reviewed or failed to save, including its staged file.
    func discard(_ id: UUID, library: Library) {
        if let video = library.video(id) {
            try? FileManager.default.removeItem(at: library.media.staging.appendingPathComponent(video.fileName))
        }
        Notifier.shared.cancelScheduled(key: Self.reminderKey(id))
        library.delete(id)
    }

    // MARK: - Saving

    private func process(_ id: UUID, library: Library) {
        guard !inFlight.contains(id) else { return }
        inFlight.insert(id)
        Task { @MainActor in
            do {
                try await self.save(id, library: library)
            } catch {
                self.markFailed(id, error: error, library: library)
            }
            self.inFlight.remove(id)
        }
    }

    private func save(_ id: UUID, library: Library) async throws {
        guard let video = library.video(id) else { return }
        let fm = FileManager.default
        let staged = library.media.staging.appendingPathComponent(video.fileName)
        let destination = library.media.videoURL(video.fileName)
        if DiskSpace.available < 20_000_000 { throw RecordingSaveError.noSpace }
        setProgress(id, 0.1, library: library)

        if fm.fileExists(atPath: staged.path) {
            if video.kind == .screen {
                await mixAudioTracksIfNeeded(staged, id: id, library: library)
            }
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.moveItem(at: staged, to: destination)
        } else if !fm.fileExists(atPath: destination.path) {
            throw RecordingSaveError.missingFile
        }
        setProgress(id, 0.7, library: library)

        let info: MediaInfo
        do {
            info = try await MediaInspector.inspect(destination)
        } catch {
            throw RecordingSaveError.unreadable
        }
        guard info.duration >= 0.3, info.hasVideo || info.hasAudio else { throw RecordingSaveError.empty }
        setProgress(id, 0.85, library: library)

        var thumbnailName: String?
        if info.hasVideo,
           let image = try? await MediaInspector.thumbnail(for: destination, at: min(0.5, info.duration / 2)) {
            thumbnailName = try? MediaInspector.writeThumbnail(image, named: id.uuidString, in: library.media.thumbnails)
            if let thumbnailName {
                ThumbnailCache.shared.remove(library.media.thumbnailURL(thumbnailName))
            }
        }

        guard library.video(id) != nil else {
            // Deleted while saving.
            try? fm.removeItem(at: destination)
            return
        }
        library.update(id) { video in
            video.duration = info.duration
            video.fileSize = info.fileSize
            video.pixelWidth = info.pixelWidth
            video.pixelHeight = info.pixelHeight
            video.thumbnailFileName = thumbnailName
            video.state = .ready
        }
        if let saved = library.video(id) {
            announce(saved, library: library)
        }
    }

    private func setProgress(_ id: UUID, _ progress: Double, library: Library) {
        library.update(id) { $0.state = .saving(progress: min(0.99, max(0, progress))) }
    }

    private func markFailed(_ id: UUID, error: Error, library: Library) {
        guard library.video(id) != nil else { return }
        let saveError = error as? RecordingSaveError
        let outOfSpace = DiskSpace.isOutOfSpace(error) || saveError == .noSpace
        let reason: String
        if outOfSpace {
            reason = "Your iPhone ran out of space while saving."
        } else if let saveError {
            reason = saveError.message
        } else {
            reason = "Something went wrong while saving. Try again."
        }
        library.update(id) { $0.state = .failed(reason: reason, outOfSpace: outOfSpace) }
    }

    /// Feed row, local notification, the one-hour title reminder and the transcript.
    private func announce(_ video: Video, library: Library) {
        if video.kind == .imported {
            Notifier.shared.post(.importFinished, title: "Import finished",
                                 body: "Your video was copied from Photos and is in your library.",
                                 videoID: video.id)
        } else {
            Notifier.shared.post(.recordingSaved, title: "\(video.kind.label) recording saved",
                                 body: "\(Format.clock(video.duration)) recording is in your library.",
                                 videoID: video.id)
        }
        if video.needsTitle {
            Notifier.shared.schedule(.needsTitle, key: Self.reminderKey(video.id),
                                     title: "Your recording needs a title",
                                     body: "Name it so it's easy to find later.",
                                     videoID: video.id, after: 60 * 60)
        }
        TranscriptService.shared.enqueue(videoID: video.id, library: library)
    }

    /// Screen recordings arrive with app sound and microphone on separate tracks. Mix them into
    /// one so every player, app and the transcript hear both. Keeps the original on any problem.
    private func mixAudioTracksIfNeeded(_ url: URL, id: UUID, library: Library) async {
        guard DiskSpace.hasRoom(for: MediaInspector.fileSize(url)) else { return }
        let mixed = url.deletingLastPathComponent().appendingPathComponent("\(id.uuidString)-mixed.mov")
        let succeeded = await RecordingAudioMixer.mix(url, into: mixed) { [weak self] fraction in
            self?.setProgress(id, 0.1 + 0.55 * fraction, library: library)
        }
        let fm = FileManager.default
        if succeeded {
            do {
                _ = try fm.replaceItemAt(url, withItemAt: mixed)
            } catch {
                try? fm.removeItem(at: mixed)
            }
        } else {
            try? fm.removeItem(at: mixed)
        }
    }

    // MARK: - Leftovers

    /// Files in staging with no row: a camera or audio recording interrupted by Snapreel
    /// closing. Camera movies are written in fragments, so most are readable; those become
    /// recordings again. Unreadable ones are removed quietly.
    func recoverLeftovers(library: Library) {
        let fm = FileManager.default
        let staging = library.media.staging
        guard let files = try? fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return
        }
        let known = Set(library.videos.map(\.fileName))
        let now = Date()
        for file in files {
            let name = file.lastPathComponent
            guard !known.contains(name), !activeCaptureFiles.contains(name) else { continue }
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            guard now.timeIntervalSince(modified) > 120 else { continue }
            if name.contains("-mixed") {
                try? fm.removeItem(at: file)
                continue
            }
            let ext = file.pathExtension.lowercased()
            guard ["mov", "mp4", "m4v", "m4a"].contains(ext) else { continue }
            let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent) ?? UUID()
            guard library.video(id) == nil, !inFlight.contains(id) else { continue }
            let kind: RecordingKind = ext == "m4a" ? .audio : .camera
            inFlight.insert(id)
            Task { @MainActor in
                let info = try? await MediaInspector.inspect(file)
                self.inFlight.remove(id)
                guard let info, info.duration >= 1 else {
                    try? FileManager.default.removeItem(at: file)
                    return
                }
                self.begin(RecordingSaveRequest(id: id, kind: kind,
                                                createdAt: modified.addingTimeInterval(-info.duration),
                                                fileName: name),
                           library: library)
            }
        }
    }
}

enum RecordingSaveError: Error, Equatable {
    case missingFile
    case unreadable
    case empty
    case noSpace

    var message: String {
        switch self {
        case .missingFile: return "The recording's file is missing, so it can't be saved."
        case .unreadable: return "The recording was cut short and can't be played."
        case .empty: return "Nothing was recorded."
        case .noSpace: return "Your iPhone ran out of space while saving."
        }
    }
}

/// Mixes every audio track of a movie into one AAC track and copies the video as it is (no
/// re-encode), keeping the video's rotation.
enum RecordingAudioMixer {
    static func mix(_ source: URL, into destination: URL,
                    progress: @escaping @MainActor (Double) -> Void) async -> Bool {
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
                let succeeded = RecordingAudioMixer.copyLoop(job) { seconds in
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
