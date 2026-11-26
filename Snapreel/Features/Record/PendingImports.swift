import Combine
import Foundation
import OSLog
import UIKit
import UserNotifications

/// The one place that decides whether a finished recording is shown for review, and shows it.
///
/// Every hand-off comes here, keyed by the recording's id:
/// - camera and voice takes: the recorder goes from saving to review by itself and reports it
///   (`reviewShown`);
/// - screen recordings: the import when Snapreel comes to the front, the extension's "finished"
///   signal while the recorder is open, a tap on the "Screen recording finished" notification,
///   and the import on a cold launch (`PendingImports`), which all call `offer`.
///
/// A recording is reviewed once. The moment its review is on screen, `Video.reviewedAt` is
/// stored (so a relaunch doesn't offer it again) and its delivered notifications are removed.
/// Nothing waits for a later recorder: a review meant for a recorder that is opening is tied
/// to that presentation, and dropped if it closes first. So after Done, Delete or close, the
/// next tap on record opens "What do you want to record?". Builds 29 and 30 had one waiting
/// slot that several hand-offs filled, which showed some reviews twice and lost others.
@MainActor
final class ReviewCoordinator {
    static let shared = ReviewCoordinator()

    /// Where a hand-off came from (for the trace).
    enum Source: String {
        case recorder = "recorder"
        case extensionFinished = "finished signal"
        case appActive = "app-active import"
        case notificationTap = "notification tap"
    }

    /// The recorder on screen, set while it is visible.
    private(set) weak var visibleRecorder: RecorderModel?
    /// A review for the recorder being presented for it (`launchID`), taken when it appears.
    /// Dropped when another recorder is presented instead, or when none appeared in 5 s (iOS
    /// can refuse a presentation), so it never blocks later hand-offs.
    private(set) var pending: (id: UUID, note: String?, launchID: UUID, since: Date)?
    /// The recording whose review (or save) is on screen.
    private(set) var showing: UUID?
    /// Hand-offs that arrived while the recorder was on its way out, or while it showed another
    /// recording's review: offered in turn once it has gone, so none is shown in a recorder
    /// sliding off screen, replaces a review being looked at, or is lost.
    private var queued: [(id: UUID, note: String?, source: Source, presentIfClosed: Bool)] = []

    private let log = Logger(subsystem: "co.arclayer.snapreel", category: "review")

    /// A finished recording should be reviewed. Shows it in the open recorder, or presents the
    /// recorder for it when `presentIfClosed` (the person is coming back to finish it, or tapped
    /// its notification). Each recording is shown once, whatever arrives later.
    func offer(_ id: UUID, note: String?, source: Source, presentIfClosed: Bool,
               library: Library, router: AppRouter) {
        let tag = "hand-off \(source.rawValue) \(Self.short(id))"
        dropStalePending(router: router)
        guard let video = library.video(id) else { return trace("\(tag): skip, not in the library") }
        guard video.reviewedAt == nil else { return trace("\(tag): skip, already reviewed") }
        guard showing != id, pending?.id != id, !queued.contains(where: { $0.id == id }) else {
            return trace("\(tag): skip, already on screen or on its way")
        }
        if let recorder = visibleRecorder {
            guard recorder.acceptsReviews else {
                queued.append((id, note, source, presentIfClosed))
                return trace("\(tag): waiting for the closing recorder to go")
            }
            if let current = recorder.currentReviewID, current != id {
                queued.append((id, note, source, presentIfClosed))
                return trace("\(tag): waiting behind the review on screen")
            }
            if recorder.showReview(id, note: note) {
                trace("\(tag): shown in the open recorder")
            } else {
                trace("\(tag): skip, the open recorder is recording")
            }
            return
        }
        if let opening = router.recorder {
            // A recorder is on its way in (the person just tapped record): it shows this when
            // it appears. If it is on its way out instead, it never takes it.
            guard pending == nil else {
                queued.append((id, note, source, presentIfClosed))
                return trace("\(tag): waiting behind the review on its way")
            }
            pending = (id, note, opening.id, Date())
            return trace("\(tag): waiting for the recorder that is opening")
        }
        guard presentIfClosed else { return trace("\(tag): skip, recorder closed and not presenting") }
        guard router.minimizedRecorder == nil else { return trace("\(tag): skip, a voice recording is running") }
        let launch = RecorderLaunch(mode: video.kind.recordMode)
        pending = (id, note, launch.id, Date())
        router.recorder = launch
        trace("\(tag): presenting the recorder for it")
    }

