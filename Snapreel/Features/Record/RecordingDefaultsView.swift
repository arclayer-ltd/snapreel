import SwiftUI

/// Session B owns this file. Settings > Recording: quality, microphone default, countdown,
/// camera, mirroring. Pushed inside the Settings NavigationStack.
struct RecordingDefaultsView: View {
    var body: some View {
        List { Text("Recording defaults") }
            .navigationTitle("Recording")
    }
}
