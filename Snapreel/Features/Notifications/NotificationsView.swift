import SwiftUI

/// Session E owns this file. Root of the Notifications tab (inside the shell's NavigationStack).
struct NotificationsView: View {
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
        .navigationTitle("Notifications")
        .settingsToolbar()
    }
}
