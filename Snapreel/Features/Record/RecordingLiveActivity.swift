import ActivityKit
import Foundation

/// The recording's Live Activity: "Recording 1:23" on the Lock Screen and, on iPhones with the
/// Dynamic Island, at the top of the screen. Tapping it opens Snapreel on the recording
/// (`snapreel://recording`, see `AppLinks`), where Stop is. It replaces build 23's floating
/// picture-in-picture button. iOS 16.1 and later; Snapreel itself runs from iOS 16.0. The
/// SnapreelLiveActivity widget extension draws it.
///
/// - Screen recordings: iOS only lets an app start a Live Activity while it's in front, and
///   the broadcast starts from iOS's own sheet with Snapreel behind it. So the activity starts
///   ("Starting screen recording") when Snapreel's record button opens that sheet, switches to
///   the running clock when the broadcast extension says recording started, and ends when it
///   says it finished. If Snapreel was suspended when the recording stopped from the red pill
///   or Control Centre, the activity ends the next time Snapreel comes to the front.
/// - Voice recordings keep running in the background; the recorder reports start, pause and
///   stop (`voiceChanged`).
@MainActor
enum RecordingLiveActivity {
    /// Live Activities exist (iOS 16.1+) and the person hasn't turned them off for Snapreel.
    static var isSupported: Bool {
        #if DEBUG
        if AppEnvironment.shared.debugScreenID != nil { return true }
        #endif
        guard #available(iOS 16.1, *) else { return false }
        return ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// The voice recording in progress, if any (set by the recorder).
    private static var voice: RecordingActivityStatus?
    private static var observers: [BroadcastSignalObserver] = []

    /// Listens to the broadcast extension for the app's whole life (the recorder may be closed
    /// while the screen is recording).
    static func startObserving() {
        guard observers.isEmpty else { return }
        observers = [
            BroadcastSignalObserver(.started) { Task { @MainActor in RecordingLiveActivity.sync() } },
            BroadcastSignalObserver(.finished) { Task { @MainActor in RecordingLiveActivity.sync() } },
        ]
    }

    /// Snapreel's record button is opening iOS's broadcast sheet (Snapreel is still in front).
    static func screenSheetOpened() {
        guard #available(iOS 16.1, *) else { return }
        LiveActivityStore.show(.screen, .starting())
    }

    /// The voice recording started, paused, resumed (a status) or ended (nil).
    static func voiceChanged(_ status: RecordingActivityStatus?) {
        voice = status
        sync()
    }

    /// Makes the activity match what is recording: called on the extension's signals and each
    /// time Snapreel comes to the front.
    static func sync() {
        guard #available(iOS 16.1, *) else { return }
        #if DEBUG
        if AppEnvironment.shared.debugScreenID != nil { return }
        #endif
        let broadcast = BroadcastStateStore.read()
        let broadcastLive = (broadcast.status == .recording || broadcast.status == .finishing)
            && Date().timeIntervalSince(broadcast.updatedAt) < 20
        if broadcastLive {
            LiveActivityStore.show(.screen, .recording(clockStart: broadcast.startedAt ?? Date()))
        } else if let voice {
            LiveActivityStore.show(.audio, voice)
        } else {
            // Covers a broadcast sheet that was closed without starting: Snapreel comes back
            // to the front, and nothing is recording.
            LiveActivityStore.endAll()
        }
    }
}

/// ActivityKit calls, iOS 16.1 and later (16.2 renamed them).
@available(iOS 16.1, *)
@MainActor
private enum LiveActivityStore {
    typealias RecordingActivity = Activity<RecordingActivityAttributes>

    static func show(_ kind: RecordingActivityKind, _ status: RecordingActivityStatus) {
        let all = RecordingActivity.activities
        let current = all.first { $0.attributes.kind == kind && $0.activityState == .active }
        for other in all where other.id != current?.id { end(other) }
        if let current {
            update(current, status)
        } else {
            request(kind, status)
        }
    }

    static func endAll() {
        for activity in RecordingActivity.activities { end(activity) }
    }

    private static func request(_ kind: RecordingActivityKind, _ status: RecordingActivityStatus) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = RecordingActivityAttributes(kind: kind)
        do {
            if #available(iOS 16.2, *) {
                _ = try RecordingActivity.request(attributes: attributes,
                                                  content: ActivityContent(state: status, staleDate: nil),
                                                  pushType: nil)
            } else {
                _ = try RecordingActivity.request(attributes: attributes, contentState: status, pushType: nil)
            }
        } catch {
            // Snapreel isn't in front (the broadcast started from Control Centre while it was in
            // the background), or the system said no. The next `sync` in front tries again.
        }
    }

    private static func update(_ activity: RecordingActivity, _ status: RecordingActivityStatus) {
        Task {
            if #available(iOS 16.2, *) {
                await activity.update(ActivityContent(state: status, staleDate: nil))
            } else {
                await activity.update(using: status)
            }
        }
    }

    private static func end(_ activity: RecordingActivity) {
        Task {
            if #available(iOS 16.2, *) {
                await activity.end(nil, dismissalPolicy: .immediate)
            } else {
                await activity.end(using: nil, dismissalPolicy: .immediate)
            }
        }
    }
}