    /// A pending review whose recorder was replaced by another presentation (the person opened
    /// the recorder some other way, a minimised voice recording came back) or never appeared.
    private func dropStalePending(router: AppRouter) {
        guard let pending else { return }
        let replaced = router.recorder?.id != pending.launchID && visibleRecorder?.launch.id != pending.launchID
        guard replaced || Date().timeIntervalSince(pending.since) > 5 else { return }
        self.pending = nil
        trace("dropped the review of \(Self.short(pending.id)) waiting for a recorder that didn't come")
    }

    /// True while `id`'s review is on screen, on its way, or its save is showing in the recorder:
    /// no "saved" alert for it (`RecordingSaver.announce`).
    func isReviewing(_ id: UUID) -> Bool {
        showing == id || pending?.id == id || queued.contains(where: { $0.id == id })
            || visibleRecorder?.isShowingReview(of: id) == true
    }

    /// The recorder `launchID` is starting: the review it was presented for, if any.
    func pendingReview(for launchID: UUID) -> (id: UUID, note: String?)? {
        guard let pending, pending.launchID == launchID else { return nil }
        return (pending.id, pending.note)
    }

    /// The recorder appeared. Takes the review it was presented for.
    func recorderAppeared(_ recorder: RecorderModel) {
        visibleRecorder = recorder
        if let pending, pending.launchID == recorder.launch.id {
            self.pending = nil
            if !recorder.isShowingReview(of: pending.id) {
                _ = recorder.showReview(pending.id, note: pending.note)
            }
        }
        trace("recorder opened: \(recorder.traceDescription)")
    }

    /// The recorder went away (Done, Delete, ✕, swipe). Nothing it was meant to show waits on,
    /// except hand-offs that arrived while it was leaving or busy: the next is offered now.
    func recorderDisappeared(_ recorder: RecorderModel) {
        if visibleRecorder === recorder { visibleRecorder = nil }
        if pending?.launchID == recorder.launch.id { pending = nil }
        showing = nil
        trace("recorder closed")
        guard !queued.isEmpty else { return }
        Task { @MainActor in
            // Let the cover finish leaving before the next one is presented.
            try? await Task.sleep(nanoseconds: 150_000_000)
            self.offerNextQueued()
        }
    }

    /// Offers queued hand-offs in order until one brings a recorder up (the rest wait for it to
    /// go), skipping any that were reviewed meanwhile.
    private func offerNextQueued() {
        let environment = AppEnvironment.shared
        while visibleRecorder == nil, environment.router.recorder == nil, !queued.isEmpty {
            let next = queued.removeFirst()
            offer(next.id, note: next.note, source: next.source, presentIfClosed: next.presentIfClosed,
                  library: environment.library, router: environment.router)
        }
    }

    /// A recording's save or review is on screen in the recorder.
    func reviewStarted(_ id: UUID) {
        showing = id
        if pending?.id == id { pending = nil }
    }

    /// The review of `id` is on screen: it is never offered again, and its notifications go.
    /// Runs once per recording (the recorder may report the same review twice as it appears).
    func reviewShown(_ id: UUID, library: Library) {
        reviewStarted(id)
        guard library.video(id)?.reviewedAt == nil else { return }
        trace("review shown \(Self.short(id))")
        ReviewTiming.mark(id, "review shown")
        ReviewTiming.finish(id, kind: library.video(id)?.kind)
        library.update(id) { $0.reviewedAt = Date() }
        Self.removeDeliveredNotifications(for: id)
    }

    /// Done, Delete or closing while saving: nothing is left on its way.
    func reviewEnded(_ id: UUID?) {
        if let id, pending?.id == id { pending = nil }
        showing = nil
    }

    /// "Screen recording finished" from the extension, and "… recording saved" from the app.
    static func removeDeliveredNotifications(for id: UUID) {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [PendingImports.broadcastNotificationPrefix + id.uuidString])
        let key = id.uuidString
        let reminder = NotificationKind.needsTitle.rawValue
        Task { @MainActor in
            let delivered = await center.deliveredNotifications()
            let matching = delivered
                .filter { ($0.request.content.userInfo["videoID"] as? String) == key
                    && ($0.request.content.userInfo["kind"] as? String) != reminder }
                .map(\.request.identifier)
            guard !matching.isEmpty else { return }
            center.removeDeliveredNotifications(withIdentifiers: matching)
        }
    }

    func trace(_ line: String) {
        log.debug("\(line, privacy: .public)")
        #if DEBUG
        DebugTrace.log(line)
        #endif
    }

    static func short(_ id: UUID) -> String { String(id.uuidString.prefix(4)) }
}

