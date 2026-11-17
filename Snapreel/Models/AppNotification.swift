import Foundation

/// The kinds of things Snapreel itself tells you about. Each has its own toggle in
/// Settings › Notifications and is delivered as a local notification and a feed row.
enum NotificationKind: String, Codable, CaseIterable, Identifiable {
    case recordingSaved
    case needsTitle
    case importFinished
    case transcriptReady
    case storageLow

    var id: String { rawValue }

    /// Settings label.
    var settingsTitle: String {
        switch self {
        case .recordingSaved: return "Recording saved"
        case .needsTitle: return "Waiting for a title"
        case .importFinished: return "Import finished"
        case .transcriptReady: return "Transcript ready"
        case .storageLow: return "Storage running low"
        }
    }

    /// Settings helper text.
    var settingsDetail: String {
        switch self {
        case .recordingSaved: return "When a screen, camera or audio recording is saved, including when a screen recording ends while you're in another app."
        case .needsTitle: return "A reminder when a recording still has its automatic title."
        case .importFinished: return "When a video from your photo library has been copied in."
        case .transcriptReady: return "When the transcript of a recording is ready to read and search."
        case .storageLow: return "When your iPhone is close to full and new recordings may not save."
        }
    }

    var systemImage: String {
        switch self {
        case .recordingSaved: return "checkmark.circle.fill"
        case .needsTitle: return "character.cursor.ibeam"
        case .importFinished: return "square.and.arrow.down.fill"
        case .transcriptReady: return "text.quote"
        case .storageLow: return "externaldrive.fill.badge.exclamationmark"
        }
    }

    /// Key in `AppGroup.defaults` for this kind's toggle (default on).
    var defaultsKey: String { "notify.\(rawValue)" }
}

/// One row in the Notifications feed.
struct AppNotification: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var kind: NotificationKind
    var videoID: UUID?
    var title: String
    var body: String
    var createdAt: Date
    var isRead: Bool = false
}
