#if DEBUG
import SwiftUI

// Debug screens for Snapreel Pro (ids under pro., account., share.link. and insights.): every
// new screen and state, on sample data, with no network, no purchases and no system prompts.
// `CloudFixtures` signs in a sample account, gives the sample recordings share links, and
// answers the API from `CloudStub`.

extension DebugCatalog {
    static var proScreens: [DebugScreen] {
        let ids = FixtureStorage.IDs.self
        return [
            // MARK: Paywall
            DebugScreen("pro.paywall", "Snapreel Pro paywall") {
                ProDebugHost(.free) { paywall(.settings) }
            },
            DebugScreen("pro.paywall.end", "Snapreel Pro paywall [fine print and links]", wait: 4, settle: .scroll(1)) {
                ProDebugHost(.free) { paywall(.settings) }
            },
            DebugScreen("pro.paywall.monthly", "Snapreel Pro paywall [monthly chosen]") {
                ProDebugHost(.free) { paywall(.settings, selected: CloudConfig.monthlyProductID) }
            },
            DebugScreen("pro.paywall.duration", "Snapreel Pro paywall [recording over 5 minutes]") {
                ProDebugHost(.free) { paywall(.duration(555)) }
            },
            DebugScreen("pro.paywall.links", "Snapreel Pro paywall [26th link]") {
                ProDebugHost(.free) { paywall(.links) }
            },
            DebugScreen("pro.paywall.feature", "Snapreel Pro paywall [Pro-only setting]") {
                ProDebugHost(.free) { paywall(.feature(.password)) }
            },
            DebugScreen("pro.paywall.signedout", "Snapreel Pro paywall [signed out]") {
                ProDebugHost(.signedOut) { paywall(.settings) }
            },
            DebugScreen("pro.paywall.welcome", "Snapreel Pro paywall [just subscribed]") {
                ProDebugHost(.pro) { paywall(.settings, outcome: .purchased) }
            },
            DebugScreen("pro.paywall.active", "Snapreel Pro paywall [already Pro]") {
                ProDebugHost(.pro) { paywall(.settings) }
            },
            DebugScreen("pro.settings", "Settings with the Pro row [Free]") {
                ProDebugHost(.free) { SettingsDebugHost(path: []) }
            },

            // MARK: Account
            DebugScreen("account.signin", "Sign in [Copy link, first time]") {
                ProDebugHost(.signedOut) { SignInSheet(reason: .link, onDone: { _ in }) }
            },
            DebugScreen("account.signin.typed", "Sign in [email typed]") {
                ProDebugHost(.signedOut) { SignInSheet(reason: .link, email: "sam@example.com", onDone: { _ in }) }
            },
            DebugScreen("account.signin.sending", "Sign in [sending the code]") {
                ProDebugHost(.signedOut) {
                    SignInSheet(reason: .link, email: "sam@example.com", isWorking: true, onDone: { _ in })
                }
            },
            DebugScreen("account.signin.code", "Sign in [enter the code]") {
                ProDebugHost(.signedOut) {
                    SignInSheet(reason: .link, step: .code, email: "sam@example.com", code: "4829", onDone: { _ in })
                }
            },
            DebugScreen("account.signin.error", "Sign in [wrong code]") {
                ProDebugHost(.signedOut) {
                    SignInSheet(reason: .link, step: .code, email: "sam@example.com", code: "482913",
                                error: "That code didn't work. Check it, or send a new one.", onDone: { _ in })
                }
            },
            DebugScreen("account.signin.subscribe", "Sign in [before subscribing]") {
                ProDebugHost(.signedOut) { SignInSheet(reason: .subscribe, onDone: { _ in }) }
            },
            DebugScreen("account.signin.returning", "Sign in [I already have an account]") {
                ProDebugHost(.signedOut) { SignInSheet(reason: .account, onDone: { _ in }) }
            },
            DebugScreen("account.welcome", "Welcome [I already have an account]", fixture: .fresh, wait: 2.5) {
                ProDebugHost(.signedOut, links: false) { OnboardingFlow(onFinish: {}) }
            },
            DebugScreen("account.settings", "Settings [signed in, Free]") {
                ProDebugHost(.free) { SettingsDebugHost(path: []) }
            },
            DebugScreen("account.settings.pro", "Settings [signed in, Pro]") {
                ProDebugHost(.pro) { SettingsDebugHost(path: []) }
            },
            DebugScreen("account.page", "Account [Free]") {
                ProDebugHost(.free) { SettingsDebugHost(path: [.account]) }
            },
            DebugScreen("account.page.pro", "Account [Pro]") {
                ProDebugHost(.pro) { SettingsDebugHost(path: [.account]) }
            },
            DebugScreen("account.page.end", "Account [sign out and delete]", wait: 4, settle: .scroll(1)) {
                ProDebugHost(.free) { SettingsDebugHost(path: [.account]) }
            },
            DebugScreen("account.page.signedout", "Account [signed out]") {
                ProDebugHost(.signedOut) { SettingsDebugHost(path: [.account]) }
            },
            DebugScreen("account.delete", "Delete account [itemised confirm]") {
                ProDebugHost(.pro) { DeleteAccountSheet(initialStep: .confirm, onClose: {}) }
            },
            DebugScreen("account.delete.end", "Delete account [subscription and confirm]", wait: 4, settle: .scroll(1)) {
                ProDebugHost(.pro) { DeleteAccountSheet(initialStep: .confirm, onClose: {}) }
            },
            DebugScreen("account.delete.deleting", "Delete account [deleting]") {
                ProDebugHost(.pro) { DeleteAccountSheet(initialStep: .deleting, onClose: {}) }
            },
            DebugScreen("account.delete.done", "Delete account [deleted]") {
                ProDebugHost(.signedOut) { DeleteAccountSheet(initialStep: .done, onClose: {}) }
            },

            // MARK: Share links
            DebugScreen("share.link.player", "Player [shared, Copy link]") {
                ProDebugHost(.pro) { player(ids.checkout) { $0.position = 4 } }
            },
            DebugScreen("share.link.creating", "Share link [creating]", wait: 4) {
                ProDebugHost(.free, states: [ids.untitled: .creating],
                             present: { ProPresenter.shareLink(ids.untitled) }) {
                    player(ids.untitled) { $0.position = 3 }
                }
            },
            DebugScreen("share.link.preparing", "Share link [preparing the video]", wait: 4) {
                ProDebugHost(.free, states: [ids.onboardingFeedback: .preparing],
                             present: { ProPresenter.shareLink(ids.onboardingFeedback) }) {
                    player(ids.onboardingFeedback) { $0.position = 3 }
                }
            },
            DebugScreen("share.link.uploading", "Share link [uploading]", wait: 4) {
                ProDebugHost(.free, present: { ProPresenter.shareLink(ids.onboardingFeedback) }) {
                    player(ids.onboardingFeedback) { $0.position = 3 }
                }
            },
            DebugScreen("share.link.ready", "Share link [ready, copied]", wait: 4) {
                ProDebugHost(.pro, present: { ProPresenter.shareLink(ids.checkout) }) {
                    player(ids.checkout) { $0.position = 4 }
                }
            },
            DebugScreen("share.link.offline", "Share link [waiting for network]", wait: 4) {
                ProDebugHost(.free, states: [ids.onboardingFeedback: .waitingForNetwork(0.38)],
                             present: { ProPresenter.shareLink(ids.onboardingFeedback) }) {
                    player(ids.onboardingFeedback) { $0.position = 3 }
                }
            },
            DebugScreen("share.link.failed", "Share link [failed, try again]", wait: 4) {
                ProDebugHost(.free, present: { ProPresenter.shareLink(ids.weeklyUpdate) }) {
                    player(ids.weeklyUpdate) { $0.position = 3 }
                }
            },
            DebugScreen("share.link.unavailable", "Share link [not switched on in this build]", wait: 4) {
                ProDebugHost(.free, states: [ids.untitled: .failed(CloudError.notConfigured.message)],
                             present: { ProPresenter.shareLink(ids.untitled) }) {
                    player(ids.untitled) { $0.position = 3 }
                }
            },
            DebugScreen("share.link.settings", "Link settings [Pro]") {
                ProDebugHost(.pro) { SettingsDebugHost(path: [.account, .sharedLinks, .linkSettings(ids.checkout)]) }
            },
            DebugScreen("share.link.settings.end", "Link settings [button and stop sharing]", wait: 4, settle: .scroll(1)) {
                ProDebugHost(.pro) { SettingsDebugHost(path: [.account, .sharedLinks, .linkSettings(ids.checkout)]) }
            },
            DebugScreen("share.link.settings.free", "Link settings [Free, Pro rows marked]") {
                ProDebugHost(.free) { SettingsDebugHost(path: [.account, .sharedLinks, .linkSettings(ids.mapBug)]) }
            },
            DebugScreen("share.link.uploads", "Shared links and uploads") {
                ProDebugHost(.free) { SettingsDebugHost(path: [.account, .sharedLinks]) }
            },
            DebugScreen("share.link.uploads.empty", "Shared links [none yet]") {
                ProDebugHost(.free, links: false) { SettingsDebugHost(path: [.account, .sharedLinks]) }
            },
            DebugScreen("share.link.library", "Library [shared badges]") {
                ProDebugHost(.pro) {
                    DebugShellHost(tab: .library, configure: { _, _ in BrowseIntent.shared.libraryTab = .videos })
                }
            },
            DebugScreen("share.link.actions", "Library actions [Copy link]") {
                ProDebugHost(.pro) {
                    DebugShellHost(tab: .library, configure: { _, _ in
                        BrowseIntent.shared.libraryTab = .videos
                        BrowseIntent.shared.librarySheet = .video(.actions(ids.checkout))
                    })
                }
            },
            DebugScreen("share.link.review", "Review after recording [Copy link]") {
                ProDebugHost(.free) { RecordDebug.recorder(.screen) { $0.stage = .review(ids.untitled) } }
            },
            DebugScreen("share.link.menu", "Player actions [Copy link, Link settings]") {
                ProDebugHost(.pro) { player(ids.checkout) { $0.position = 4; $0.sheet = .actions(confirmingDelete: false) } }
            },
            DebugScreen("share.link.comments", "Comments tab") {
                ProDebugHost(.pro) {
                    player(ids.checkout) {
                        $0.position = 4
                        $0.panel = .comments
                        $0.scrollsToPanel = true
                        $0.activity = CloudFixtures.checkoutActivity
                    }
                }
            },
            DebugScreen("share.link.comments.empty", "Comments tab [none yet]") {
                ProDebugHost(.free) {
                    player(ids.launchMemo) {
                        $0.position = 4
                        $0.panel = .comments
                        $0.scrollsToPanel = true
                        $0.activity = .empty
                    }
                }
            },
            DebugScreen("share.link.timeline", "Player [viewers' reactions on the timeline]") {
                ProDebugHost(.pro) {
                    player(ids.checkout) {
                        $0.position = 52
                        $0.activity = CloudFixtures.checkoutActivity
                    }
                }
            },
            .shell("share.link.feed", "Notifications [viewers, comments and uploads]", tab: .notifications) { _, library in
                CloudFixtures.install(.pro, library: library)
                CloudFixtures.addFeed(to: library)
            },
            DebugScreen("share.link.notifications", "Notification settings [share links]", wait: 4, settle: .scroll(0.75)) {
                ProDebugHost(.free) { SettingsDebugHost(path: [.notifications]) }
            },

            // MARK: Insights
            DebugScreen("insights.pro", "Stats [shared, Pro insights]") {
                ProDebugHost(.pro) { player(ids.checkout) { $0.position = 4; $0.sheet = .stats } }
            },
            DebugScreen("insights.pro.viewers", "Stats [who watched]", wait: 4, settle: .scroll(0.55)) {
                ProDebugHost(.pro) { player(ids.checkout) { $0.position = 4; $0.sheet = .stats } }
            },
            DebugScreen("insights.free", "Stats [shared, Free with upsell]") {
                ProDebugHost(.free) { player(ids.mapBug) { $0.position = 4; $0.sheet = .stats } }
            },
            DebugScreen("insights.empty", "Stats [shared, no views yet]") {
                ProDebugHost(.free) { player(ids.launchMemo) { $0.position = 4; $0.sheet = .stats } }
            },
        ]
    }

