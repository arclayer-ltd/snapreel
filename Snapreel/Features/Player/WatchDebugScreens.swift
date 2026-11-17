#if DEBUG
import SwiftUI

extension DebugCatalog {
    /// Session C owns this list: player and its states, notes, transcript, reactions, stats.
    static var watchScreens: [DebugScreen] {
        [
            .shell("video.player", "Player", tab: .home) { router, _ in
                router.play(FixtureStorage.IDs.checkout)
            },
        ]
    }
}
#endif
