import Foundation

/// One recording's upload to its share link, kept on disk (Application Support/Uploads/{id}/job.json) so it
/// survives a relaunch. Fields added after build 47 are optional: its job files still decode (`version` is nil) and
/// are brought up to date by `UploadJob.upgrade`.
struct UploadJob: Codable, Hashable {
    enum Stage: String, Codable {
        /// Making the web copy, poster and preview. What is ready is already being sent.
        case preparing
        /// Sending the rest.
        case uploading
        /// All files are up; telling the server (`status: ready`).
        case finishing
        case done
        case failed
    }

    /// One of the three files.
    struct Part: Codable, Hashable {
        enum Kind: String, Codable {
            case poster
            case preview
            case video
        }

        /// How a file is sent.
        enum Method: String, Codable {
            /// One request (small files).
            case single
            /// S3 multipart: pieces in any order, several at once, each safe to send twice.
            case multipart
            /// TUS: one chunk after another. The fallback when the S3 endpoint refuses its key.
            case tus
        }

        /// One multipart piece. `md5` is what the server answers (its ETag) once it has it, so a lost answer costs
        /// nothing: the list of pieces can be completed from here.
        struct Piece: Codable, Hashable {
            /// 1, 2, 3…
            var number: Int
            var start: Int64
            var size: Int64
            var md5: String?
            var done = false
        }

        var kind: Kind
        /// Inside the job's folder.
        var fileName: String
        /// The object name inside the bucket (`{userId}/{videoId}/video.mp4`).
        var objectName: String
        var contentType: String
        /// For a video still being prepared: the bytes that are final so far.
        var size: Int64
        /// The TUS upload's address once created.
        var location: String?
        /// Bytes the server has confirmed (TUS).
        var offset: Int64 = 0

        var method: Method?
        /// The multipart upload's id.
        var uploadID: String?
        var pieces: [Piece]?
        /// The server has the whole file.
        var stored: Bool?
        /// Left out: an empty preview never goes up, and a missing one doesn't hold the video back.
        var skipped: Bool?
        /// The video is still being written.
        var growing: Bool?
        /// Bytes at the start of the video that are written last (its index), so their pieces go last.
        var headerEnd: Int64?
        /// Which web copy the pieces belong to: a copy started over makes the old pieces useless.
        var copyID: String?

        var isComplete: Bool { stored == true || skipped == true }

        /// Bytes on the server.
        var sentBytes: Int64 {
            if skipped == true { return 0 }
            if stored == true { return size }
            switch method {
            case .multipart?: return (pieces ?? []).reduce(0) { $0 + ($1.done ? $1.size : 0) }
            case .tus?: return min(offset, size)
            case .single?, nil: return 0
            }
        }

        /// Lists the pieces that are final, keeping the ones already known.
        mutating func layOutPieces(pieceSize: Int64 = CloudConfig.pieceSize) {
            var known = Dictionary((pieces ?? []).map { ($0.number, $0) }, uniquingKeysWith: { a, _ in a })
            let header = headerEnd ?? 0
            var list: [Piece] = []
            var start: Int64 = 0
            var number = 1
            while start < size {
                let end = min(start + pieceSize, size)
                let isFinal = growing != true
                // While the video grows only whole pieces past its index are final.
                if isFinal || (end - start == pieceSize && start >= header) {
                    if var piece = known.removeValue(forKey: number) {
                        if piece.size != end - start { piece = Piece(number: number, start: start, size: end - start) }
                        list.append(piece)
                    } else {
                        list.append(Piece(number: number, start: start, size: end - start))
                    }
                }
                start = end
                number += 1
            }
            pieces = list
        }

        /// Forgets everything sent, to send the file again from the start.
        mutating func startOver() {
            location = nil
            offset = 0
            uploadID = nil
            stored = nil
            pieces = pieces?.map {
                var piece = $0
                piece.done = false
                return piece
            }
        }
    }

    var videoID: UUID
    var serverID: String
    var bucket: String
    var videoPath: String
    var posterPath: String
    var previewPath: String
    var maxLongSide: Int
    var title: String
    var stage: Stage
    var parts: [Part] = []
    var failure: String?
    var createdAt: Date
    var updatedAt: Date

    /// 2 since build 48; nil for jobs saved by build 47 and older.
    var version: Int?
    /// 0…1 while preparing.
    var prepared: Double?
    /// What the whole upload should come to, while the web copy is still being made.
    var estimatedBytes: Int64?
    /// The S3 endpoint refused its key: send with TUS.
    var usesTUS: Bool?
    /// Times a file was sent again from the start (capped, also across relaunches).
    var restarts: Int?

    static let currentVersion = 2