    /// The paywall as its sheet shows it.
    @MainActor
    private static func paywall(_ reason: PaywallReason, selected: String = CloudConfig.yearlyProductID,
                                outcome: PaywallView.Outcome = .none) -> some View {
        NavigationStack {
            PaywallView(reason: reason, selected: selected, outcome: outcome, onClose: {})
        }
    }

    /// The player in a paused state, as the shell presents it.
    @MainActor
    private static func player(_ videoID: UUID, _ change: @escaping (inout PlayerInitialState) -> Void) -> some View {
        WatchDebugHost(videoID: videoID, prepare: { _ in }, initial: { _ in
            var state = PlayerInitialState()
            state.autoplay = false
            change(&state)
            return state
        })
    }
}

/// Installs a cloud scenario once, then shows `content`; optionally presents a Pro sheet over it.
struct ProDebugHost<Content: View>: View {
    let scenario: CloudFixtures.Scenario
    var links = true
    var states: [UUID: LinkState] = [:]
    var present: (@MainActor () -> Void)? = nil
    let content: @MainActor () -> Content

    @EnvironmentObject private var library: Library
    @State private var installed = false

    init(_ scenario: CloudFixtures.Scenario, links: Bool = true, states: [UUID: LinkState] = [:],
         present: (@MainActor () -> Void)? = nil, @ViewBuilder content: @escaping @MainActor () -> Content) {
        self.scenario = scenario
        self.links = links
        self.states = states
        self.present = present
        self.content = content
    }

