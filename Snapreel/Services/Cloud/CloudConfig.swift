import Foundation

/// Where Snapreel Pro's services live, and the plan limits the app shows (the server enforces
/// its own copy of every limit; these are only for the screens). Values follow
/// `docs/pro/API.md`.
///
/// The Supabase URL and publishable key are public values. Until the backend fills them in,
/// they hold placeholders: `isConfigured` is then false, nothing reaches the network, and
/// Copy link explains that links aren't switched on in this build.
enum CloudConfig {
    // MARK: Supabase (public values)

    /// `SUPABASE_URL` from docs/pro/API.md, for example "https://abcdefghijklmnopqrst.supabase.co".
    static let supabaseURLString = "https://SUPABASE-PROJECT-REF.supabase.co"
    /// `SUPABASE_PUBLISHABLE_KEY` from docs/pro/API.md ("sb_publishable_…").
    static let publishableKey = "SUPABASE-PUBLISHABLE-KEY"

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

    /// TUS uploads go straight to Supabase Storage's own host:
    /// `https://<ref>.storage.supabase.co/storage/v1/upload/resumable`.
    static var tusURL: URL? {
        guard let host = supabaseURL?.host, let ref = host.split(separator: ".").first else { return nil }
        return URL(string: "https://\(ref).storage.supabase.co/storage/v1/upload/resumable")
    }

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

    /// TUS chunks must be exactly this size, except the last.
    static let chunkSize = 6 * 1_024 * 1_024

    /// Background upload session identifier.
    static let uploadSessionID = "co.arclayer.snapreel.uploads"
}
