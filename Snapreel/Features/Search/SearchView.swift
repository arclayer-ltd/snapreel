import SwiftUI

/// Session D owns this file. Root of the Search tab (inside the shell's NavigationStack).
/// Idle: recent searches and tags to browse by. Typing: results as you type, grouped into
/// Recordings, Folders, Tags and Said in the video (tap a line to play from that moment).
struct SearchView: View {
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var intent = BrowseIntent.shared
    @ObservedObject private var recents = RecentSearchStore.shared
    @StateObject private var actions = LibraryActionsModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var selectedTag: String?
    @FocusState private var fieldFocused: Bool

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isSearching: Bool { !trimmed.isEmpty || selectedTag != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                searchBar
                if isSearching {
                    SearchResultsList(query: trimmed, tag: selectedTag, actions: actions,
                                      onSelectTag: { tag in select(tag) },
                                      onRemember: { recents.add(trimmed) })
                } else {
                    idle
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.xs)
            .padding(.bottom, BrowseLayout.bottomPadding(router))
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Color.srCanvas.ignoresSafeArea())
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.large)
        .settingsToolbar()
        .libraryVideoActions(actions)
        .onReceive(intent.$search) { request in
            handle(request)
        }
    }

    // MARK: Search bar

    private var showsCancel: Bool { fieldFocused || isSearching }

    private var searchBar: some View {
        HStack(spacing: Space.s) {
            HStack(spacing: Space.xs) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.srTextTertiary)
                if let selectedTag {
                    tagToken(selectedTag)
                }
                TextField(selectedTag == nil ? "Titles, folders, tags or words said" : "Search within this tag",
                          text: $query)
                    .font(.srBody)
                    .foregroundStyle(Color.srText)
                    .focused($fieldFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit { recents.add(trimmed) }
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.srTextTertiary)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, Space.s)
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).fill(Color.srFill))
            if showsCancel {
                Button("Cancel") { cancel() }
                    .font(.srBody)
                    .foregroundStyle(Color.srRed)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : Motion.quick, value: showsCancel)
    }

    private func tagToken(_ name: String) -> some View {
        Button {
            Haptics.tap()
            withAnimation(reduceMotion ? nil : Motion.quick) { selectedTag = nil }
        } label: {
            HStack(spacing: 3) {
                Text(verbatim: "#\(name)")
                    .font(.srSubheadlineStrong)
                    .lineLimit(1)
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, Space.xs)
            .frame(height: 26)
            .background(Capsule().fill(Color.srRed))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel("Tag \(name). Remove")
    }

    // MARK: Idle

    @ViewBuilder private var idle: some View {
        let tags = LibrarySearch.tagCounts(in: library)
        if recents.items.isEmpty && tags.isEmpty {
            EmptyStateView(systemImage: "magnifyingglass",
                           title: "Find any recording",
                           message: "Search titles, folders and tags, and the words said in any recording with a transcript. It all happens on this iPhone.")
                .padding(.top, Space.xxl)
        } else {
            Text("Searches titles, folders, tags and transcripts on this iPhone.")
                .font(.srFootnote)
                .foregroundStyle(Color.srTextSecondary)
                .padding(.top, -Space.xs)
            if !recents.items.isEmpty {
                recentSection
            }
            if !tags.isEmpty {
                tagsSection(tags)
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack {
                Text("Recent searches")
                    .font(.srHeadline)
                    .foregroundStyle(Color.srText)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Clear") {
                    Haptics.tap()
                    withAnimation(reduceMotion ? nil : Motion.quick) { recents.clear() }
                }
                .font(.srSubheadlineStrong)
                .foregroundStyle(Color.srRed)
                .accessibilityLabel("Clear recent searches")
            }
            VStack(spacing: 0) {
                ForEach(recents.items, id: \.self) { item in
                    recentRow(item)
                    if item != recents.items.last {
                        Divider().padding(.leading, 32)
                    }
                }
            }
            .padding(.horizontal, Space.m)
            .srCard()
        }
    }

    private func recentRow(_ item: String) -> some View {
        HStack(spacing: Space.s) {
            Button {
                Haptics.tap()
                query = item
                recents.add(item)
            } label: {
                HStack(spacing: Space.s) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.srTextTertiary)
                        .frame(width: 20)
                    Text(verbatim: item)
                        .font(.srBody)
                        .foregroundStyle(Color.srText)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, Space.s)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search for \(item)")
            Button {
                withAnimation(reduceMotion ? nil : Motion.quick) { recents.remove(item) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.srTextTertiary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(item) from recent searches")
        }
    }

    private func tagsSection(_ tags: [LibrarySearch.TagMatch]) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Browse by tag")
                .font(.srHeadline)
                .foregroundStyle(Color.srText)
                .accessibilityAddTraits(.isHeader)
            BrowseChipFlow {
                ForEach(tags) { match in
                    BrowseTagChip(text: match.tag, count: match.count) {
                        select(match.tag)
                    }
                }
            }
        }
    }

    // MARK: Behaviour

    private func select(_ tag: String) {
        withAnimation(reduceMotion ? nil : Motion.quick) {
            selectedTag = tag
            query = ""
        }
        fieldFocused = false
    }

    private func cancel() {
        query = ""
        selectedTag = nil
        fieldFocused = false
    }

    private func handle(_ request: BrowseSearchRequest?) {
        guard let request else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard intent.search == request else { return }
            intent.search = nil
            query = request.query
            if request.focusesField { fieldFocused = true }
        }
    }
}

