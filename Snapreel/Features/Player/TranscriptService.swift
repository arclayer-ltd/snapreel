import Foundation

/// Session C owns this file. On-device transcription. Session B calls `enqueue` after a
/// recording or import is saved; it posts `.transcriptReady` through `Notifier` when done.
@MainActor
final class TranscriptService {
    static let shared = TranscriptService()

    func enqueue(videoID: UUID, library: Library) {}
}
