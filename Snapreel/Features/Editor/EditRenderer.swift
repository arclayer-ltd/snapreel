import AVFoundation
import Combine
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
        case .exportUnavailable: return "Your iPhone couldn't start saving this edit. Close other apps and try again."
        case .interrupted: return "Saving was interrupted. Try again: it carries on from where it stopped."
        case .failed: return "Something went wrong while saving your edit. Try again, or choose 720p for a smaller file."
        }
    }
}

/// Saves an edit as a new recording. The library row exists from the first moment (saving, with
/// progress), and `RecordingSaver` does the rest exactly as for a recording: when the file is
/// missing it asks `render` to make it, so a save interrupted by the app closing carries on next
/// launch, and a failure offers "Try saving again" in the library.
@MainActor
final class EditRenderer: ObservableObject {
    static let shared = EditRenderer()

    /// A save in progress. It exists from before the first step, so Cancel works at any moment.
    private final class Job {
        var exporter: EditExporter?
        var isCancelled = false
    }

    private var jobs: [UUID: Job] = [:]
    private var observers: [NSObjectProtocol] = []
    private var isInBackground = false
    /// Edits whose save waits because Snapreel isn't on screen.
    @Published private(set) var isPaused = false

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

    /// Stops a save in progress (the editor's Cancel), whatever step it is at.
    func cancel(_ id: UUID) {
        jobs[id]?.isCancelled = true
        jobs[id]?.exporter?.cancel()
    }

    func isRendering(_ id: UUID) -> Bool { jobs[id] != nil }

    static func workFolder(_ id: UUID, in editFolder: URL) -> URL {
        editFolder.appendingPathComponent("saving-\(id.uuidString)", isDirectory: true)
    }

    /// Makes the edited file at `url` from the stored recipe, reporting progress on the row.
    func render(_ id: UUID, to url: URL, library: Library) async throws {
        guard let output = library.editOutput(id) else { throw EditRenderError.missingRecipe }
        let job = Job()
        jobs[id] = job
        observe()
        keepAwake()
        let background = BackgroundTime(name: "Saving an edit")
        defer {
            jobs[id] = nil
            keepAwake()
            background.end()
        }
        do {
            try await render(output, id: id, job: job, to: url, library: library)
        } catch {
            try? FileManager.default.removeItem(at: url)
            if job.isCancelled {
                try? FileManager.default.removeItem(at: Self.workFolder(id, in: library.media.editFolder(output.recipe.sourceID)))
                library.removeEditFilesIfUnused(output.recipe.sourceID)
                throw CancellationError()
            }
            throw error
        }
    }

