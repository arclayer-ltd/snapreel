#if DEBUG
import SwiftUI

extension DebugCatalog {
    /// Session B owns this list: recorder, permissions, camera, screen, audio, import, review, saving.
    static var recordScreens: [DebugScreen] {
        [
            DebugScreen("rec.shell", "Recorder shell", fixture: .filled) { RecorderView(launch: RecorderLaunch(mode: .camera)) },
        ]
    }
}
#endif
