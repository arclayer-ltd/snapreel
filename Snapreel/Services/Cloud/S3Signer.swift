import CryptoKit
import Foundation

/// Signs requests to Storage's S3 endpoint (AWS Signature Version 4) in the query string, with the person's session
/// token, so the row-level security rules decide what they may touch.
///
/// Query signing because a header-signed request is refused once its date is 15 minutes old
/// (`RequestTimeTooSkewed`), and a piece can wait in the background session much longer than that. A signed URL
/// stays good for `expires`; what ends it is the token inside running out, after an hour.
struct S3Signer {
    var endpoint: URL
    var region: String
    var accessKey: String
    var secret: String

    /// The signer for this project, or nil while `CloudConfig` holds placeholders.
    static var project: S3Signer? {
        guard let endpoint = CloudConfig.s3URL, let ref = CloudConfig.projectRef else { return nil }
        return S3Signer(endpoint: endpoint, region: CloudConfig.s3Region, accessKey: ref, secret: CloudConfig.anonKey)
    }

    func url(_ method: String, bucket: String, key: String, query: [String: String] = [:], token: String,
             date: Date, expires: Int = 86_400) -> URL? {
        guard let host = endpoint.host else { return nil }
        let path = endpoint.path + "/" + Self.encode(bucket) + "/"
            + key.split(separator: "/", omittingEmptySubsequences: false).map { Self.encode(String($0)) }.joined(separator: "/")
        let stamp = Self.stamp(date)
        let day = String(stamp.prefix(8))
        let scope = "\(day)/\(region)/s3/aws4_request"
        var items = query
        items["X-Amz-Algorithm"] = "AWS4-HMAC-SHA256"
        items["X-Amz-Credential"] = "\(accessKey)/\(scope)"
        items["X-Amz-Date"] = stamp
        items["X-Amz-Expires"] = String(expires)
        items["X-Amz-Security-Token"] = token
        items["X-Amz-SignedHeaders"] = "host"
        let canonicalQuery = items.map { (Self.encode($0.key), Self.encode($0.value)) }
            .sorted { $0.0 < $1.0 }
            .map { "\($0.0)=\($0.1)" }
            .joined(separator: "&")
        let canonical = [method, path, canonicalQuery, "host:\(host)\n", "host", "UNSIGNED-PAYLOAD"].joined(separator: "\n")
        let toSign = ["AWS4-HMAC-SHA256", stamp, scope, Self.hex(SHA256.hash(data: Data(canonical.utf8)))].joined(separator: "\n")
        var signingKey = Self.hmac(Data("AWS4\(secret)".utf8), day)
        for part in [region, "s3", "aws4_request"] { signingKey = Self.hmac(signingKey, part) }
        let signature = Self.hmac(signingKey, toSign).map { String(format: "%02x", $0) }.joined()

        var components = URLComponents()
        components.scheme = endpoint.scheme
        components.host = host
        components.port = endpoint.port
        components.percentEncodedPath = path
        components.percentEncodedQuery = canonicalQuery + "&X-Amz-Signature=" + signature
        return components.url
    }

    private static func hmac(_ key: Data, _ text: String) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: Data(text.utf8), using: SymmetricKey(data: key)))
    }

    private static func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func encode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? text
    }

    /// "20261125T091500Z".
    static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }
}
