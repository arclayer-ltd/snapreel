import SwiftUI

/// Places inside the Settings sheet, pushed by value so Settings can open at any of them
/// (`SettingsView(initialPath:)`). Other sessions' pages (notifications, recording, storage)
/// are listed here too.
enum SettingsPage: Hashable {
    case notifications
    case recording
    case appearance
    case storage
    case help
    case helpArticle(String)
    /// Contact support, optionally with a topic already chosen.
    case contact(SupportTopic?)
    case legal
    case legalDocument(LegalDocument)
    case acknowledgements
    // Snapreel Pro
    case account
    case sharedLinks
    case linkSettings(UUID)
}

extension View {
    /// Registers every `SettingsPage` destination on a NavigationStack.
    func settingsDestinations() -> some View {
        navigationDestination(for: SettingsPage.self) { page in
            SettingsDestination(page: page)
        }
    }
}

/// Maps a settings page to the view that owns it.
struct SettingsDestination: View {
    let page: SettingsPage

    var body: some View {
        switch page {
        case .notifications: NotificationSettingsView()
        case .recording: RecordingDefaultsView()
        case .appearance: AppearanceView()
        case .storage: StorageView()
        case .help: HelpCenterView()
        case .helpArticle(let id): HelpArticleView(articleID: id)
        case .contact(let topic): ContactSupportView(initialTopic: topic)
        case .legal: LegalMenuView()
        case .legalDocument(let document): LegalDocumentView(document: document)
        case .acknowledgements: AcknowledgementsView()
        case .account: AccountView()
        case .sharedLinks: SharedLinksView()
        case .linkSettings(let id): LinkSettingsView(videoID: id)
        }
    }
}

/// Settings root, presented as a sheet from the gear on every tab: your account and Snapreel
/// Pro, preferences, help and support, legal, and the app's version.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var library: Library
    @ObservedObject private var auth = AuthService.shared
    @ObservedObject private var links = ShareLinks.shared
    @ObservedObject private var uploader = Uploader.shared
    @State private var path: [SettingsPage]

    init(initialPath: [SettingsPage] = []) {
        _path = State(initialValue: initialPath)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    account
                    preferences
                    support
                    about
                    SettingsFooter()
                }
                .padding(.horizontal, Space.gutter)
                .padding(.top, Space.s)
                .padding(.bottom, Space.xxl)
            }
            .background(Color.srCanvas.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            // The plan may have changed since it was last read (on the web, on another iPhone).
            .task { await auth.refreshMe() }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { close() }
                        .font(.srHeadline)
                }
            }
            .settingsDestinations()
        }
        .tint(Color.srRed)
    }

    // MARK: Groups

    /// Signed in: you, your plan and your links. Signed out: sign in, and what Pro is.
    private var account: some View {
        SettingsGroup(title: "Account") {
            NavigationLink(value: SettingsPage.account) {
                accountRow
                    .padding(.horizontal, Space.m)
                    .padding(.vertical, 3)
            }
            .buttonStyle(SettingsRowStyle())
            SettingsDivider()
            SettingsActionRow(systemImage: "sparkles", title: "Snapreel Pro",
                              value: auth.isPro ? "Active" : "Try it free", showsChevron: true) {
                ProPresenter.paywall(.settings)
            }
            if auth.isSignedIn {
                SettingsDivider()
                SettingsLinkRow(page: .sharedLinks, systemImage: "link", title: "Shared links",
                                value: sharedLinksValue)
            }
        }
    }

    private var accountRow: some View {
        HStack(spacing: Space.s) {
            if auth.isSignedIn {
                AccountAvatar(name: auth.displayName, size: 32)
            } else {
                IconTile(systemName: "person.crop.circle.fill")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(auth.isSignedIn ? auth.displayName : "Sign in")
                    .font(.srBody)
                    .foregroundStyle(Color.srText)
                    .lineLimit(1)
                Text(auth.isSignedIn ? (auth.email ?? "Signed in") : "Share links and see who watched")
                    .font(.srFootnote)
                    .foregroundStyle(Color.srTextSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: Space.xs)
            if auth.isSignedIn {
                if auth.isPro {
                    ProBadge()
                } else {
                    Text("Free")
                        .font(.srSubheadline)
                        .foregroundStyle(Color.srTextTertiary)
                }
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.srTextTertiary)
        }
        .padding(.vertical, Space.xs)
        .contentShape(Rectangle())
    }

    /// "Uploading 45%", "Upload stopped" or the number of links.
    private var sharedLinksValue: String {
        var stopped = false
        var uploading: Double?
        for id in uploader.jobs.keys {
            switch links.state(for: id) {
            case .failed: stopped = true
            case .uploading(let value): uploading = uploading ?? value
            default: break
            }
        }
        if stopped { return "Upload stopped" }
        if let uploading { return "Uploading \(Int((uploading * 100).rounded()))%" }
        return library.links.isEmpty ? "None" : "\(library.links.count)"
    }

    private var preferences: some View {
        SettingsGroup(title: "Preferences") {
            SettingsLinkRow(page: .notifications, systemImage: "bell.fill", title: "Notifications",
                            value: notificationSummary)
            SettingsDivider()
            SettingsLinkRow(page: .recording, systemImage: "video.fill", title: "Recording",
                            value: settings.recordingQuality.label)
            SettingsDivider()
            SettingsLinkRow(page: .appearance, systemImage: "circle.lefthalf.filled", title: "Appearance",
                            value: settings.appearance.label)
            SettingsDivider()
            SettingsLinkRow(page: .storage, systemImage: "internaldrive.fill", title: "Storage",
                            value: Format.bytes(library.totalVideoBytes))
        }
    }

    private var support: some View {
        SettingsGroup(title: "Help") {
            SettingsLinkRow(page: .help, systemImage: "questionmark.circle.fill", title: "Help centre")
            SettingsDivider()
            SettingsLinkRow(page: .contact(nil), systemImage: "envelope.fill", title: "Contact support")
            SettingsDivider()
            SettingsActionRow(systemImage: "hand.wave.fill", title: "Take the tour again") {
                replayTour()
            }
        }
    }

    private var about: some View {
        SettingsGroup(title: "About") {
            SettingsLinkRow(page: .legal, systemImage: "doc.text.fill", title: "Legal")
        }
    }

    /// "All on", "3 of 5 on" or "Off".
    private var notificationSummary: String {
        let total = NotificationKind.allCases.count
        let enabled = NotificationKind.allCases.filter { settings.isNotificationEnabled($0) }.count
        if enabled == total { return "All on" }
        if enabled == 0 { return "Off" }
        return "\(enabled) of \(total) on"
    }

    /// Presented through UIKit (`SettingsSheet`); elsewhere (screenshots) the usual way.
    private func close() {
        if SettingsSheet.shared.isPresented {
            SettingsSheet.shared.isPresented = false
        } else {
            dismiss()
        }
    }

    /// Closes Settings, then shows the guided tour over the tabs again.
    private func replayTour() {
        close()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            withAnimation(Motion.standard) { settings.hasCompletedTour = false }
        }
    }
}

