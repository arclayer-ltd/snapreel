#if DEBUG
import SwiftUI

extension DebugCatalog {
    /// Session E owns this list: notifications feed, notification settings, storage, sharing, save to Photos.
    static var inboxScreens: [DebugScreen] {
        [
            .shell("notif.feed", "Notifications", tab: .notifications),
        ]
    }
}
#endif
