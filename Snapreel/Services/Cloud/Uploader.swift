import Foundation
import Network
import UIKit

/// One recording's upload to its share link, kept on disk so it survives a relaunch.
struct UploadJob: Codable, Hashable {
    enum Stage: String, Codable {
        /// Making the web copy, poster and preview.
        case preparing
        /// Sending the files with TUS.
        case uploading
        /// All files are up; telling the server (`status: ready`).
        case finishing
        case done
        case failed
    }

    /// One of the three files.
    struct Part: Codable, Hashable {
        enum Kind: String, Codable {
            case poster
            case preview
            case video
        }

        var kind: Kind
        /// Inside the job's folder.
        var fileName: String
        /// The object name inside the bucket (`{userId}/{videoId}/video.mp4`).
        var objectName: String
        var contentType: String
        var size: Int64
        /// The TUS upload's address once created.
        var location: String?
        /// Bytes the server has confirmed.
        var offset: Int64 = 0

        var isComplete: Bool { size > 0 && offset >= size }
    }

    var videoID: UUID
    var serverID: String
    var bucket: String
    var videoPath: String
    var posterPath: String
    var previewPath: String
    var maxLongSide: Int
    var title: String
    var stage: Stage
    var parts: [Part] = []
    var failure: String?
    var createdAt: Date
    var updatedAt: Date

    var totalBytes: Int64 { parts.reduce(0) { $0 + $1.size } }
    var confirmedBytes: Int64 { parts.reduce(0) { $0 + min($1.offset, $1.size) } }
}

/// Where an upload is, for the share-link sheet, cards and the uploads list.
enum UploadPhase: Equatable {
    case preparing
    case uploading(Double)
    /// Offline: the upload carries on by itself when the connection comes back.
    case waitingForNetwork(Double)
    case finishing
    case done
    case failed(String)

    var fraction: Double? {
        switch self {
        case .uploading(let value), .waitingForNetwork(let value): return value
        case .finishing, .done: return 1
        case .preparing, .failed: return nil
        }
    }
}

/// Sends share-link uploads: makes the web copy (`WebExport`), then sends each file to
/// Supabase Storage with TUS 1.0.0 in chunks of exactly 6 MB, through a background
/// URLSession so the upload carries on when Snapreel is in the background or closed by iOS.
/// Each chunk is written to its own file (background sessions only upload from files). Jobs
/// live in Application Support/Uploads and resume after a relaunch or a lost connection; the
/// server's offset (`HEAD`) decides where to carry on. When all three files are up it sends
/// `PATCH status: ready`.
@MainActor
final class Uploader: ObservableObject {
    static let shared = Uploader()

    @Published private(set) var jobs: [UUID: UploadJob] = [:]
    /// Bytes sent so far including the chunk in flight, for smooth progress.
    @Published private(set) var liveBytes: [UUID: Int64] = [:]
    @Published private(set) var isOnline = true

    #if DEBUG
    /// Fixture screens: phases to show instead of real jobs.
    @Published var debugPhases: [UUID: UploadPhase] = [:]
    #endif

