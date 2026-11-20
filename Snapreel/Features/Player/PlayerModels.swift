import Foundation

/// The tabs under the video. Comments appears only for a recording shared as a link.
enum PlayerPanel: String, CaseIterable, Hashable {
    case notes
    case transcript
    case comments

    var title: String {
        switch self {
        case .notes: return "Notes"
        case .transcript: return "Transcript"
        case .comments: return "Comments"
        }
    }
}

/// Things that float over the video area.
enum PlayerOverlay: Equatable {
    /// Playback speed list under the speed pill.
    case speed
    /// Grid of quick reactions over the video.
    case reactions
}

/// Sheets the player presents. One at a time, through `.sheet(item:)`.
enum PlayerSheet: Identifiable, Equatable {
    /// New note stamped at `time` (seconds).
    case compose(time: Double)
    case editNote(UUID)
    case emoji
    /// Video actions; `confirmingDelete` opens it straight on the delete confirmation.
    case actions(confirmingDelete: Bool)
    case title
    case stats

    var id: String {
        switch self {
        case .compose: return "compose"
        case .editNote(let id): return "edit-\(id.uuidString)"
        case .emoji: return "emoji"
        case .actions: return "actions"
        case .title: return "title"
        case .stats: return "stats"
        }
    }
}

/// Work that waits until the current sheet has finished dismissing.
enum PlayerFollowUp: Equatable {
    case share
    case saveToPhotos
    case editTitle
    case stats
    case delete
    case react(String)
    case copyLink
    case linkSettings
    case editVideo
    case deleteWithEdits
}

/// What the Transcript tab shows.
enum TranscriptPhase: Equatable {
    case notStarted
    case working
    case ready
    case unavailable(TranscriptUnavailableReason)
}

/// Why a recording has no transcript. Each has its own message in the Transcript tab.
enum TranscriptUnavailableReason: String, Codable, Equatable {
    /// Recognition ran and heard nobody talking.
    case noSpeech
    /// No on-device recogniser for the device language (or US English) on this iPhone.
    case languageUnsupported
    /// Speech recognition is switched off for Snapreel.
    case permissionDenied
    /// Something interrupted recognition; worth trying again.
    case failed
}

/// How the player opens. The shell uses the defaults; debug screens use the other values to
/// open a menu, sheet or state directly.
struct PlayerInitialState {
    var panel: PlayerPanel = .notes
    /// Starting position in seconds; overrides the presentation's `startAt` and the resume point.
    var position: Double? = nil
    var autoplay = true
    var showsDetails = false
    var isFullscreen = false
    var overlay: PlayerOverlay? = nil
    var sheet: PlayerSheet? = nil
    /// Shows the picture-in-picture placeholder as if PiP were running.
    var showsPictureInPicturePlaceholder = false
    /// Pins the Transcript tab to one state.
    var transcriptPhase: TranscriptPhase? = nil
    /// A reaction emoji held at the top of its rise over the video.
    var pinnedBurst: String? = nil
    /// Opens session E's Save to Photos flow on this video at this stage, and holds it there.
    var photosStage: PhotosSaveStage? = nil
    /// Scrolls the Notes / Transcript switch to the top of the details area on open.
    var scrollsToPanel = false
    /// Shows "Keep watching", as after a note paused a playing video.
    var showsResumePill = false
    /// Holds the page part-way through a swipe down to minimise.
    var swipeOffset: CGFloat = 0
    /// Viewers' comments and reactions already loaded (debug screens).
    var activity: CloudActivity? = nil
}

/// A large emoji that rises over the video when you react.
struct ReactionBurst: Identifiable, Equatable {
    let id = UUID()
    var emoji: String
    /// Held still at the top of its rise (debug screenshots).
    var isPinned = false
    /// Horizontal position as a fraction of the video width.
    var xFraction: Double = Double.random(in: 0.3...0.7)
}

/// Labels for playback speeds.
enum PlaybackSpeed {
    /// The speeds offered in the speed menu.
    static let rates: [Double] = [1, 1.2, 1.5, 1.7, 2]

    /// "1x", "1.2x", "2x".
    static func label(_ rate: Double) -> String {
        String(format: "%gx", rate)
    }

    /// "normal speed", "1.5 times speed".
    static func spoken(_ rate: Double) -> String {
        abs(rate - 1) < 0.01 ? "normal speed" : String(format: "%g times speed", rate)
    }
}

/// A seed that stays the same across launches (unlike `hashValue`), for drawn artwork.
enum PlayerArtSeed {
    static func of(_ id: UUID) -> Int {
        id.uuidString.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
    }
}

/// What the player keeps outside the library, in `UserDefaults.standard` under "player.":
/// why a transcript couldn't be made, and your recent reactions. "Delete all my data" can
/// call `erase()` so nothing about deleted recordings is left behind.
enum PlayerLocalData {
    @MainActor
    static func erase() {
        PlaybackSession.shared.close()
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("player.") {
            defaults.removeObject(forKey: key)
        }
    }
}
