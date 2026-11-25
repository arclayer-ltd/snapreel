import CryptoKit
import Foundation
import Network
import UIKit

/// Sends share-link uploads.
///
/// - `WebPreparer` writes the web copy, poster and preview. Everything that is final is sent while the rest is still
///   being made.
/// - Small files go up in one request. The video goes up as S3 multipart pieces of 5 MB, signed with the person's own
///   session token: pieces can go in any order, several at once, and sending one twice is harmless, so a lost answer
///   costs nothing. While Snapreel is open three are under way; when it leaves the screen the remaining pieces are
///   handed to iOS's background session, which keeps sending them while Snapreel is suspended or closed or the phone
///   is locked. iOS sends all it has at the same time, and a dropped connection loses whatever was under way, so it
///   gets about two minutes' worth at once and the rest with times to begin. (TUS, the old way, needs the app woken for every next chunk; it stays as the fallback for
///   when the S3 endpoint refuses its key.)
/// - Every answer goes through `UploadAnswer`; every way to try again has a pause and a cap, and ends in progress or
///   in a failed state with Try again. What is on the server stays there for Try again.
///
/// Jobs live in Application Support/Uploads and carry on after a relaunch, a lost connection or an expired token.
@MainActor
final class Uploader: ObservableObject {
    static let shared = Uploader(environment: .live)

    @Published private(set) var jobs: [UUID: UploadJob] = [:]
    /// Bytes sent by transfers under way, by recording.
    @Published private(set) var liveBytes: [UUID: Int64] = [:]
    @Published private(set) var isOnline = true
    /// Recordings whose web copy waits for Snapreel to be open again.
    @Published private(set) var pausedPreparing: Set<UUID> = []

    #if DEBUG
    /// Fixture screens: phases and numbers to show instead of real ones.
    @Published var debugPhases: [UUID: UploadPhase] = [:]
    @Published var debugProgress: [UUID: UploadProgress] = [:]
    #endif

    private let environment: UploadEnvironment
    private var transfers: UploadTransfers { environment.transfers() }
    private var monitor: NWPathMonitor?
    private var started = false

    /// Transfers under way and what each has sent.
    private var inFlight: [TransferTag: Int64] = [:]
    private var startedAt: [TransferTag: Date] = [:]
    /// Jobs with a request of their own under way (creating, completing, finishing).
    private var control: Set<UUID> = []
    private var isFilling = false
    private var fillsAgain = false
    /// Hand everything to the background session instead of three pieces at a time.
    private var queuesEverything = false
    private var isActive = true
    /// TUS uploads whose offset is known to match the server's.
    private var tusSynced: Set<UUID> = []
    private var trouble: [UUID: Trouble] = [:]
    private var preparingID: UUID?
    private var preparation: Task<Void, Never>?
    private var lastPreparation: Task<Void, Never>?
    /// The token each transfer carries (not known for those found after a relaunch), and the last one refreshed to.
    private var carried: [TransferTag: String] = [:]
    private var refreshedToken: String?
    private var isRefreshing = false
    /// Server time minus this phone's.
    private var clockOffset: TimeInterval = 0
    private var speeds: [UUID: [(time: Date, bytes: Int64)]] = [:]
    private var lastPublish: [UUID: Date] = [:]
    private var lastReport: [UUID: Date] = [:]
    /// The last speed measured, bytes a second.
    private var lastRate: Double?
    private var backgroundCompletion: (() -> Void)?
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid

    /// Counts of what went wrong since the last progress.
    private struct Trouble {
        var temporary = 0
        var network = 0
        var token = 0
        var denied = 0
        /// Preparing that was cut short without Snapreel leaving the screen.
        var interruptions = 0
        var until: Date?

        mutating func madeProgress() {
            temporary = 0
            network = 0
            token = 0
            denied = 0
            until = nil
        }
    }

    private enum Limits {
        static let openTransfers = 3
        static let temporary = 10
        static let network = 30
        static let token = 4
        static let denied = 2
        /// Times a file may start over.
        static let restarts = 4
        /// Handed to iOS when Snapreel leaves the screen: what goes at the same time (two minutes' worth, between these),
        /// and the most in all (what can begin while the token is still good).
        static let batchSeconds = 120.0
        static let leastBatch: Int64 = 30 * 1_024 * 1_024
        static let mostBatch: Int64 = 150 * 1_024 * 1_024
        static let queuedSeconds = 2_400.0
        /// Assumed while nothing has been measured (slow 4G).
        static let usualRate = 300_000.0
        /// Pieces written ahead while Snapreel is open.
        static let stock = 24
        /// Never filled by piece files.
        static let freeDisk: Int64 = 300_000_000
    }

    /// Jobs are read at once, so the first screens already know which links are uploading.
    init(environment: UploadEnvironment) {
        self.environment = environment
        jobs = Self.loadJobs(in: environment.root)
        for id in jobs.keys {
            guard var job = jobs[id] else { continue }
            let folder = folder(for: id)
            if job.upgrade(fileSize: { FileFacts.size(folder.appendingPathComponent($0.fileName)) }) { save(job) }
        }
    }

    // MARK: - Lifecycle

