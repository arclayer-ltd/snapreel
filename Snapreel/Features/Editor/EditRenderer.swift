import AVFoundation
import UIKit

enum EditRenderError: Error, Equatable {
    case missingRecipe
    case missingSource
    case exportUnavailable
    case interrupted
    case failed

    var message: String {
        switch self {
        case .missingRecipe: return "This edit's details are missing, so it can't be saved."
        case .missingSource: return "The original recording is gone, so this edit can't be saved."
        case .exportUnavailable: return "Your iPhone couldn't start saving this edit. Try again."
        case .interrupted: return "Snapreel was closed while saving your edit. Try again."
        case .failed: return "Something went wrong while saving your edit. Try again."
        }
    }
}

/// Saves an edit as a new recording. The library row exists from the first moment (saving, with
/// progress), and `RecordingSaver` does the rest exactly as for a recording: when the file is
/// missing it asks `render` to make it, so a save interrupted by the app closing is made again
/// next launch, and a failure offers "Try saving again" in the library.
@MainActor
final class EditRenderer {
    static let shared = EditRenderer()

    private var sessions: [UUID: AVAssetExportSession] = [:]

    /// Adds the new recording's row and starts saving. Returns its id.
    func begin(recipe: EditRecipe, source: Video, library: Library) -> UUID {
        let id = UUID()
        let audioOnly = source.isAudioOnly
        let video = Video(id: id, title: Self.title(for: source), createdAt: Date(), kind: source.kind,
                          fileName: id.uuidString + (audioOnly ? ".m4a" : ".mp4"),
                          thumbnailFileName: nil, duration: recipe.outputDuration, fileSize: 0,
                          pixelWidth: 0, pixelHeight: 0, needsTitle: false,
                          folderID: source.folderID, tags: source.tags,
                          state: .saving(progress: 0.02), reviewedAt: Date(), editedFrom: source.id)
        library.saveEditOutput(EditOutput(videoID: id, recipe: recipe))
        library.add(video)
        RecordingSaver.shared.beginEdit(id, library: library)
        return id
    }

    static func title(for source: Video) -> String {
        source.needsTitle ? "Edited \(source.kind.titlePrefix.lowercased())" : "\(source.title) (edited)"
    }

    /// Stops a save in progress (the editor's Cancel).
    func cancel(_ id: UUID) {
        sessions[id]?.cancelExport()
    }

    func isRendering(_ id: UUID) -> Bool { sessions[id] != nil }

    /// Makes the edited file at `url` from the stored recipe, reporting progress on the row.
    func render(_ id: UUID, to url: URL, library: Library) async throws {
        guard let output = library.editOutput(id) else { throw EditRenderError.missingRecipe }
        let recipe = output.recipe
        guard let source = library.video(recipe.sourceID), source.state.isReady else { throw EditRenderError.missingSource }
        let sourceURL = library.fileURL(for: source)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { throw EditRenderError.missingSource }

        let info: EditSource
        do {
            info = try await EditSource.load(sourceURL)
        } catch {
            throw EditRenderError.missingSource
        }
        let estimate = EditEstimate.bytes(recipe: recipe, picture: info.hasVideo ? info.uprightSize : nil,
                                          quality: recipe.quality)
        guard DiskSpace.hasRoom(for: estimate) else { throw RecordingSaveError.noSpace }

        let folder = library.media.editFolder(source.id)
        let cleaned = folder.appendingPathComponent("clean-sound.m4a")
        if recipe.audio.reducesNoise && !FileManager.default.fileExists(atPath: cleaned.path) {
            try? await NoiseReducer.clean(source: sourceURL, to: cleaned) { _ in }
        }
        setProgress(id, 0.05, library: library)

        let renderSize = recipe.renderSize(source: info.uprightSize, quality: recipe.quality)
        let overlays = info.hasVideo
            ? EditOverlayRasterizer.images(recipe: recipe, transcript: library.transcript(for: source.id), size: renderSize)
            : []
        let build = try await EditCompositionBuilder.build(recipe: recipe, source: info, editFolder: folder,
                                                           cleanedAudio: cleaned,
                                                           purpose: .export(quality: recipe.quality, overlays: overlays))
        let preset = info.hasVideo ? AVAssetExportPresetHighestQuality : AVAssetExportPresetAppleM4A
        guard let session = AVAssetExportSession(asset: build.composition, presetName: preset) else {
            throw EditRenderError.exportUnavailable
        }
        try? FileManager.default.removeItem(at: url)
        session.outputURL = url
        session.outputFileType = info.hasVideo ? .mp4 : .m4a
        session.audioMix = build.audioMix
        session.videoComposition = build.videoComposition
        session.audioTimePitchAlgorithm = .spectral
        session.shouldOptimizeForNetworkUse = true

        sessions[id] = session
        var background = UIBackgroundTaskIdentifier.invalid
        background = UIApplication.shared.beginBackgroundTask(withName: "Saving an edit") {
            // Out of background time: the export fails and the save offers to try again.
            session.cancelExport()
        }
        let progress = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                self?.setProgress(id, 0.05 + Double(session.progress) * 0.9, library: library)
            }
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously {
                continuation.resume()
            }
        }
        progress.cancel()
        sessions[id] = nil
        let wentToBackground = UIApplication.shared.applicationState == .background
        if background != .invalid { UIApplication.shared.endBackgroundTask(background) }

        switch session.status {
        case .completed:
            setProgress(id, 0.96, library: library)
        case .cancelled:
            try? FileManager.default.removeItem(at: url)
            if wentToBackground { throw EditRenderError.interrupted }
            throw CancellationError()
        default:
            try? FileManager.default.removeItem(at: url)
            if let error = session.error, DiskSpace.isOutOfSpace(error) { throw RecordingSaveError.noSpace }
            throw wentToBackground ? EditRenderError.interrupted : EditRenderError.failed
        }
    }

    /// After the new recording is ready: its transcript comes from the original's (re-timed, no
    /// second recognition), and the draft and recipe are no longer needed.
    func finish(_ id: UUID, library: Library) -> Bool {
        guard let output = library.editOutput(id) else { return false }
        let recipe = output.recipe
        var hasTranscript = false
        if let transcript = library.transcript(for: recipe.sourceID) {
            let retimed = recipe.retimedTranscript(transcript, for: id)
            if !retimed.segments.isEmpty {
                library.saveTranscript(retimed)
                hasTranscript = true
            }
        }
        if let draft = library.draft(for: recipe.sourceID), draft.recipe.sameEdit(as: recipe) {
            library.deleteDraft(recipe.sourceID)
        }
        library.deleteEditOutput(id)
        library.removeEditFilesIfUnused(recipe.sourceID)
        return hasTranscript
    }

    /// Output seconds for the library card's frame.
    func thumbnailTime(_ id: UUID, library: Library, duration: Double) -> Double {
        if let time = library.editOutput(id)?.recipe.thumbnailTime {
            return min(max(0, time), max(0, duration - 0.05))
        }
        return min(0.5, duration / 2)
    }

    private func setProgress(_ id: UUID, _ value: Double, library: Library) {
        guard let video = library.video(id), case .saving(let current) = video.state, value > current else { return }
        library.update(id) { $0.state = .saving(progress: min(0.99, value)) }
    }
}
