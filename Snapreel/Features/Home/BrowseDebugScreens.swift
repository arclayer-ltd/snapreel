#if DEBUG
import SwiftUI

extension DebugCatalog {
    /// Session D owns this list: home, watch lists, library, folders, tags, search.
    static var browseScreens: [DebugScreen] {
        [
            .shell("lib.videos", "My videos", tab: .library),
        ]
    }
}
#endif
