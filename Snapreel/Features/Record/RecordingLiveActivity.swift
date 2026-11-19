import ActivityKit
import Foundation
import UIKit

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
///   says it finished.
/// - Only the app can change its Live Activity: the broadcast extension is another bundle and
///   ActivityKit only lists and ends the calling app's own activities. So when the broadcast
///   ends while Snapreel is in the background, Snapreel does it if it's still running: leaving
///   Snapreel while the screen records takes a short background grace (`beginBackgroundTask`),
///   which covers locking the phone straight away (iOS ends a broadcast when the phone locks,
///   build 29). The card then freezes as "Screen recording stopped" until Snapreel opens.
/// - If Snapreel was already suspended (stopped later from the red pill or Control Centre),
///   nothing can update the card until Snapreel opens and ends it. As a backstop the running
///   card carries a stale date (`staleAfter`): past it, iOS redraws it without the clock,
///   asking to open Snapreel to check.
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
    private static var lifecycle: [NSObjectProtocol] = []
    private static var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    /// How long a running screen-recording card is trusted without Snapreel renewing it.
    static let staleAfter: TimeInterval = 15 * 60

    /// Listens to the broadcast extension for the app's whole life (the recorder may be closed
    /// while the screen is recording).
    static func startObserving() {
        guard observers.isEmpty else { return }
        observers = [
            BroadcastSignalObserver(.started) { Task { @MainActor in RecordingLiveActivity.sync() } },
            BroadcastSignalObserver(.finished) { Task { @MainActor in RecordingLiveActivity.broadcastEnded() } },
        ]
        let center = NotificationCenter.default
        lifecycle = [
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in RecordingLiveActivity.enteredBackground() }
            },
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in RecordingLiveActivity.endBackgroundGrace() }
            },
        ]
    }

    /// A screen recording is running: the extension wrote its heartbeat in the last 20 seconds.
    private static var broadcastIsLive: Bool {
        let broadcast = BroadcastStateStore.read()
        return (broadcast.status == .recording || broadcast.status == .finishing)
            && Date().timeIntervalSince(broadcast.updatedAt) < 20
    }

    /// Snapreel went to the background while the screen records. Renew the card's stale date
    /// and stay awake a little, so that if the phone is locked now (which ends the broadcast)
    /// the card can still be stopped.
    private static func enteredBackground() {
        guard broadcastIsLive else { return }
        sync()
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Stop the Lock Screen timer") {
            Task { @MainActor in RecordingLiveActivity.endBackgroundGrace() }
        }
    }

    private static func endBackgroundGrace() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    /// The extension says the broadcast ended (stopped, the phone locked, an error, no space).
    /// In front, the card just goes. In the background it stays, frozen as "stopped", so the
    /// Lock Screen no longer counts and a tap opens Snapreel on the review.
    private static func broadcastEnded() {
        defer { endBackgroundGrace() }
        guard #available(iOS 16.1, *) else { return }
        #if DEBUG
        if AppEnvironment.shared.debugScreenID != nil { return }
        #endif
        guard UIApplication.shared.applicationState != .active, voice == nil, !broadcastIsLive else {
            sync()
            return
        }
        let broadcast = BroadcastStateStore.read()
        let elapsed = broadcast.startedAt.map { max(0, broadcast.updatedAt.timeIntervalSince($0)) } ?? 0
        LiveActivityStore.finish(.screen, .stopped(elapsed: elapsed))
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
        if broadcastIsLive {
            LiveActivityStore.show(.screen, .recording(clockStart: broadcast.startedAt ?? Date()),
                                   staleDate: Date().addingTimeInterval(staleAfter))
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

    /// `staleDate`: past it iOS redraws the card as stale (iOS 16.2 and later).
    static func show(_ kind: RecordingActivityKind, _ status: RecordingActivityStatus, staleDate: Date? = nil) {
        let all = RecordingActivity.activities
        let current = all.first { $0.attributes.kind == kind && $0.activityState == .active }
        for other in all where other.id != current?.id { end(other) }
        if let current {
            update(current, status, staleDate: staleDate)
        } else {
            request(kind, status, staleDate: staleDate)
        }
    }

    /// Ends the activity but leaves its last state (`status`) on the Lock Screen until the
    /// person clears it or Snapreel opens (`endAll`).
    static func finish(_ kind: RecordingActivityKind, _ status: RecordingActivityStatus) {
        for activity in RecordingActivity.activities {
            guard activity.attributes.kind == kind, activity.activityState == .active else {
                end(activity)
                continue
            }
            Task {
                if #available(iOS 16.2, *) {
                    await activity.end(ActivityContent(state: status, staleDate: nil), dismissalPolicy: .default)
                } else {
                    await activity.end(using: status, dismissalPolicy: .default)
                }
            }
        }
    }

    static func endAll() {
        for activity in RecordingActivity.activities { end(activity) }
    }

    private static func request(_ kind: RecordingActivityKind, _ status: RecordingActivityStatus, staleDate: Date?) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = RecordingActivityAttributes(kind: kind)
        do {
            if #available(iOS 16.2, *) {
                _ = try RecordingActivity.request(attributes: attributes,
                                                  content: ActivityContent(state: status, staleDate: staleDate),
                                                  pushType: nil)
            } else {
                _ = try RecordingActivity.request(attributes: attributes, contentState: status, pushType: nil)
            }
        } catch {
            // Snapreel isn't in front (the broadcast started from Control Centre while it was in
            // the background), or the system said no. The next `sync` in front tries again.
        }
    }

    private static func update(_ activity: RecordingActivity, _ status: RecordingActivityStatus, staleDate: Date?) {
        Task {
            if #available(iOS 16.2, *) {
                await activity.update(ActivityContent(state: status, staleDate: staleDate))
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
