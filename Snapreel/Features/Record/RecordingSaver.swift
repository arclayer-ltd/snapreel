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
///
/// Review comes first. A save is `.ready` as soon as the file is in the library (moved, never
/// copied) and its length and size are read, which takes a fraction of a second. What can wait
/// happens after review is up: a screen recording's two sound tracks are mixed into one (the
/// slow part, it reads the whole movie), the thumbnail is made off the main thread, and the
/// "saved" notification and transcript follow. Share and Save to Photos in review wait for that
/// (`waitUntilFinished`). Builds up to 30 did all of it before review.
@MainActor
final class RecordingSaver {
    static let shared = RecordingSaver()

    /// Key of the "still needs a title" reminder for a video.
    static func reminderKey(_ id: UUID) -> String { "needs-title-\(id.uuidString)" }

    private var inFlight = Set<UUID>()
    private var waiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]
    /// Staging files the recorder is writing right now; never treated as leftovers.
    var activeCaptureFiles = Set<String>()

    func isProcessing(_ id: UUID) -> Bool { inFlight.contains(id) }

    /// Returns once everything for `id` is done, including the work after review (a screen
    /// recording's sound mixing), so a shared or saved file is the finished one.
    func waitUntilFinished(_ id: UUID) async {
        guard inFlight.contains(id) else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters[id, default: []].append(continuation)
        }
    }

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

    /// Starts saving an edit whose row `EditRenderer` has just added; `save` renders it.
    func beginEdit(_ id: UUID, library: Library) {
        process(id, library: library)
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

    /// Runs the work after review that a killed app didn't finish (`Video.isFinishing`).
    func resumeFinishing(_ id: UUID, library: Library) {
        run(id) { await self.finishAfterReview(id, library: library) }
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
        run(id) {
            do {
                try await self.save(id, library: library)
            } catch {
                self.markFailed(id, error: error, library: library)
            }
        }
    }

    /// One piece of work per recording at a time; `waitUntilFinished` callers resume after it.
    private func run(_ id: UUID, _ work: @escaping @MainActor () async -> Void) {
        guard !inFlight.contains(id) else { return }
        inFlight.insert(id)
        Task { @MainActor in
            await work()
            self.inFlight.remove(id)
            for waiter in self.waiters.removeValue(forKey: id) ?? [] { waiter.resume() }
        }
    }

    private func save(_ id: UUID, library: Library) async throws {
        guard let video = library.video(id) else { return }
        let fm = FileManager.default
        let staged = library.media.staging.appendingPathComponent(video.fileName)
        let destination = library.media.videoURL(video.fileName)
        if DiskSpace.available < 20_000_000 { throw RecordingSaveError.noSpace }

        // 0. An edit is rendered from its recipe until its file is in the library (again after
        //    a failure or the app closing, which can leave a partial file in staging).
        if video.editedFrom != nil, library.editOutput(id) != nil, !fm.fileExists(atPath: destination.path) {
            try? fm.removeItem(at: staged)
            try await EditRenderer.shared.render(id, to: staged, library: library)
            guard library.video(id) != nil else {
                try? fm.removeItem(at: staged)
                return
            }
        }

        // 1. Ready for review: the file into the library (a move on the same volume), then its
        //    length, size and picture size.
        if fm.fileExists(atPath: staged.path) {
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.moveItem(at: staged, to: destination)
        } else if !fm.fileExists(atPath: destination.path) {
            throw RecordingSaveError.missingFile
        }
        ReviewTiming.mark(id, "moved")
        let info: MediaInfo
        do {
            info = try await MediaInspector.inspect(destination)
        } catch {
            throw RecordingSaveError.unreadable
        }
        guard info.duration >= 0.3, info.hasVideo || info.hasAudio else { throw RecordingSaveError.empty }
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
            video.state = .ready
            video.isFinishing = true
        }
        ReviewTiming.mark(id, "read")
        await finishAfterReview(id, library: library)
    }

    /// The work after review: the library card's frame, then (screen recordings) one sound
    /// track, then the notice and transcript. Marked done only at the end, so a launch after
    /// the app was killed midway runs it again (each step checks what is already done).
    private func finishAfterReview(_ id: UUID, library: Library) async {
        guard let video = library.video(id), video.state.isReady else { return }
        let destination = library.media.videoURL(video.fileName)
        guard FileManager.default.fileExists(atPath: destination.path) else {
            library.update(id) { $0.isFinishing = nil }
            return
        }
        let hasVideo = video.kind != .audio && video.pixelWidth > 0

        if hasVideo && video.thumbnailFileName == nil {
            let started = Date()
            let thumbnails = library.media.thumbnails
            let at = video.editedFrom != nil
                ? EditRenderer.shared.thumbnailTime(id, library: library, duration: video.duration)
                : min(0.5, video.duration / 2)
            let name = await Task.detached(priority: .utility) {
                await RecordingSaver.makeThumbnail(for: destination, at: at, named: id.uuidString, in: thumbnails)
            }.value
            if let name, library.video(id) != nil {
                ThumbnailCache.shared.remove(library.media.thumbnailURL(name))
                library.update(id) { $0.thumbnailFileName = name }
                ReviewTiming.after(id, "thumbnail", seconds: Date().timeIntervalSince(started))
            }
        }
        if video.kind == .screen {
            let started = Date()
            if await mixAudioTracksIfNeeded(destination, id: id, library: library) {
                ReviewTiming.after(id, "sound mixed", seconds: Date().timeIntervalSince(started))
                library.update(id) { $0.fileSize = MediaInspector.fileSize(destination) }
            }
        }
        if let saved = library.video(id) {
            announce(saved, library: library)
            library.update(id) { $0.isFinishing = nil }
        }
    }

    /// The frame for the library card, made and written as a JPEG away from the main thread.
    nonisolated private static func makeThumbnail(for url: URL, at seconds: Double, named name: String,
                                                  in directory: URL) async -> String? {
        guard let image = try? await MediaInspector.thumbnail(for: url, at: seconds) else { return nil }
        return try? MediaInspector.writeThumbnail(image, named: name, in: directory)
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
        } else if let editError = error as? EditRenderError {
            reason = editError.message
        } else {
            reason = "Something went wrong while saving. Try again."
        }
        library.update(id) { $0.state = .failed(reason: reason, outOfSpace: outOfSpace) }
    }

    /// Feed row, local notification, the one-hour title reminder and the transcript. A recording
    /// whose review was shown, is on screen or is on its way gets the feed row only: the person
    /// is looking at it.
    private func announce(_ video: Video, library: Library) {
        let alert = video.reviewedAt == nil && !ReviewCoordinator.shared.isReviewing(video.id)
        if video.editedFrom != nil {
            // The original's transcript, moved onto the edit's clock; recognition only when
            // the original had none.
            let hasTranscript = EditRenderer.shared.finish(video.id, library: library)
            Notifier.shared.post(.recordingSaved, title: "Edit saved",
                                 body: "\(Format.clock(video.duration)) edit is in your library.",
                                 videoID: video.id, alert: alert)
            if !hasTranscript { TranscriptService.shared.enqueue(videoID: video.id, library: library) }
            return
        }
        if video.kind == .imported {
            Notifier.shared.post(.importFinished, title: "Import finished",
                                 body: "Your video was copied from Photos and is in your library.",
                                 videoID: video.id, alert: alert)
        } else {
            Notifier.shared.post(.recordingSaved, title: "\(video.kind.label) recording saved",
                                 body: "\(Format.clock(video.duration)) recording is in your library.",
                                 videoID: video.id, alert: alert)
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
    /// Runs after review is up (Snapreel's own players play both tracks meanwhile); the mixed
    /// file is written in staging and swapped in, so a player holding the old one carries on.
    /// True when the file was replaced.
    private func mixAudioTracksIfNeeded(_ url: URL, id: UUID, library: Library) async -> Bool {
        guard DiskSpace.hasRoom(for: MediaInspector.fileSize(url)) else { return false }
        let mixed = library.media.staging.appendingPathComponent("\(id.uuidString)-mixed.mov")
        let succeeded = await RecordingAudioMixer.mix(url, into: mixed) { _ in }
        let fm = FileManager.default
        guard succeeded, library.video(id) != nil, fm.fileExists(atPath: url.path) else {
            try? fm.removeItem(at: mixed)
            return false
        }
        do {
            _ = try fm.replaceItemAt(url, withItemAt: mixed)
            return true
        } catch {
            try? fm.removeItem(at: mixed)
            return false
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
