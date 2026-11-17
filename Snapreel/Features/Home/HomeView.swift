import SwiftUI
import UIKit

/// Session D owns this file. Root of the Home tab (inside the shell's NavigationStack): a
/// time-of-day greeting, Watch later and History rows, a "From my library" rail and a
/// "Recently watched" rail. With no recordings yet it leads with a first-recording panel.
struct HomeView: View {
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var router: AppRouter
    @StateObject private var actions = LibraryActionsModel()
    @State private var now = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                if failedCount > 0 { failedBanner }
                shortcuts
                if library.allVideos.isEmpty { firstRecordingPanel }
                libraryRail
                watchedRail
            }
            .padding(.top, Space.xs)
            .padding(.bottom, BrowseLayout.bottomPadding(router))
        }
        .background(Color.srCanvas.ignoresSafeArea())
        .navigationTitle(HomeGreeting.title(for: now))
        .navigationBarTitleDisplayMode(.large)
        .settingsToolbar()
        .libraryVideoActions(actions)
        .onAppear { now = Date() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            now = Date()
        }
    }

    // MARK: Shortcuts

    private var shortcuts: some View {
        VStack(spacing: 0) {
            NavigationLink(value: Route.watchLater) {
                ListRow(systemImage: "bookmark.fill", title: "Watch later", value: countText(library.watchLater.count))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Watch later, \(BrowseText.recordings(library.watchLater.count))")
            Divider().padding(.leading, 44)
            NavigationLink(value: Route.history) {
                ListRow(systemImage: "clock.fill", title: "History", value: countText(library.history.count))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("History, \(BrowseText.recordings(library.history.count))")
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.xxs)
        .srCard()
        .padding(.horizontal, Space.gutter)
    }

    private func countText(_ count: Int) -> String? {
        count > 0 ? "\(count)" : nil
    }

    // MARK: First recording

    private var firstRecordingPanel: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.xs) {
                ForEach(RecordMode.allCases) { mode in
                    modeTile(mode)
                }
            }
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Make your first recording")
                    .font(.srTitle3)
                    .foregroundStyle(Color.srText)
                Text("Show your screen, talk to the camera or just use your voice. It's kept on this iPhone, ready to send as a file whenever you like.")
                    .font(.srSubheadline)
                    .foregroundStyle(Color.srTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Start a recording") {
                Haptics.firm()
                router.record()
            }
            .buttonStyle(.srPrimary)
        }
        .padding(Space.l)
        .srCard(radius: Radius.xl)
        .srCardShadow()
        .padding(.horizontal, Space.gutter)
    }

    private func modeTile(_ mode: RecordMode) -> some View {
        Button {
            Haptics.tap()
            router.record(mode)
        } label: {
            VStack(spacing: Space.xs) {
                IconTile(systemName: mode.kind.systemImage, size: 40)
                Text(mode.label)
                    .font(.srCaption)
                    .foregroundStyle(Color.srText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.s)
            .background(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).fill(Color.srCanvas))
        }
        .buttonStyle(PressScaleStyle(scale: 0.96))
        .accessibilityLabel("Record \(mode.label.lowercased())")
    }

    // MARK: Rails

    private var libraryRail: some View {
        let videos = Array(library.readyVideos.prefix(10))
        return VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader(title: "From my library",
                          actionTitle: videos.isEmpty ? nil : "See all",
                          action: videos.isEmpty ? nil : { seeAllLibrary() })
                .padding(.horizontal, Space.gutter)
            if videos.isEmpty {
                RailPlaceholder(systemImage: "film",
                                text: "Your newest recordings will line up here, ready to play or send.")
            } else {
                rail(videos, showsProgress: false)
            }
        }
    }

    private var watchedRail: some View {
        let videos = Array(library.history.filter { $0.state.isReady }.prefix(10))
        return VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader(title: "Recently watched",
                          subtitle: "Pick up where you left off",
                          actionTitle: videos.isEmpty ? nil : "See all",
                          action: videos.isEmpty ? nil : { router.homePath.append(Route.history) })
                .padding(.horizontal, Space.gutter)
            if videos.isEmpty {
                RailPlaceholder(systemImage: "play.circle",
                                text: "Recordings you play show up here, with how far you got.")
            } else {
                rail(videos, showsProgress: true)
            }
        }
    }

    private func rail(_ videos: [Video], showsProgress: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: Space.s) {
                ForEach(videos) { video in
                    VideoRailCard(video: video, actions: actions, showsProgress: showsProgress)
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.vertical, Space.xxs)
        }
    }

    private func seeAllLibrary() {
        BrowseIntent.shared.libraryTab = .videos
        router.select(.library)
    }

    // MARK: Failed saves

    private var failedCount: Int {
        library.allVideos.filter { video in
            if case .failed = video.state { return true }
            return false
        }.count
    }

    private var failedBanner: some View {
        Button {
            Haptics.tap()
            seeAllLibrary()
        } label: {
            HStack(spacing: Space.s) {
                IconTile(systemName: "exclamationmark.triangle.fill", size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: failedCount == 1 ? "A recording wasn't saved" : "\(failedCount) recordings weren't saved")
                        .font(.srSubheadlineStrong)
                        .foregroundStyle(Color.srText)
                    Text("Open Library to try again or free up space.")
                        .font(.srFootnote)
                        .foregroundStyle(Color.srTextSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.srTextTertiary)
            }
            .padding(Space.m)
            .srCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
        .padding(.horizontal, Space.gutter)
    }
}

/// The large title on Home, by time of day.
enum HomeGreeting {
    static func title(for date: Date, calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: date) {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Up late?"
        }
    }
}

/// What an empty rail shows: a dashed outline the size of a short card, with what will appear.
private struct RailPlaceholder: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(spacing: Space.s) {
            IconTile(systemName: systemImage, size: 40)
            Text(text)
                .font(.srSubheadline)
                .foregroundStyle(Color.srTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
                .strokeBorder(Color.srTextTertiary.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        )
        .padding(.horizontal, Space.gutter)
        .accessibilityElement(children: .combine)
    }
}