// MARK: - Building blocks

/// A titled white card holding rows. Put `SettingsDivider()` between rows.
struct SettingsGroup<Content: View>: View {
    var title: String?
    var footnote: String?
    let content: Content

    init(title: String? = nil, footnote: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footnote = footnote
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if let title {
                Text(title.uppercased())
                    .font(.srCaption)
                    .kerning(0.6)
                    .foregroundStyle(Color.srTextTertiary)
                    .padding(.horizontal, Space.xxs)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) {
                content
            }
            .srCard()
            .clipShape(RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
            if let footnote {
                Text(footnote)
                    .font(.srFootnote)
                    .foregroundStyle(Color.srTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Space.xxs)
            }
        }
    }
}

/// Hairline between rows, inset past the icon tile.
struct SettingsDivider: View {
    var inset: CGFloat = Space.m + 32 + Space.s

    var body: some View {
        Rectangle()
            .fill(Color.srLine)
            .frame(height: 0.5)
            .padding(.leading, inset)
    }
}

/// A row that pushes a settings page.
struct SettingsLinkRow: View {
    let page: SettingsPage
    let systemImage: String
    let title: String
    var value: String? = nil

    var body: some View {
        NavigationLink(value: page) {
            ListRow(systemImage: systemImage, title: title, value: value)
                .padding(.horizontal, Space.m)
                .padding(.vertical, 3)
        }
        .buttonStyle(SettingsRowStyle())
    }
}

/// A row that runs an action instead of pushing a page.
struct SettingsActionRow: View {
    let systemImage: String
    let title: String
    var value: String? = nil
    /// For a row that opens a page of its own (Snapreel Pro).
    var showsChevron = false
    let action: @MainActor () -> Void

    init(systemImage: String, title: String, value: String? = nil, showsChevron: Bool = false,
         action: @escaping @MainActor () -> Void) {
        self.systemImage = systemImage
        self.title = title
        self.value = value
        self.showsChevron = showsChevron
        self.action = action
    }

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            ListRow(systemImage: systemImage, title: title, value: value, showsChevron: showsChevron)
                .padding(.horizontal, Space.m)
                .padding(.vertical, 3)
        }
        .buttonStyle(SettingsRowStyle())
    }
}

/// Grey highlight while a row is pressed.
struct SettingsRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.srFill : Color.srSurface)
            .contentShape(Rectangle())
    }
}

/// Mark, name, version and build from the bundle, and what Snapreel does with your data.
struct SettingsFooter: View {
    var body: some View {
        VStack(spacing: Space.xs) {
            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)
            Text("Snapreel")
                .font(.srHeadline)
                .foregroundStyle(Color.srText)
            Text(AppInfo.versionLine)
                .font(.srFootnote)
                .foregroundStyle(Color.srTextTertiary)
            Text("Your recordings stay on this iPhone. Only the ones you share as links are uploaded, and only while you share them.")
                .font(.srFootnote)
                .foregroundStyle(Color.srTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.xxs)
            Text("Made by \(AppInfo.publisher)")
                .font(.srCaption)
                .foregroundStyle(Color.srTextTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Space.s)
        .accessibilityElement(children: .combine)
    }
}

/// Version details read from the bundle.
enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    /// "Version 1.0 (12)"
    static var versionLine: String { "Version \(version) (\(build))" }

    static let supportEmail = "support@snapreel.video"
    /// The developer, as App Store Connect names the seller (an individual). Same as web/lib/legal-entity.ts.
    static let publisher = "Rezan Ferdous"
}
