import Foundation

/// What Storage's answer means for an upload. One place, because the same thing arrives in different clothes: an
/// expired token is `"exp" claim timestamp check failed` in a 400 (TUS, REST) or a 403 (S3), and a 409
/// can mean "the file is already there" or "you are at the wrong offset". Measured against the live project on
/// 25 November 2026 (docs/pro/BACKEND.md, "Uploads").
enum UploadAnswer: Equatable {
    case ok
    /// The object exists already (409 `KeyAlreadyExists`).
    case exists
    /// TUS: the server is at another offset.
    case offsetConflict
    /// The access token ran out (or can't be read): refresh it and go on.
    case tokenExpired
    /// The phone's clock is wrong enough for a signature to be refused.
    case clockSkew
    /// Row-level security said no.
    case denied
    /// The S3 endpoint refuses the key: use TUS.
    case keyRefused
    /// Another request holds the upload (423).
    case busy
    /// The upload id or address is unknown: it finished, was aborted, or is over 24 hours old.
    case gone
    /// Completing: some pieces are missing or don't match.
    case badPieces
    case tooLarge
    /// Worth trying again after a pause: 5xx, 429, 408, no status at all.
    case temporary(Int)
    /// Anything else the server refuses for good.
    case refused(Int)

    static func classify(status: Int, body: Data) -> UploadAnswer {
        let text = String(decoding: body.prefix(4_096), as: UTF8.self)
        let code = Self.code(in: text)
        if (200..<300).contains(status) {
            // S3 can answer 200 and still carry an error (a completion that failed late).
            if text.contains("<Error>") { return fromCode(code, text: text) ?? .temporary(500) }
            return .ok
        }
        if let known = fromCode(code, text: text) { return known }
        // JSON answers carry the real status inside ("statusCode":"404" in an HTTP 400).
        switch Self.innerStatus(in: text) ?? status {
        case 401: return .tokenExpired
        case 403: return .denied
        case 404, 410: return .gone
        case 408, 425, 429: return .temporary(status)
        case 409, 412, 460: return .offsetConflict
        case 413: return .tooLarge
        case 423: return .busy
        case 0: return .temporary(0)
        case 500...: return .temporary(status)
        default: return .refused(status)
        }
    }

    private static func fromCode(_ code: String?, text: String) -> UploadAnswer? {
        let lower = text.lowercased()
        if lower.contains("\"exp\\\" claim") || lower.contains("\"exp\" claim") || lower.contains("claim timestamp check failed")
            || lower.contains("jwt expired") || lower.contains("invalid compact jws") || lower.contains("jwtexpired") {
            return .tokenExpired
        }
        switch code {
        case "ExpiredToken"?, "InvalidToken"?, "InvalidJWT"?, "TokenRefreshRequired"?: return .tokenExpired
        case "RequestTimeTooSkewed"?, "RequestExpired"?: return .clockSkew
        case "SignatureDoesNotMatch"?, "InvalidAccessKeyId"?, "InvalidSignature"?, "S3InvalidAccessKeyId"?, "NotImplemented"?: return .keyRefused
        case "NoSuchUpload"?, "NoSuchKey"?: return .gone
        case "InvalidPart"?, "InvalidPartOrder"?, "EntityTooSmall"?, "InvalidPartNumber"?: return .badPieces
        case "EntityTooLarge"?: return .tooLarge
        case "KeyAlreadyExists"?, "Duplicate"?, "ResourceAlreadyExists"?: return .exists
        case "SlowDown"?, "InternalError"?, "ServiceUnavailable"?, "DatabaseTimeout"?, "LockTimeout"?, "RequestTimeout"?: return .temporary(503)
        case "ResourceLocked"?: return .busy
        case "AccessDenied"?:
            return lower.contains("signature verification failed") ? .tokenExpired : .denied
        default: break
        }
        if lower.contains("the resource already exists") { return .exists }
        if lower.contains("upload-offset conflict") { return .offsetConflict }
        return nil
    }

    /// `<Code>…</Code>` (S3) or `"code":"…"` (REST, TUS).
    private static func code(in text: String) -> String? {
        if let range = text.range(of: "<Code>"), let end = text.range(of: "</Code>", range: range.upperBound..<text.endIndex) {
            return String(text[range.upperBound..<end.lowerBound])
        }
        return json(text)?["code"] as? String ?? json(text)?["error"] as? String
    }

    private static func innerStatus(in text: String) -> Int? {
        guard let value = json(text)?["statusCode"] else { return nil }
        return (value as? Int) ?? (value as? String).flatMap(Int.init)
    }

    private static func json(_ text: String) -> [String: Any]? {
        guard text.hasPrefix("{") else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
    }

    /// The upload id in S3's answer to a new multipart upload.
    static func uploadID(in body: Data) -> String? {
        let text = String(decoding: body, as: UTF8.self)
        guard let range = text.range(of: "<UploadId>"),
              let end = text.range(of: "</UploadId>", range: range.upperBound..<text.endIndex) else { return nil }
        let id = String(text[range.upperBound..<end.lowerBound])
        return id.isEmpty ? nil : id
    }
}