    /// Called at launch (also when iOS relaunches Snapreel for upload events): reconnects to the background session
    /// and carries on.
    func setUp(watchesNetwork: Bool = true) {
        guard !started else { return }
        started = true
        AppActivity.startObserving()
        transfers.onProgress = { [weak self] tag, sent in self?.transferProgress(tag, sent: sent) }
        transfers.onFinish = { [weak self] tag, result in self?.transferFinished(tag, result) }
        (transfers as? BackgroundTransfers)?.onEventsDelivered = { [weak self] in self?.backgroundEventsDelivered() }
        if watchesNetwork {
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { [weak self] path in
                let online = path.status == .satisfied
                Task { @MainActor in self?.networkChanged(online: online) }
            }
            monitor.start(queue: DispatchQueue(label: "co.arclayer.snapreel.network"))
            self.monitor = monitor
            let center = NotificationCenter.default
            center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.willLeave() }
            }
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.didEnterBackground() }
            }
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.didBecomeActive() }
            }
        }
        resumeAll()
    }

    /// About to leave the screen: hand iOS everything that is ready, while transfers still count as started by an
    /// open app (the ones started later are sent when iOS finds it convenient).
    func willLeave() {
        isActive = false
        queuesEverything = true
        pumpAll()
    }

    private func didEnterBackground() {
        guard jobs.values.contains(where: \.isActive) else { return }
        UploadBackground.schedule()
        beginBackgroundTask()
    }

    func didBecomeActive() {
        isActive = true
        queuesEverything = false
        endBackgroundTask()
        pausedPreparing = []
        // Pieces waiting for their time go again now, three at a time.
        transfers.cancelWaiting()
        pumpAll()
    }

    /// iOS gives about half a minute for the work under way: the web copy's current stretch, writing the pieces,
    /// and the calls that finish an upload.
    private func beginBackgroundTask() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Share link upload") { [weak self] in
            MainActor.assumeIsolated {
                self?.pausePreparing()
                self?.endBackgroundTask()
            }
        }
        Task { @MainActor [weak self] in
            while let self, self.backgroundTask != .invalid {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if !self.isBusy { self.endBackgroundTask() }
            }
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        let task = backgroundTask
        backgroundTask = .invalid
        UIApplication.shared.endBackgroundTask(task)
    }

    /// Work that needs Snapreel running (transfers don't: iOS runs those).
    var isBusy: Bool { preparation != nil || isFilling || !control.isEmpty }

    /// iOS woke Snapreel for the background session; `completion` runs once its events are dealt with.
    func handleBackgroundEvents(identifier: String, completion: @escaping () -> Void) {
        guard identifier == CloudConfig.uploadSessionID else { return completion() }
        backgroundCompletion = completion
        isActive = UIApplication.shared.applicationState == .active
        queuesEverything = !isActive
        setUp()
    }

    private func backgroundEventsDelivered() {
        Task { @MainActor in
            // The results just arrived may call for a request that completes the upload.
            await self.settle(seconds: 20)
            let completion = self.backgroundCompletion
            self.backgroundCompletion = nil
            completion?()
        }
    }

    /// Waits until nothing needs Snapreel running, at most `seconds`.
    func settle(seconds: Double) async {
        let deadline = Date().addingTimeInterval(seconds)
        repeat { try? await Task.sleep(nanoseconds: 200_000_000) } while isBusy && Date() < deadline && !Task.isCancelled
    }

    func networkChanged(online: Bool) {
        let cameBack = online && !isOnline
        isOnline = online
        if cameBack {
            for id in trouble.keys {
                trouble[id]?.network = 0
                trouble[id]?.until = nil
            }
            pumpAll()
        }
    }

    /// Carries on every unfinished job, after asking iOS which transfers it still has.
    func resumeAll() {
        guard environment.isConfigured() else { return }
        Task { @MainActor in
            let running = await self.transfers.running()
            for tag in running where self.inFlight[tag] == nil {
                if let job = self.jobs[tag.videoID], job.isActive, self.isCurrent(tag, in: job) {
                    self.inFlight[tag] = 0
                } else {
                    self.transfers.cancel { $0 == tag }
                }
            }
            // Anything iOS lost track of goes again.
            let alive = Set(running), now = self.environment.now()
            for tag in Array(self.inFlight.keys) where !alive.contains(tag) {
                if let began = self.startedAt[tag], now.timeIntervalSince(began) < 60 { continue }
                self.inFlight[tag] = nil
                self.startedAt[tag] = nil
            }
            self.pumpAll()
        }
    }

    // MARK: - Starting and stopping

    /// Starts the upload for a link that was just created. A job already under way for it carries on.
    func start(video: Video, source: URL, link: CreateVideoResponse) {
        if let job = jobs[video.id], job.isActive, job.serverID == link.id {
            pump(video.id)
            return
        }
        let now = environment.now()
        let job = UploadJob(videoID: video.id, serverID: link.id, bucket: link.upload.bucket,
                            videoPath: link.upload.videoPath, posterPath: link.upload.posterPath,
                            previewPath: link.upload.previewPath, maxLongSide: link.limits.maxLongSide,
                            title: video.title, stage: .preparing, createdAt: now, updatedAt: now,
                            version: UploadJob.currentVersion)
        forget(video.id)
        save(job)
        pump(video.id)
    }

    /// Tries a stopped upload again, from wherever the server got to.
    func retry(_ videoID: UUID, library: Library) {
        guard var job = jobs[videoID] else {
            // No job on this iPhone (an older link, or the job was cleared): start over.
            ShareLinks.shared.reupload(videoID)
            return
        }
        job.failure = nil
        job.restarts = 0
        trouble[videoID] = nil
        pausedPreparing.remove(videoID)
        let folder = folder(for: videoID)
        let hasFiles = job.parts.allSatisfy { part in
            part.isComplete || FileManager.default.fileExists(atPath: folder.appendingPathComponent(part.fileName).path)
        }
        if job.prepared == nil && job.index(of: .video) != nil && job.parts.allSatisfy({ $0.growing != true }) && hasFiles {
            job.stage = .uploading
        } else {
            if library.video(videoID) == nil {
                fail(videoID, "This recording isn't on this iPhone any more.")
                return
            }
            job.stage = .preparing
        }
        save(job)
        pump(videoID)
    }

    /// Stops an upload and forgets it (after Stop sharing, or signing out).
    func cancel(_ videoID: UUID) {
        forget(videoID)
        jobs[videoID] = nil
    }

    func cancelAll() {
        for id in Array(jobs.keys) { cancel(id) }
    }

    /// Someone else signed in: their uploads only.
    func cancelJobs(notOwnedBy userID: String) {
        for (id, job) in jobs where !job.videoPath.lowercased().hasPrefix(userID.lowercased() + "/") { cancel(id) }
    }

    /// Clears a finished or stopped job from the uploads list.
    func dismiss(_ videoID: UUID) {
        guard let job = jobs[videoID], job.stage == .done || job.stage == .failed else { return }
        cancel(videoID)
    }

    private func forget(_ videoID: UUID) {
        transfers.cancel(videoID)
        for tag in Array(inFlight.keys) where tag.videoID == videoID { inFlight[tag] = nil; startedAt[tag] = nil; carried[tag] = nil }
        if preparingID == videoID {
            preparation?.cancel()
            preparation = nil
            preparingID = nil
        }
        trouble[videoID] = nil
        liveBytes[videoID] = nil
        speeds[videoID] = nil
        tusSynced.remove(videoID)
        pausedPreparing.remove(videoID)
        try? FileManager.default.removeItem(at: folder(for: videoID))
    }

    // MARK: - Progress

    func phase(for videoID: UUID) -> UploadPhase? {
        #if DEBUG
        if let phase = debugPhases[videoID] { return phase }
        #endif
        guard let job = jobs[videoID] else { return nil }
        if job.isActive && !environment.isSignedIn() { return .failed("Sign in to finish this upload.") }
        let waits = !isOnline || (trouble[videoID]?.network ?? 0) > 2
        switch job.stage {
        case .preparing: return .preparing
        case .finishing: return waits ? .waitingForNetwork(0.99) : .finishing
        case .done: return .done
        case .failed: return .failed(job.failure ?? "The upload stopped.")
        case .uploading:
            let fraction = progress(for: videoID)?.fraction ?? 0
            return waits ? .waitingForNetwork(fraction) : .uploading(fraction)
        }
    }

    /// The numbers for the share-link sheet and the uploads list.
    func progress(for videoID: UUID) -> UploadProgress? {
        #if DEBUG
        if let progress = debugProgress[videoID] { return progress }
        #endif
        guard let job = jobs[videoID], job.isActive else { return nil }
        var progress = UploadProgress()
        progress.prepared = job.stage == .preparing ? job.prepared : nil
        progress.totalBytes = job.totalBytes
        progress.isEstimate = job.stage == .preparing
        progress.sentBytes = min(job.confirmedBytes + (liveBytes[videoID] ?? 0), max(job.totalBytes, 0))
        progress.isPaused = pausedPreparing.contains(videoID)
        if let samples = speeds[videoID], let first = samples.first, let last = samples.last,
           last.time.timeIntervalSince(first.time) >= 4, last.bytes > first.bytes,
           environment.now().timeIntervalSince(last.time) < 20 {
            progress.rate = Double(last.bytes - first.bytes) / last.time.timeIntervalSince(first.time)
        }
        return progress
    }

    /// Jobs newest first, for the uploads list.
    var sortedJobs: [UploadJob] {
        jobs.values.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Moving on

    private func pumpAll() {
        for id in jobs.values.filter(\.isActive).sorted(by: { $0.createdAt < $1.createdAt }).map(\.videoID) { pump(id) }
    }

    /// Takes the next step of one job. Safe to call at any time, as often as you like.
    private func pump(_ id: UUID) {
        guard started, let job = jobs[id], job.isActive, environment.isConfigured(), environment.isSignedIn() else { return }
        if job.stage == .preparing { startPreparing() }
        guard isOnline, !isRefreshing else { return }
        if let until = trouble[id]?.until, until > environment.now() { return }
        guard !control.contains(id) else { return }
        if job.stage == .finishing || (job.stage == .uploading && job.parts.allSatisfy(\.isComplete) && !job.parts.isEmpty) {
            finish(id)
            return
        }
        for part in job.parts where !part.isComplete {
            if step(id, part) { break }
        }
        fill()
    }

    /// Decides how a file is sent and makes the requests that aren't file transfers. Returns true when it started
    /// one (the job is pumped again after it) or stopped the job.
    private func step(_ id: UUID, _ original: UploadJob.Part) -> Bool {
        guard var job = jobs[id], let index = job.index(of: original.kind) else { return true }
        var part = job.parts[index]
        let isFinal = part.growing != true
        if isFinal && part.size <= 0 {
            // Nothing to send. A video must have something; a preview is optional.
            if part.kind == .video {
                fail(id, WebExport.Failure.cannotExport(nil).errorDescription ?? "")
            } else {
                part.skipped = true
                job.parts[index] = part
                save(job)
                pump(id)
            }
            return true
        }
        if part.size > CloudConfig.maxFileBytes {
            fail(id, WebExport.Failure.tooLarge.errorDescription ?? "")
            return true
        }
        if !isFinal {
            part.layOutPieces()
            if part.pieces?.isEmpty != false { return false }
        }
        if part.method == nil || (job.usesTUS == true && part.method == .multipart) {
            let large = !isFinal || part.size > CloudConfig.singleLimit
            part.method = large ? (job.usesTUS == true ? .tus : .multipart) : .single
            job.parts[index] = part
            save(job)
        }
        switch part.method {
        case .single?, nil:
            return false
        case .multipart?:
            part.layOutPieces()
            if job.parts[index] != part {
                job.parts[index] = part
                save(job)
            }
            let pieces = part.pieces ?? []
            if pieces.isEmpty { return false }
            if part.uploadID == nil {
                runControl(id) { try await self.createMultipart(id, part) }
                return true
            }
            if isFinal && pieces.allSatisfy(\.done) {
                runControl(id) { try await self.completeMultipart(id, part) }
                return true
            }
            return false
        case .tus?:
            guard isFinal else { return false }
            let busy = inFlight.keys.contains { $0.videoID == id && $0.part == part.kind }
            if busy { return false }
            runControl(id) { try await self.sendTUS(id, part) }
            return true
        }
    }

    /// Runs one request for a job at a time, then pumps it again.
    private func runControl(_ id: UUID, _ work: @escaping @MainActor () async throws -> Void) {
        guard !control.contains(id) else { return }
        control.insert(id)
        Task { @MainActor in
            var failed: Error?
            do { try await work() } catch { failed = error }
            self.control.remove(id)
            if let failed { self.handle(failed, for: id) }
            self.pump(id)
        }
    }

    // MARK: - Filling the session

    private struct Work {
        var id: UUID
        var part: UploadJob.Part
        var piece: UploadJob.Part.Piece?
        var tag: TransferTag
        var size: Int64
        var begins: Date?
    }

    /// Starts transfers until there are enough under way.
    private func fill() {
        guard !isFilling else {
            fillsAgain = true
            return
        }
        isFilling = true
        Task { @MainActor in
            repeat {
                self.fillsAgain = false
                while let work = self.nextWork() { await self.begin(work) }
                if !self.fillsAgain { await self.stockUp() }
            } while self.fillsAgain
            self.isFilling = false
        }
    }

    /// The next file or piece to start, oldest job first, small files before the video.
    private func nextWork() -> Work? {
        guard started, isOnline, !isRefreshing, environment.isSignedIn() else { return nil }
        let now = environment.now()
        let videoInFlight = inFlight.keys.filter { $0.part == .video }.count
        var videoAllowed = videoInFlight < Limits.openTransfers
        var begins: Date?
        if queuesEverything {
            let rate = max(Limits.usualRate / 3, lastRate ?? Limits.usualRate)
            let batch = max(Limits.leastBatch, min(Limits.mostBatch, Int64(rate * Limits.batchSeconds)))
            // Pieces already handed over, in batches; each batch begins when the ones before it should be through.
            let number = Int64(videoInFlight) * CloudConfig.pieceSize / batch
            let delay = Double(number) * Double(batch) / rate
            videoAllowed = delay < Limits.queuedSeconds && environment.freeDisk() > Limits.freeDisk
            if number > 0 { begins = now.addingTimeInterval(delay) }
        }
        // With the phone nearly full, still send, one piece at a time.
        if videoInFlight == 0 { videoAllowed = true }
        for job in jobs.values.filter(\.isActive).sorted(by: { $0.createdAt < $1.createdAt }) {
            if let until = trouble[job.videoID]?.until, until > now { continue }
            for part in job.parts where !part.isComplete {
                if part.kind == .video && !videoAllowed { continue }
                switch part.method {
                case .single?:
                    let tag = TransferTag(videoID: job.videoID, part: part.kind, number: 0, lane: "-")
                    if inFlight[tag] == nil { return Work(id: job.videoID, part: part, piece: nil, tag: tag, size: part.size) }
                case .multipart?:
                    guard let uploadID = part.uploadID else { continue }
                    for piece in part.pieces ?? [] where !piece.done {
                        let tag = TransferTag(videoID: job.videoID, part: part.kind, number: Int64(piece.number), lane: Self.lane(uploadID))
                        if inFlight[tag] == nil { return Work(id: job.videoID, part: part, piece: piece, tag: tag, size: piece.size, begins: begins) }
                    }
                case .tus?, nil:
                    continue
                }
            }
        }
        return nil
    }

    private func begin(_ work: Work) async {
        inFlight[work.tag] = 0
        startedAt[work.tag] = environment.now()
        do {
            // A token with most of its hour left, so pieces waiting their turn stay valid.
            let token = try await environment.token(2_700)
            let file = folder(for: work.id).appendingPathComponent(work.tag.fileName)
            let md5 = try await writePiece(work, to: file)
            guard inFlight[work.tag] != nil, var job = jobs[work.id], job.isActive, isCurrent(work.tag, in: job),
                  let index = job.index(of: work.part.kind) else {
                drop(work.tag)
                return
            }
            let request: URLRequest
            if let piece = work.piece, let uploadID = work.part.uploadID {
                if let slot = job.parts[index].pieces?.firstIndex(where: { $0.number == piece.number }) {
                    job.parts[index].pieces?[slot].md5 = md5
                    save(job)
                }
                request = try s3Request("PUT", job, work.part, ["partNumber": String(piece.number), "uploadId": uploadID], token: token)
            } else {
                request = try singleRequest(job, work.part, token: token)
            }
            carried[work.tag] = token
            transfers.start(request, file: file, tag: work.tag, begins: work.begins)
        } catch {
            drop(work.tag)
            handle(error, for: work.id)
        }
    }

    /// Writes the next pieces to their files ahead of time, so that when Snapreel leaves the screen they can be handed
    /// over in an instant, while they still count as started by an open app.
    private func stockUp() async {
        guard isActive, !queuesEverything else { return }
        var stocked = 0
        for job in jobs.values.filter(\.isActive).sorted(by: { $0.createdAt < $1.createdAt }) {
            guard let index = job.index(of: .video), job.parts[index].method == .multipart, let uploadID = job.parts[index].uploadID else { continue }
            let part = job.parts[index]
            for piece in part.pieces ?? [] where !piece.done {
                let tag = TransferTag(videoID: job.videoID, part: .video, number: Int64(piece.number), lane: Self.lane(uploadID))
                if inFlight[tag] != nil { continue }
                stocked += 1
                if stocked > Limits.stock || environment.freeDisk() < Limits.freeDisk * 2 || fillsAgain || queuesEverything { return }
                let file = folder(for: job.videoID).appendingPathComponent(tag.fileName)
                if piece.md5 != nil && FileFacts.size(file) == piece.size { continue }
                let work = Work(id: job.videoID, part: part, piece: piece, tag: tag, size: piece.size)
                guard let md5 = try? await writePiece(work, to: file) else { return }
                guard isCurrent(tag, in: jobs[job.videoID] ?? job) else { return }
                change(job.videoID, .video) { current in
                    guard let slot = current.pieces?.firstIndex(where: { $0.number == piece.number && $0.size == piece.size }) else { return }
                    current.pieces?[slot].md5 = md5
                }
            }
        }
    }

    /// The piece's own file, from the stock or written now.
    private func writePiece(_ work: Work, to file: URL) async throws -> String {
        if let md5 = work.piece?.md5, FileFacts.size(file) == work.size { return md5 }
        let source = folder(for: work.id).appendingPathComponent(work.part.fileName)
        return try await Self.copyRange(of: source, start: work.piece?.start ?? 0, size: work.size, to: file)
    }

    private func drop(_ tag: TransferTag) {
        inFlight[tag] = nil
        startedAt[tag] = nil
        carried[tag] = nil
        try? FileManager.default.removeItem(at: folder(for: tag.videoID).appendingPathComponent(tag.fileName))
        publishLive(tag.videoID, force: true)
    }

    /// Whether a transfer still belongs to its job (not to an upload that was started over).
    private func isCurrent(_ tag: TransferTag, in job: UploadJob) -> Bool {
        guard let index = job.index(of: tag.part) else { return false }
        let part = job.parts[index]
        guard !part.isComplete else { return false }
        switch part.method {
        case .single?: return tag.lane == "-"
        case .multipart?: return part.uploadID.map(Self.lane) == tag.lane
        case .tus?: return part.location.map(Self.lane) == tag.lane
        case nil: return false
        }
    }

    /// A short name for an upload id, in the transfer's tag.
    private static func lane(_ id: String) -> String {
        Insecure.MD5.hash(data: Data(id.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    /// Copies part of a file to its own file (background sessions only send whole files), off the main thread.
    /// Returns its MD5, which is what S3 answers.
    nonisolated private static func copyRange(of source: URL, start: Int64, size: Int64, to file: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let handle = try FileHandle(forReadingFrom: source)
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(start))
            let data = try handle.read(upToCount: Int(size)) ?? Data()
            guard Int64(data.count) == size, size > 0 else { throw WebExport.Failure.cannotRead }
            try? FileManager.default.removeItem(at: file)
            try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }.value
    }

    // MARK: - Requests

    private func s3Request(_ method: String, _ job: UploadJob, _ part: UploadJob.Part, _ query: [String: String],
                           token: String) throws -> URLRequest {
        guard let signer = environment.signer(),
              let url = signer.url(method, bucket: job.bucket, key: part.objectName, query: query, token: token,
                                   date: environment.now().addingTimeInterval(clockOffset)) else { throw CloudError.notConfigured }
        var request = URLRequest(url: url)
        request.httpMethod = method
        return request
    }

    private func storageRequest(_ method: String, _ path: String, token: String) throws -> URLRequest {
        guard let base = environment.storageURL() else { throw CloudError.notConfigured }
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(CloudConfig.publishableKey, forHTTPHeaderField: "apikey")
        return request
    }

    /// One request for a whole small file. It overwrites, so sending it again is harmless.
    private func singleRequest(_ job: UploadJob, _ part: UploadJob.Part, token: String) throws -> URLRequest {
        var request = try storageRequest("POST", "object/\(job.bucket)/\(part.objectName)", token: token)
        request.setValue("true", forHTTPHeaderField: "x-upsert")
        request.setValue(part.contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("max-age=3600", forHTTPHeaderField: "Cache-Control")
        return request
    }

    /// Sends a request and gives its answer a meaning. Keeps the server's clock.
    private func ask(_ request: URLRequest) async throws -> (answer: UploadAnswer, body: Data, headers: HTTPURLResponse) {
        let (body, response) = try await environment.send(request)
        noteClock(response.value(forHTTPHeaderField: "Date"))
        return (UploadAnswer.classify(status: response.statusCode, body: body), body, response)
    }

    /// A phone whose clock is wrong by minutes would sign requests the server refuses.
    private func noteClock(_ header: String?) {
        guard let header, let date = Self.httpDate.date(from: header) else { return }
        let offset = date.timeIntervalSince(environment.now())
        clockOffset = abs(offset) > 120 ? offset : 0
    }

    private static let httpDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()

    private struct Refused: Error { var answer: UploadAnswer }

    // MARK: - Multipart

    private func createMultipart(_ id: UUID, _ part: UploadJob.Part) async throws {
        guard let job = jobs[id] else { return }
        let token = try await environment.token(300)
        var request = try s3Request("POST", job, part, ["uploads": ""], token: token)
        request.setValue(part.contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("max-age=3600", forHTTPHeaderField: "Cache-Control")
        let (answer, body, _) = try await ask(request)
        guard answer == .ok else { throw Refused(answer: answer) }
        guard let uploadID = UploadAnswer.uploadID(in: body) else { throw Refused(answer: .temporary(200)) }
        change(id, part.kind) {
            $0.uploadID = uploadID
            $0.pieces = $0.pieces?.map { piece in
                var piece = piece
                piece.done = false
                return piece
            }
        }
    }

    /// All pieces are up: joins them into the file, then checks its size.
    private func completeMultipart(_ id: UUID, _ part: UploadJob.Part) async throws {
        guard let job = jobs[id], let uploadID = part.uploadID, let pieces = part.pieces else { return }
        let token = try await environment.token(300)
        let list = pieces.map { "<Part><PartNumber>\($0.number)</PartNumber><ETag>\"\($0.md5 ?? "")\"</ETag></Part>" }.joined()
        var request = try s3Request("POST", job, part, ["uploadId": uploadID], token: token)
        request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("<CompleteMultipartUpload>\(list)</CompleteMultipartUpload>".utf8)
        let (answer, _, _) = try await ask(request)
        switch answer {
        case .ok, .gone, .exists:
            // "Gone" after everything was sent usually means an earlier completion whose answer was lost.
            if try await storedSize(job, part, token: token) == part.size {
                change(id, part.kind) { $0.stored = true }
                progressed(id)
            } else {
                startOver(id, part.kind)
            }
        case .badPieces:
            startOver(id, part.kind)
        default:
            throw Refused(answer: answer)
        }
    }

    /// The size of the object on the server, or nil when there is none.
    private func storedSize(_ job: UploadJob, _ part: UploadJob.Part, token: String) async throws -> Int64? {
        let request = try storageRequest("GET", "object/info/authenticated/\(job.bucket)/\(part.objectName)", token: token)
        let (answer, body, _) = try await ask(request)
        switch answer {
        case .ok:
            let info = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
            return (info?["size"] as? NSNumber)?.int64Value
        case .gone:
            return nil
        default:
            throw Refused(answer: answer)
        }
    }

    /// Sends a file again from the start, a few times at most.
    private func startOver(_ id: UUID, _ kind: UploadJob.Part.Kind) {
        guard var job = jobs[id], let index = job.index(of: kind) else { return }
        let restarts = (job.restarts ?? 0) + 1
        job.restarts = restarts
        guard restarts <= Limits.restarts else {
            fail(id, "snapreel.video couldn't put the video together.")
            return
        }
        transfers.cancel { $0.videoID == id && $0.part == kind }
        for tag in Array(inFlight.keys) where tag.videoID == id && tag.part == kind { drop(tag) }
        tusSynced.remove(id)
        job.parts[index].startOver()
        save(job)
    }

    /// Piece files written from a web copy that was started over.
    private func removePieceFiles(_ id: UUID) {
        let folder = folder(for: id)
        for item in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        where item.lastPathComponent.hasPrefix("piece-video-") || item.lastPathComponent.hasPrefix("chunk-") {
            try? FileManager.default.removeItem(at: item)
        }
    }

    // MARK: - TUS (the fallback)

    /// One step of a TUS upload: create it, ask where it is, or start its next chunk.
    private func sendTUS(_ id: UUID, _ original: UploadJob.Part) async throws {
        guard let job = jobs[id] else { return }
        var part = original
        let token = try await environment.token(300)
        if part.location == nil {
            let location = try await createTUS(job, part, token: token)
            part.location = location
            part.offset = 0
            change(id, part.kind) { $0.location = location; $0.offset = 0 }
            tusSynced.insert(id)
        } else if !tusSynced.contains(id), let location = part.location.flatMap(URL.init(string:)) {
            var request = URLRequest(url: location)
            request.httpMethod = "HEAD"
            tusHeaders(&request, token: token)
            let (answer, _, response) = try await ask(request)
            switch answer {
            case .ok:
                guard let value = response.value(forHTTPHeaderField: "Upload-Offset"), let offset = Int64(value) else {
                    throw Refused(answer: .temporary(200))
                }
                part.offset = offset
                change(id, part.kind) { $0.offset = offset }
                tusSynced.insert(id)
            case .gone, .denied:
                // The server forgot it (they last 24 hours): send it again, in pieces unless S3 is off.
                startOver(id, part.kind)
                if job.usesTUS != true { change(id, part.kind) { $0.method = nil } }
                return
            default:
                throw Refused(answer: answer)
            }
        }
        if part.offset >= part.size {
            if try await storedSize(job, part, token: token) == part.size {
                change(id, part.kind) { $0.stored = true }
                progressed(id)
            } else {
                startOver(id, part.kind)
            }
            return
        }
        guard let location = part.location.flatMap(URL.init(string:)), let text = part.location else { return }
        let size = min(Int64(CloudConfig.chunkSize), part.size - part.offset)
        let tag = TransferTag(videoID: id, part: part.kind, number: part.offset, lane: Self.lane(text))
        guard inFlight[tag] == nil else { return }
        inFlight[tag] = 0
        startedAt[tag] = environment.now()
        do {
            let folder = folder(for: id)
            let file = folder.appendingPathComponent(tag.fileName)
            _ = try await Self.copyRange(of: folder.appendingPathComponent(part.fileName), start: part.offset, size: size, to: file)
            var request = URLRequest(url: location)
            request.httpMethod = "PATCH"
            tusHeaders(&request, token: token)
            // Storage checks this on every PATCH, not only when the upload is created. Without it a file that exists
            // already answers 409 for ever (build 47's loop).
            request.setValue("true", forHTTPHeaderField: "x-upsert")
            request.setValue(String(part.offset), forHTTPHeaderField: "Upload-Offset")
            request.setValue("application/offset+octet-stream", forHTTPHeaderField: "Content-Type")
            carried[tag] = token
            transfers.start(request, file: file, tag: tag, begins: nil)
        } catch {
            drop(tag)
            throw error
        }
    }

    private func createTUS(_ job: UploadJob, _ part: UploadJob.Part, token: String) async throws -> String {
        guard let endpoint = environment.storageURL()?.appendingPathComponent("upload/resumable") else { throw CloudError.notConfigured }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        tusHeaders(&request, token: token)
        request.setValue(String(part.size), forHTTPHeaderField: "Upload-Length")
        request.setValue("true", forHTTPHeaderField: "x-upsert")
        let metadata = [("bucketName", job.bucket), ("objectName", part.objectName),
                        ("contentType", part.contentType), ("cacheControl", "3600")]
            .map { "\($0.0) \(Data($0.1.utf8).base64EncodedString())" }
            .joined(separator: ",")
        request.setValue(metadata, forHTTPHeaderField: "Upload-Metadata")
        let (answer, _, response) = try await ask(request)
        guard answer == .ok else { throw Refused(answer: answer) }
        guard let location = response.value(forHTTPHeaderField: "Location"),
              let url = URL(string: location, relativeTo: endpoint)?.absoluteURL else { throw Refused(answer: .temporary(201)) }
        return url.absoluteString
    }

    private func tusHeaders(_ request: inout URLRequest, token: String) {
        request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(CloudConfig.publishableKey, forHTTPHeaderField: "apikey")
    }

    // MARK: - Transfer results

    private func transferProgress(_ tag: TransferTag, sent: Int64) {
        guard inFlight[tag] != nil else { return }
        inFlight[tag] = sent
        publishLive(tag.videoID, force: false)
    }

    private func publishLive(_ id: UUID, force: Bool) {
        let now = environment.now()
        if !force, let last = lastPublish[id], now.timeIntervalSince(last) < 0.3 { return }
        lastPublish[id] = now
        let live = inFlight.reduce(Int64(0)) { $0 + ($1.key.videoID == id ? $1.value : 0) }
        if liveBytes[id] != live { liveBytes[id] = live }
        guard let job = jobs[id], job.isActive else { return }
        // The speed over the last 20 seconds.
        var samples = speeds[id] ?? []
        samples.append((now, job.confirmedBytes + live))
        samples.removeAll { now.timeIntervalSince($0.time) > 20 }
        speeds[id] = samples
        if let first = samples.first, now.timeIntervalSince(first.time) >= 4, job.confirmedBytes + live > first.bytes {
            lastRate = Double(job.confirmedBytes + live - first.bytes) / now.timeIntervalSince(first.time)
        }
        report(id)
    }

    /// Tells the watch page how far the upload is: at most every 15 seconds, and only while Snapreel is open.
    private func report(_ id: UUID) {
        guard isActive, let job = jobs[id], job.stage != .finishing else { return }
        let now = environment.now()
        if let last = lastReport[id], now.timeIntervalSince(last) < 15 { return }
        lastReport[id] = now
        let sent = job.confirmedBytes + (liveBytes[id] ?? 0), total = job.totalBytes, serverID = job.serverID
        guard total > 0, sent > 0 else { return }
        let environment = environment
        Task { @MainActor in await environment.report(serverID, min(sent, total), total) }
    }

    private func transferFinished(_ tag: TransferTag, _ result: TransferResult) {
        let used = carried[tag]
        drop(tag)
        noteClock(result.header("Date"))
        guard var job = jobs[tag.videoID], job.isActive, isCurrent(tag, in: job), let index = job.index(of: tag.part) else { return }
        let id = tag.videoID
        if result.wasCancelled {
            pumpSoon(id)
            return
        }
        if let error = result.error, result.status == 0 {
            wait(id, for: CloudError.from(network: error) == .offline ? .network : .temporary(0))
            return
        }
        switch UploadAnswer.classify(status: result.status, body: result.body) {
        case .ok:
            switch job.parts[index].method {
            case .multipart?:
                guard let slot = job.parts[index].pieces?.firstIndex(where: { Int64($0.number) == tag.number }) else { break }
                let etag = result.header("Etag")?.replacingOccurrences(of: "\"", with: "").lowercased()
                if let etag, let md5 = job.parts[index].pieces?[slot].md5, etag != md5, !etag.contains("-") {
                    // Damaged on the way: send this piece again.
                    wait(id, for: .temporary(200))
                    return
                }
                if job.parts[index].pieces?[slot].md5 == nil { job.parts[index].pieces?[slot].md5 = etag }
                job.parts[index].pieces?[slot].done = true
            case .tus?:
                let confirmed = result.header("Upload-Offset").flatMap(Int64.init)
                    ?? tag.number + min(Int64(CloudConfig.chunkSize), job.parts[index].size - tag.number)
                job.parts[index].offset = min(job.parts[index].size, confirmed)
            case .single?, nil:
                job.parts[index].stored = true
            }
            job.updatedAt = environment.now()
            save(job)
            progressed(id)
            publishLive(id, force: true)
            pump(id)
        case .exists:
            // TUS without overwriting, or a race with another copy of this upload: look at what is there.
            runControl(id) { try await self.checkStored(id, tag.part) }
        case .tokenExpired:
            tusSynced.remove(id)
            refreshToken(for: id, used: used)
        case let answer:
            tusSynced.remove(id)
            handle(Refused(answer: answer), for: id, part: tag.part)
            pump(id)
        }
    }

    /// The server says the object exists: finished if its size is right, otherwise it is replaced.
    private func checkStored(_ id: UUID, _ kind: UploadJob.Part.Kind) async throws {
        guard let job = jobs[id], let index = job.index(of: kind) else { return }
        let part = job.parts[index]
        let token = try await environment.token(300)
        if try await storedSize(job, part, token: token) == part.size {
            change(id, kind) { $0.stored = true }
            progressed(id)
        } else {
            startOver(id, kind)
            if jobs[id]?.isActive == true { wait(id, for: .temporary(409)) }
        }
    }

    // MARK: - Trouble

    private enum Cause {
        case network
        case temporary(Int)
    }

    private func progressed(_ id: UUID) {
        trouble[id]?.madeProgress()
    }

    /// Waits longer each time, then tries again; after too many times without progress the upload stops with a
    /// clear message and Try again.
    private func wait(_ id: UUID, for cause: Cause) {
        guard jobs[id]?.isActive == true else { return }
        var counts = trouble[id] ?? Trouble()
        // Many pieces failing together are one event: the pause for it is already running.
        if let until = counts.until, until > environment.now() { return }
        let count: Int, delay: Double
        switch cause {
        case .network:
            tusSynced.remove(id)
            // Offline: the path monitor starts it again.
            guard isOnline else { return }
            counts.network += 1
            count = counts.network
            if count > Limits.network {
                fail(id, "Your connection keeps dropping. What was sent is kept: try again on a better connection.")
                return
            }
            delay = min(60, pow(2, Double(min(count, 6))))
        case .temporary:
            counts.temporary += 1
            count = counts.temporary
            if count > Limits.temporary {
                fail(id, "snapreel.video isn't accepting the upload right now. What was sent is kept.")
                return
            }
            delay = min(120, pow(2, Double(min(count, 7))))
        }
        let until = environment.now().addingTimeInterval(delay)
        counts.until = until
        trouble[id] = counts
        let environment = environment
        Task { @MainActor in
            await environment.sleep(delay + Double.random(in: 0...0.5))
            if let current = self.trouble[id]?.until, current <= until.addingTimeInterval(0.01) { self.trouble[id]?.until = nil }
            self.pump(id)
        }
    }

    private func pumpSoon(_ id: UUID) {
        let environment = environment
        Task { @MainActor in
            await environment.sleep(1)
            self.pump(id)
        }
    }

    /// The token ran out while something waited. Gets a new one, once however many transfers ran into it, drops the
    /// transfers that still carry an old one, and goes on.
    private func refreshToken(for id: UUID, used: String?) {
        if isRefreshing { return }
        if let used, let refreshedToken, used != refreshedToken {
            // It was already replaced while this transfer was under way.
            pump(id)
            return
        }
        var counts = trouble[id] ?? Trouble()
        counts.token += 1
        trouble[id] = counts
        guard counts.token <= Limits.token else {
            fail(id, "Your sign-in wasn't accepted. Sign out and in again, then try again.")
            return
        }
        isRefreshing = true
        Task { @MainActor in
            do {
                try await self.environment.refreshToken()
                let token = try await self.environment.token(60)
                self.refreshedToken = token
                let stale = Set(self.inFlight.keys.filter { self.carried[$0] != token })
                self.transfers.cancel { stale.contains($0) }
                for tag in stale { self.drop(tag) }
                self.isRefreshing = false
            } catch {
                self.isRefreshing = false
                self.handle(error, for: id)
            }
            self.pumpAll()
        }
    }

    private func handle(_ error: Error, for id: UUID, part: UploadJob.Part.Kind = .video) {
        guard jobs[id]?.isActive == true else { return }
        if let refused = error as? Refused {
            switch refused.answer {
            case .ok: break
            case .tokenExpired: refreshToken(for: id, used: nil)
            case .clockSkew:
                // `ask` keeps the server's clock from the next answer.
                wait(id, for: .temporary(403))
            case .denied:
                if isRefreshing { return }
                var counts = trouble[id] ?? Trouble()
                counts.denied += 1
                trouble[id] = counts
                if counts.denied > Limits.denied {
                    fail(id, "snapreel.video refused the upload. Sign out and in again, then try again.")
                } else {
                    refreshToken(for: id, used: nil)
                }
            case .keyRefused:
                guard var job = jobs[id] else { return }
                if job.usesTUS == true {
                    wait(id, for: .temporary(403))
                } else {
                    job.usesTUS = true
                    for index in job.parts.indices where job.parts[index].method == .multipart {
                        job.parts[index].startOver()
                        job.parts[index].method = job.parts[index].growing == true ? nil : .tus
                    }
                    save(job)
                }
            case .gone: startOver(id, part)
            case .badPieces: startOver(id, part)
            case .exists: runControl(id) { try await self.checkStored(id, part) }
            case .tooLarge: fail(id, WebExport.Failure.tooLarge.errorDescription ?? "")
            case .offsetConflict: wait(id, for: .temporary(409))
            case .busy: wait(id, for: .temporary(423))
            case .temporary(let status): wait(id, for: .temporary(status))
            case .refused(let status): fail(id, "snapreel.video refused the upload (\(status)).")
            }
            return
        }
        if error is CancellationError { return pumpSoon(id) }
        if let export = error as? WebExport.Failure {
            // A prepared file can't be read: make it again.
            if case .cannotRead = export, var job = jobs[id], (job.restarts ?? 0) < Limits.restarts {
                job.restarts = (job.restarts ?? 0) + 1
                job.parts.removeAll { !$0.isComplete }
                job.stage = .preparing
                save(job)
                pumpSoon(id)
                return
            }
            return fail(id, export.errorDescription ?? "Snapreel couldn't prepare the video.")
        }
        if (error as NSError).domain == NSCocoaErrorDomain || (error as NSError).domain == NSPOSIXErrorDomain {
            if DiskSpace.isOutOfSpace(error) { return fail(id, "Your iPhone is too full to send the video.") }
            return handle(WebExport.Failure.cannotRead, for: id)
        }
        switch (error as? CloudError) ?? CloudError.from(network: error) {
        case .offline: wait(id, for: .network)
        case .signedOut, .notConfigured: break
        case .limit(let reason): fail(id, CloudError.limit(reason).message)
        case .notFound: fail(id, "This link was deleted, so the upload stopped.")
        case .incomplete(let missing): sendMissing(id, missing)
        case .server(let status, _) where status >= 500 || status == 0 || status == 429: wait(id, for: .temporary(status))
        case let other: fail(id, other.message)
        }
    }

    private func fail(_ id: UUID, _ message: String) {
        guard var job = jobs[id], job.stage != .failed else { return }
        job.stage = .failed
        job.failure = message
        job.updatedAt = environment.now()
        save(job)
        transfers.cancel(id)
        for tag in Array(inFlight.keys) where tag.videoID == id { drop(tag) }
        if preparingID == id {
            preparation?.cancel()
            preparation = nil
            preparingID = nil
        }
        liveBytes[id] = nil
        speeds[id] = nil
        environment.failed(id, message)
        startPreparing()
    }

    // MARK: - Preparing

    /// Starts the next job's web copy, one at a time (an iPhone X has one encoder and 3 GB of memory).
    private func startPreparing() {
        guard preparation == nil, started else { return }
        guard let job = jobs.values.filter({ $0.stage == .preparing && !pausedPreparing.contains($0.videoID) })
            .min(by: { $0.createdAt < $1.createdAt }) else { return }
        let id = job.videoID
        let previous = lastPreparation
        preparingID = id
        let request = PrepareRequest(videoID: id, folder: folder(for: id), maxLongSide: job.maxLongSide, title: job.title,
                                     hasPoster: isReady(job, .poster), hasPreview: isReady(job, .preview))
        let environment = environment
        let task = Task { @MainActor in
            // One encoder: a web copy that was just stopped ends first.
            await previous?.value
            var failure: Error?
            do {
                try Task.checkCancellation()
                try await environment.prepare(request) { update in
                    guard self.preparingID == id else { return }
                    self.apply(update, to: id)
                }
            } catch {
                failure = error
            }
            guard self.preparingID == id else { return }
            self.preparation = nil
            self.preparingID = nil
            if let failure { self.preparingStopped(id, failure) } else { self.preparingFinished(id) }
            self.startPreparing()
            self.pump(id)
        }
        preparation = task
        lastPreparation = task
    }

    private func isReady(_ job: UploadJob, _ kind: UploadJob.Part.Kind) -> Bool {
        guard let index = job.index(of: kind) else { return false }
        let part = job.parts[index]
        return part.isComplete || (part.size > 0 && FileFacts.size(folder(for: job.videoID).appendingPathComponent(part.fileName)) == part.size)
    }

    private func apply(_ update: PrepareUpdate, to id: UUID) {
        guard var job = jobs[id], job.stage == .preparing else { return }
        var startsOver = false
        switch update {
        case .file(let kind, let size):
            set(&job, kind) {
                $0.size = size
                $0.skipped = size > 0 ? nil : true
            }
        case .video(let video):
            if video.finalBytes > 0 { trouble[id]?.interruptions = 0 }
            job.prepared = video.fraction
            job.estimatedBytes = video.estimatedBytes
            set(&job, .video) {
                if $0.copyID != video.copyID {
                    // A copy started over: nothing sent before belongs to it.
                    if $0.copyID != nil || $0.pieces != nil { startsOver = true }
                    $0.startOver()
                    $0.pieces = nil
                    $0.method = nil
                    $0.copyID = video.copyID
                }
                $0.growing = true
                $0.size = video.finalBytes
                $0.headerEnd = video.headerEnd
            }
        case .videoDone(let copyID, let size, let headerEnd):
            set(&job, .video) {
                if $0.copyID != copyID {
                    if $0.copyID != nil || $0.pieces != nil { startsOver = true }
                    $0.startOver()
                    $0.pieces = nil
                    $0.method = nil
                    $0.copyID = copyID
                }
                $0.growing = nil
                $0.size = size
                $0.headerEnd = headerEnd
            }
            job.prepared = 1
        }
        if startsOver {
            transfers.cancel { $0.videoID == id && $0.part == .video }
            for tag in Array(inFlight.keys) where tag.videoID == id && tag.part == .video { drop(tag) }
            removePieceFiles(id)
        }
        save(job)
        pump(id)
    }

    private func set(_ job: inout UploadJob, _ kind: UploadJob.Part.Kind, _ edit: (inout UploadJob.Part) -> Void) {
        if let index = job.index(of: kind) {
            edit(&job.parts[index])
        } else {
            var part: UploadJob.Part
            switch kind {
            case .poster: part = UploadJob.Part(kind: kind, fileName: "poster.jpg", objectName: job.posterPath, contentType: "image/jpeg", size: 0)
            case .preview: part = UploadJob.Part(kind: kind, fileName: "preview.mp4", objectName: job.previewPath, contentType: "video/mp4", size: 0)
            case .video: part = UploadJob.Part(kind: kind, fileName: "video.mp4", objectName: job.videoPath, contentType: "video/mp4", size: 0)
            }
            edit(&part)
            // Small files first.
            if kind == .video { job.parts.append(part) } else { job.parts.insert(part, at: kind == .poster ? 0 : min(1, job.parts.count)) }
        }
    }

    private func preparingFinished(_ id: UUID) {
        guard var job = jobs[id], job.stage == .preparing else { return }
        guard let index = job.index(of: .video), job.parts[index].growing != true, job.parts[index].size > 0 else {
            fail(id, WebExport.Failure.cannotExport(nil).errorDescription ?? "")
            return
        }
        guard job.parts[index].size <= CloudConfig.maxFileBytes else {
            fail(id, WebExport.Failure.tooLarge.errorDescription ?? "")
            return
        }
        job.stage = .uploading
        job.prepared = nil
        job.estimatedBytes = nil
        job.updatedAt = environment.now()
        save(job)
    }

    private func preparingStopped(_ id: UUID, _ error: Error) {
        if error is CancellationError || error is WebExport.Interrupted {
            // Snapreel left the screen: what is encoded is kept, and it goes on when Snapreel is open again.
            pausedPreparing.insert(id)
            if isActive { // Interrupted while open (a phone call): try again shortly.
                var counts = trouble[id] ?? Trouble()
                counts.interruptions += 1
                trouble[id] = counts
                guard counts.interruptions <= Limits.temporary else {
                    fail(id, WebExport.Failure.cannotExport(nil).errorDescription ?? "")
                    return
                }
                let environment = environment
                Task { @MainActor in
                    await environment.sleep(2)
                    self.pausedPreparing.remove(id)
                    self.pump(id)
                }
            }
            return
        }
        fail(id, (error as? LocalizedError)?.errorDescription ?? "Snapreel couldn't prepare the video.")
    }

    /// Tries web copies again that were cut short.
    func resumePaused() {
        pausedPreparing = []
        resumeAll()
    }

    /// Stops making the web copy for now; what is done is kept.
    func pausePreparing() {
        preparation?.cancel()
    }

    // MARK: - Finishing

    /// Everything is up: tells snapreel.video. Safe to repeat.
    private func finish(_ id: UUID) {
        guard var job = jobs[id] else { return }
        if job.stage != .finishing {
            job.stage = .finishing
            save(job)
        }
        let size = job.index(of: .video).map { job.parts[$0].size } ?? 0
        let serverID = job.serverID
        runControl(id) {
            let detail = try await self.environment.finish(serverID, size)
            guard var done = self.jobs[id] else { return }
            done.stage = .done
            done.failure = nil
            done.updatedAt = self.environment.now()
            self.save(done)
            self.trouble[id] = nil
            self.liveBytes[id] = nil
            self.speeds[id] = nil
            self.removeFiles(for: id)
            self.environment.finished(id, detail)
        }
    }

    /// The server lists files it doesn't have: those go again.
    private func sendMissing(_ id: UUID, _ missing: [String]) {
        guard var job = jobs[id] else { return }
        let restarts = (job.restarts ?? 0) + 1
        job.restarts = restarts
        guard restarts <= Limits.restarts else {
            fail(id, "snapreel.video still misses part of the upload.")
            return
        }
        job.stage = .uploading
        let folder = folder(for: id)
        var canGoOn = false
        for index in job.parts.indices where missing.contains(job.parts[index].fileName) {
            let file = folder.appendingPathComponent(job.parts[index].fileName)
            if job.parts[index].kind != .video, FileFacts.size(file) == 0 {
                // A server that insists on all three files: stand in for the one that couldn't be made.
                environment.makeStandIn(job.parts[index].kind, file, job.title)
            }
            let size = FileFacts.size(file)
            guard size > 0 else { continue }
            if job.parts[index].kind != .video { job.parts[index].size = size }
            job.parts[index].skipped = nil
            job.parts[index].startOver()
            canGoOn = true
        }
        save(job)
        if !canGoOn { fail(id, "snapreel.video still misses part of the upload.") }
    }

    // MARK: - Files

    private func folder(for id: UUID) -> URL {
        let folder = environment.root.appendingPathComponent(id.uuidString, isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                     attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        }
        return folder
    }

    private func change(_ id: UUID, _ kind: UploadJob.Part.Kind, _ edit: (inout UploadJob.Part) -> Void) {
        guard var job = jobs[id], let index = job.index(of: kind) else { return }
        edit(&job.parts[index])
        job.updatedAt = environment.now()
        save(job)
    }

    private func save(_ job: UploadJob) {
        if jobs[job.videoID] != job { jobs[job.videoID] = job }
        guard let data = try? JSONEncoder.snapreel.encode(job) else { return }
        try? data.write(to: folder(for: job.videoID).appendingPathComponent("job.json"),
                        options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Keeps the job file (so the list can say "Uploaded") but frees the web copy.
    private func removeFiles(for id: UUID) {
        let folder = folder(for: id)
        for item in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        where item.lastPathComponent != "job.json" {
            try? FileManager.default.removeItem(at: item)
        }
    }

    private static func loadJobs(in root: URL) -> [UUID: UploadJob] {
        var loaded: [UUID: UploadJob] = [:]
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for folder in folders {
            let file = folder.appendingPathComponent("job.json")
            guard let data = try? Data(contentsOf: file),
                  let job = try? JSONDecoder.snapreel.decode(UploadJob.self, from: data) else { continue }
            // Finished jobs are listed for a day, then forgotten.
            if job.stage == .done, job.updatedAt.timeIntervalSinceNow < -86_400 {
                try? FileManager.default.removeItem(at: folder)
                continue
            }
            loaded[job.videoID] = job
        }
        return loaded
    }
}
