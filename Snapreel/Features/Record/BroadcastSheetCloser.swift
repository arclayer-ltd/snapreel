import UIKit

/// Closes iOS's "Screen Broadcast" sheet once a screen recording has started.
///
/// Since iOS 14 that sheet is shown by the system outside Snapreel, so the app can't dismiss
/// it (build 23 tried walking its own view controllers and found nothing; the owner's iPhone X
/// kept the sheet up with "Snapreel 00:06"). What does close it is bringing Snapreel back to
/// the front: Snapreel opens its own `snapreel://` link the moment the broadcast extension
/// says it started. While the sheet is up Snapreel is in the background, so a background task
/// keeps it awake long enough to hear that signal.
///
/// None of the big apps checked (Loom, Zoom, Teams, Meet, Webex) close the sheet for you; they
/// tell you to swipe up after the countdown, which the recorder still says too.
@MainActor
enum BroadcastSheetCloser {
    static let returnURL = URL(string: "snapreel://recording")!

    /// Off: after the sheet closes, the recorder says "Go to your Home Screen", as Loom and
    /// Zoom do. On: Snapreel also leaves for the Home Screen by itself, using UIApplication's
    /// undocumented `suspend`. That is a private API (App Review guideline 2.5.1) and could
    /// stop working in any iOS update, so it is the owner's call.
    static let leavesForHomeScreen = false

    private static var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private static var openedAt: Date?

    /// Snapreel's record button opened the system sheet.
    static func sheetOpened() {
        openedAt = Date()
        endBackgroundTask()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Screen broadcast starting") {
            Task { @MainActor in endBackgroundTask() }
        }
    }

    /// The broadcast extension says recording has started.
    static func broadcastStarted() {
        guard let openedAt, Date().timeIntervalSince(openedAt) < 180 else {
            endBackgroundTask()
            return
        }
        self.openedAt = nil
        UIApplication.shared.open(returnURL, options: [:]) { opened in
            Task { @MainActor in
                endBackgroundTask()
                guard opened, leavesForHomeScreen else { return }
                // Long enough to see that recording has started.
                try? await Task.sleep(nanoseconds: 700_000_000)
                leaveForHomeScreen()
            }
        }
    }

    /// The same as swiping up to the Home Screen. Undocumented; see `leavesForHomeScreen`.
    private static func leaveForHomeScreen() {
        UIControl().sendAction(#selector(URLSessionTask.suspend), to: UIApplication.shared, for: nil)
    }

    private static func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}
