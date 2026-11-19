import Foundation

/// How a recording was made.
enum RecordingKind: String, Codable, CaseIterable, Identifiable {
    case camera
    case screen
    case audio
    case imported

    var id: String { rawValue }

    var label: String {
        switch self {
        case .camera: return "Camera"
        case .screen: return "Screen"
        case .audio: return "Audio"
        case .imported: return "Imported"
        }
    }

    var systemImage: String {
        switch self {
        case .camera: return "video.fill"
        case .screen: return "rectangle.inset.filled.on.rectangle"
        case .audio: return "waveform"
        case .imported: return "photo.on.rectangle"
        }
    }

    /// Used for default titles ("Screen recording – 18 Nov, 09:41").
    var titlePrefix: String {
        switch self {
        case .camera: return "Camera recording"
        case .screen: return "Screen recording"
        case .audio: return "Audio recording"
        case .imported: return "Imported video"
        }
    }
}

/// The recorder's three modes (import is a separate action, not a mode).
enum RecordMode: String, Codable, CaseIterable, Identifiable {
    case camera
    case screen
    case audio

    var id: String { rawValue }

    var label: String {
        switch self {
        case .camera: return "Camera"
        case .screen: return "Screen"
        case .audio: return "Audio"
        }
    }

    var kind: RecordingKind {
        switch self {
        case .camera: return .camera
        case .screen: return .screen
        case .audio: return .audio
        }
    }
}

/// Where a video is in its life. A video row exists from the moment saving starts, so a save
/// that is interrupted (app closed, out of space) is still visible and can be retried.
enum VideoState: Codable, Hashable {
    case ready
    /// Being written/copied into the library. `progress` is 0...1.
    case saving(progress: Double)
    /// Saving failed. `reason` is plain language; `outOfSpace` drives the storage-specific message.
    case failed(reason: String, outOfSpace: Bool)

    var isReady: Bool { if case .ready = self { return true } else { return false } }
}

enum TranscriptStatus: String, Codable {
    case notStarted
    case inProgress
    case ready
    /// No speech found, recognition not available for the language, or permission denied.
    case unavailable
}

/// One recording in the library. Files live in `MediaLocations` (videos/, thumbnails/).
struct Video: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var createdAt: Date
    var kind: RecordingKind
    /// File name inside the media videos directory ("<id>.mp4" or ".m4a" for audio).
    var fileName: String
    /// File name inside the thumbnails directory, if one was generated.
    var thumbnailFileName: String?
    var duration: Double
    var fileSize: Int64
    /// 0 for audio-only recordings.
    var pixelWidth: Int
    var pixelHeight: Int

    /// True until the person gives the recording a title (drives the "waiting for a title"
    /// notification and the title prompt in review).
    var needsTitle: Bool = false
    var folderID: UUID?
    var tags: [String] = []

    // Watching
    var watchLaterAddedAt: Date?
    var lastWatchedAt: Date?
    var playCount: Int = 0
    /// Furthest point reached, as a fraction of the duration (0...1).
    var furthestProgress: Double = 0
    /// Where playback resumes, in seconds.
    var resumePosition: Double = 0

    // Sending
    var shareCount: Int = 0
    var photosSaveCount: Int = 0

    var transcriptStatus: TranscriptStatus = .notStarted
    var state: VideoState = .ready
    /// When its review (after recording) was shown. Set once; a recording is never offered for
    /// review again, also after a relaunch (`ReviewCoordinator`). Nil for older recordings.
    var reviewedAt: Date?

    var isAudioOnly: Bool { kind == .audio || pixelWidth == 0 }
    var isPortrait: Bool { pixelHeight > pixelWidth }
    var isInWatchLater: Bool { watchLaterAddedAt != nil }
}

struct Folder: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var createdAt: Date
    var updatedAt: Date
}

/// The person's own note, stamped with a moment in the video ("Note at 0:14").
struct VideoNote: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var videoID: UUID
    /// Seconds into the video.
    var time: Double
    var text: String
    var createdAt: Date
    var updatedAt: Date
}

/// An emoji reaction pinned to a moment in the video.
struct VideoReaction: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var videoID: UUID
    var time: Double
    var emoji: String
    var createdAt: Date
}

/// On-device speech recognition result for one video.
struct Transcript: Codable, Hashable {
    var videoID: UUID
    var localeIdentifier: String
    var segments: [TranscriptSegment]
    var createdAt: Date
    /// Short summary, only when produced on this device by an on-device model. Nil otherwise;
    /// the player hides the summary block when nil.
    var summary: String?

    var fullText: String { segments.map(\.text).joined(separator: " ") }
}

struct TranscriptSegment: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    /// Seconds into the video.
    var start: Double
    var duration: Double
    var text: String
}
