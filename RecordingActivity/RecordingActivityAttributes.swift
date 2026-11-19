import ActivityKit
import Foundation

// The recording's Live Activity, shared by the app (which starts, updates and ends it, see
// `RecordingLiveActivity`) and the SnapreelLiveActivity widget extension (which draws it).

/// What is being recorded.
enum RecordingActivityKind: String, Codable, Hashable {
    case screen
    case audio
}

/// What the Live Activity shows right now.
struct RecordingActivityStatus: Codable, Hashable {
    enum Phase: String, Codable, Hashable {
        /// iOS's broadcast sheet is open; the screen recording hasn't started yet.
        case starting
        case recording
        case paused
        /// The recording ended while Snapreel was in the background (the phone locked, which
        /// ends a screen broadcast, or it was stopped from the red pill or Control Centre). The
        /// card stays with the time frozen until Snapreel opens.
        case stopped
    }

    var phase: Phase
    /// While recording: when the clock read 0:00 (later than the real start after a pause), so
    /// the Lock Screen counts by itself without Snapreel sending updates.
    var clockStart: Date
    /// While paused, starting or stopped: the time to show.
    var elapsed: TimeInterval

    static func starting() -> RecordingActivityStatus {
        RecordingActivityStatus(phase: .starting, clockStart: Date(), elapsed: 0)
    }

    static func recording(clockStart: Date) -> RecordingActivityStatus {
        RecordingActivityStatus(phase: .recording, clockStart: clockStart, elapsed: 0)
    }

    static func paused(elapsed: TimeInterval) -> RecordingActivityStatus {
        RecordingActivityStatus(phase: .paused, clockStart: Date().addingTimeInterval(-elapsed), elapsed: elapsed)
    }

    static func stopped(elapsed: TimeInterval) -> RecordingActivityStatus {
        RecordingActivityStatus(phase: .stopped, clockStart: Date().addingTimeInterval(-elapsed), elapsed: elapsed)
    }
}

@available(iOS 16.1, *)
struct RecordingActivityAttributes: ActivityAttributes {
    typealias ContentState = RecordingActivityStatus

    var kind: RecordingActivityKind
}
