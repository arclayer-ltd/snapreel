import SwiftUI

/// Session E owns this file. The two ways a recording leaves Snapreel, used by review (B),
/// the player (C) and library actions (D):
///
///     .shareVideo($videoToShare)      // system share sheet with the file; counts shares
///     .saveToPhotos($videoToSave)     // permission, progress, "Saved" confirmation
///
/// Set the binding to a video to start; the modifier sets it back to nil when finished.
extension View {
    func shareVideo(_ video: Binding<Video?>) -> some View {
        self
    }

    func saveToPhotos(_ video: Binding<Video?>) -> some View {
        self
    }
}