/// How long it took from stopping a recording to its review, step by step, for the last few
/// recordings. Logged, and listed in the Contact support email (Settings › Help) so a phone's
/// real timings can be sent without a Mac.
@MainActor
enum ReviewTiming {
    private static var marks: [UUID: [(String, Date)]] = [:]
    private static let key = "review.timings"
    private static let log = Logger(subsystem: "co.arclayer.snapreel", category: "review")

    /// The first mark of a recording is the stop; later ones are its steps.
    static func mark(_ id: UUID, _ step: String, at date: Date = Date()) {
        if step == "stop" { marks[id] = [] }
        marks[id, default: []].append((step, date))
    }

    /// Review is up: "Camera 0.42 s: file closed 0.18, moved 0.01, read 0.05, review shown 0.18".
    static func finish(_ id: UUID, kind: RecordingKind?) {
        guard let steps = marks.removeValue(forKey: id), let first = steps.first, first.0 == "stop",
              steps.count > 1, let last = steps.last else { return }
        var parts: [String] = []
        var previous = first.1
        for (step, date) in steps.dropFirst() {
            parts.append("\(step) \(seconds(date.timeIntervalSince(previous)))")
            previous = date
        }
        let label = kind.map { $0.label } ?? "Recording"
        let line = "\(label) \(seconds(last.1.timeIntervalSince(first.1))) s: \(parts.joined(separator: ", "))"
        record(line)
    }

    /// Work done after review was up (screen sound mixing, thumbnail).
    static func after(_ id: UUID, _ step: String, seconds value: TimeInterval) {
        record("after review \(ReviewCoordinator.short(id)): \(step) \(seconds(value)) s")
    }

    /// The last six lines, newest first.
    static var recent: [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }

    private static func record(_ line: String) {
        log.info("\(line, privacy: .public)")
        #if DEBUG
        DebugTrace.log("timing: \(line)")
        #endif
        // The time of day first, so the support email's lines are told apart.
        let lines = ["\(clock.string(from: Date())) \(line)"] + recent
        UserDefaults.standard.set(Array(lines.prefix(6)), forKey: key)
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static func seconds(_ value: TimeInterval) -> String {
        String(format: "%.2f", max(0, value))
    }
}

private extension RecordingKind {
    /// The recorder mode a review of this kind opens in (an import keeps the last mode).
    var recordMode: RecordMode? {
        switch self {
        case .camera: return .camera
        case .screen: return .screen
        case .audio: return .audio
        case .imported: return nil
        }
    }
}

/// Session B owns this file. Called by the shell each time the app becomes active, and by the
/// recorder when a screen recording finishes.
@MainActor
enum PendingImports {
    /// Must match `SampleHandler.notificationPrefix` in the broadcast extension.
    static let broadcastNotificationPrefix = "broadcast-"