    /// Bytes to send: what is final, or the estimate while that is larger.
    var totalBytes: Int64 {
        let known = parts.reduce(Int64(0)) { $0 + ($1.skipped == true ? 0 : $1.size) }
        return stage == .preparing ? max(known, estimatedBytes ?? 0) : known
    }

    var confirmedBytes: Int64 { parts.reduce(0) { $0 + $1.sentBytes } }

    /// The bytes a person waits for: everything but a web copy that isn't written yet.
    var isActive: Bool { stage == .preparing || stage == .uploading || stage == .finishing }

    func index(of kind: Part.Kind) -> Int? { parts.firstIndex { $0.kind == kind } }

    /// Brings a job saved by build 47 (or older) up to date, including the ones that stopped:
    /// - sent files are marked stored;
    /// - an empty preview is left out instead of never completing;
    /// - a file stuck in the 409 loop (its object already existed) is sent again, this time overwriting;
    /// - a half-sent TUS video carries on if most of it is up, otherwise it goes again in pieces;
    /// - uploads that failed because their token ran out start again by themselves.
    /// Returns true when the job changed and should be tried now.
    mutating func upgrade(fileSize: (Part) -> Int64) -> Bool {
        guard version == nil else { return false }
        version = Self.currentVersion
        guard stage != .done else { return true }
        for index in parts.indices {
            var part = parts[index]
            let onDisk = fileSize(part)
            if part.size > 0 && part.offset >= part.size {
                part.stored = true
            } else if part.kind != .video && (part.size == 0 || onDisk == 0) {
                part.skipped = true
            } else if part.kind == .video, part.location != nil, part.size > 0, part.offset * 2 >= part.size {
                part.method = .tus
            } else {
                part.location = nil
                part.offset = 0
            }
            parts[index] = part
        }
        failure = nil
        if let video = index(of: .video), parts[video].isComplete || fileSize(parts[video]) == parts[video].size, parts[video].size > 0 {
            stage = .uploading
        } else {
            // Nothing usable was prepared (or its file is gone): make the web copy again.
            parts = []
            stage = .preparing
        }
        return true
    }
}

/// A file's size and date, asked of the disk every time. `URL.resourceValues` keeps its first answer on the URL, so a
/// file that was empty or missing a moment ago would stay so.
enum FileFacts {
    static func size(_ url: URL) -> Int64 {
        (attributes(url)?[.size] as? NSNumber)?.int64Value ?? 0
    }

    static func modified(_ url: URL) -> Date? {
        attributes(url)?[.modificationDate] as? Date
    }

    private static func attributes(_ url: URL) -> [FileAttributeKey: Any]? {
        try? FileManager.default.attributesOfItem(atPath: url.path)
    }
}

/// Where an upload is, for the share-link sheet, cards and the uploads list.
enum UploadPhase: Equatable {
    case preparing
    case uploading(Double)
    /// Offline: the upload carries on by itself when the connection comes back.
    case waitingForNetwork(Double)
    case finishing
    case done
    case failed(String)

    var fraction: Double? {
        switch self {
        case .uploading(let value), .waitingForNetwork(let value): return value
        case .finishing, .done: return 1
        case .preparing, .failed: return nil
        }
    }
}

/// The numbers behind a phase.
struct UploadProgress: Equatable {
    /// 0…1 while the web copy is being made; nil before its length is known.
    var prepared: Double?
    var sentBytes: Int64 = 0
    /// Everything to send. While preparing it is an estimate.
    var totalBytes: Int64 = 0
    var isEstimate = false
    /// Bytes a second over the last seconds, once there is enough to go by.
    var rate: Double?
    /// Preparing stopped because Snapreel isn't open; it carries on from where it was.
    var isPaused = false

    var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(0.99, Double(sentBytes) / Double(totalBytes))
    }

    var secondsLeft: Double? {
        guard let rate, rate > 1_000, totalBytes > sentBytes else { return nil }
        return Double(totalBytes - sentBytes) / rate
    }

    /// "45.2 of 73 MB".
    var bytesLabel: String {
        guard totalBytes > 0 else { return "" }
        let total = Format.bytes(totalBytes)
        return "\(Format.bytes(sentBytes)) of \(isEstimate ? "about " : "")\(total)"
    }

    /// "About 2 min left".
    var timeLabel: String? {
        guard let seconds = secondsLeft else { return nil }
        if seconds < 8 { return "A few seconds left" }
        if seconds < 55 { return "About \(Int((seconds / 10).rounded(.up)) * 10) sec left" }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "About \(max(1, minutes)) min left" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "About \(hours) hr left" : "About \(hours) hr \(rest) min left"
    }
}
