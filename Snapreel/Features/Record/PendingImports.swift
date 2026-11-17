import Foundation

/// Session B owns this file. Called by the shell each time the app becomes active.
@MainActor
enum PendingImports {
    /// Moves finished screen recordings from the App Group inbox into the library.
    static func importFinishedBroadcasts(into library: Library) {}

    /// Resumes or marks failed any save that was interrupted when the app was closed.
    static func resumeInterruptedSaves(in library: Library) {}
}
