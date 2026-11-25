import AVFoundation
import Foundation
import UIKit

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
/// happens after review is up: the thumbnail is made off the main thread, the file is put in order
/// (a screen recording's two sound tracks become one, a cut-off recording gets one index; most
/// files need neither), and the "saved" notification and transcript follow. Share and Save to Photos
/// wait only for the file (`waitUntilFileSettled`), with its progress. Leaving Snapreel pauses the
/// work; it carries on when Snapreel is back, also after the app was closed.
@MainActor
final class RecordingSaver {
    static let shared = RecordingSaver()

    /// Key of the "still needs a title" reminder for a video.
    static func reminderKey(_ id: UUID) -> String { "needs-title-\(id.uuidString)" }

    private var inFlight = Set<UUID>()
    private var waiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]
    /// Staging files the recorder is writing right now; never treated as leftovers.
    var activeCaptureFiles = Set<String>()

    /// Recordings whose file is still being saved or may still be replaced.
    private var unsettled = Set<UUID>()
    private var settleWaiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]
    /// How far putting a file in order is, 0...1.
    private var tidyProgress: [UUID: Double] = [:]

    func isProcessing(_ id: UUID) -> Bool { inFlight.contains(id) }

    /// True while the file in the library isn't there yet or is about to be replaced.
    func isFileChanging(_ id: UUID) -> Bool { unsettled.contains(id) }

    /// How far it is, 0...1; nil while there is nothing to measure.
    func fileProgress(_ id: UUID) -> Double? { tidyProgress[id] }

    /// Returns once the recording's file is the one to share, upload or keep (or saving failed).
    func waitUntilFileSettled(_ id: UUID) async {
        guard unsettled.contains(id) else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            settleWaiters[id, default: []].append(continuation)
        }
    }

    private func settle(_ id: UUID) {
        tidyProgress[id] = nil
        guard unsettled.remove(id) != nil else { return }
        for waiter in settleWaiters.removeValue(forKey: id) ?? [] { waiter.resume() }
    }

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
        TidyAttempts.clear(id)
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
        unsettled.insert(id)
        Task { @MainActor in
            await work()
            self.settle(id)
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
        if hasVideo {
            let started = Date()
            if await tidy(destination, id: id, kind: video.kind, library: library) {
                ReviewTiming.after(id, "file put in order", seconds: Date().timeIntervalSince(started))
                // A new URL: one that was asked before remembers the old file's size.
                library.update(id) { $0.fileSize = MediaInspector.fileSize(URL(fileURLWithPath: destination.path)) }
            }
        }
        settle(id)
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

    // MARK: - Putting the file in order

    /// Screen recordings can arrive with phone sound and microphone on separate tracks, and any
    /// recording that was cut off is in fragments. Writes such a file again, the picture copied as it
    /// is, so every player, app and the transcript get all of it; keeps the original on any problem.
    /// Runs after review is up (Snapreel's own players cope with either); the new file is written in
    /// staging and swapped in, so a player holding the old one carries on. Only a file that needs it
    /// is touched, and two sounds are only decoded when both can be heard. True when it was replaced.
    private func tidy(_ url: URL, id: UUID, kind: RecordingKind, library: Library) async -> Bool {
        guard let plan = try? await MoviePlan.make(for: url, isScreenRecording: kind == .screen), plan.needsRewrite else {
            TidyAttempts.clear(id)
            return false
        }
        let written = library.media.staging.appendingPathComponent("\(id.uuidString)-mixed.mov")
        let type: AVFileType = url.pathExtension.lowercased() == "mov" ? .mov : .mp4
        while library.video(id) != nil {
            // Not enough room now: the original stays, and sharing makes a finished copy when there is.
            guard DiskSpace.hasRoom(for: MediaInspector.fileSize(url)) else { return false }
            guard TidyAttempts.begin(id) else { return false }
            let control = MovieRewriteControl { [weak self] value in
                Task { @MainActor in
                    guard let self, self.unsettled.contains(id) else { return }
                    self.tidyProgress[id] = value
                }
            }
            let background = BackgroundTime("Finishing a recording") { control.interrupt() }
            var problem: MovieRewriteError?
            do {
                try await MovieRewrite.run(url, to: written, plan: plan, fileType: type, indexFirst: false, control: control)
            } catch {
                problem = error as? MovieRewriteError ?? .failed
            }
            let inBackground = UIApplication.shared.applicationState == .background
            background.end()
            if let problem {
                // iOS ended the time in the background (or refused something there): start again when
                // Snapreel is back, which doesn't count as a failed attempt.
                guard problem == .interrupted || (problem == .failed && inBackground) else { return false }
                TidyAttempts.undo(id)
                tidyProgress[id] = nil
                await BackgroundTime.waitUntilActive()
                continue
            }
            let fm = FileManager.default
            guard library.video(id) != nil, fm.fileExists(atPath: url.path), await isWhole(written, plan: plan) else {
                try? fm.removeItem(at: written)
                return false
            }
            do {
                _ = try fm.replaceItemAt(url, withItemAt: written)
                TidyAttempts.clear(id)
                return true
            } catch {
                try? fm.removeItem(at: written)
                return false
            }
        }
        return false
    }

    /// The new file plays for as long as the original, so nothing is lost by replacing it.
    nonisolated private func isWhole(_ url: URL, plan: MoviePlan) async -> Bool {
        guard let info = try? await MediaInspector.inspect(url) else { return false }
        return info.duration >= plan.duration - 1
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
                // Half-written by an app that was closed, unless it is being written right now.
                let owner = UUID(uuidString: String(name.prefix(36)))
                if owner.map({ !inFlight.contains($0) }) ?? true { try? fm.removeItem(at: file) }
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

/// How often putting a recording's file in order was started without getting to the end. After three
/// times (the app closed or crashed each time) it is left as it is, so it can never go on forever.
enum TidyAttempts {
    static let most = 3
    private static let key = "recording.tidyAttempts"
    static var defaults: UserDefaults = .standard

    /// Counts an attempt; false when there were too many.
    static func begin(_ id: UUID) -> Bool {
        let count = self.count(id)
        guard count < most else { return false }
        set(count + 1, id)
        return true
    }

    /// The attempt was stopped by iOS, not by a problem.
    static func undo(_ id: UUID) { set(max(0, count(id) - 1), id) }
    static func clear(_ id: UUID) { set(0, id) }

    static func count(_ id: UUID) -> Int { all[id.uuidString] ?? 0 }

    private static var all: [String: Int] { defaults.dictionary(forKey: key) as? [String: Int] ?? [:] }

    private static func set(_ count: Int, _ id: UUID) {
        var counts = all
        counts[id.uuidString] = count > 0 ? count : nil
        if counts != all { defaults.set(counts, forKey: key) }
    }
}