// MARK: - Results

/// Grouped results for a query (and optional tag), or the no-results state.
private struct SearchResultsList: View {
    let query: String
    let tag: String?
    let actions: LibraryActionsModel
    let onSelectTag: @MainActor (String) -> Void
    /// Remembers the query as a recent search when a result is opened.
    let onRemember: @MainActor () -> Void

    @EnvironmentObject private var library: Library
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        let results = LibrarySearch.run(query: query, tag: tag, in: library)
        if results.isEmpty {
            noResults
        } else {
            if !results.videos.isEmpty { videosGroup(results.videos) }
            if !results.folders.isEmpty { foldersGroup(results.folders) }
            if !results.tags.isEmpty { tagsGroup(results.tags) }
            if !results.spoken.isEmpty { spokenGroup(results.spoken) }
        }
    }

    private var noResults: some View {
        EmptyStateView(systemImage: "magnifyingglass",
                       title: "No matches",
                       message: noResultsMessage)
            .padding(.top, Space.xxl)
    }

    private var noResultsMessage: String {
        if let tag {
            if query.isEmpty { return "Nothing is tagged #\(tag) any more." }
            return "Nothing tagged #\(tag) matches “\(query)”. Try another word, or remove the tag."
        }
        return "Nothing matches “\(query)”. Try fewer letters or another word. Words said are searched once a recording has a transcript."
    }

    private var videosTitle: String {
        guard let tag else { return "Recordings" }
        return query.isEmpty ? "Tagged #\(tag)" : "Recordings tagged #\(tag)"
    }

    private func header(_ title: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
            Text(verbatim: title)
                .font(.srHeadline)
                .foregroundStyle(Color.srText)
            Text(verbatim: "\(count)")
                .font(.srFootnote)
                .foregroundStyle(Color.srTextTertiary)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: Groups

    private func videosGroup(_ videos: [Video]) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            header(videosTitle, count: videos.count)
            ForEach(videos) { video in
                VideoCard(video: video, actions: actions, context: .search(query), onOpen: { onRemember() })
            }
        }
    }

    private func foldersGroup(_ folders: [LibrarySearch.FolderMatch]) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            header("Folders", count: folders.count)
            VStack(spacing: 0) {
                ForEach(folders) { match in
                    folderRow(match)
                    if match.id != folders.last?.id {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .padding(.horizontal, Space.m)
            .srCard()
        }
    }

    private func folderRow(_ match: LibrarySearch.FolderMatch) -> some View {
        NavigationLink(value: Route.folder(match.folder.id)) {
            HStack(spacing: Space.s) {
                IconTile(systemName: "folder.fill")
                VStack(alignment: .leading, spacing: 2) {
                    BrowseHighlight.text(match.folder.name, query: query)
                        .font(.srBody)
                        .foregroundColor(Color.srText)
                        .lineLimit(1)
                    Text(verbatim: BrowseText.recordings(match.count))
                        .font(.srFootnote)
                        .foregroundStyle(Color.srTextSecondary)
                }
                Spacer(minLength: Space.xs)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.srTextTertiary)
            }
            .padding(.vertical, Space.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded { onRemember() })
        .accessibilityLabel("Folder \(match.folder.name), \(BrowseText.recordings(match.count))")
    }

    private func tagsGroup(_ tags: [LibrarySearch.TagMatch]) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            header("Tags", count: tags.count)
            BrowseChipFlow {
                ForEach(tags) { match in
                    BrowseTagChip(text: match.tag, count: match.count) {
                        onRemember()
                        onSelectTag(match.tag)
                    }
                }
            }
        }
    }

    private func spokenGroup(_ matches: [LibrarySearch.SpokenMatch]) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            header("Said in the video", count: matches.count)
            VStack(spacing: 0) {
                ForEach(matches) { match in
                    SpokenMatchRow(match: match, query: query) {
                        onRemember()
                        Haptics.tap()
                        router.play(match.video.id, at: match.segment.start)
                    }
                    if match.id != matches.last?.id {
                        Divider().padding(.leading, 76)
                    }
                }
            }
            .padding(.horizontal, Space.s)
            .srCard()
        }
    }
}

/// One transcript line that matched: thumbnail, the moment, the recording and the line itself.
private struct SpokenMatchRow: View {
    let match: LibrarySearch.SpokenMatch
    let query: String
    let action: @MainActor () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack(alignment: .top, spacing: Space.s) {
                VideoThumbnail(video: match.video, cornerRadius: 6, showsDuration: false)
                    .frame(width: 64)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    HStack(spacing: Space.xs) {
                        Text(verbatim: Format.stamp(match.segment.start))
                            .font(.srTimerSmall)
                            .foregroundStyle(Color.srRedDeep)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.srRedSoft))
                        Text(verbatim: match.video.title)
                            .font(.srFootnote)
                            .foregroundStyle(Color.srTextSecondary)
                            .lineLimit(1)
                    }
                    quote
                        .font(.srSubheadline)
                        .foregroundColor(Color.srText)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.srRed)
                    .padding(.top, 2)
            }
            .padding(.vertical, Space.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
        .accessibilityLabel("Play from \(Format.stamp(match.segment.start)) in \(match.video.title): \(match.segment.text)")
    }

    private var quote: Text {
        let open = Text(verbatim: "“")
        let line = BrowseHighlight.text(match.segment.text, query: query)
        let close = Text(verbatim: "”")
        return open + line + close
    }
}