    private func render(_ output: EditOutput, id: UUID, job: Job, to url: URL, library: Library) async throws {
        let recipe = output.recipe
        guard let source = library.video(recipe.sourceID), source.state.isReady else { throw EditRenderError.missingSource }
        // A screen recording's file is swapped for one with a single sound track shortly after it
        // is recorded; wait for that, so the file doesn't change underneath.
        await RecordingSaver.shared.waitUntilFinished(source.id)
        try check(job)
        let sourceURL = library.fileURL(for: source)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { throw EditRenderError.missingSource }

        let info: EditSource
        do {
            info = try await EditSource.load(sourceURL)
        } catch {
            throw EditRenderError.missingSource
        }
        try check(job)
        let settings = EditExportSettings(recipe: recipe, picture: info.hasVideo ? info.uprightSize : nil,
                                          sourceBitRate: info.videoBitRate, frameRate: Double(info.frameRate),
                                          quality: recipe.quality)
        guard EditEstimate.hasRoom(for: EditEstimate.bytes(recipe: recipe, settings: settings)) else { throw RecordingSaveError.noSpace }

        let folder = library.media.editFolder(source.id)
        let cleaned = folder.appendingPathComponent("clean-sound.m4a")
        if recipe.audio.reducesNoise && !FileManager.default.fileExists(atPath: cleaned.path) {
            try? await NoiseReducer.clean(source: sourceURL, to: cleaned) { _ in }
            try check(job)
        }
        setProgress(id, 0.03, library: library)

        let build = try await EditCompositionBuilder.build(recipe: recipe, source: info, editFolder: folder,
                                                           cleanedAudio: cleaned, originalSound: false)
        try check(job)
        guard build.duration > .zero else { throw EditRenderError.failed }
        let transcript = library.transcript(for: source.id)
        let drawing = EditOverlayRasterizer(recipe: recipe, transcript: transcript, size: settings.size,
                                            managed: info.isHDR)
        let plan = EditExportPlan(id: id, recipe: recipe, source: info, build: build, settings: settings,
                                  workFolder: Self.workFolder(id, in: folder), output: url,
                                  overlays: { drawing.images(in: $0) },
                                  overlayTimes: info.hasVideo ? drawing.times : [])
        let exporter = EditExporter(plan: plan) { fraction in
            Task { @MainActor in EditRenderer.shared.setProgress(id, 0.03 + fraction * 0.95, library: library) }
        }
        job.exporter = exporter
        if isInBackground { exporter.suspend() }
        do {
            try await exporter.run()
        } catch EditExportFailure.cancelled {
            throw CancellationError()
        } catch EditExportFailure.interrupted {
            throw EditRenderError.interrupted
        } catch EditExportFailure.failed(let underlying) {
            if let underlying, DiskSpace.isOutOfSpace(underlying) { throw RecordingSaveError.noSpace }
            throw isInBackground ? EditRenderError.interrupted : EditRenderError.failed
        } catch {
            if DiskSpace.isOutOfSpace(error) { throw RecordingSaveError.noSpace }
            throw EditRenderError.failed
        }
        try check(job)
        setProgress(id, 0.98, library: library)
    }

    private func check(_ job: Job) throws {
        if job.isCancelled { throw CancellationError() }
    }

    // MARK: - Leaving and coming back

    /// Drawing and encoding aren't allowed in the background, so a save stops as Snapreel leaves
    /// the screen and carries on, from the last few seconds, as it comes back.
    private func observe() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { EditRenderer.shared.setBackground(true) }
        })
        observers.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { EditRenderer.shared.setBackground(false) }
        })
        isInBackground = UIApplication.shared.applicationState == .background
    }

    func setBackground(_ background: Bool) {
        isInBackground = background
        for job in jobs.values {
            if background { job.exporter?.suspend() } else { job.exporter?.resume() }
        }
        isPaused = background && !jobs.isEmpty
    }

    /// The screen stays on while an edit saves, so the iPhone doesn't lock halfway.
    private func keepAwake() {
        UIApplication.shared.isIdleTimerDisabled = !jobs.isEmpty
    }

    // MARK: - Afterwards

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
        try? FileManager.default.removeItem(at: Self.workFolder(id, in: library.media.editFolder(recipe.sourceID)))
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

    /// On the row, a percent at a time: each change is written to the database and redraws the
    /// library.
    private func setProgress(_ id: UUID, _ value: Double, library: Library) {
        guard let video = library.video(id), case .saving(let current) = video.state,
              value >= current + 0.01 || value >= 0.98 && value > current else { return }
        library.update(id) { $0.state = .saving(progress: min(0.99, value)) }
    }
}

/// Asks iOS for a little more time when the app leaves the screen.
@MainActor
private final class BackgroundTime {
    private var id = UIBackgroundTaskIdentifier.invalid

    init(name: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}

/// File size of an edit before it is made.
enum EditEstimate {
    static func bytes(recipe: EditRecipe, settings: EditExportSettings) -> Int64 {
        Int64((settings.videoBitRate + EditExportSettings.audioBitRate) * max(0, recipe.outputDuration) / 8)
    }

    /// Room for the file and the pieces it is put together from, and 200 MB left over.
    static func hasRoom(for bytes: Int64, available: Int64 = DiskSpace.available) -> Bool {
        available - spaceNeeded(for: bytes) > 0
    }

    static func spaceNeeded(for bytes: Int64) -> Int64 { bytes * 2 + bytes / 4 + 200_000_000 }
}