    var body: some View {
        ZStack {
            Color.srCanvas.ignoresSafeArea()
            if installed { content() }
        }
        .onAppear {
            guard !installed else { return }
            CloudFixtures.install(scenario, library: library, links: links)
            for (id, state) in states { ShareLinks.shared.debugStates[id] = state }
            installed = true
            if let present {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 900_000_000)
                    present()
                }
            }
        }
    }
}

/// Sample account, links, insights and comments for the debug screens.
@MainActor
enum CloudFixtures {
    enum Scenario {
        case signedOut
        case free
        case pro
    }

    private static let userID = "5f0c2a1e-7b3d-4c8e-9a61-2d4f8b0e3c17"
    private static var now: Date { Date() }

    static func install(_ scenario: Scenario, library: Library, links: Bool = true) {
        let me: CloudMe? = scenario == .signedOut ? nil : Self.me(pro: scenario == .pro, links: links ? 5 : 0)
        AuthService.shared.debugInstall(me: me)
        PurchaseService.shared.debugPlans = [
            ProPlan(id: CloudConfig.yearlyProductID, period: .year, displayPrice: "$39.99", trialDays: 7,
                    perMonth: "$3.33 a month", isPurchasable: true),
            ProPlan(id: CloudConfig.monthlyProductID, period: .month, displayPrice: "$5.99", trialDays: nil,
                    perMonth: nil, isPurchasable: true),
        ]
        PurchaseService.shared.debugSetActive(scenario == .pro ? CloudConfig.yearlyProductID : nil,
                                              expiry: scenario == .pro ? now.addingTimeInterval(86_400 * 290) : nil)
        APIClient.shared.stub = CloudStub(pro: scenario == .pro)
        guard links, scenario != .signedOut else { return }
        for link in sampleLinks { library.saveLink(link) }
        Uploader.shared.debugPhases = [
            FixtureStorage.IDs.onboardingFeedback: .uploading(0.64),
            FixtureStorage.IDs.weeklyUpdate: .failed("The connection dropped too many times. What was sent is kept: try again on Wi-Fi."),
        ]
    }

