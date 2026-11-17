import Foundation
import UIKit
import UserNotifications

/// Hands a recording to the recorder's review screen, whether or not the recorder is open.
/// `PendingImports` sets it; `RecorderView` takes it.
@MainActor
final class RecorderInbox: ObservableObject {
    static let shared = RecorderInbox()

    @Published var reviewRequest: UUID?
    /// Shown above the review when the screen recording stopped early.
    var reviewNote: String?
}

/// Session B owns this file. Called by the shell each time the app becomes active, and by the
/// recorder when a screen recording finishes.
@MainActor
enum PendingImports {
    /// Must match `SampleHandler.notificationPrefix` in the broadcast extension.
    static let broadcastNotificationPrefix = "broadcast-"

    /// Moves finished screen recordings from the App Group inbox into the library, then opens
    /// review for the newest one if the recorder is on screen or it finished in the last
    /// quarter of an hour (the person is coming back to finish it).
    static func importFinishedBroadcasts(into library: Library) {
        salvageAbandonedBroadcast()

        let fm = FileManager.default
        let inbox = AppGroup.inboxURL
        let manifests = ((try? fm.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
        var imported: [InboxRecording] = []

        for manifestURL in manifests {
            guard let data = try? Data(contentsOf: manifestURL),
                  let item = try? JSONDecoder.snapreel.decode(InboxRecording.self, from: data) else {
                try? fm.removeItem(at: manifestURL)
                continue
            }
            let movie = inbox.appendingPathComponent(item.movieFileName)
            if library.video(item.id) != nil {
                try? fm.removeItem(at: manifestURL)
                continue
            }
            guard fm.fileExists(atPath: movie.path) else {
                try? fm.removeItem(at: manifestURL)
                continue
            }
            let ext = movie.pathExtension.isEmpty ? "mov" : movie.pathExtension.lowercased()
            let fileName = "\(item.id.uuidString).\(ext)"
            let staged = library.media.staging.appendingPathComponent(fileName)
            try? fm.removeItem(at: staged)
            do {
                try fm.moveItem(at: movie, to: staged)
            } catch {
                continue
            }
            try? fm.removeItem(at: manifestURL)
            RecordingSaver.shared.begin(RecordingSaveRequest(id: item.id, kind: .screen,
                                                             createdAt: item.createdAt, fileName: fileName),
                                        library: library)
            UNUserNotificationCenter.current()
                .removeDeliveredNotifications(withIdentifiers: [broadcastNotificationPrefix + item.id.uuidString])
            imported.append(item)
        }

        guard let newest = imported.max(by: { $0.finishedAt < $1.finishedAt }) else { return }
        let router = AppEnvironment.shared.router
        let recorderOpen = router.recorder != nil
        let finishedRecently = Date().timeIntervalSince(newest.finishedAt) < 15 * 60
        let canPresent = !router.isSettingsPresented && (router.player.map { $0.isMinimized } ?? true)
        guard recorderOpen || (finishedRecently && canPresent) else { return }
        openReview(newest.id, note: newest.endedEarly ? newest.note : nil, router: router)
    }

    /// For a tap on the extension's "Your screen recording is ready" notification
    /// (`userInfo["broadcastID"]`). Imports it if needed and opens its review.
    static func openReviewFromNotification(broadcastID: UUID, library: Library) {
        importFinishedBroadcasts(into: library)
        guard library.video(broadcastID) != nil else { return }
        let router = AppEnvironment.shared.router
        router.closePlayer()
        router.isSettingsPresented = false
        openReview(broadcastID, note: nil, router: router)
    }

    /// Resumes or marks failed any save that was interrupted when the app was closed, and
    /// recovers camera or audio recordings left in staging by a crash.
    static func resumeInterruptedSaves(in library: Library) {
        let saver = RecordingSaver.shared
        for video in library.videos where !saver.isProcessing(video.id) {
            if case .saving = video.state {
                saver.resume(video.id, library: library)
            }
        }
        saver.recoverLeftovers(library: library)
    }

    // MARK: - Private

    /// True while anything records or mirrors the screen (a live broadcast included).
    private static var isScreenCaptured: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen }
            .contains { $0.isCaptured }
    }

    private static func openReview(_ id: UUID, note: String?, router: AppRouter) {
        let inbox = RecorderInbox.shared
        inbox.reviewNote = note
        inbox.reviewRequest = id
        if router.recorder == nil {
            router.record(.screen)
        }
    }

    /// If the extension was stopped by the system mid-recording it never moved its movie to
    /// the inbox. Once the shared state has been silent for a minute and nothing is capturing
    /// the screen, move whatever it wrote to the inbox so it can be saved.
    private static func salvageAbandonedBroadcast() {
        let state = BroadcastStateStore.read()
        guard state.status == .recording || state.status == .finishing,
              let id = state.recordingID,
              Date().timeIntervalSince(state.updatedAt) > 60,
              !isScreenCaptured else { return }

        let fm = FileManager.default
        let candidates = ((try? fm.contentsOfDirectory(at: AppGroup.inProgressURL, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix(id.uuidString) }
        if let movie = candidates.first(where: { ["mov", "mp4"].contains($0.pathExtension.lowercased()) }),
           MediaInspector.fileSize(movie) > 100_000 {
            let destination = AppGroup.inboxURL.appendingPathComponent(movie.lastPathComponent)
            try? fm.removeItem(at: destination)
            if (try? fm.moveItem(at: movie, to: destination)) != nil {
                let manifest = InboxRecording(id: id, movieFileName: movie.lastPathComponent,
                                              createdAt: state.startedAt ?? state.updatedAt,
                                              finishedAt: state.updatedAt,
                                              microphoneEnabled: state.microphoneEnabled,
                                              endedEarly: true,
                                              note: "The recording stopped unexpectedly. Snapreel kept everything it could.")
                if let data = try? JSONEncoder.snapreel.encode(manifest) {
                    try? data.write(to: InboxRecording.manifestURL(for: id), options: .atomic)
                }
            }
        }
        for leftover in candidates where fm.fileExists(atPath: leftover.path) {
            try? fm.removeItem(at: leftover)
        }
        BroadcastStateStore.write(BroadcastState(status: .idle, updatedAt: Date()))
    }
}
