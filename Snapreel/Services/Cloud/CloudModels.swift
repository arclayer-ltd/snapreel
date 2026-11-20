import Foundation

// The API's JSON shapes, mirroring `web/lib/contract.ts` (docs/pro/API.md). Keys are camelCase
// on the wire, so the property names match them exactly. Enums decode leniently: a value the
// app doesn't know yet maps to a safe default instead of failing the whole response.

enum CloudTier: String, Codable, Hashable {
    case free
    case pro

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CloudTier(rawValue: raw) ?? .free
    }
}

enum CloudVideoKind: String, Codable, Hashable {
    case screen
    case camera
    case audio

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CloudVideoKind(rawValue: raw) ?? .screen
    }

    /// Imports go up as camera recordings: the web shows them the same way.
    init(_ kind: RecordingKind) {
        switch kind {
        case .screen: self = .screen
        case .audio: self = .audio
        case .camera, .imported: self = .camera
        }
    }
}

enum CloudVideoStatus: String, Codable, Hashable {
    case uploading
    case ready
    case failed

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CloudVideoStatus(rawValue: raw) ?? .uploading
    }
}

enum CloudAccess: String, Codable, Hashable {
    case link
    case password

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CloudAccess(rawValue: raw) ?? .link
    }
}

/// Why the server refused with 402.
enum CloudLimitReason: String, Codable, Hashable {
    case links
    case duration
    case proFeature = "pro_feature"
}

// MARK: - Account

struct CloudPlan: Codable, Hashable {
    var tier: CloudTier
    var productId: String?
    var expiresAt: Date?
}

struct CloudUsage: Codable, Hashable {
    var activeLinks: Int
    /// Nil on Pro (unlimited).
    var linkLimit: Int?
    var maxDurationS: Double
    /// "720p" or "1080p".
    var quality: String
}

struct CloudUser: Codable, Hashable {
    var id: String
    var email: String?
    var displayName: String?
}

/// `GET /api/me`.
struct CloudMe: Codable, Hashable {
    var user: CloudUser
    var plan: CloudPlan
    var usage: CloudUsage

    var isPro: Bool { plan.tier == .pro }
}

struct UpdateMeRequest: Encodable {
    var displayName: String?
    var brandColor: String?
}

// MARK: - Videos

struct CloudTranscript: Codable, Hashable {
    struct Segment: Codable, Hashable {
        var start: Double
        var duration: Double
        var text: String
    }

    var locale: String
    var segments: [Segment]

    init(locale: String, segments: [Segment]) {
        self.locale = locale
        self.segments = segments
    }

    /// The on-device transcript, which becomes the watch page's captions and searchable text.
    init(_ transcript: Transcript) {
        locale = transcript.localeIdentifier
        segments = transcript.segments.map { Segment(start: $0.start, duration: $0.duration, text: $0.text) }
    }
}

struct CallToAction: Codable, Hashable {
    var label: String
    var url: String
}

/// `POST /api/videos`.
struct CreateVideoRequest: Encodable {
    var localId: String
    var title: String
    var kind: CloudVideoKind
    var durationS: Double
    var width: Int
    var height: Int
    var sizeBytes: Int64
    var transcript: CloudTranscript?
}

struct CreateVideoResponse: Codable, Hashable {
    struct Upload: Codable, Hashable {
        var bucket: String
        var videoPath: String
        var posterPath: String
        var previewPath: String
    }

    struct Limits: Codable, Hashable {
        var maxDurationS: Double
        var maxLongSide: Int
    }

    var id: String
    var slug: String
    var url: String
    var status: CloudVideoStatus
    var upload: Upload
    var limits: Limits
}

/// One of your shared videos (`GET /api/videos`).
struct VideoSummary: Codable, Hashable, Identifiable {
    var id: String
    var slug: String
    var url: String
    var localId: String
    var title: String
    var kind: CloudVideoKind
    var durationS: Double
    var status: CloudVideoStatus
    var posterUrl: String?
    var createdAt: Date
    var views: Int
    var uniqueViewers: Int
    var lastViewedAt: Date?
    var commentCount: Int
}

/// A shared video with its link settings (`GET /api/videos/{id}`).
struct VideoDetail: Codable, Hashable, Identifiable {
    var id: String
    var slug: String
    var url: String
    var localId: String
    var title: String
    var kind: CloudVideoKind
    var durationS: Double
    var status: CloudVideoStatus
    var posterUrl: String?
    var createdAt: Date
    var views: Int
    var uniqueViewers: Int
    var lastViewedAt: Date?
    var commentCount: Int

    var access: CloudAccess
    var hasPassword: Bool
    var expiresAt: Date?
    var allowDownload: Bool
    var allowComments: Bool
    var allowReactions: Bool
    var cta: CallToAction?
    var width: Int
    var height: Int
    var sizeBytes: Int64

    var summary: VideoSummary {
        VideoSummary(id: id, slug: slug, url: url, localId: localId, title: title, kind: kind,
                     durationS: durationS, status: status, posterUrl: posterUrl, createdAt: createdAt,
                     views: views, uniqueViewers: uniqueViewers, lastViewedAt: lastViewedAt,
                     commentCount: commentCount)
    }
}

/// `PATCH /api/videos/{id}`: only the fields that are set are sent. `clearsExpiry` and
/// `clearsCallToAction` send an explicit null to remove them.
struct UpdateVideoRequest: Encodable {
    var title: String?
    var status: CloudVideoStatus?
    var uploadedBytes: Int64?
    var access: CloudAccess?
    var password: String?
    var expiresAt: Date?
    var clearsExpiry = false
    var allowDownload: Bool?
    var allowComments: Bool?
    var allowReactions: Bool?
    var cta: CallToAction?
    var clearsCallToAction = false

