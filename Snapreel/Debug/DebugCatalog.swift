#if DEBUG
import SwiftUI

/// Which sample data a debug screen starts with.
enum FixtureSet: String {
    /// First launch: no data, onboarding and tour not done.
    case fresh
    /// Onboarding done, no recordings.
    case empty
    /// A realistic library: recordings, folders, notes, reactions, a transcript, notifications.
    case filled
}

/// One screen in one state, reachable with the launch argument `-screen <id>`.
/// CI screenshots every entry (see scripts/ci-screenshots.sh).
struct DebugScreen: Identifiable {
    /// Stable id, also the screenshot file name. "<area>.<screen>[.<state>]", e.g. "lib.videos.empty".
    let id: String
    /// Plan name of the screen, e.g. "My videos [empty]".
    let title: String
    var fixture: FixtureSet = .filled
    /// Seconds the screenshot script waits after launch (animations, async loads).
    var wait: Double = 3
    /// Builds the view. For screens inside the tab shell use `DebugScreen.shell`.
    let content: () -> AnyView

    init<Content: View>(_ id: String, _ title: String, fixture: FixtureSet = .filled, wait: Double = 3,
                        @ViewBuilder content: @escaping () -> Content) {
        self.id = id
        self.title = title
        self.fixture = fixture
        self.wait = wait
        self.content = { AnyView(content()) }
    }

    /// The real tab shell on `tab`, after `configure` has set up the router (push routes,
    /// open the player, show a sheet...). The library already holds the fixture data.
    static func shell(_ id: String, _ title: String, tab: AppTab, fixture: FixtureSet = .filled,
                      wait: Double = 3, configure: ((AppRouter, Library) -> Void)? = nil) -> DebugScreen {
        DebugScreen(id, title, fixture: fixture, wait: wait) {
            DebugShellHost(tab: tab, configure: configure)
        }
    }
}

enum DebugCatalog {
    /// Every debug screen. Each session owns one list in its feature folder.
    static var all: [DebugScreen] {
        foundationScreens
            + startScreens      // A: Features/Onboarding, Settings, Help, Legal
            + recordScreens     // B: Features/Record
            + watchScreens      // C: Features/Player
            + browseScreens     // D: Features/Home, Library, Search
            + inboxScreens      // E: Features/Notifications, Storage, Sharing
    }

    static func screen(_ id: String) -> DebugScreen? { all.first { $0.id == id } }

    /// Written to Documents/debug-screens.tsv on `-dumpScreens`; the screenshot script reads it.
    static func writeList() {
        let lines = all.map { "\($0.id)\t\($0.wait)\t\($0.title)" }.joined(separator: "\n")
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("debug-screens.tsv")
        try? lines.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Screens that belong to the shell itself.
    static var foundationScreens: [DebugScreen] {
        [
            .shell("shell.home", "Tab shell on Home", tab: .home),
            DebugScreen("kit.components", "Component kit", fixture: .filled) { KitGallery() },
        ]
    }
}

/// Shows the requested debug screen with the fixture environment.
struct DebugHost: View {
    let screenID: String

    var body: some View {
        if let screen = DebugCatalog.screen(screenID) {
            screen.content()
        } else {
            VStack(spacing: Space.s) {
                Text("No debug screen").font(.srTitle)
                Text(screenID).font(.srFootnote).foregroundStyle(Color.srTextSecondary)
            }
        }
    }
}

/// The tab shell, configured once before it first appears.
struct DebugShellHost: View {
    let tab: AppTab
    let configure: ((AppRouter, Library) -> Void)?
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var library: Library
    @State private var configured = false

    var body: some View {
        MainShell()
            .onAppear {
                guard !configured else { return }
                configured = true
                router.tab = tab
                configure?(router, library)
            }
    }
}

/// A page showing the shared kit, for checking tokens and components in one screenshot.
struct KitGallery: View {
    @EnvironmentObject private var library: Library
    @State private var tab = 0
    @State private var mode: RecordMode = .camera

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                Text("Snapreel kit").font(.srLargeTitle)
                HStack(spacing: Space.xs) {
                    ForEach([Color.srRed, .srRedDeep, .srRedGlow, .srInk, .srInkRaised, .srCanvas, .srFill, .srLine], id: \.self) { color in
                        RoundedRectangle(cornerRadius: 6).fill(color).frame(height: 28)
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.srLine))
                    }
                }
                UnderlineTabs(tabs: [0, 1], selection: $tab, title: { $0 == 0 ? "My videos" : "Folders" })
                Button("Start a recording") {}.buttonStyle(.srPrimary)
                Button("Secondary") {}.buttonStyle(.srSecondary)
                HStack {
                    Button("Compact") {}.buttonStyle(.srPrimaryCompact)
                    Button("Tertiary") {}.buttonStyle(.srTertiary)
                    CircleIconButton(systemName: "gearshape", label: "Settings") {}
                }
                SectionHeader(title: "From my library", actionTitle: "See all", action: {})
                if let video = library.readyVideos.first {
                    VideoThumbnail(video: video)
                }
                ListRow(systemImage: "bell.fill", title: "Notifications", value: "On")
                    .padding(.horizontal, Space.m)
                    .srCard()
                PillSwitch(options: RecordMode.allCases, selection: $mode, title: { $0.label })
                    .padding()
                    .background(Color.srInk)
                ToastView(message: ToastMessage(text: "Saved to Photos"))
            }
            .padding(Space.gutter)
        }
        .background(Color.srCanvas.ignoresSafeArea())
    }
}
#endif
