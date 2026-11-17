import SwiftUI

/// Session D owns this file. Root of the Library tab (inside the shell's NavigationStack).
struct LibraryView: View {
    @EnvironmentObject private var library: Library

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.m) {
                ForEach(library.allVideos) { video in
                    VideoThumbnail(video: video)
                    Text(video.title).font(.srHeadline)
                }
            }
            .padding(Space.gutter)
        }
        .background(Color.srCanvas.ignoresSafeArea())
        .navigationTitle("Library")
        .settingsToolbar()
    }
}