    static func me(pro: Bool, links: Int) -> CloudMe {
        CloudMe(user: CloudUser(id: userID, email: "sam@example.com", displayName: "Sam Rivera"),
                plan: CloudPlan(tier: pro ? .pro : .free,
                                productId: pro ? CloudConfig.yearlyProductID : nil,
                                expiresAt: pro ? now.addingTimeInterval(86_400 * 290) : nil),
                usage: CloudUsage(activeLinks: links, linkLimit: pro ? nil : CloudConfig.freeLinkLimit,
                                  maxDurationS: pro ? CloudConfig.proMaxDuration : CloudConfig.freeMaxDuration,
                                  quality: pro ? "1080p" : "720p"))
    }

    // MARK: Links

    private struct Sample {
        let videoID: UUID
        let slug: String
        let title: String
        let kind: CloudVideoKind
        let duration: Double
        let status: CloudVideoStatus
        let views: Int
        let viewers: Int
        let comments: Int
        let minutesAgo: Double
    }

    private static let samples: [Sample] = [
        Sample(videoID: FixtureStorage.IDs.checkout, slug: "k7Qm2xRb9L", title: "Checkout flow walkthrough",
               kind: .screen, duration: 125, status: .ready, views: 128, viewers: 64, comments: 5, minutesAgo: 118),
        Sample(videoID: FixtureStorage.IDs.mapBug, slug: "Wp3dN8vYc2", title: "Bug: map pins jump on zoom",
               kind: .screen, duration: 48, status: .ready, views: 9, viewers: 6, comments: 1, minutesAgo: 60 * 25),
        Sample(videoID: FixtureStorage.IDs.onboardingFeedback, slug: "Hs5tLq0Za8", title: "Feedback on the onboarding copy",
               kind: .camera, duration: 192, status: .uploading, views: 0, viewers: 0, comments: 0, minutesAgo: 6),
        Sample(videoID: FixtureStorage.IDs.weeklyUpdate, slug: "Rb6cJ1mXe4", title: "Weekly update, week 47",
               kind: .camera, duration: 280, status: .uploading, views: 0, viewers: 0, comments: 0, minutesAgo: 30),
        Sample(videoID: FixtureStorage.IDs.launchMemo, slug: "Tg9fV2nKw7", title: "Launch plan, voice memo",
               kind: .audio, duration: 96, status: .ready, views: 0, viewers: 0, comments: 0, minutesAgo: 60 * 70),
    ]

