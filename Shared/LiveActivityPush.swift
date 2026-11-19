import Foundation

/// Ends the screen recording's Lock Screen card from the broadcast extension, through
/// Snapreel's push relay (`server/push`), which sends Apple's ActivityKit "end" push.
///
/// Only the app can change its Live Activity, and it is usually suspended when a screen
/// recording stops (the phone locks, or the red pill or Control Centre stops it), so the card
/// used to keep counting (build 30: "1:03" for a 0:35 clip). Now:
/// - the app asks for the card with a push token and keeps it here, in the App Group
///   (`store`), and forgets it when the card ends (`clear`);
/// - the extension, when the broadcast finishes, posts the token and the "stopped" state with
///   the real length to the relay (`sendEnd`), and iOS redraws the card within seconds.
///
/// Only the token and that state leave the phone: no recording, title or account. The app's
/// own fallbacks stay (the short background grace, the 15-minute stale date, ending leftover
/// cards when Snapreel opens); a push that arrives after the app ended the card does nothing.
public enum LiveActivityPush {
    /// The relay, then its fallback (one carrier couldn't reach the vercel.app address).
    static let endpoints = [
        URL(string: "https://snapreel.video/api/live-activity")!,
        URL(string: "https://snapreel-push.vercel.app/api/live-activity")!,
    ]

    private static let tokenKey = "liveActivity.pushToken"
    private static let activityKey = "liveActivity.activityID"
    private static let outcomeKey = "liveActivity.lastOutcome"

    // MARK: - Token (app writes, extension reads)

    /// The screen recording card's push token, hex-encoded, and which card it belongs to.
    public static func store(token: Data, activityID: String) {
        let defaults = AppGroup.defaults
        defaults.set(token.map { String(format: "%02x", $0) }.joined(), forKey: tokenKey)
        defaults.set(activityID, forKey: activityKey)
    }

    /// Forgets the token: the card ended (`activityID` nil forgets whatever is stored).
    public static func clear(activityID: String? = nil) {
        let defaults = AppGroup.defaults
        if let activityID, defaults.string(forKey: activityKey) != activityID { return }
        defaults.removeObject(forKey: tokenKey)
        defaults.removeObject(forKey: activityKey)
    }

    public static var storedToken: String? { AppGroup.defaults.string(forKey: tokenKey) }

    /// What the last end push did ("18:02:11 snapreel.video: HTTP 200"), for the support email.
    public static var lastOutcome: String? { AppGroup.defaults.string(forKey: outcomeKey) }

    // MARK: - The request

    /// `RecordingActivityStatus.stopped(elapsed:)` as ActivityKit decodes it from the push:
    /// the same keys, encoded by a default `JSONEncoder` (dates as seconds since 2001). The
    /// extension can't see that type (it lives with the widget), so this mirrors it; the app's
    /// `rec.live.push` debug screen decodes this into the real type to prove they match.
    public struct StoppedState: Codable, Equatable {
        public var phase = "stopped"
        public var clockStart: Date
        public var elapsed: TimeInterval

        public init(elapsed: TimeInterval, now: Date = Date()) {
            self.clockStart = now.addingTimeInterval(-elapsed)
            self.elapsed = elapsed
        }
    }

    struct EndRequest: Encodable {
        var token: String
        var event = "end"
        var contentState: StoppedState
    }

    /// The relay's JSON body: `{"token":…,"event":"end","contentState":{…}}`.
    public static func requestBody(token: String, state: StoppedState) throws -> Data {
        try JSONEncoder().encode(EndRequest(token: token, contentState: state))
    }

    // MARK: - Sending (extension)

    /// Ends the card as "Screen recording stopped" at `elapsed`, if the app left a token. Waits
    /// for the answer (about 4 s for each address, `budget` in all) so ReplayKit doesn't end the
    /// extension first. Falls back to the second address only when the first can't be reached.
    public static func sendEnd(elapsed: TimeInterval, budget: TimeInterval = 6) {
        guard let token = storedToken else { return }
        let body: Data
        do {
            body = try requestBody(token: token, state: StoppedState(elapsed: max(0, elapsed)))
        } catch {
            return record("couldn't encode the end push")
        }
        let deadline = Date().addingTimeInterval(budget)
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        for url in endpoints {
            let wait = min(4, deadline.timeIntervalSinceNow)
            guard wait > 0.5 else { return record("end push: out of time") }
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: wait)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
            let host = url.host ?? url.absoluteString
            switch post(request, session: session, wait: wait) {
            case .answered(let status, let text):
                // The relay was reached: done, whatever it says (retrying won't change it).
                clear()
                return record("\(host): HTTP \(status) \(text)")
            case .failed(let reason):
                record("\(host): \(reason), trying the next address")
            }
        }
    }

    fileprivate enum Outcome {
        case answered(Int, String)
        case failed(String)
    }

    /// Holds the answer between URLSession's queue and the waiting thread.
    fileprivate final class Answer: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Outcome?
        func set(_ outcome: Outcome) { lock.lock(); value = outcome; lock.unlock() }
        func get() -> Outcome? { lock.lock(); defer { lock.unlock() }; return value }
    }

    private static func post(_ request: URLRequest, session: URLSession, wait: TimeInterval) -> Outcome {
        let answer = Answer()
        let done = DispatchSemaphore(value: 0)
        let task = session.dataTask(with: request) { data, response, error in
            if let response = response as? HTTPURLResponse {
                let text = data.flatMap { String(data: $0.prefix(160), encoding: .utf8) } ?? ""
                answer.set(.answered(response.statusCode, text))
            } else {
                answer.set(.failed(error?.localizedDescription ?? "no answer"))
            }
            done.signal()
        }
        task.resume()
        guard done.wait(timeout: .now() + wait + 0.25) == .success, let outcome = answer.get() else {
            task.cancel()
            return .failed("timed out")
        }
        return outcome
    }

    private static func record(_ line: String) {
        let stamped = "\(SharedLog.clock.string(from: Date())) \(line)"
        AppGroup.defaults.set(String(stamped.prefix(200)), forKey: outcomeKey)
        SharedLog.append("live activity: \(line)")
    }
}

/// A few lines both processes append to in the App Group (the newest 60 kept), for what neither
/// a screenshot nor the app's own log can show: what the broadcast extension did.
public enum SharedLog {
    static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static var url: URL { AppGroup.containerURL.appendingPathComponent("shared-log.txt") }
    private static let lock = NSLock()

    public static func append(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        var lines = (try? String(contentsOf: url, encoding: .utf8))?
            .split(separator: "\n").map(String.init) ?? []
        lines.append("\(clock.string(from: Date())) \(line)")
        let kept = lines.suffix(60).joined(separator: "\n") + "\n"
        try? kept.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Newest last.
    public static var lines: [String] {
        (try? String(contentsOf: url, encoding: .utf8))?.split(separator: "\n").map(String.init) ?? []
    }
}