    private lazy var backgroundSession: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: CloudConfig.uploadSessionID)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.allowsCellularAccess = true
        configuration.timeoutIntervalForRequest = 120
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }()
    private let foreground: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration)
    }()
    private let delegate = UploadSessionDelegate()
    private let monitor = NWPathMonitor()
    private var started = false
    /// Jobs with a step or a chunk in flight, so they aren't started twice.
    private var busy: Set<UUID> = []
    private var retries: [UUID: Int] = [:]
    private var lastProgressPublish: [UUID: Date] = [:]
    private var backgroundCompletion: (() -> Void)?

    /// Jobs are read at once, so the first screens already know which links are uploading.
    private init() {
        jobs = Self.loadJobs()
    }

    // MARK: - Lifecycle

    /// Called at launch (also when iOS relaunches Snapreel for upload events): reconnects to the
    /// background session and loads the jobs from disk.
    func setUp() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            Task { @MainActor in Uploader.shared.networkChanged(online: online) }
        }
        monitor.start(queue: DispatchQueue(label: "co.arclayer.snapreel.network"))
        _ = backgroundSession
        resumeAll()
    }

    /// iOS woke Snapreel for the background session; `completion` runs once its events are delivered.
    func handleBackgroundEvents(identifier: String, completion: @escaping () -> Void) {
        guard identifier == CloudConfig.uploadSessionID else { return completion() }
        backgroundCompletion = completion
        setUp()
    }

    fileprivate func backgroundEventsFinished() {
        let completion = backgroundCompletion
        backgroundCompletion = nil
        completion?()
    }

    private func networkChanged(online: Bool) {
        let cameBack = online && !isOnline
        isOnline = online
        if cameBack { resumeAll() }
    }

    /// Carries on every unfinished job that has nothing in flight.
    func resumeAll() {
        guard CloudConfig.isConfigured, AuthService.shared.isSignedIn else { return }
        backgroundSession.getAllTasks { tasks in
            let running = Set(tasks.compactMap { $0.state == .running || $0.state == .suspended
                ? ChunkTag(description: $0.taskDescription)?.videoID : nil })
            Task { @MainActor in
                let uploader = Uploader.shared
                for (id, job) in uploader.jobs where job.stage != .done && job.stage != .failed {
                    if running.contains(id) {
                        uploader.busy.insert(id)
                    } else if !uploader.busy.contains(id) {
                        uploader.advance(id, syncOffset: true)
                    }
                }
            }
        }
    }

    // MARK: - Starting and stopping

    /// Starts the upload for a link that was just created.
    func start(video: Video, source: URL, link: CreateVideoResponse) {
        let now = Date()
        let job = UploadJob(videoID: video.id, serverID: link.id, bucket: link.upload.bucket,
                            videoPath: link.upload.videoPath, posterPath: link.upload.posterPath,
                            previewPath: link.upload.previewPath, maxLongSide: link.limits.maxLongSide,
                            title: video.title, stage: .preparing, createdAt: now, updatedAt: now)
        cancelTasks(for: video.id)
        try? FileManager.default.removeItem(at: Self.folder(for: video.id))
        save(job)
        busy.remove(video.id)
        retries[video.id] = 0
        prepare(job, source: source)
    }

    /// Tries a failed upload again, from wherever the server got to.
    func retry(_ videoID: UUID, library: Library) {
        guard var job = jobs[videoID] else {
            // No job on this iPhone (an older link, or the job was cleared): start over.
            ShareLinks.shared.reupload(videoID)
            return
        }
        job.failure = nil
        retries[videoID] = 0
        if job.parts.isEmpty || job.parts.contains(where: { !FileManager.default.fileExists(atPath: Self.fileURL(job, $0).path) }) {
            guard let video = library.video(videoID) else {
                fail(videoID, "This recording isn't on this iPhone any more.")
                return
            }
            job.stage = .preparing
            job.parts = []
            save(job)
            prepare(job, source: library.fileURL(for: video))
        } else {
            job.stage = .uploading
            save(job)
            advance(videoID, syncOffset: true)
        }
    }

    /// Stops an upload and forgets it (after Stop sharing, or signing out).
    func cancel(_ videoID: UUID) {
        cancelTasks(for: videoID)
        busy.remove(videoID)
        jobs[videoID] = nil
        liveBytes[videoID] = nil
        try? FileManager.default.removeItem(at: Self.folder(for: videoID))
    }

    func cancelAll() {
        for id in Array(jobs.keys) { cancel(id) }
    }

    /// Clears a finished or failed job from the uploads list.
    func dismiss(_ videoID: UUID) {
        guard let job = jobs[videoID], job.stage == .done || job.stage == .failed else { return }
        cancel(videoID)
    }

    // MARK: - Progress

    func phase(for videoID: UUID) -> UploadPhase? {
        #if DEBUG
        if let phase = debugPhases[videoID] { return phase }
        #endif
        guard let job = jobs[videoID] else { return nil }
        switch job.stage {
        case .preparing: return .preparing
        case .finishing: return .finishing
        case .done: return .done
        case .failed: return .failed(job.failure ?? "The upload stopped.")
        case .uploading:
            let total = max(1, job.totalBytes)
            let sent = max(job.confirmedBytes, liveBytes[videoID] ?? 0)
            let fraction = min(0.99, Double(sent) / Double(total))
            return isOnline ? .uploading(fraction) : .waitingForNetwork(fraction)
        }
    }

    /// Jobs newest first, for the uploads list.
    var sortedJobs: [UploadJob] {
        jobs.values.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Preparing

    private func prepare(_ job: UploadJob, source: URL) {
        let id = job.videoID
        busy.insert(id)
        let folder = Self.folder(for: id)
        let isAudio = (AppEnvironment.shared.library.video(id)?.isAudioOnly) ?? false
        let duration = AppEnvironment.shared.library.video(id)?.duration ?? 0
        let title = job.title
        let maxLongSide = job.maxLongSide
        Task { @MainActor in
            do {
                // The screen recording's sound mix finishes first, so the link has all its sound.
                await RecordingSaver.shared.waitUntilFinished(id)
                let videoURL = folder.appendingPathComponent("video.mp4")
                let posterURL = folder.appendingPathComponent("poster.jpg")
                let previewURL = folder.appendingPathComponent("preview.mp4")
                try await WebExport.exportVideo(from: source, to: videoURL, maxLongSide: maxLongSide)
                let card = try await WebExport.writePoster(from: source, isAudio: isAudio, title: title,
                                                           duration: duration, to: posterURL)
                try await WebExport.writePreview(from: source, isAudio: isAudio, card: card, to: previewURL)
                let videoSize = MediaInspector.fileSize(videoURL)
                guard videoSize <= CloudConfig.maxFileBytes else { throw WebExport.Failure.tooLarge }
                guard var current = self.jobs[id] else { return }
                current.parts = [
                    UploadJob.Part(kind: .poster, fileName: "poster.jpg", objectName: current.posterPath,
                                   contentType: "image/jpeg", size: MediaInspector.fileSize(posterURL)),
                    UploadJob.Part(kind: .preview, fileName: "preview.mp4", objectName: current.previewPath,
                                   contentType: "video/mp4", size: MediaInspector.fileSize(previewURL)),
                    UploadJob.Part(kind: .video, fileName: "video.mp4", objectName: current.videoPath,
                                   contentType: "video/mp4", size: videoSize),
                ]
                current.stage = .uploading
                self.save(current)
                self.busy.remove(id)
                self.advance(id, syncOffset: false)
            } catch {
                self.busy.remove(id)
                self.fail(id, (error as? LocalizedError)?.errorDescription ?? "Snapreel couldn't prepare the video.")
            }
        }
    }

    // MARK: - Sending

    /// Moves a job on by one step: create the next file's TUS upload, or send its next chunk,
    /// or finish.
    private func advance(_ id: UUID, syncOffset: Bool) {
        guard let job = jobs[id], !busy.contains(id) else { return }
        switch job.stage {
        case .preparing:
            // Interrupted while preparing (the app was closed): prepare again.
            if let video = AppEnvironment.shared.library.video(id) {
                prepare(job, source: AppEnvironment.shared.library.fileURL(for: video))
            } else {
                fail(id, "This recording isn't on this iPhone any more.")
            }
        case .uploading:
            guard let index = job.parts.firstIndex(where: { !$0.isComplete }) else {
                finish(id)
                return
            }
            busy.insert(id)
            Task { @MainActor in
                do {
                    try await self.sendNext(id, partIndex: index, syncOffset: syncOffset)
                } catch {
                    self.busy.remove(id)
                    self.handle(error, for: id)
                }
            }
        case .finishing:
            finish(id)
        case .done, .failed:
            break
        }
    }

    private func sendNext(_ id: UUID, partIndex: Int, syncOffset: Bool) async throws {
        guard var job = jobs[id] else { return }
        var part = job.parts[partIndex]
        let token = try await AuthService.shared.validAccessToken()
        if part.location == nil {
            part.location = try await createUpload(part, bucket: job.bucket, token: token).absoluteString
            part.offset = 0
        } else if syncOffset, let location = part.location.flatMap(URL.init(string:)) {
            if let offset = try await serverOffset(location, token: token) {
                part.offset = offset
            } else {
                // The server forgot this upload (they last 24 hours): start the file again.
                part.location = try await createUpload(part, bucket: job.bucket, token: token).absoluteString
                part.offset = 0
            }
        }
        job.parts[partIndex] = part
        save(job)
        if part.isComplete {
            busy.remove(id)
            advance(id, syncOffset: false)
            return
        }
        guard let location = part.location.flatMap(URL.init(string:)) else { throw CloudError.unreadable }
        let chunk = try writeChunk(job, part)
        var request = URLRequest(url: location)
        request.httpMethod = "PATCH"
        request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
        request.setValue(String(part.offset), forHTTPHeaderField: "Upload-Offset")
        request.setValue("application/offset+octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(CloudConfig.publishableKey, forHTTPHeaderField: "apikey")
        let task = backgroundSession.uploadTask(with: request, fromFile: chunk)
        task.taskDescription = ChunkTag(videoID: id, part: part.kind, offset: part.offset).description
        task.resume()
    }

    /// TUS creation: `POST` with the file's length and metadata; the answer's `Location` is
    /// where its chunks go.
    private func createUpload(_ part: UploadJob.Part, bucket: String, token: String) async throws -> URL {
        guard let endpoint = CloudConfig.tusURL else { throw CloudError.notConfigured }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
        request.setValue(String(part.size), forHTTPHeaderField: "Upload-Length")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(CloudConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("true", forHTTPHeaderField: "x-upsert")
        let metadata = [("bucketName", bucket), ("objectName", part.objectName),
                        ("contentType", part.contentType), ("cacheControl", "3600")]
            .map { "\($0.0) \(Data($0.1.utf8).base64EncodedString())" }
            .joined(separator: ",")
        request.setValue(metadata, forHTTPHeaderField: "Upload-Metadata")
        let (_, response) = try await data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CloudError.unreadable }
        guard http.statusCode == 201 || http.statusCode == 200,
              let location = http.value(forHTTPHeaderField: "Location"),
              let url = URL(string: location, relativeTo: endpoint)?.absoluteURL else {
            throw Self.error(for: http.statusCode)
        }
        return url
    }

    /// `HEAD`: how much of the file the server has, or nil when it no longer knows the upload.
    private func serverOffset(_ location: URL, token: String) async throws -> Int64? {
        var request = URLRequest(url: location)
        request.httpMethod = "HEAD"
        request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(CloudConfig.publishableKey, forHTTPHeaderField: "apikey")
        let (_, response) = try await data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CloudError.unreadable }
        if http.statusCode == 404 || http.statusCode == 410 || http.statusCode == 403 { return nil }
        guard (200..<300).contains(http.statusCode),
              let value = http.value(forHTTPHeaderField: "Upload-Offset"), let offset = Int64(value) else {
            throw Self.error(for: http.statusCode)
        }
        return offset
    }

    private func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await foreground.data(for: request)
        } catch {
            throw CloudError.from(network: error)
        }
    }

    /// The next 6 MB (or the rest) of the file, as its own file for the background session.
    private func writeChunk(_ job: UploadJob, _ part: UploadJob.Part) throws -> URL {
        let source = Self.fileURL(job, part)
        let chunkURL = Self.folder(for: job.videoID).appendingPathComponent("chunk-\(part.kind.rawValue)-\(part.offset).bin")
        try? FileManager.default.removeItem(at: chunkURL)
        let handle = try FileHandle(forReadingFrom: source)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(part.offset))
        let length = Int(min(Int64(CloudConfig.chunkSize), part.size - part.offset))
        let data = try handle.read(upToCount: length) ?? Data()
        guard data.count == length else { throw WebExport.Failure.cannotRead }
        try data.write(to: chunkURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return chunkURL
    }

    // MARK: - Chunk results (from the session delegate)

    fileprivate func chunkProgress(_ tag: ChunkTag, sent: Int64) {
        guard let job = jobs[tag.videoID] else { return }
        let before = job.parts.filter { $0.kind != tag.part }.reduce(Int64(0)) { $0 + min($1.offset, $1.size) }
        let now = Date()
        if let last = lastProgressPublish[tag.videoID], now.timeIntervalSince(last) < 0.25 { return }
        lastProgressPublish[tag.videoID] = now
        liveBytes[tag.videoID] = before + tag.offset + sent
    }

    fileprivate func chunkFinished(_ tag: ChunkTag, status: Int?, offsetHeader: String?, error: Error?) {
        let id = tag.videoID
        busy.remove(id)
        let chunkURL = Self.folder(for: id).appendingPathComponent("chunk-\(tag.part.rawValue)-\(tag.offset).bin")
        try? FileManager.default.removeItem(at: chunkURL)
        guard var job = jobs[id], let index = job.parts.firstIndex(where: { $0.kind == tag.part }) else { return }
        if let error {
            if (error as NSError).code == NSURLErrorCancelled { return }
            handle(CloudError.from(network: error), for: id)
            return
        }
        switch status ?? 0 {
        case 200..<300:
            let confirmed = offsetHeader.flatMap(Int64.init) ?? (tag.offset + Int64(CloudConfig.chunkSize))
            job.parts[index].offset = min(job.parts[index].size, confirmed)
            job.updatedAt = Date()
            save(job)
            retries[id] = 0
            if tag.part == .video {
                let sent = job.parts[index].offset
                let serverID = job.serverID
                Task { _ = try? await APIClient.shared.updateVideo(serverID, UpdateVideoRequest(uploadedBytes: sent)) }
            }
            advance(id, syncOffset: false)
        case 401, 403:
            // The token ran out while the chunk was queued: refresh and try the chunk again.
            Task { @MainActor in
                _ = try? await AuthService.shared.refresh()
                self.retryLater(id, syncOffset: true)
            }
        case 404, 409, 410:
            // Offset mismatch or a forgotten upload: ask the server where it is.
            retryLater(id, syncOffset: true)
        case 413:
            fail(id, "This video is larger than a link can hold.")
        default:
            handle(Self.error(for: status ?? 0), for: id)
        }
    }

    // MARK: - Finishing and failing

    private func finish(_ id: UUID) {
        guard var job = jobs[id] else { return }
        job.stage = .finishing
        save(job)
        busy.insert(id)
        Task { @MainActor in
            do {
                let detail = try await APIClient.shared.updateVideo(job.serverID, UpdateVideoRequest(status: .ready))
                self.busy.remove(id)
                guard var done = self.jobs[id] else { return }
                done.stage = .done
                done.updatedAt = Date()
                self.save(done)
                self.liveBytes[id] = nil
                self.removeFiles(for: id)
                ShareLinks.shared.uploadFinished(id, detail: detail)
            } catch {
                self.busy.remove(id)
                self.handle(error, for: id)
            }
        }
    }

    private func handle(_ error: Error, for id: UUID) {
        let cloud = (error as? CloudError) ?? CloudError.from(network: error)
        switch cloud {
        case .offline:
            // The background session waits for the network by itself; the path monitor
            // resumes anything else when the connection is back.
            retryLater(id, syncOffset: true, delay: isOnline ? 10 : 30)
        case .signedOut, .notConfigured:
            break
        case .limit(let reason):
            fail(id, CloudError.limit(reason).message)
        case .notFound:
            fail(id, "This link was deleted, so the upload stopped.")
        case .server(let status, _) where status >= 500 || status == 0:
            let count = (retries[id] ?? 0) + 1
            retries[id] = count
            if count > 6 {
                fail(id, "snapreel.video isn't accepting the upload right now.")
            } else {
                retryLater(id, syncOffset: true, delay: min(120, pow(2, Double(count)) * 5))
            }
        default:
            fail(id, cloud.message)
        }
    }

    private func retryLater(_ id: UUID, syncOffset: Bool, delay: Double = 3) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            self.advance(id, syncOffset: syncOffset)
        }
    }

    private func fail(_ id: UUID, _ message: String) {
        guard var job = jobs[id] else { return }
        job.stage = .failed
        job.failure = message
        job.updatedAt = Date()
        save(job)
        liveBytes[id] = nil
        ShareLinks.shared.uploadFailed(id, message: message)
    }

    private static func error(for status: Int) -> CloudError {
        switch status {
        case 401: return .signedOut
        case 402: return .limit(.proFeature)
        case 404, 410: return .notFound
        default: return .server(status: status, message: nil)
        }
    }

    private func cancelTasks(for id: UUID) {
        backgroundSession.getAllTasks { tasks in
            for task in tasks where ChunkTag(description: task.taskDescription)?.videoID == id {
                task.cancel()
            }
        }
    }

    // MARK: - Files

    private static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent("Uploads", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                     attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        }
        return folder
    }

    private static func folder(for id: UUID) -> URL {
        let folder = root.appendingPathComponent(id.uuidString, isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                     attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        }
        return folder
    }

    private static func fileURL(_ job: UploadJob, _ part: UploadJob.Part) -> URL {
        folder(for: job.videoID).appendingPathComponent(part.fileName)
    }

    private func save(_ job: UploadJob) {
        jobs[job.videoID] = job
        guard let data = try? JSONEncoder.snapreel.encode(job) else { return }
        try? data.write(to: Self.folder(for: job.videoID).appendingPathComponent("job.json"),
                        options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Keeps the job file (so the list can say "Uploaded") but frees the exported copies.
    private func removeFiles(for id: UUID) {
        let folder = Self.folder(for: id)
        for item in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        where item.lastPathComponent != "job.json" {
            try? FileManager.default.removeItem(at: item)
        }
    }

    private static func loadJobs() -> [UUID: UploadJob] {
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

/// "videoID|part|offset" on each chunk task, to find its job when it finishes.
struct ChunkTag {
    var videoID: UUID
    var part: UploadJob.Part.Kind
    var offset: Int64

    init(videoID: UUID, part: UploadJob.Part.Kind, offset: Int64) {
        self.videoID = videoID
        self.part = part
        self.offset = offset
    }

    init?(description: String?) {
        let pieces = description?.split(separator: "|") ?? []
        guard pieces.count == 3, let id = UUID(uuidString: String(pieces[0])),
              let part = UploadJob.Part.Kind(rawValue: String(pieces[1])), let offset = Int64(pieces[2]) else { return nil }
        self.init(videoID: id, part: part, offset: offset)
    }

    var description: String { "\(videoID.uuidString)|\(part.rawValue)|\(offset)" }
}

/// The background session's delegate. Its callbacks arrive on the session's queue and hop to
/// the main actor.
final class UploadSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard let tag = ChunkTag(description: task.taskDescription) else { return }
        Task { @MainActor in Uploader.shared.chunkProgress(tag, sent: totalBytesSent) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let tag = ChunkTag(description: task.taskDescription) else { return }
        let response = task.response as? HTTPURLResponse
        let status = response?.statusCode
        let offset = response?.value(forHTTPHeaderField: "Upload-Offset")
        Task { @MainActor in
            Uploader.shared.chunkFinished(tag, status: status, offsetHeader: offset, error: error)
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in Uploader.shared.backgroundEventsFinished() }
    }
}
