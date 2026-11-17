#if DEBUG
import SwiftUI

extension DebugCatalog {
    /// Session D owns this list: home, watch lists, library, folders, tags, search.
    static var browseScreens: [DebugScreen] {
        homeScreens + libraryScreens + searchScreens
    }

    private static var homeScreens: [DebugScreen] {
        [
            .shell("home.filled", "Home", tab: .home),
            .shell("home.empty", "Home [empty]", tab: .home, fixture: .empty),
            .shell("home.history", "Watch history", tab: .home, configure: { router, _ in
                router.homePath.append(Route.history)
            }),
            .shell("home.history.empty", "Watch history [empty]", tab: .home, fixture: .empty, configure: { router, _ in
                router.homePath.append(Route.history)
            }),
            .shell("home.later", "Watch later", tab: .home, configure: { router, _ in
                router.homePath.append(Route.watchLater)
            }),
            .shell("home.later.empty", "Watch later [empty]", tab: .home, fixture: .empty, configure: { router, _ in
                router.homePath.append(Route.watchLater)
            }),
        ]
    }

    private static var libraryScreens: [DebugScreen] {
        [
            .shell("lib.videos", "My videos", tab: .library, configure: { _, _ in
                BrowseIntent.shared.libraryTab = .videos
            }),
            .shell("lib.videos.empty", "My videos [empty]", tab: .library, fixture: .empty, configure: { _, _ in
                BrowseIntent.shared.libraryTab = .videos
            }),
            .shell("lib.videos.saving", "My videos [saving and failed]", tab: .library, configure: { _, library in
                BrowseIntent.shared.libraryTab = .videos
                BrowseDebugData.addUnfinishedSaves(to: library)
            }),
            .shell("lib.folders", "Folders", tab: .library, configure: { _, _ in
                BrowseIntent.shared.libraryTab = .folders
            }),
            .shell("lib.folders.empty", "Folders [empty]", tab: .library, fixture: .empty, configure: { _, _ in
                BrowseIntent.shared.libraryTab = .folders
            }),
            .shell("lib.folder", "Folder detail", tab: .library, configure: { router, _ in
                BrowseIntent.shared.libraryTab = .folders
                router.libraryPath.append(Route.folder(FixtureStorage.IDs.product))
            }),
            .shell("lib.folder.editor", "New or rename folder", tab: .library, configure: { _, _ in
                BrowseIntent.shared.libraryTab = .folders
                BrowseIntent.shared.librarySheet = .newFolder(name: "Design reviews")
            }),
            .shell("lib.move", "Move to folder", tab: .library, configure: { _, _ in
                BrowseIntent.shared.libraryTab = .videos
                BrowseIntent.shared.librarySheet = .video(.move(FixtureStorage.IDs.checkout))
            }),
            .shell("lib.tags", "Tag editor", tab: .library, configure: { _, _ in
                BrowseIntent.shared.libraryTab = .videos
                BrowseIntent.shared.librarySheet = .video(.tags(FixtureStorage.IDs.checkout))
            }),
            .shell("lib.actions", "Video actions sheet", tab: .library, configure: { _, _ in
                BrowseIntent.shared.libraryTab = .videos
                BrowseIntent.shared.librarySheet = .video(.actions(FixtureStorage.IDs.checkout))
            }),
        ]
    }

    private static var searchScreens: [DebugScreen] {
        [
            .shell("search.idle", "Search idle", tab: .search, configure: { _, _ in
                RecentSearchStore.shared.replace(with: ["checkout", "launch plan", "map pins"])
            }),
            .shell("search.results", "Search results", tab: .search, configure: { _, _ in
                BrowseIntent.shared.search = BrowseSearchRequest(query: "checkout", focusesField: false)
            }),
            .shell("search.typing", "Search results [typing]", tab: .search, configure: { _, _ in
                BrowseIntent.shared.search = BrowseSearchRequest(query: "lau", focusesField: true)
            }),
            .shell("search.none", "Search results [none]", tab: .search, configure: { _, _ in
                BrowseIntent.shared.search = BrowseSearchRequest(query: "invoice", focusesField: false)
            }),
        ]
    }
}

/// Extra sample rows for the saving / failed card states (DEBUG only).
@MainActor
enum BrowseDebugData {
    static func addUnfinishedSaves(to library: Library) {
        let now = Date()
        library.add(Video(title: Format.defaultTitle(for: .screen, at: now),
                          createdAt: now,
                          kind: .screen,
                          fileName: "debug-saving.mp4",
                          thumbnailFileName: nil,
                          duration: 74,
                          fileSize: 0,
                          pixelWidth: 886,
                          pixelHeight: 1920,
                          state: .saving(progress: 0.62)))
        library.add(Video(title: "Design review with Sam",
                          createdAt: now.addingTimeInterval(-90),
                          kind: .camera,
                          fileName: "debug-failed.mp4",
                          thumbnailFileName: nil,
                          duration: 212,
                          fileSize: 0,
                          pixelWidth: 1920,
                          pixelHeight: 1080,
                          state: .failed(reason: "Your iPhone ran out of space before this recording finished saving.",
                                         outOfSpace: true)))
    }
}
#endif