    /// Moves finished screen recordings from the App Group inbox into the library (a move, no
    /// copy), then offers the newest for review (`ReviewCoordinator`): in the recorder if it is
    /// on screen, or by opening it if it finished in the last quarter of an hour (the person is
    /// coming back to finish it). `source` says which hand-off called it.
    static func importFinishedBroadcasts(into library: Library, source: ReviewCoordinator.Source = .appActive) {
        salvageAbandonedBroadcast()

        let fm = FileManager.default
        let inbox = AppGroup.inboxURL
        let manifests = ((try? fm.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
        var imported: [InboxRecording] = []
        var arrived: [(item: InboxRecording, manifest: URL?)] = []

        for manifestURL in manifests {
            guard let data = try? Data(contentsOf: manifestURL),
                  let item = try? JSONDecoder.snapreel.decode(InboxRecording.self, from: data) else {
                try? fm.removeItem(at: manifestURL)
                continue
            }
            arrived.append((item, manifestURL))
        }
        // A phone with no space left can keep the movie but not write its manifest.
        arrived += moviesWithoutManifest(in: inbox, known: Set(arrived.map(\.item.movieFileName))).map { ($0, nil) }

        for (item, manifestURL) in arrived {
            let movie = inbox.appendingPathComponent(item.movieFileName)
            func forgetManifest() { if let manifestURL { try? fm.removeItem(at: manifestURL) } }
            if library.video(item.id) != nil {
                forgetManifest()
                continue
            }
            let ext = movie.pathExtension.isEmpty ? "mov" : movie.pathExtension.lowercased()
            let fileName = "\(item.id.uuidString).\(ext)"
            let staged = library.media.staging.appendingPathComponent(fileName)
            if fm.fileExists(atPath: movie.path) {
                try? fm.removeItem(at: staged)
                do {
                    try fm.moveItem(at: movie, to: staged)
                } catch {
                    continue
                }
            } else if !fm.fileExists(atPath: staged.path) {
                // Neither here nor moved by an import that was cut short.
                forgetManifest()
                continue
            }
            ReviewTiming.mark(item.id, "stop", at: item.finishedAt)
            ReviewTiming.mark(item.id, "imported")
            RecordingSaver.shared.begin(RecordingSaveRequest(id: item.id, kind: .screen,
                                                             createdAt: item.createdAt, fileName: fileName),
                                        library: library)
            // Only once the library has it: closed before this, the next launch finds both again.
            forgetManifest()
            // Its "Screen recording finished" notification stays until review is shown
            // (`ReviewCoordinator.reviewShown`): if this hand-off is skipped, it's the way back.
            imported.append(item)
        }

        guard let newest = imported.max(by: { $0.finishedAt < $1.finishedAt }) else {
            return ReviewCoordinator.shared.trace("hand-off \(source.rawValue): nothing new in the inbox")
        }
        let router = AppEnvironment.shared.router
        let finishedRecently = Date().timeIntervalSince(newest.finishedAt) < 15 * 60
        let canPresent = !router.isSettingsPresented && (router.player.map { $0.isMinimized } ?? true)
        ReviewCoordinator.shared.offer(newest.id, note: newest.endedEarly ? newest.note : nil, source: source,
                                       presentIfClosed: finishedRecently && canPresent,
                                       library: library, router: router)
    }

    /// For a tap on the extension's "Your screen recording is ready" notification
    /// (`userInfo["broadcastID"]`). Imports it if needed and opens its review.
    static func openReviewFromNotification(broadcastID: UUID, library: Library) {
        importFinishedBroadcasts(into: library, source: .notificationTap)
        guard let video = library.video(broadcastID) else { return }
        let router = AppEnvironment.shared.router
        if video.reviewedAt != nil {
            // Already reviewed (often just now, by coming back to Snapreel): play it instead.
            ReviewCoordinator.shared.trace("hand-off notification tap \(ReviewCoordinator.short(broadcastID)): "
                                           + "already reviewed, \(router.recorder == nil ? "playing it" : "nothing to do")")
            if router.recorder == nil { router.open(videoID: broadcastID) }
            return
        }
        let covered = router.isSettingsPresented || router.player.map { !$0.isMinimized } == true
        if router.recorder == nil {
            router.closePlayer()
            router.isSettingsPresented = false
        }
        guard covered && router.recorder == nil else {
            return ReviewCoordinator.shared.offer(broadcastID, note: nil, source: .notificationTap,
                                                  presentIfClosed: true, library: library, router: router)
        }
        // Settings or the full player is closing: present the recorder once it has gone, not in
        // the same moment (iOS can drop a presentation made during a dismissal).
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            ReviewCoordinator.shared.offer(broadcastID, note: nil, source: .notificationTap,
                                           presentIfClosed: true, library: library, router: router)
        }
    }

    /// Resumes or marks failed any save that was interrupted when the app was closed, and
    /// recovers camera or audio recordings left in staging by a crash.
    static func resumeInterruptedSaves(in library: Library) {
        let saver = RecordingSaver.shared
        for video in library.videos where !saver.isProcessing(video.id) {
            if case .saving = video.state {
                saver.resume(video.id, library: library)
            } else if video.state.isReady, video.isFinishing == true {
                saver.resumeFinishing(video.id, library: library)
            }
        }
        saver.recoverLeftovers(library: library)
    }

    // MARK: - Private

    /// Movies the extension delivered whose manifest is missing for half a minute.
    static func moviesWithoutManifest(in inbox: URL, known: Set<String>, now: Date = Date()) -> [InboxRecording] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .creationDateKey]
        return ((try? fm.contentsOfDirectory(at: inbox, includingPropertiesForKeys: keys)) ?? []).compactMap { movie in
            guard ["mov", "mp4"].contains(movie.pathExtension.lowercased()),
                  !known.contains(movie.lastPathComponent),
                  let id = UUID(uuidString: movie.deletingPathExtension().lastPathComponent),
                  MediaInspector.fileSize(movie) > 100_000,
                  let values = try? movie.resourceValues(forKeys: Set(keys)),
                  let finished = values.contentModificationDate, now.timeIntervalSince(finished) > 30 else { return nil }
            return InboxRecording(id: id, movieFileName: movie.lastPathComponent,
                                  createdAt: values.creationDate ?? finished, finishedAt: finished,
                                  microphoneEnabled: false)
        }
    }

    /// True while anything records or mirrors the screen (a live broadcast included).
    private static var isScreenCaptured: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen }
            .contains { $0.isCaptured }
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
