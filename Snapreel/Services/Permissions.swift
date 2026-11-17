import AVFoundation
import Photos
import Speech
import UIKit
import UserNotifications

/// One place to ask for and check every permission Snapreel uses.
enum PermissionKind: CaseIterable {
    case camera
    case microphone
    case photosAdd
    case speech
    case notifications

    var title: String {
        switch self {
        case .camera: return "Camera"
        case .microphone: return "Microphone"
        case .photosAdd: return "Photos"
        case .speech: return "Speech recognition"
        case .notifications: return "Notifications"
        }
    }
}

enum PermissionState: Equatable {
    case notDetermined
    case granted
    /// Denied or restricted: only the Settings app can change it now.
    case denied
}

enum Permissions {
    /// Current state without prompting. Notifications need `await`.
    static func state(_ kind: PermissionKind) async -> PermissionState {
        switch kind {
        case .camera: return map(AVCaptureDevice.authorizationStatus(for: .video))
        case .microphone: return map(AVCaptureDevice.authorizationStatus(for: .audio))
        case .photosAdd:
            switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
            case .authorized, .limited: return .granted
            case .notDetermined: return .notDetermined
            default: return .denied
            }
        case .speech:
            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized: return .granted
            case .notDetermined: return .notDetermined
            default: return .denied
            }
        case .notifications:
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            switch status {
            case .authorized, .provisional, .ephemeral: return .granted
            case .notDetermined: return .notDetermined
            default: return .denied
            }
        }
    }

    /// Synchronous variant for camera, microphone, photos and speech.
    static func currentState(_ kind: PermissionKind) -> PermissionState {
        switch kind {
        case .camera: return map(AVCaptureDevice.authorizationStatus(for: .video))
        case .microphone: return map(AVCaptureDevice.authorizationStatus(for: .audio))
        case .photosAdd:
            switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
            case .authorized, .limited: return .granted
            case .notDetermined: return .notDetermined
            default: return .denied
            }
        case .speech:
            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized: return .granted
            case .notDetermined: return .notDetermined
            default: return .denied
            }
        case .notifications:
            return .notDetermined
        }
    }

    /// Shows the system prompt if it hasn't been answered yet; returns the resulting state.
    static func request(_ kind: PermissionKind) async -> PermissionState {
        switch kind {
        case .camera:
            return await AVCaptureDevice.requestAccess(for: .video) ? .granted : .denied
        case .microphone:
            return await AVCaptureDevice.requestAccess(for: .audio) ? .granted : .denied
        case .photosAdd:
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            return (status == .authorized || status == .limited) ? .granted : .denied
        case .speech:
            let status: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
            return status == .authorized ? .granted : .denied
        case .notifications:
            return await Notifier.shared.requestAuthorization() ? .granted : .denied
        }
    }

    /// Opens Snapreel's page in the Settings app.
    @MainActor
    static func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private static func map(_ status: AVAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }
}
