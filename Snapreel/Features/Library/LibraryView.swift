import SwiftUI

/// Session D owns this file. Root of the Library tab (inside the shell's NavigationStack), also
/// pushed for `Route.allVideos`. Two sections: My videos (every recording as a card, sortable)
/// and Folders (cards, new / rename / delete).
struct LibraryView: View {
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var intent = BrowseIntent.shared
    @StateObject private var actions = LibraryActionsModel()
    @AppStorage(LibrarySort.storageKey) private var sort: LibrarySort = .newest
    @State private var folderEditor: FolderEditorMode?
    @State private var folderToDelete: Folder?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    sectionContent
                        .padding(.horizontal, Space.gutter)
                        .padding(.top, Space.m)
                        .padding(.bottom, BrowseLayout.bottomPadding(router))
                } header: {
                    tabsHeader
                }
            }
        }
        .background(Color.srCanvas.ignoresSafeArea())
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.large)
        .settingsToolbar()
        .libraryVideoActions(actions)
        .sheet(item: $folderEditor) { mode in
            folderEditorSheet(mode)
        }
        .alert("Delete this folder?", isPresented: folderDeleteShown, presenting: folderToDelete) { folder in
            Button("Delete folder", role: .destructive) { deleteFolder(folder) }
            Button("Cancel", role: .cancel) {}
        } message: { folder in
            Text(FolderDeleteText.message(for: folder, count: library.videos(inFolder: folder.id).count))
        }
        .onReceive(intent.$librarySheet) { request in
            handle(request)
        }
    }

    private var tabsHeader: some View {
        UnderlineTabs(tabs: LibraryTab.allCases, selection: $intent.libraryTab, title: { $0.title })
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.xs)
            .background(Color.srCanvas)
    }

    @ViewBuilder private var sectionContent: some View {
        switch intent.libraryTab {
        case .videos: videosSection
        case .folders: foldersSection
        }
    }

    // MARK: My videos

    @ViewBuilder private var videosSection: some View {
        let videos = sort.sorted(library.allVideos)
        if videos.isEmpty {
            EmptyStateView(character: .emptyLibrary,
                           title: "Your library is ready",
                           message: "Record your screen, your camera or just your voice. Everything you make lands here, on this iPhone.",
                           actionTitle: "Start a recording",
                           action: { router.record() })
                .padding(.top, Space.l)
        } else {
            LazyVStack(alignment: .leading, spacing: Space.s) {
                videosSummary(videos)
                ForEach(videos) { video in
                    VideoCard(video: video, actions: actions, context: .library)
                }
            }
        }
    }

    private func videosSummary(_ videos: [Video]) -> some View {
        HStack(spacing: Space.xs) {
            Text(verbatim: "\(BrowseText.recordings(videos.count)) · \(BrowseText.totalDuration(videos))")
                .font(.srFootnote)
                .foregroundStyle(Color.srTextSecondary)
                .lineLimit(1)
            Spacer(minLength: Space.xs)
            LibrarySortMenu(sort: $sort)
        }
    }

    // MARK: Folders

    @ViewBuilder private var foldersSection: some View {
        let folders = library.sortedFolders
        if folders.isEmpty {
            EmptyStateView(systemImage: "folder.badge.plus",
                           title: "No folders yet",
                           message: "Group recordings by project, client or class. A recording sits in one folder at a time, and stays in My videos too.",
                           actionTitle: "New folder",
                           action: { folderEditor = .create(initialName: "") })
                .padding(.top, Space.xxl)
        } else {
            VStack(alignment: .leading, spacing: Space.s) {
                foldersSummary(folders)
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: Space.s) {
                    ForEach(folders) { folder in
                        folderLink(folder)
                    }
                    newFolderTile
                }
            }
        }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.flexible(), spacing: Space.s, alignment: .top),
         GridItem(.flexible(), spacing: Space.s, alignment: .top)]
    }

    private func foldersSummary(_ folders: [Folder]) -> some View {
        HStack {
            Text(verbatim: BrowseText.count(folders.count, "folder", "folders"))
                .font(.srFootnote)
                .foregroundStyle(Color.srTextSecondary)
            Spacer()
            Button {
                Haptics.tap()
                folderEditor = .create(initialName: "")
            } label: {
                Label("New folder", systemImage: "plus")
                    .font(.srSubheadlineStrong)
                    .foregroundStyle(Color.srRed)
            }
        }
        .frame(minHeight: 32)
    }

    private func folderLink(_ folder: Folder) -> some View {
        NavigationLink(value: Route.folder(folder.id)) {
            LibraryFolderCard(folder: folder, videos: library.videos(inFolder: folder.id))
        }
        .buttonStyle(PressScaleStyle(scale: 0.97))
        .contextMenu {
            Button {
                folderEditor = .rename(folder.id)
            } label: {
                Label("Edit title", systemImage: "pencil")
            }
            Button(role: .destructive) {
                folderToDelete = folder
            } label: {
                Label("Delete folder", systemImage: "trash")
            }
        }
    }

    private var newFolderTile: some View {
        Button {
            Haptics.tap()
            folderEditor = .create(initialName: "")
        } label: {
            VStack(spacing: Space.xs) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.srRed)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Color.srRedSoft))
                Text("New folder")
                    .font(.srSubheadlineStrong)
                    .foregroundStyle(Color.srText)
            }
            .frame(maxWidth: .infinity, minHeight: 160)
            .background(
                RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
                    .strokeBorder(Color.srTextTertiary.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.97))
    }

    private func folderEditorSheet(_ mode: FolderEditorMode) -> some View {
        FolderEditorSheet(mode: mode, initialName: initialName(for: mode), onFinish: { folder in
            folderEditor = nil
            guard let folder else { return }
            if mode.isCreate {
                router.showToast("Folder created", systemImage: "folder.fill")
                router.show(.folder(folder.id), in: router.tab)
            } else {
                router.showToast("Folder renamed", systemImage: "pencil")
            }
        })
        .presentationDetents([.height(230)])
        .environmentObject(library)
        .environmentObject(router)
        .environmentObject(settings)
    }

    private func initialName(for mode: FolderEditorMode) -> String {
        switch mode {
        case .create(let name): return name
        case .rename(let id): return library.folder(id)?.name ?? ""
        }
    }

    private var folderDeleteShown: Binding<Bool> {
        Binding(get: { folderToDelete != nil },
                set: { shown in if !shown { folderToDelete = nil } })
    }

    private func deleteFolder(_ folder: Folder) {
        library.deleteFolder(folder.id)
        Haptics.success()
        router.showToast("Folder deleted. Its recordings are in My videos.", systemImage: "folder.badge.minus")
    }

    // MARK: Requests

    private func handle(_ request: LibrarySheetRequest?) {
        guard let request else { return }
        Task { @MainActor in
            // Let the screen settle before presenting.
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard intent.librarySheet == request else { return }
            intent.librarySheet = nil
            switch request {
            case .video(let sheet): actions.open(sheet)
            case .newFolder(let name): folderEditor = .create(initialName: name)
            case .renameFolder(let id): folderEditor = .rename(id)
            }
        }
    }
}

/// "Newest ⌄" menu used above lists of recordings.
struct LibrarySortMenu: View {
    @Binding var sort: LibrarySort

    var body: some View {
        Menu {
            Picker("Sort by", selection: $sort) {
                ForEach(LibrarySort.allCases) { option in
                    Label(option.label, systemImage: option.systemImage).tag(option)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 12, weight: .semibold))
                Text(sort.shortLabel)
                    .font(.srSubheadlineStrong)
            }
            .foregroundStyle(Color.srText)
            .padding(.horizontal, Space.s)
            .frame(height: 32)
            .background(Capsule().fill(Color.srSurface))
            .overlay(Capsule().strokeBorder(Color.srLine, lineWidth: 1))
        }
        .accessibilityLabel("Sort, \(sort.label)")
    }
}

/// Wording for the delete-folder confirmation (Library and folder detail).
enum FolderDeleteText {
    static func message(for folder: Folder, count: Int) -> String {
        if count == 0 {
            return "“\(folder.name)” is empty, so nothing else changes."
        }
        let moved = count == 1 ? "Its recording moves" : "Its \(count) recordings move"
        return "\(moved) back to My videos. No recordings are deleted."
    }
}
