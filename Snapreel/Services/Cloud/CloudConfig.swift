import Foundation

/// Where Snapreel Pro's services live, and the plan limits the app shows (the server enforces
/// its own copy of every limit; these are only for the screens). Values follow
/// `docs/pro/API.md`.
///
/// The Supabase URL and publishable key are public values (project "Snapreel", us-east-1). With
/// placeholders instead, `isConfigured` is false, nothing reaches the network, and
/// Copy link explains that links aren't switched on in this build.
enum CloudConfig {
    // MARK: Supabase (public values)

    /// `SUPABASE_URL` from docs/pro/API.md, for example "https://abcdefghijklmnopqrst.supabase.co".
    static let supabaseURLString = "https://jaajkutdglblwtpfcgag.supabase.co"
    /// `SUPABASE_PUBLISHABLE_KEY` from docs/pro/API.md ("sb_publishable_…").
    static let publishableKey = "sb_publishable_TMSX2mDy_fE7eYhJggL8hg_tMU_Eq91"
    /// The project's public `anon` key. Storage's S3 endpoint signs session-token requests with it (it doesn't take
    /// publishable keys yet: github.com/supabase/storage/issues/750). Public like the key above, and it grants
    /// nothing by itself: the session token decides what a request may touch. If Supabase ever switches it off,
    /// uploads fall back to TUS by themselves.
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImphYWprdXRkZ2xibHd0cGZjZ2FnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTUxMjk5MDQsImV4cCI6MjExMDcwNTkwNH0.YNJmE8g8pFi2OkKKmcEvCiT2rvbFFwRiaMcLe9c4QoM"
    static let s3Region = "us-east-1"

    // MARK: snapreel.video

    /// The API, watch pages and dashboard.
    static let siteURL = URL(string: "https://snapreel.video")!
    static let apiBaseURL = siteURL.appendingPathComponent("api")
    static let linkHost = "snapreel.video"

    static let termsURL = URL(string: "https://snapreel.video/terms")!
    static let privacyURL = URL(string: "https://snapreel.video/privacy")!
    static let dashboardURL = URL(string: "https://snapreel.video/app")!

    /// The bundle that pushes and purchases belong to.
    static let bundleID = "co.arclayer.snapreel"

    // MARK: Derived

    /// False while the values above are placeholders. Everything cloud-related checks this
    /// first and stays quiet instead of failing.
    static var isConfigured: Bool {
        !supabaseURLString.contains("SUPABASE-PROJECT-REF") && !publishableKey.contains("SUPABASE-PUBLISHABLE-KEY")
            && supabaseURL != nil
    }

    static var supabaseURL: URL? { URL(string: supabaseURLString) }

    /// GoTrue: `<SUPABASE_URL>/auth/v1`.
    static var authURL: URL? { supabaseURL?.appendingPathComponent("auth/v1") }

    /// The project's id, the first part of its host.
    static var projectRef: String? {
        supabaseURL?.host?.split(separator: ".").first.map(String.init)
    }

    /// Uploads go straight to Supabase Storage's own host: `https://<ref>.storage.supabase.co/storage/v1`.
    static var storageURL: URL? {
        projectRef.flatMap { URL(string: "https://\($0).storage.supabase.co/storage/v1") }
    }

    /// The fallback transport: TUS 1.0.0.
    static var tusURL: URL? { storageURL?.appendingPathComponent("upload/resumable") }

    /// Storage's S3 endpoint, for multipart uploads signed with the person's own session token.
    static var s3URL: URL? { storageURL?.appendingPathComponent("s3") }

    // MARK: Plans

    static let monthlyProductID = "co.arclayer.snapreel.pro.monthly"
    static let yearlyProductID = "co.arclayer.snapreel.pro.yearly"
    static let productIDs = [yearlyProductID, monthlyProductID]
    /// Shown while the App Store's own prices load (and in debug screenshots); the paywall
    /// uses the App Store's localised prices whenever they're available.
    static let fallbackMonthlyPrice = "$5.99"
    static let fallbackYearlyPrice = "$39.99"

    static let freeLinkLimit = 25
    static let freeMaxDuration: Double = 300
    static let proMaxDuration: Double = 7_200
    static let freeLongSide = 1_280
    static let proLongSide = 1_920
    /// The server refuses files over 2 GB.
    static let maxFileBytes: Int64 = 2 * 1_024 * 1_024 * 1_024

    /// One multipart piece: S3's smallest, so a dropped connection costs little.
    static let pieceSize: Int64 = 5 * 1_024 * 1_024
    /// Files up to this size go up in one request.
    static let singleLimit: Int64 = 6 * 1_024 * 1_024
    /// TUS chunks must be exactly this size, except the last.
    static let chunkSize = 6 * 1_024 * 1_024

    /// Background upload session identifier.
    static let uploadSessionID = "co.arclayer.snapreel.uploads"
}
