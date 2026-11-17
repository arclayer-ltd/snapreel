import Foundation

/// Identifiers and locations shared by the app and the broadcast upload extension.
/// Foundation only: this file is compiled into both targets, and the extension may use
/// extension-safe APIs only.
public enum AppGroup {
    public static let identifier = "group.co.arclayer.snapreel"
    public static let appBundleID = "co.arclayer.snapreel"
    public static let broadcastExtensionBundleID = "co.arclayer.snapreel.broadcast"

    /// The shared container. Unsigned simulator builds have no App Group entitlement, so they
    /// fall back to a folder in Application Support (only the app runs in the simulator).
    public static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return url
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SnapreelGroup", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Finished screen recordings land here (one movie plus one manifest per recording) until the
    /// app moves them into its library.
    public static var inboxURL: URL { directory("Inbox") }

    /// Recordings in progress. The extension writes here and moves the file to the inbox when done.
    public static var inProgressURL: URL { directory("InProgress") }

    /// State of the current or last broadcast, written by the extension, read by the app.
    public static var broadcastStateURL: URL { containerURL.appendingPathComponent("broadcast-state.json") }

    /// Settings both processes read (notification preferences, microphone default).
    public static var defaults: UserDefaults { UserDefaults(suiteName: identifier) ?? .standard }

    private static func directory(_ name: String) -> URL {
        let url = containerURL.appendingPathComponent(name, isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }
}

/// Keys in `AppGroup.defaults` that both processes use.
public enum SharedDefaultsKey {
    /// Bool. Notification preference for "screen recording finished" (default true).
    public static let notifyRecordingSaved = "notify.recordingSaved"
    /// Bool. Whether local notifications are allowed by the user in Snapreel's settings flow.
    public static let notificationsAuthorized = "notify.authorized"
    /// String. Recording quality raw value chosen in recording defaults.
    public static let recordingQuality = "recording.quality"
}
