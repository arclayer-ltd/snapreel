import SwiftUI

/// Session D owns this file. Videos in one folder (pushed with `Route.folder`).
struct FolderDetailView: View {
    let folderID: UUID
    @EnvironmentObject private var library: Library

    var body: some View {
        List(library.videos(inFolder: folderID)) { video in Text(video.title) }
            .navigationTitle(library.folder(folderID)?.name ?? "Folder")
    }
}
