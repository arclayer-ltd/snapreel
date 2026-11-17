import Foundation

/// What the broadcast extension reports to the app through the App Group container.
public struct BroadcastState: Codable, Equatable {
    public enum Status: String, Codable {
        case idle
        case recording
        case finishing
        case finished
        case failed
    }

    public var status: Status
    public var recordingID: UUID?
    public var startedAt: Date?
    public var updatedAt: Date
    public var microphoneEnabled: Bool
    /// Plain-language reason when `status == .failed` (for example "Your iPhone is out of space").
    public var errorMessage: String?

    public init(status: Status,
                recordingID: UUID? = nil,
                startedAt: Date? = nil,
                updatedAt: Date = Date(),
                microphoneEnabled: Bool = false,
                errorMessage: String? = nil) {
        self.status = status
        self.recordingID = recordingID
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.microphoneEnabled = microphoneEnabled
        self.errorMessage = errorMessage
    }

    public static let idle = BroadcastState(status: .idle)
}

public enum BroadcastStateStore {
    public static func read() -> BroadcastState {
        guard let data = try? Data(contentsOf: AppGroup.broadcastStateURL),
              let state = try? JSONDecoder.snapreel.decode(BroadcastState.self, from: data) else {
            return .idle
        }
        return state
    }

    public static func write(_ state: BroadcastState) {
        guard let data = try? JSONEncoder.snapreel.encode(state) else { return }
        try? data.write(to: AppGroup.broadcastStateURL, options: .atomic)
    }
}

/// A finished screen recording waiting in the inbox. Written next to the movie as
/// `<id>.json`; the movie is `<id>.mp4`.
public struct InboxRecording: Codable, Equatable {
    public var id: UUID
    public var movieFileName: String
    public var createdAt: Date
    public var finishedAt: Date
    public var microphoneEnabled: Bool
    /// True when the extension stopped early (memory pressure, storage full) but kept what it had.
    public var endedEarly: Bool
    public var note: String?

    public init(id: UUID, movieFileName: String, createdAt: Date, finishedAt: Date,
                microphoneEnabled: Bool, endedEarly: Bool = false, note: String? = nil) {
        self.id = id
        self.movieFileName = movieFileName
        self.createdAt = createdAt
        self.finishedAt = finishedAt
        self.microphoneEnabled = microphoneEnabled
        self.endedEarly = endedEarly
        self.note = note
    }

    public static func manifestURL(for id: UUID) -> URL {
        AppGroup.inboxURL.appendingPathComponent("\(id.uuidString).json")
    }
}

/// Darwin notifications cross the process boundary between app and extension. They carry no
/// payload; the receiver reads `BroadcastStateStore` after one arrives.
public enum BroadcastSignal: String {
    /// Extension → app: a broadcast started.
    case started = "co.arclayer.snapreel.broadcast.started"
    /// Extension → app: a broadcast ended and its file is in the inbox (or it failed).
    case finished = "co.arclayer.snapreel.broadcast.finished"
    /// App → extension: the user tapped Stop in the app.
    case stopRequested = "co.arclayer.snapreel.broadcast.stop"

    public func post() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(center, CFNotificationName(rawValue as CFString), nil, nil, true)
    }
}

/// Observes Darwin notifications and calls the handler on the main queue.
public final class BroadcastSignalObserver {
    private let signal: BroadcastSignal
    private let handler: () -> Void

    public init(_ signal: BroadcastSignal, handler: @escaping () -> Void) {
        self.signal = signal
        self.handler = handler
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(center, observer, { _, observer, _, _, _ in
            guard let observer else { return }
            let me = Unmanaged<BroadcastSignalObserver>.fromOpaque(observer).takeUnretainedValue()
            DispatchQueue.main.async { me.handler() }
        }, signal.rawValue as CFString, nil, .deliverImmediately)
    }

    deinit {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterRemoveObserver(center, observer, CFNotificationName(signal.rawValue as CFString), nil)
    }
}

public extension JSONEncoder {
    static var snapreel: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

public extension JSONDecoder {
    static var snapreel: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
