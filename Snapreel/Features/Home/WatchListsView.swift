import SwiftUI

/// Session D owns this file. Watch later and History (pushed from Home with `.watchLater` /
/// `.history`). Swipe a row to take it off the list; the recording itself stays.

struct WatchLaterView: View {
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var router: AppRouter
    @StateObject private var actions = LibraryActionsModel()

    var body: some View {
        Group {
            if library.watchLater.isEmpty {
                WatchListEmptyState(title: "Nothing saved for later",
                                    message: "Saw something you want to come back to? Tap … on any recording and choose Watch later. It waits here until you're ready.")
            } else {
                list
            }
        }
        .background(Color.srCanvas.ignoresSafeArea())
        .navigationTitle("Watch later")
        .navigationBarTitleDisplayMode(.large)
        .libraryVideoActions(actions)
    }

    private var list: some View {
        let videos = library.watchLater
        return List {
            WatchListCaption(text: "\(BrowseText.recordings(videos.count)) · newest first · swipe to remove")
            ForEach(videos) { video in
                VideoCard(video: video, actions: actions, context: .watchLater)
                    .watchListRow()
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            remove(video)
                        } label: {
                            Label("Remove", systemImage: "bookmark.slash")
                        }
                    }
            }
            WatchListBottomSpacer(height: BrowseLayout.bottomPadding(router))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func remove(_ video: Video) {
        library.update(video.id) { $0.watchLaterAddedAt = nil }
        Haptics.success()
        router.showToast("Removed from Watch later", systemImage: "bookmark.slash.fill")
    }
}

struct WatchHistoryView: View {
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var router: AppRouter
    @StateObject private var actions = LibraryActionsModel()
    @State private var confirmsClear = false

    var body: some View {
        Group {
            if library.history.isEmpty {
                WatchListEmptyState(title: "Nothing watched yet",
                                    message: "Recordings you play show up here, newest first, with how far through you got.")
            } else {
                list
            }
        }
        .background(Color.srCanvas.ignoresSafeArea())
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !library.history.isEmpty {
                    Button("Clear") { confirmsClear = true }
                        .font(.srBody)
                        .foregroundStyle(Color.srRed)
                }
            }
        }
        .libraryVideoActions(actions)
        .alert("Clear your watch history?", isPresented: $confirmsClear) {
            Button("Clear history", role: .destructive) { clearAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your recordings stay in your library. Only this list of what you watched is cleared.")
        }
    }

    private var list: some View {
        List {
            WatchListCaption(text: "Swipe a recording to remove it from your history.")
            ForEach(days, id: \.day) { day in
                Text(verbatim: day.title)
                    .font(.srHeadline)
                    .foregroundStyle(Color.srText)
                    .accessibilityAddTraits(.isHeader)
                    .listRowInsets(EdgeInsets(top: Space.m, leading: Space.gutter, bottom: Space.xxs, trailing: Space.gutter))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                ForEach(day.videos) { video in
                    VideoCard(video: video, actions: actions, context: .history)
                        .watchListRow()
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                remove(video)
                            } label: {
                                Label("Remove", systemImage: "eye.slash")
                            }
                        }
                }
            }
            WatchListBottomSpacer(height: BrowseLayout.bottomPadding(router))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    /// History grouped by the day it was last watched, most recent first.
    private var days: [HistoryDay] {
        let calendar = Calendar.current
        let thisYear = calendar.component(.year, from: Date())
        var result: [HistoryDay] = []
        for video in library.history {
            let watched = video.lastWatchedAt ?? video.createdAt
            let day = calendar.startOfDay(for: watched)
            if let last = result.last, last.day == day {
                result[result.count - 1].videos.append(video)
            } else {
                // Older than a week, the day title drops the year; add it back for other years.
                let title = calendar.component(.year, from: day) == thisYear ? Format.dayTitle(day) : Format.date(day)
                result.append(HistoryDay(day: day, title: title, videos: [video]))
            }
        }
        return result
    }

    private func remove(_ video: Video) {
        library.update(video.id) { $0.lastWatchedAt = nil }
        Haptics.success()
        router.showToast("Removed from History", systemImage: "eye.slash.fill")
    }

    private func clearAll() {
        for video in library.history {
            library.update(video.id) { $0.lastWatchedAt = nil }
        }
        Haptics.success()
        router.showToast("History cleared", systemImage: "clock.arrow.circlepath")
    }
}

private struct HistoryDay {
    let day: Date
    let title: String
    var videos: [Video]
}

// MARK: - Shared pieces

/// Empty Watch later / History: the relaxing character, what goes here and a way back.
private struct WatchListEmptyState: View {
    let title: String
    let message: String

    @EnvironmentObject private var router: AppRouter

    var body: some View {
        ScrollView {
            EmptyStateView(character: .emptyWatch,
                           title: title,
                           message: message,
                           actionTitle: "Browse my library",
                           action: {
                               BrowseIntent.shared.libraryTab = .videos
                               router.select(.library)
                           })
                .padding(.top, Space.xl)
                .padding(.bottom, Space.xxl)
        }
    }
}

private struct WatchListCaption: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.srFootnote)
            .foregroundStyle(Color.srTextSecondary)
            .listRowInsets(EdgeInsets(top: Space.xs, leading: Space.gutter, bottom: Space.xxs, trailing: Space.gutter))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

private struct WatchListBottomSpacer: View {
    let height: CGFloat

    var body: some View {
        Color.clear
            .frame(height: height)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .accessibilityHidden(true)
    }
}

private extension View {
    /// A card as a list row on the canvas: no row background, no separators, gutter insets.
    func watchListRow() -> some View {
        listRowInsets(EdgeInsets(top: Space.xs / 2 + 2, leading: Space.gutter, bottom: Space.xs / 2 + 2, trailing: Space.gutter))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