    private static func summary(_ sample: Sample) -> VideoSummary {
        VideoSummary(id: "srv-\(sample.slug)", slug: sample.slug, url: "https://snapreel.video/v/\(sample.slug)",
                     localId: sample.videoID.uuidString.lowercased(), title: sample.title, kind: sample.kind,
                     durationS: sample.duration, status: sample.status, posterUrl: nil,
                     createdAt: now.addingTimeInterval(-sample.minutesAgo * 60), views: sample.views,
                     uniqueViewers: sample.viewers,
                     lastViewedAt: sample.views > 0 ? now.addingTimeInterval(-12 * 60) : nil,
                     commentCount: sample.comments)
    }

    static func detail(for serverID: String, pro: Bool) -> VideoDetail? {
        guard let sample = samples.first(where: { "srv-\($0.slug)" == serverID }) else { return nil }
        let summary = self.summary(sample)
        let isCheckout = sample.videoID == FixtureStorage.IDs.checkout
        return VideoDetail(id: summary.id, slug: summary.slug, url: summary.url, localId: summary.localId,
                           title: summary.title, kind: summary.kind, durationS: summary.durationS,
                           status: summary.status, posterUrl: nil, createdAt: summary.createdAt,
                           views: summary.views, uniqueViewers: summary.uniqueViewers,
                           lastViewedAt: summary.lastViewedAt, commentCount: summary.commentCount,
                           access: pro && isCheckout ? .password : .link, hasPassword: pro && isCheckout,
                           expiresAt: nil, allowDownload: pro && isCheckout, allowComments: true,
                           allowReactions: true,
                           cta: pro && isCheckout ? CallToAction(label: "Book a demo", url: "https://example.com/demo") : nil,
                           width: 886, height: 1920, sizeBytes: 38_400_000)
    }

