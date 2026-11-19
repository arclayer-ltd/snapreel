import Foundation

/// A recording's share link on snapreel.video, kept on this iPhone with the latest counts so
/// cards can say "Shared · 12 views" offline. Stored as its own record type ("cloudLink"),
/// keyed by the recording's id, so the `Video` record is untouched.
///
/// The server is the source of truth: `ShareLinks.refresh()` rebuilds these from
/// `GET /api/videos`. A record that fails to decode is skipped, so any field added later must
/// be Optional.
struct CloudLink: Codable, Hashable, Identifiable {
    /// The recording on this iPhone (the server's `localId`).
    var videoID: UUID
    /// The server's video id.
    var serverID: String
    var slug: String
    var url: String
    var title: String
    var createdAt: Date
    var status: CloudVideoStatus
    var views: Int
    var uniqueViewers: Int
    var commentCount: Int
    var lastViewedAt: Date?
    var syncedAt: Date?
    /// The link's settings, from the last `GET /api/videos/{id}`.
    var detail: VideoDetail?
    var durationS: Double?

    var id: UUID { videoID }
    var linkURL: URL? { URL(string: url) }

    init(videoID: UUID, created: CreateVideoResponse, title: String, durationS: Double) {
        self.videoID = videoID
        serverID = created.id
        slug = created.slug
        url = created.url
        self.title = title
        createdAt = Date()
        status = created.status
        views = 0
        uniqueViewers = 0
        commentCount = 0
        syncedAt = Date()
        self.durationS = durationS
    }

    init(videoID: UUID, summary: VideoSummary) {
        self.videoID = videoID
        serverID = summary.id
        slug = summary.slug
        url = summary.url
        title = summary.title
        createdAt = summary.createdAt
        status = summary.status
        views = summary.views
        uniqueViewers = summary.uniqueViewers
        commentCount = summary.commentCount
        lastViewedAt = summary.lastViewedAt
        syncedAt = Date()
        durationS = summary.durationS
    }

    mutating func apply(_ summary: VideoSummary) {
        serverID = summary.id
        slug = summary.slug
        url = summary.url
        title = summary.title
        status = summary.status
        views = summary.views
        uniqueViewers = summary.uniqueViewers
        commentCount = summary.commentCount
        lastViewedAt = summary.lastViewedAt
        durationS = summary.durationS
        syncedAt = Date()
    }

    mutating func apply(_ detail: VideoDetail) {
        apply(detail.summary)
        self.detail = detail
    }

    /// "Shared · 12 views", "Shared · 1 view", "Shared".
    var sharedLabel: String {
        switch views {
        case 0: return "Shared"
        case 1: return "Shared · 1 view"
        default: return "Shared · \(views) views"
        }
    }
}

extension CloudLink: StoredRecord {
    static var recordType: String { "cloudLink" }
    var recordID: String { videoID.uuidString }
}
