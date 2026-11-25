import Foundation

/// "v2|videoID|part|number|lane" on each transfer, to find its job when it finishes (also after a relaunch). Build 47's
/// tags had another shape ("videoID|part|offset"); they don't parse here, so its leftover tasks are cancelled.
struct TransferTag: Hashable {
    var videoID: UUID
    var part: UploadJob.Part.Kind
    /// A piece's number; 0 for a whole file; a TUS chunk's offset.
    var number: Int64
    /// Which upload it belongs to, so a piece of an upload that was started over isn't counted for the new one.
    var lane: String

    init(videoID: UUID, part: UploadJob.Part.Kind, number: Int64, lane: String) {
        self.videoID = videoID
        self.part = part
        self.number = number
        self.lane = lane
    }

    init?(_ text: String?) {
        let fields = text?.split(separator: "|") ?? []
        guard fields.count == 5, fields[0] == "v2", let id = UUID(uuidString: String(fields[1])),
              let part = UploadJob.Part.Kind(rawValue: String(fields[2])), let number = Int64(fields[3]) else { return nil }
        self.init(videoID: id, part: part, number: number, lane: String(fields[4]))
    }

    var text: String { "v2|\(videoID.uuidString)|\(part.rawValue)|\(number)|\(lane)" }
    /// The file holding the bytes this transfer sends.
    var fileName: String { "piece-\(part.rawValue)-\(number).bin" }
}

/// How one transfer ended.
struct TransferResult {
    var status = 0
    var headers: [String: String] = [:]
    var body = Data()
    var error: Error?
    /// iOS or the app stopped it: nothing is wrong with the upload.
    var wasCancelled = false

    /// A header, whatever its case.
    func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

/// Sends files. The real one is a background URLSession; the tests use a stub server.
@MainActor
protocol UploadTransfers: AnyObject {
    var onProgress: ((TransferTag, Int64) -> Void)? { get set }
    var onFinish: ((TransferTag, TransferResult) -> Void)? { get set }
    func start(_ request: URLRequest, file: URL, tag: TransferTag)
    /// Transfers still under way (kept by iOS while Snapreel was closed). Cancels any it can't recognise.
    func running() async -> [TransferTag]
    func cancel(_ videoID: UUID)
    /// Cancels the ones `keep` refuses.
    func cancel(where matches: @escaping (TransferTag) -> Bool)
}

/// The background URLSession: iOS's own process sends the files, so they keep going while Snapreel is in the
/// background, suspended or closed by iOS, or the phone is locked. Background sessions only upload from files.
@MainActor
final class BackgroundTransfers: UploadTransfers {
    var onProgress: ((TransferTag, Int64) -> Void)?
    var onFinish: ((TransferTag, TransferResult) -> Void)?
    /// All events iOS was holding have been delivered.
    var onEventsDelivered: (() -> Void)?

    private let delegate = TransferDelegate()
    private let session: URLSession

    init(identifier: String = CloudConfig.uploadSessionID) {
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.sessionSendsLaunchEvents = true
        // "Now, please" for transfers started while Snapreel is open (iOS decides for the others).
        configuration.isDiscretionary = false
        configuration.allowsCellularAccess = true
        configuration.allowsExpensiveNetworkAccess = true
        configuration.allowsConstrainedNetworkAccess = true
        configuration.waitsForConnectivity = true
        configuration.shouldUseExtendedBackgroundIdleMode = true
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 6 * 3_600
        // One connection already fills a 4G uplink; more only lose more when it drops.
        configuration.httpMaximumConnectionsPerHost = 3
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        delegate.owner = self
    }

    func start(_ request: URLRequest, file: URL, tag: TransferTag) {
        let task = session.uploadTask(with: request, fromFile: file)
        task.taskDescription = tag.text
        task.countOfBytesClientExpectsToSend = MediaInspector.fileSize(file)
        task.countOfBytesClientExpectsToReceive = 2_048
        // Earlier pieces first; the small files before the video.
        task.priority = tag.part == .video ? URLSessionTask.defaultPriority : URLSessionTask.highPriority
        task.resume()
    }

    func running() async -> [TransferTag] {
        let tasks = await session.allTasks
        var tags: [TransferTag] = []
        for task in tasks where task.state == .running || task.state == .suspended {
            if let tag = TransferTag(task.taskDescription) { tags.append(tag) } else { task.cancel() }
        }
        return tags
    }

    func cancel(_ videoID: UUID) {
        cancel { $0.videoID == videoID }
    }

    func cancel(where matches: @escaping (TransferTag) -> Bool) {
        session.getAllTasks { tasks in
            for task in tasks {
                if let tag = TransferTag(task.taskDescription), matches(tag) { task.cancel() }
            }
        }
    }

    fileprivate func finished(_ tag: TransferTag, _ result: TransferResult) { onFinish?(tag, result) }
    fileprivate func progressed(_ tag: TransferTag, _ sent: Int64) { onProgress?(tag, sent) }
    fileprivate func eventsDelivered() { onEventsDelivered?() }
}

/// The session's delegate. Its callbacks arrive on the session's own serial queue and hop to the main actor.
private final class TransferDelegate: NSObject, URLSessionDataDelegate {
    weak var owner: BackgroundTransfers?
    /// Answers as they arrive, by task (only touched on the session's queue).
    private var bodies: [Int: Data] = [:]
    private var lastProgress: [Int: Date] = [:]

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard let tag = TransferTag(task.taskDescription) else { return }
        // At most five updates a second for each transfer.
        let now = Date()
        if let last = lastProgress[task.taskIdentifier], now.timeIntervalSince(last) < 0.2 { return }
        lastProgress[task.taskIdentifier] = now
        Task { @MainActor [weak owner] in owner?.progressed(tag, totalBytesSent) }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        var body = bodies[dataTask.taskIdentifier] ?? Data()
        if body.count < 16_384 { body.append(data.prefix(16_384)) }
        bodies[dataTask.taskIdentifier] = body
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let body = bodies.removeValue(forKey: task.taskIdentifier) ?? Data()
        lastProgress[task.taskIdentifier] = nil
        guard let tag = TransferTag(task.taskDescription) else { return }
        let response = task.response as? HTTPURLResponse
        var result = TransferResult()
        result.status = response?.statusCode ?? 0
        for (key, value) in response?.allHeaderFields ?? [:] {
            if let key = key as? String, let value = value as? String { result.headers[key] = value }
        }
        result.body = body
        result.error = error
        result.wasCancelled = (error as NSError?)?.code == NSURLErrorCancelled
        Task { @MainActor [weak owner] in owner?.finished(tag, result) }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor [weak owner] in owner?.eventsDelivered() }
    }
}
