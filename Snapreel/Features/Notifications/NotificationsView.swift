import SwiftUI

/// Session E owns this file. Root of the Notifications tab (inside the shell's NavigationStack):
/// what Snapreel itself did, newest first, grouped by day. Tapping a row opens the recording
/// (or Storage, or the title editor); rows are marked read after the tab has been on screen
/// for a few seconds.
@MainActor
struct NotificationsView: View {
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.scenePhase) private var scenePhase

    @State private var filter: FeedFilter
    @State private var titleTarget: Video?
    @State private var showsStorage = false
    @State private var showsSettings = false
    @State private var confirmsClearRead = false

    /// How long the tab must be on screen before its unread rows count as read.
    private let readDelay: UInt64 = 4_000_000_000

    init(initialFilter: FeedFilter = .all) {
        _filter = State(initialValue: initialFilter)
    }

    var body: some View {
        content
            .background(Color.srCanvas.ignoresSafeArea())
            .navigationTitle("Notifications")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { moreMenu }
            }
            .settingsToolbar()
            .navigationDestination(isPresented: $showsSettings) { NotificationSettingsView() }
            .sheet(item: $titleTarget) { video in titleSheet(for: video) }
            .sheet(isPresented: $showsStorage) { storageSheet }
            .confirmationDialog("Clear read notifications?", isPresented: $confirmsClearRead, titleVisibility: .visible) {
                Button("Clear \(readCount) read", role: .destructive) { clearRead() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("They're removed from this list. Your recordings stay as they are.")
            }
            .task(id: viewingKey) { await markReadAfterViewing() }
    }

    @ViewBuilder private var content: some View {
        if library.notifications.isEmpty {
            emptyFeed
        } else {
            feed
        }
    }

    // MARK: Feed

    private var feed: some View {
        List {
            Section {
                FeedFilterBar(selection: $filter, unreadCounts: unreadCounts)
                    .listRowInsets(EdgeInsets(top: Space.xxs, leading: 0, bottom: Space.xxs, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            if days.isEmpty {
                Section {
                    filterEmptyState
                        .padding(.vertical, Space.xxl)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            ForEach(days) { day in
                Section {
                    ForEach(day.items) { item in
                        row(for: item)
                    }
                } header: {
                    Text(day.title)
                        .font(.srSubheadlineStrong)
                        .foregroundStyle(Color.srTextSecondary)
                        .textCase(nil)
                }
            }
            Section {
                EmptyView()
            } footer: {
                Text("Snapreel keeps this list on this iPhone. Choose which alerts you get in Notification settings.")
                    .font(.srFootnote)
                    .foregroundStyle(Color.srTextTertiary)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .animation(Motion.standard, value: filter)
    }

    private func row(for item: AppNotification) -> some View {
        let video = item.videoID.flatMap { library.video($0) }
        return Button {
            open(item)
        } label: {
            NotificationRow(item: item, video: video)
        }
        .listRowInsets(EdgeInsets(top: Space.s, leading: Space.m, bottom: Space.s, trailing: Space.m))
        .listRowBackground(Color.srSurface)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                delete(item)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if !item.isRead {
                Button {
                    markRead(item)
                } label: {
                    Label("Mark as read", systemImage: "envelope.open")
                }
                .tint(Color.srInk)
            }
        }
        .contextMenu {
            if let video {
                Button {
                    open(item)
                } label: {
                    if item.kind == .needsTitle && video.needsTitle {
                        Label("Add a title", systemImage: "character.cursor.ibeam")
                    } else {
                        Label("Open recording", systemImage: "play.circle")
                    }
                }
            }
            if !item.isRead {
                Button {
                    markRead(item)
                } label: {
                    Label("Mark as read", systemImage: "envelope.open")
                }
            }
            Button(role: .destructive) {
                delete(item)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var emptyFeed: some View {
        GeometryReader { proxy in
            ScrollView {
                EmptyStateView(systemImage: "bell",
                               title: "Nothing new",
                               message: "We'll let you know when a recording is saved or a transcript is ready.")
                    .padding(.bottom, Space.xxxl)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
        }
    }

    private var filterEmptyState: some View {
        EmptyStateView(systemImage: filter.emptySystemImage,
                       title: filter.emptyTitle,
                       message: filter.emptyMessage)
    }

    // MARK: Toolbar

    private var moreMenu: some View {
        Menu {
            Button {
                markAllRead()
            } label: {
                Label("Mark all as read", systemImage: "checkmark.circle")
            }
            .disabled(library.unreadNotificationCount == 0)
            Button {
                showsSettings = true
            } label: {
                Label("Notification settings", systemImage: "bell.badge")
            }
            if readCount > 0 {
                Button(role: .destructive) {
                    confirmsClearRead = true
                } label: {
                    Label("Clear read notifications", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.srText)
        }
        .accessibilityLabel("More")
    }

    // MARK: Sheets

    private func titleSheet(for video: Video) -> some View {
        TitleEditorSheet(initialTitle: "", heading: "Name this recording", onSave: { title in
            library.rename(video.id, to: title)
            titleTarget = nil
            router.showToast("Title saved")
        }, onCancel: {
            titleTarget = nil
        })
        .presentationDetents([.height(220)])
    }

    private var storageSheet: some View {
        NavigationStack {
            StorageView()
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { showsStorage = false }
                            .font(.srHeadline)
                            .foregroundStyle(Color.srRed)
                    }
                }
        }
        .environmentObject(library)
        .environmentObject(router)
        .environmentObject(settings)
    }

    // MARK: Data

    private var visibleItems: [AppNotification] {
        library.sortedNotifications.filter { filter.includes($0.kind) }
    }

    private var days: [FeedDay] { FeedDay.group(visibleItems) }

    private var readCount: Int { library.notifications.filter(\.isRead).count }

    private var unreadCounts: [FeedFilter: Int] {
        var counts: [FeedFilter: Int] = [:]
        let unread = library.notifications.filter { !$0.isRead }
        for option in FeedFilter.allCases {
            counts[option] = unread.filter { option.includes($0.kind) }.count
        }
        return counts
    }

    // MARK: Actions

    private func open(_ item: AppNotification) {
        Haptics.tap()
        markRead(item)
        if item.kind == .storageLow {
            showsStorage = true
            return
        }
        guard let id = item.videoID else { return }
        guard let video = library.video(id) else {
            router.showToast("That recording is no longer on this iPhone", systemImage: "exclamationmark.circle.fill")
            return
        }
        if item.kind == .needsTitle && video.needsTitle {
            titleTarget = video
        } else if video.state.isReady {
            router.play(id)
        } else {
            // Still saving or failed: the library shows its progress and the retry button.
            router.select(.library)
        }
    }

    private func markRead(_ item: AppNotification) {
        guard !item.isRead else { return }
        withAnimation(Motion.quick) { library.markNotificationRead(item.id) }
    }

    private func markAllRead() {
        Haptics.success()
        withAnimation(Motion.standard) { library.markAllNotificationsRead() }
    }

    private func delete(_ item: AppNotification) {
        Haptics.tap()
        withAnimation(Motion.standard) { library.deleteNotification(item.id) }
    }

    private func clearRead() {
        let ids = library.notifications.filter(\.isRead).map(\.id)
        Haptics.success()
        withAnimation(Motion.standard) {
            for id in ids { library.deleteNotification(id) }
        }
    }

    // MARK: Marking read while viewed

    /// True while the feed is actually in front of the person.
    private var isViewing: Bool {
        router.tab == .notifications
            && scenePhase == .active
            && !router.isSettingsPresented
            && router.recorder == nil
            && (router.player?.isMinimized ?? true)
            && !showsStorage
            && !showsSettings
            && titleTarget == nil
    }

    private var viewingKey: String {
        "\(isViewing)-\(filter.rawValue)-\(library.unreadNotificationCount)"
    }

    private func markReadAfterViewing() async {
        guard isViewing, visibleItems.contains(where: { !$0.isRead }) else { return }
        try? await Task.sleep(nanoseconds: readDelay)
        guard !Task.isCancelled, isViewing else { return }
        let ids = visibleItems.filter { !$0.isRead }.map(\.id)
        withAnimation(Motion.gentle) {
            for id in ids { library.markNotificationRead(id) }
        }
    }
}

// MARK: - Filter

/// The feed's filter chips. Recordings: saved, waiting for a title, imports. Transcripts:
/// transcript ready. Storage warnings only show under All.
enum FeedFilter: String, CaseIterable, Identifiable {
    case all
    case recordings
    case transcripts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .recordings: return "Recordings"
        case .transcripts: return "Transcripts"
        }
    }

    func includes(_ kind: NotificationKind) -> Bool {
        switch self {
        case .all: return true
        case .recordings: return kind == .recordingSaved || kind == .needsTitle || kind == .importFinished
        case .transcripts: return kind == .transcriptReady
        }
    }

    var emptySystemImage: String {
        switch self {
        case .all: return "bell"
        case .recordings: return "video.badge.checkmark"
        case .transcripts: return "text.quote"
        }
    }

    var emptyTitle: String {
        switch self {
        case .all: return "Nothing new"
        case .recordings: return "No recording updates"
        case .transcripts: return "No transcripts yet"
        }
    }

    var emptyMessage: String {
        switch self {
        case .all: return "We'll let you know when a recording is saved or a transcript is ready."
        case .recordings: return "Saved recordings, titles to add and finished imports show up here."
        case .transcripts: return "When a recording's transcript is ready to read and search, it shows up here."
        }
    }
}

/// One day of the feed.
struct FeedDay: Identifiable {
    /// Start of the day.
    let id: Date
    let title: String
    var items: [AppNotification]

    /// Splits newest-first rows into days ("Today", "Yesterday", "Monday", "12 November").
    static func group(_ items: [AppNotification], now: Date = Date()) -> [FeedDay] {
        let calendar = Calendar.current
        var days: [FeedDay] = []
        for item in items {
            let start = calendar.startOfDay(for: item.createdAt)
            if let last = days.indices.last, days[last].id == start {
                days[last].items.append(item)
            } else {
                days.append(FeedDay(id: start, title: Format.dayTitle(item.createdAt, now: now), items: [item]))
            }
        }
        return days
    }
}
