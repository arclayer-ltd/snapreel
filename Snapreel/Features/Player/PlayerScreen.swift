import SwiftUI

/// Session C owns this file. Full-screen dark player with details, notes, transcript and
/// reactions, presented by the shell while `router.player` is set and not minimised.
struct PlayerScreen: View {
    let presentation: PlayerPresentation
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack {
                CircleIconButton(systemName: "chevron.down", label: "Minimise", tone: .dark) { router.minimizePlayer() }
                Spacer()
                CircleIconButton(systemName: "xmark", label: "Close", tone: .dark) { router.closePlayer() }
            }
            if let video = library.video(presentation.videoID) {
                VideoThumbnail(video: video)
                Text(video.title).font(.srTitle3).foregroundStyle(Color.srOnDark)
            }
            Spacer()
        }
        .padding(Space.gutter)
        .background(Color.srInk.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}
