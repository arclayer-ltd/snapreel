import SwiftUI

/// Session E owns this file. The two ways a recording leaves Snapreel, used by review (B),
/// the player (C) and library actions (D):
///
///     .shareVideo($videoToShare)      // system share sheet with the file; counts shares
///     .saveToPhotos($videoToSave)     // permission, progress, "Saved" confirmation
///
/// Set the binding to a video to start; the modifier sets it back to nil when finished.
///
/// Attach both to a screen's root view (not to a row): `saveToPhotos` shows its progress and
/// confirmation along the bottom edge of the view it is attached to, and its questions in a
/// small sheet. The share sheet is presented from the topmost view controller, so it works
/// over the dark player, the recorder review and any sheet. You may set the binding in the
/// same action that closes your own sheet or menu: presentation waits for that to finish.
extension View {
    /// Presents the system share sheet with the recording's file (named after its title).
    /// A completed share calls `library.recordShare`; "Save Video" from the sheet calls
    /// `library.recordSavedToPhotos` instead.
    @MainActor
    func shareVideo(_ video: Binding<Video?>) -> some View {
        modifier(ShareVideoModifier(video: video))
    }

    /// Saves the recording to the Photos library: explains the add-only permission before the
    /// system prompt, shows progress, then "Saved to Photos" with Open Photos. Audio recordings
    /// get a clear message with "Share instead". Calls `library.recordSavedToPhotos` on success.
    @MainActor
    func saveToPhotos(_ video: Binding<Video?>) -> some View {
        modifier(SaveToPhotosModifier(video: video, initialStage: nil))
    }

    /// Same as `saveToPhotos(_:)`, but the first time `video` is set the flow opens straight at
    /// `initialStage` and stays there (no permission request, no saving). For debug screenshots:
    ///
    ///     .saveToPhotos($videoToSave, initialStage: initialPhotosStage)
    ///     .onAppear { if initialPhotosStage != nil { videoToSave = library.video(id) } }
    ///
    /// Passing nil behaves exactly like `saveToPhotos(_:)`.
    @MainActor
    func saveToPhotos(_ video: Binding<Video?>, initialStage: PhotosSaveStage?) -> some View {
        modifier(SaveToPhotosModifier(video: video, initialStage: initialStage))
    }
}

/// Where the save-to-Photos flow is. Used for debug screens (`initialStage`).
enum PhotosSaveStage: Equatable {
    /// Explanation shown before the system's add-only Photos prompt.
    case permission
    /// Photos access was turned off; only the Settings app can change it.
    case denied
    /// The file is being added to the Photos library.
    case saving
    /// "Saved to Photos" with Open Photos.
    case saved
    /// Audio recordings can't go to Photos; offers Share instead.
    case audioOnly
    /// Saving failed for the given reason.
    case failed(PhotosSaveFailure)

    /// Stages that ask the person something, shown in a sheet. The others are a status card.
    var asksQuestion: Bool {
        switch self {
        case .permission, .denied, .audioOnly, .failed: return true
        case .saving, .saved: return false
        }
    }
}

enum PhotosSaveFailure: Equatable {
    /// Not enough free space for Photos to keep a copy.
    case outOfSpace
    /// The recording's file is missing from the library.
    case missingFile
    /// Anything else, with a plain-language reason.
    case other(String)
}
