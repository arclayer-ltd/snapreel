import SwiftUI

/// Session D owns this file. Videos in one folder (pushed with `Route.folder`): its recordings
/// as cards, add recordings, rename and delete in a menu (deleting moves the recordings back to
/// My videos).
struct FolderDetailView: View {
    let folderID: UUID

    @EnvironmentObject private var library: Library
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @StateObject private var actions = LibraryActionsModel()
    @AppStorage(LibrarySort.storageKey) private var sort: LibrarySort = .newest
    @State private var editor: FolderEditorMode?
    @State private var showsAdd = false
    @State private var confirmsDelete = false

    var body: some View {
        Group {
            if let folder = library.folder(folderID) {
                content(folder)
            } else {
                deletedState
            }
        }
        .background(Color.srCanvas.ignoresSafeArea())
        .navigationTitle(library.folder(folderID)?.name ?? "Folder")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if library.folder(folderID) != nil { menu }
            }
        }
        .libraryVideoActions(actions)
        .sheet(item: $editor) { mode in
            editorSheet(mode)
        }
        .sheet(isPresented: $showsAdd) {
            AddRecordingsSheet(folderID: folderID, onDone: { showsAdd = false })
                .presentationDetents([.large])
                .environmentObject(library)
                .environmentObject(router)
                .environmentObject(settings)
        }
        .alert("Delete this folder?", isPresented: $confirmsDelete) {
            Button("Delete folder", role: .destructive) { deleteFolder() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteMessage)
        }
    }

    private func content(_ folder: Folder) -> some View {
        let videos = sort.sorted(library.videos(inFolder: folder.id))
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: Space.s) {
                if videos.isEmpty {
                    EmptyStateView(systemImage: "folder",
                                   title: "Nothing in here yet",
                                   message: "Add recordings from your library, or choose Move to folder from any recording's … menu.",
                                   actionTitle: "Add recordings",
                                   action: { showsAdd = true })
                        .padding(.top, Space.xxl)
                } else {
                    summary(videos)
                    ForEach(videos) { video in
                        VideoCard(video: video, actions: actions, context: .folder)
                    }
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.xs)
            .padding(.bottom, BrowseLayout.bottomPadding(router))
        }
    }

    private func summary(_ videos: [Video]) -> some View {
        HStack(spacing: Space.xs) {
            Text(verbatim: "\(BrowseText.recordings(videos.count)) · \(BrowseText.totalDuration(videos))")
                .font(.srFootnote)
                .foregroundStyle(Color.srTextSecondary)
                .lineLimit(1)
            Spacer(minLength: Space.xs)
            LibrarySortMenu(sort: $sort)
        }
    }

    private var deletedState: some View {
        VStack {
            EmptyStateView(systemImage: "folder.badge.minus",
                           title: "This folder is gone",
                           message: "Its recordings are back in My videos.",
                           actionTitle: "Go to My videos",
                           action: {
                               BrowseIntent.shared.libraryTab = .videos
                               dismiss()
                           })
                .padding(.top, Space.xxxl)
            Spacer()
        }
    }

    private var menu: some View {
        Menu {
            Button {
                showsAdd = true
            } label: {
                Label("Add recordings", systemImage: "plus")
            }
            Button {
                editor = .rename(folderID)
            } label: {
                Label("Rename folder", systemImage: "pencil")
            }
            Button(role: .destructive) {
                confirmsDelete = true
            } label: {
                Label("Delete folder", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.srText)
        }
        .accessibilityLabel("Folder options")
    }

    private func editorSheet(_ mode: FolderEditorMode) -> some View {
        FolderEditorSheet(mode: mode, initialName: library.folder(folderID)?.name ?? "", onFinish: { folder in
            editor = nil
            if folder != nil {
                router.showToast("Folder renamed", systemImage: "pencil")
            }
        })
        .presentationDetents([.height(230)])
        .environmentObject(library)
    }

    private var deleteMessage: String {
        guard let folder = library.folder(folderID) else { return "" }
        return FolderDeleteText.message(for: folder, count: library.videos(inFolder: folderID).count)
    }

    private func deleteFolder() {
        library.deleteFolder(folderID)
        Haptics.success()
        router.showToast("Folder deleted. Its recordings are in My videos.", systemImage: "folder.badge.minus")
        dismiss()
    }
}
