import Foundation
import SwiftUI

/// Preferences, persisted in the App Group's UserDefaults so the broadcast extension can read
/// the notification and recording ones. Views use `@EnvironmentObject var settings: AppSettings`.
@MainActor
final class AppSettings: ObservableObject {
    let defaults: UserDefaults

    // Getting started
    @Published var hasCompletedOnboarding: Bool { didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.onboarding) } }
    @Published var hasCompletedTour: Bool { didSet { defaults.set(hasCompletedTour, forKey: Keys.tour) } }
    @Published var useCase: UseCase? { didSet { defaults.set(useCase?.rawValue, forKey: Keys.useCase) } }

    // Recording defaults
    @Published var recordingQuality: RecordingQuality {
        didSet { defaults.set(recordingQuality.rawValue, forKey: SharedDefaultsKey.recordingQuality) }
    }
    @Published var microphoneOnByDefault: Bool { didSet { defaults.set(microphoneOnByDefault, forKey: Keys.micDefault) } }
    @Published var countdown: CountdownLength { didSet { defaults.set(countdown.rawValue, forKey: Keys.countdown) } }
    @Published var defaultCamera: CameraSide { didSet { defaults.set(defaultCamera.rawValue, forKey: Keys.camera) } }
    @Published var mirrorFrontCamera: Bool { didSet { defaults.set(mirrorFrontCamera, forKey: Keys.mirror) } }
    @Published var lastRecordMode: RecordMode { didSet { defaults.set(lastRecordMode.rawValue, forKey: Keys.lastMode) } }
    @Published var hasSeenScreenTutorial: Bool { didSet { defaults.set(hasSeenScreenTutorial, forKey: Keys.screenTutorial) } }

    // Speaker notes shown over the camera while recording
    @Published var speakerNotes: String { didSet { defaults.set(speakerNotes, forKey: Keys.speakerNotes) } }
    @Published var showsSpeakerNotes: Bool { didSet { defaults.set(showsSpeakerNotes, forKey: Keys.showsNotes) } }

    // Playback
    @Published var playbackRate: Double { didSet { defaults.set(playbackRate, forKey: Keys.rate) } }

    // Appearance: match the iPhone, or always Light or Dark (Settings > Appearance).
    @Published var appearance: AppearanceMode {
        didSet {
            defaults.set(appearance.rawValue, forKey: Keys.appearance)
            AppearanceController.apply(appearance)
        }
    }

    // Notifications: one toggle per kind, default on.
    @Published private(set) var notificationToggles: [NotificationKind: Bool]

    init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
        hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarding)
        hasCompletedTour = defaults.bool(forKey: Keys.tour)
        useCase = defaults.string(forKey: Keys.useCase).flatMap(UseCase.init(rawValue:))
        recordingQuality = defaults.string(forKey: SharedDefaultsKey.recordingQuality).flatMap(RecordingQuality.init(rawValue:)) ?? .high
        microphoneOnByDefault = defaults.object(forKey: Keys.micDefault) as? Bool ?? true
        countdown = defaults.object(forKey: Keys.countdown) == nil
            ? .three
            : (CountdownLength(rawValue: defaults.integer(forKey: Keys.countdown)) ?? .three)
        defaultCamera = defaults.string(forKey: Keys.camera).flatMap(CameraSide.init(rawValue:)) ?? .front
        mirrorFrontCamera = defaults.object(forKey: Keys.mirror) as? Bool ?? true
        lastRecordMode = defaults.string(forKey: Keys.lastMode).flatMap(RecordMode.init(rawValue:)) ?? .camera
        hasSeenScreenTutorial = defaults.bool(forKey: Keys.screenTutorial)
        speakerNotes = defaults.string(forKey: Keys.speakerNotes) ?? ""
        showsSpeakerNotes = defaults.bool(forKey: Keys.showsNotes)
        let rate = defaults.double(forKey: Keys.rate)
        playbackRate = rate > 0 ? rate : 1
        appearance = defaults.string(forKey: Keys.appearance).flatMap(AppearanceMode.init(rawValue:)) ?? .system
        var toggles: [NotificationKind: Bool] = [:]
        for kind in NotificationKind.allCases {
            toggles[kind] = defaults.object(forKey: kind.defaultsKey) as? Bool ?? true
        }
        notificationToggles = toggles
    }

    func isNotificationEnabled(_ kind: NotificationKind) -> Bool {
        notificationToggles[kind] ?? true
    }

    func setNotification(_ kind: NotificationKind, enabled: Bool) {
        notificationToggles[kind] = enabled
        defaults.set(enabled, forKey: kind.defaultsKey)
        // Viewer and comment alerts are pushes: both off stops them reaching this iPhone.
        if kind == .newViewer || kind == .newComment { PushService.shared.syncRegistration() }
    }

    /// Binding for a toggle row.
    func notificationBinding(_ kind: NotificationKind) -> Binding<Bool> {
        Binding(get: { [weak self] in self?.isNotificationEnabled(kind) ?? true },
                set: { [weak self] in self?.setNotification(kind, enabled: $0) })
    }

    /// Settings › Storage › Delete all my data also resets preferences to first-run values,
    /// except that onboarding is not shown again.
    func resetAfterErase() {
        speakerNotes = ""
        showsSpeakerNotes = false
    }

    private enum Keys {
        static let onboarding = "start.onboardingDone"
        static let tour = "start.tourDone"
        static let useCase = "start.useCase"
        static let micDefault = "recording.micDefault"
        static let countdown = "recording.countdown"
        static let camera = "recording.camera"
        static let mirror = "recording.mirror"
        static let lastMode = "recording.lastMode"
        static let screenTutorial = "recording.screenTutorialSeen"
        static let speakerNotes = "recording.speakerNotes"
        static let showsNotes = "recording.showsSpeakerNotes"
        static let rate = "playback.rate"
        static let appearance = "display.appearance"
    }
}
