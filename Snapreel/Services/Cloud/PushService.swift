import UIKit
import UserNotifications

/// Pushes from snapreel.video about your share links: a new viewer, a comment, reactions.
/// Registers for remote notifications once you're signed in, sends the device token to
/// `POST /api/devices`, and turns the `sr` part of a push into a Notifications row and the
/// right place in the app.
@MainActor
final class PushService {
    static let shared = PushService()

    private let defaults = UserDefaults.standard
    private static let registeredKey = "push.registeredToken"
    private static let importedKey = "push.importedIDs"

    private init() {}

    /// The token the server knows about, hex-encoded.
    private var registeredToken: String? {
        get { defaults.string(forKey: Self.registeredKey) }
        set { defaults.set(newValue, forKey: Self.registeredKey) }
    }

    /// Viewer or comment alerts are switched on (Settings › Notifications › Share links).
    var wantsAlerts: Bool {
        let settings = AppEnvironment.shared.settings
        return settings.isNotificationEnabled(.newViewer) || settings.isNotificationEnabled(.newComment)
    }

    // MARK: - Registration

    /// Asks iOS for a device token when signed in and the alerts are wanted. Never shows a
    /// prompt: whether alerts appear is still up to the notification permission.
    func registerIfPossible() {
        guard CloudConfig.isConfigured, AuthService.shared.isSignedIn, wantsAlerts else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Follows the two switches: registers, or tells the server to stop.
    func syncRegistration() {
        if wantsAlerts {
            registerIfPossible()
        } else {
            Task { await unregister() }
        }
    }

    func didRegister(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        guard AuthService.shared.isSignedIn, wantsAlerts else { return }
        Task { @MainActor in
            do {
                // The entitlement is `production` in every build (TestFlight and the App Store).
                try await APIClient.shared.registerDevice(token: token, environment: "production")
                self.registeredToken = token
            } catch {
                // Tried again on the next launch.
            }
        }
    }

    /// Stops pushes to this iPhone (signing out, or both switches off).
    func unregister() async {
        guard let token = registeredToken else { return }
        try? await APIClient.shared.unregisterDevice(token: token)
        registeredToken = nil
    }

    // MARK: - Payloads

    /// The `sr` dictionary of a push, if it's one of ours.
    nonisolated static func payload(from userInfo: [AnyHashable: Any]) -> PushPayload? {
        guard let object = userInfo["sr"], JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return try? JSONDecoder().decode(PushPayload.self, from: data)
    }

    private static func kind(for payload: PushPayload) -> NotificationKind {
        switch payload.type {
        case .view: return .newViewer
        case .comment, .reaction: return .newComment
        case .upload: return .uploadFinished
        }
    }

    /// A push arrived while Snapreel was open: add it to the feed and refresh the counts.
    func received(_ payload: PushPayload, title: String, body: String, identifier: String) {
        addToFeed(payload, title: title, body: body, identifier: identifier, date: Date())
        Task { await ShareLinks.shared.refresh(force: true) }
    }

    /// A push was tapped: open the recording (on its comments for a comment), or the
    /// dashboard page when the recording isn't on this iPhone.
    func opened(_ payload: PushPayload, title: String, body: String, identifier: String) {
        addToFeed(payload, title: title, body: body, identifier: identifier, date: Date(), read: true)
        let environment = AppEnvironment.shared
        let localID = UUID(uuidString: payload.localId)
        if let localID, let video = environment.library.video(localID), video.state.isReady {
            environment.router.open(videoID: localID, opensComments: payload.type == .comment || payload.type == .reaction)
        } else if let url = URL(string: "https://\(CloudConfig.linkHost)/app/v/\(payload.videoId)") {
            ShareLinks.openInSafari(url)
        }
        Task { await ShareLinks.shared.refresh(force: true) }
    }

    /// Pushes that arrived while Snapreel was closed and weren't tapped still get a feed row.
    func importDelivered() async {
        let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
        for notification in delivered {
            let content = notification.request.content
            guard let payload = Self.payload(from: content.userInfo) else { continue }
            addToFeed(payload, title: content.title, body: content.body,
                      identifier: notification.request.identifier, date: notification.date)
        }
    }

    private func addToFeed(_ payload: PushPayload, title: String, body: String, identifier: String,
                           date: Date, read: Bool = false) {
        var imported = Set(defaults.stringArray(forKey: Self.importedKey) ?? [])
        guard !imported.contains(identifier) else { return }
        imported.insert(identifier)
        defaults.set(Array(imported.suffix(300)), forKey: Self.importedKey)
        let kind = Self.kind(for: payload)
        let item = AppNotification(kind: kind, videoID: UUID(uuidString: payload.localId),
                                   title: title.isEmpty ? kind.settingsTitle : title, body: body,
                                   createdAt: date, isRead: read)
        AppEnvironment.shared.library.appendNotification(item)
    }
}

/// Starts and nudges the cloud services. Not used in debug fixture screens.
@MainActor
enum CloudServices {
    private static var lastActive: Date?

    /// At launch.
    static func start() {
        Uploader.shared.setUp()
        PurchaseService.shared.startListening()
        guard AuthService.shared.isSignedIn else { return }
        PushService.shared.registerIfPossible()
        Task {
            await AuthService.shared.refreshMe()
            await PurchaseService.shared.refreshEntitlements()
            await ShareLinks.shared.refresh(force: true)
        }
    }

    /// Each time Snapreel comes to the foreground.
    static func becameActive() {
        guard AuthService.shared.isSignedIn else { return }
        Uploader.shared.resumeAll()
        if let lastActive, Date().timeIntervalSince(lastActive) < 30 { return }
        lastActive = Date()
        Task {
            await PushService.shared.importDelivered()
            await AuthService.shared.refreshMe()
            await ShareLinks.shared.refresh()
        }
    }

    /// Right after signing in.
    static func didSignIn() {
        PushService.shared.registerIfPossible()
        Uploader.shared.resumeAll()
        Task {
            await PurchaseService.shared.refreshEntitlements()
            await ShareLinks.shared.refresh(force: true)
        }
    }
}
