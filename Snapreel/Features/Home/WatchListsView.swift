import SwiftUI

/// Session D owns this file. Watch Later and Watch History lists (pushed from Home).
struct WatchLaterView: View {
    @EnvironmentObject private var library: Library

    var body: some View {
        List(library.watchLater) { video in Text(video.title) }
            .navigationTitle("Watch Later")
    }
}

struct WatchHistoryView: View {
    @EnvironmentObject private var library: Library

    var body: some View {
        List(library.history) { video in Text(video.title) }
            .navigationTitle("History")
    }
}