    static var summaries: [VideoSummary] { samples.map(summary) }

    private static var sampleLinks: [CloudLink] {
        samples.map { sample in
            var link = CloudLink(videoID: sample.videoID, summary: summary(sample))
            link.detail = detail(for: link.serverID, pro: AuthService.shared.isPro)
            return link
        }
    }

    // MARK: Insights

    static func insights(for serverID: String, pro: Bool) -> CloudInsights {
        guard let sample = samples.first(where: { "srv-\($0.slug)" == serverID }) else {
            return CloudInsights(views: 0, uniqueViewers: 0)
        }
        guard pro, sample.views > 0 else {
            return CloudInsights(views: sample.views, uniqueViewers: sample.viewers)
        }
        // A realistic curve: most stay for the intro, a dip at the coupon bug, a tail to the end.
        let dropoff = (0..<100).map { index -> Int in
            let x = Double(index) / 99
            let base = 64 * (1 - 0.55 * x) - 6 * exp(-pow((x - 0.36) * 9, 2))
            return max(20, Int(base.rounded()))
        }
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        let viewers: [CloudViewer] = [
            CloudViewer(name: "Priya Shah", anonymous: false, country: "GB", device: .phone,
                        firstSeenAt: ago(25), lastSeenAt: ago(12), percent: 100),
            CloudViewer(name: nil, anonymous: true, country: "US", device: .desktop,
                        firstSeenAt: ago(70), lastSeenAt: ago(64), percent: 64),
            CloudViewer(name: "Tom Becker", anonymous: false, country: "DE", device: .desktop,
                        firstSeenAt: ago(130), lastSeenAt: ago(122), percent: 88),
            CloudViewer(name: "Lena Vos", anonymous: false, country: "NL", device: .tablet,
                        firstSeenAt: ago(190), lastSeenAt: ago(181), percent: 100),
            CloudViewer(name: nil, anonymous: true, country: "GB", device: .phone,
                        firstSeenAt: ago(240), lastSeenAt: ago(239), percent: 23),
            CloudViewer(name: "Marcus Hill", anonymous: false, country: "US", device: .desktop,
                        firstSeenAt: ago(300), lastSeenAt: ago(296), percent: 51),
            CloudViewer(name: "Aoife Byrne", anonymous: false, country: "IE", device: .desktop,
                        firstSeenAt: ago(420), lastSeenAt: ago(415), percent: 96),
            CloudViewer(name: nil, anonymous: true, country: "CA", device: .phone,
                        firstSeenAt: ago(600), lastSeenAt: ago(599), percent: 9),
        ]
        return CloudInsights(views: sample.views, uniqueViewers: sample.viewers, avgPercent: 72,
                             completionRate: 0.41, dropoff: dropoff,
                             countries: [CloudCountryCount(code: "GB", count: 28), CloudCountryCount(code: "US", count: 19),
                                         CloudCountryCount(code: "DE", count: 7), CloudCountryCount(code: "NL", count: 4),
                                         CloudCountryCount(code: "IE", count: 3), CloudCountryCount(code: "CA", count: 3)],
                             viewers: viewers)
    }

    // MARK: Comments and reactions

