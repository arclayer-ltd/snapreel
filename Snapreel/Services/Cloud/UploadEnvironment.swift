import BackgroundTasks
import Foundation
import UIKit

/// What preparing a job needs.
struct PrepareRequest {
    var videoID: UUID
    var folder: URL
    var maxLongSide: Int
    var title: String
    /// Already made (an earlier run).
    var hasPoster: Bool
    var hasPreview: Bool
}

/// What preparing has made so far.
enum PrepareUpdate {
    struct Video {
        /// Changes when the web copy had to be started over.
        var copyID: String
        /// 0…1.
        var fraction: Double
        /// Bytes that won't change any more (counting from the start of the file).
        var finalBytes: Int64
        /// The start of the file up to here is written last.
        var headerEnd: Int64
        /// What the web copy should come to.
        var estimatedBytes: Int64
    }

    /// The poster or preview (0 bytes: it couldn't be made).
    case file(UploadJob.Part.Kind, size: Int64)
    case video(Video)
    case videoDone(copyID: String, size: Int64, headerEnd: Int64)
}

/// Everything the uploader reaches outside itself, so the tests can put a stub server in its place.
@MainActor
struct UploadEnvironment {
    var root: URL
    var transfers: () -> UploadTransfers
    var isConfigured: () -> Bool
    var isSignedIn: () -> Bool
    /// A token good for at least this many seconds.
    var token: (TimeInterval) async throws -> String
    /// Gets a new token whatever is left of the old one.
    var refreshToken: () async throws -> Void
    /// A request answered while Snapreel waits (not a file transfer).
    var send: (URLRequest) async throws -> (Data, HTTPURLResponse)
    var signer: () -> S3Signer?
    var storageURL: () -> URL?
    /// `PATCH status: ready` with the video's size.
    var finish: (_ serverID: String, _ size: Int64) async throws -> VideoDetail
    var report: (_ serverID: String, _ sent: Int64, _ total: Int64) async -> Void
    var prepare: (PrepareRequest, @escaping @MainActor (PrepareUpdate) -> Void) async throws -> Void
    /// Draws a poster or preview when the server insists on one that couldn't be made.
    var makeStandIn: (UploadJob.Part.Kind, URL, String) -> Void
    var finished: (UUID, VideoDetail) -> Void
    var failed: (UUID, String) -> Void
    var freeDisk: () -> Int64
    var now: () -> Date
    var sleep: (Double) async -> Void

    static var live: UploadEnvironment {
        // Made on first use: the background session must exist once per process.
        var background: BackgroundTransfers?
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.waitsForConnectivity = false
        configuration.httpCookieStorage = nil
        let foreground = URLSession(configuration: configuration)
        return UploadEnvironment(
            root: defaultRoot,
            transfers: {
                if let background { return background }
                let made = BackgroundTransfers()
                background = made
                return made
            },
            isConfigured: { CloudConfig.isConfigured },
            isSignedIn: { AuthService.shared.isSignedIn },
            token: { try await AuthService.shared.validAccessToken(for: $0) },
            refreshToken: { _ = try await AuthService.shared.refresh() },
            send: { request in
                do {
                    let (data, response) = try await foreground.data(for: request)
                    guard let http = response as? HTTPURLResponse else { throw CloudError.unreadable }
                    return (data, http)
                } catch {
                    throw CloudError.from(network: error)
                }
            },
            signer: { S3Signer.project },
            storageURL: { CloudConfig.storageURL },
            finish: { try await APIClient.shared.finishUpload($0, size: $1) },
            report: { await APIClient.shared.reportUpload($0, sent: $1, total: $2) },
            prepare: { request, update in try await Self.prepare(request, update) },
            makeStandIn: { kind, file, title in WebExport.writeStandIn(kind, to: file, title: title) },
            finished: { ShareLinks.shared.uploadFinished($0, detail: $1) },
            failed: { ShareLinks.shared.uploadFailed($0, message: $1) },
            freeDisk: { DiskSpace.available },
            now: { Date() },
            sleep: { try? await Task.sleep(nanoseconds: UInt64(max(0, $0) * 1_000_000_000)) }
        )
    }

    /// Waits for the recording to be finished, then makes its three files.
    private static func prepare(_ request: PrepareRequest, _ update: @escaping @MainActor (PrepareUpdate) -> Void) async throws {
        let library = AppEnvironment.shared.library
        // The screen recording's sound mix finishes first, so the link has all its sound.
        await RecordingSaver.shared.waitUntilFinished(request.videoID)
        guard let video = library.video(request.videoID) else { throw WebExport.Failure.gone }
        let job = WebPreparer.Job(source: library.fileURL(for: video), folder: request.folder,
                                  maxLongSide: request.maxLongSide, isScreen: video.kind == .screen,
                                  isAudio: video.isAudioOnly, title: request.title, duration: video.duration,
                                  hasPoster: request.hasPoster, hasPreview: request.hasPreview)
        try await WebPreparer(job: job, update: update).run()
    }

    static var defaultRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent("Uploads", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                     attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        }
        return folder
    }
}

/// iOS wakes Snapreel now and then (usually while charging) to finish uploads that still need it: preparing that was
/// cut short, or the last calls.
enum UploadBackground {
    static let identifier = "co.arclayer.snapreel.uploads.finish"

    /// Must run before the app finishes launching.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let task = task as? BGProcessingTask else { return task.setTaskCompleted(success: false) }
            let work = Task { @MainActor in
                let uploader = Uploader.shared
                uploader.setUp()
                uploader.resumeAll()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await uploader.settle(seconds: 600)
                if uploader.jobs.values.contains(where: \.isActive) { schedule() }
                if !Task.isCancelled { task.setTaskCompleted(success: true) }
            }
            task.expirationHandler = {
                work.cancel()
                // What is encoded so far is kept; the next task or launch carries on.
                Task { @MainActor in Uploader.shared.pausePreparing() }
                task.setTaskCompleted(success: false)
            }
        }
    }

    static func schedule() {
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 5 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
