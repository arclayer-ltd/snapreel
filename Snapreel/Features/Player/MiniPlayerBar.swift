import SwiftUI

/// Session C owns this file. Bar above the tab bar while the player is minimised; tap to expand.
struct MiniPlayerBar: View {
    let videoID: UUID
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        Button { router.expandPlayer() } label: {
            Text(library.video(videoID)?.title ?? "")
                .font(.srSubheadlineStrong)
                .foregroundStyle(Color.srOnDark)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.m)
                .background(RoundedRectangle(cornerRadius: Radius.l).fill(Color.srInk))
        }
        .buttonStyle(.plain)
    }
}