    static var checkoutActivity: CloudActivity {
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        let comments = [
            CloudComment(id: "c1", authorName: "Priya Shah", isOwner: false,
                         body: "The total still shows £42 after I remove the coupon, same as in your video.",
                         atS: 14, parentId: nil, createdAt: ago(25)),
            CloudComment(id: "c2", authorName: "Tom Becker", isOwner: false,
                         body: "Autocomplete is so much quicker now 🙌", atS: 41, parentId: nil, createdAt: ago(122)),
            CloudComment(id: "c3", authorName: "Sam Rivera", isOwner: true,
                         body: "Thanks! It ships on Thursday.", atS: nil, parentId: "c2", createdAt: ago(95)),
            CloudComment(id: "c4", authorName: "Lena Vos", isOwner: false,
                         body: "+1 for Apple Pay first. Most of our checkouts happen on iPhone.",
                         atS: 82, parentId: nil, createdAt: ago(181)),
            CloudComment(id: "c5", authorName: "Marcus Hill", isOwner: false,
                         body: "Could you send me the staging link too?", atS: nil, parentId: nil, createdAt: ago(296)),
        ]
        let reactions: [(String, Double)] = [("🔥", 9), ("👍", 20), ("🔥", 33), ("👍", 41), ("❤️", 52), ("🔥", 65),
                                             ("😮", 70), ("👍", 88), ("👏", 110), ("👏", 118)]
        return CloudActivity(comments: comments, reactions: reactions.enumerated().map { index, item in
            CloudReaction(id: "r\(index)", emoji: item.0, atS: item.1, authorName: nil, createdAt: ago(Double(20 + index * 15)))
        })
    }

    // MARK: Notifications feed

    static func addFeed(to library: Library) {
        func ago(_ minutes: Double) -> Date { Date().addingTimeInterval(-minutes * 60) }
        let items: [(NotificationKind, UUID, String, String, Double, Bool)] = [
            (.newComment, FixtureStorage.IDs.checkout, "Priya commented on \u{201C}Checkout flow walkthrough\u{201D}",
             "\u{201C}The total still shows £42 after I remove the coupon…\u{201D}", 1, false),
            (.newViewer, FixtureStorage.IDs.checkout, "Priya Shah watched \u{201C}Checkout flow walkthrough\u{201D}",
             "Watched all of it, on an iPhone in the United Kingdom.", 2, false),
            (.uploadFinished, FixtureStorage.IDs.mapBug, "Your link is ready",
             "\u{201C}Bug: map pins jump on zoom\u{201D} can be watched now.", 50, false),
            (.uploadFailed, FixtureStorage.IDs.weeklyUpdate, "Upload stopped",
             "\u{201C}Weekly update, week 47\u{201D}: the connection dropped. Tap to try again.", 28, true),
            (.newViewer, FixtureStorage.IDs.mapBug, "Someone watched \u{201C}Bug: map pins jump on zoom\u{201D}",
             "Watched 88%, on a computer in Germany.", 120, true),
        ]
        for (kind, video, title, body, minutes, read) in items {
            library.appendNotification(AppNotification(kind: kind, videoID: video, title: title, body: body,
                                                       createdAt: ago(minutes), isRead: read))
        }
    }
}

/// Answers the owner API in debug screens, from `CloudFixtures`.
@MainActor
final class CloudStub {
    let pro: Bool

    init(pro: Bool) {
        self.pro = pro
    }

    func answer(_ method: String, _ path: String) throws -> Data {
        let parts = path.split(separator: "/").map(String.init)
        let encoder = CloudJSON.encoder
        switch (method, parts.first ?? "", parts.count) {
        case ("GET", "me", _), ("PATCH", "me", _):
            return try encoder.encode(CloudFixtures.me(pro: pro, links: 5))
        case ("GET", "videos", 1):
            return try encoder.encode(CloudFixtures.summaries)
        case ("GET", "videos", 2), ("PATCH", "videos", 2):
            guard let detail = CloudFixtures.detail(for: parts[1], pro: pro) else { throw CloudError.notFound }
            return try encoder.encode(detail)
        case ("GET", "videos", 3) where parts[2] == "insights":
            return try encoder.encode(CloudFixtures.insights(for: parts[1], pro: pro))
        case ("GET", "videos", 3) where parts[2] == "activity":
            let isCheckout = parts[1] == "srv-k7Qm2xRb9L"
            return try encoder.encode(isCheckout ? CloudFixtures.checkoutActivity : CloudActivity.empty)
        case ("POST", "purchases", _):
            return try encoder.encode(VerifyPurchaseResponse(plan: CloudFixtures.me(pro: true, links: 5).plan))
        case ("DELETE", _, _), ("POST", "blocks", _), ("POST", "devices", _), ("POST", "account", _):
            return Data()
        default:
            throw CloudError.offline
        }
    }
}
#endif