    private enum CodingKeys: String, CodingKey {
        case title, status, uploadedBytes, access, password, expiresAt, allowDownload, allowComments,
             allowReactions, cta
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(uploadedBytes, forKey: .uploadedBytes)
        try container.encodeIfPresent(access, forKey: .access)
        try container.encodeIfPresent(password, forKey: .password)
        if clearsExpiry {
            try container.encodeNil(forKey: .expiresAt)
        } else {
            try container.encodeIfPresent(expiresAt, forKey: .expiresAt)
        }
        try container.encodeIfPresent(allowDownload, forKey: .allowDownload)
        try container.encodeIfPresent(allowComments, forKey: .allowComments)
        try container.encodeIfPresent(allowReactions, forKey: .allowReactions)
        if clearsCallToAction {
            try container.encodeNil(forKey: .cta)
        } else {
            try container.encodeIfPresent(cta, forKey: .cta)
        }
    }

    var isEmpty: Bool {
        title == nil && status == nil && uploadedBytes == nil && access == nil && password == nil
            && expiresAt == nil && !clearsExpiry && allowDownload == nil && allowComments == nil
            && allowReactions == nil && cta == nil && !clearsCallToAction
    }
}

// MARK: - Insights and activity

enum ViewerDevice: String, Codable, Hashable {
    case phone
    case tablet
    case desktop

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ViewerDevice(rawValue: raw) ?? .desktop
    }

    var systemImage: String {
        switch self {
        case .phone: return "iphone"
        case .tablet: return "ipad"
        case .desktop: return "laptopcomputer"
        }
    }
}

struct CloudViewer: Codable, Hashable {
    var name: String?
    var anonymous: Bool
    var country: String?
    var device: ViewerDevice?
    var firstSeenAt: Date
    var lastSeenAt: Date
    /// How much of the video this viewer watched, 0–100.
    var percent: Double
}

struct CloudCountryCount: Codable, Hashable {
    var code: String
    var count: Int
}

/// `GET /api/videos/{id}/insights`. Free plans get `views` and `uniqueViewers`; the rest is nil.
struct CloudInsights: Codable, Hashable {
    var views: Int
    var uniqueViewers: Int
    /// Average share of the video watched, 0–100.
    var avgPercent: Double?
    /// Share of views that reached the end. Accepted as 0–1 or 0–100.
    var completionRate: Double?
    /// 100 buckets: how many views reached each 1% of the video.
    var dropoff: [Int]?
    var countries: [CloudCountryCount]?
    var viewers: [CloudViewer]?

    /// True when the detail beyond the two counts came back (Pro).
    var hasDetail: Bool { avgPercent != nil || dropoff != nil || viewers != nil }

    /// `completionRate` as 0–100 whichever way the server sends it.
    var completionPercent: Double? {
        guard let completionRate else { return nil }
        return completionRate <= 1 ? completionRate * 100 : completionRate
    }
}

struct CloudComment: Codable, Hashable, Identifiable {
    var id: String
    var authorName: String
    var isOwner: Bool
    var body: String
    /// Seconds into the video, when the viewer pinned it to a moment.
    var atS: Double?
    var parentId: String?
    var createdAt: Date
}

struct CloudReaction: Codable, Hashable, Identifiable {
    var id: String
    var emoji: String
    var atS: Double
    var authorName: String?
    var createdAt: Date
}

/// `GET /api/videos/{id}/activity`.
struct CloudActivity: Codable, Hashable {
    var comments: [CloudComment]
    var reactions: [CloudReaction]

    static let empty = CloudActivity(comments: [], reactions: [])
}

// MARK: - Devices and purchases

struct RegisterDeviceRequest: Encodable {
    var token: String
    var environment: String
    var appVersion: String
}

struct VerifyPurchaseRequest: Encodable {
    var signedTransaction: String
}

struct VerifyPurchaseResponse: Codable, Hashable {
    var plan: CloudPlan
}

struct BlockRequest: Encodable {
    var commentId: String?
    var reactionId: String?
}

/// `{error, message, reason}`.
struct APIErrorBody: Decodable {
    var error: String
    var message: String?
    var reason: CloudLimitReason?
}

/// The `sr` part of a push (`docs/pro/API.md`, "Push to the app").
struct PushPayload: Codable, Hashable {
    enum Kind: String, Codable, Hashable {
        case view
        case comment
        case reaction
        case upload

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: raw) ?? .view
        }
    }

    var type: Kind
    var videoId: String
    var localId: String
    var commentId: String?
}

// MARK: - JSON

enum CloudJSON {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(isoFractional.string(from: date))
        }
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let seconds = try? container.decode(Double.self) {
                // Epoch seconds or milliseconds.
                return Date(timeIntervalSince1970: seconds > 10_000_000_000 ? seconds / 1_000 : seconds)
            }
            let text = try container.decode(String.self)
            if let date = parse(text) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unreadable date \(text)")
        }
        return decoder
    }()

    /// Postgres and JavaScript both appear: "2026-11-20T10:21:33.123Z", "…33.123456+00:00",
    /// "…33+00:00".
    static func parse(_ text: String) -> Date? {
        if let date = isoFractional.date(from: text) ?? iso.date(from: text) { return date }
        // Trim microseconds to milliseconds, which ISO8601DateFormatter understands.
        if let dot = text.firstIndex(of: ".") {
            let fraction = text[text.index(after: dot)...].prefix { $0.isNumber }
            if fraction.count > 3 {
                let trimmed = text.replacingOccurrences(of: "." + fraction, with: "." + fraction.prefix(3))
                return isoFractional.date(from: trimmed)
            }
        }
        return nil
    }

    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
