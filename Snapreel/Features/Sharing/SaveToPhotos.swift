import Photos
import SwiftUI
import UIKit

// MARK: - .saveToPhotos

/// `.saveToPhotos($video)`: add-only permission (explained first), progress, confirmation.
@MainActor
struct SaveToPhotosModifier: ViewModifier {
    @Binding var video: Video?
    /// Debug: the first request opens at this stage and stays there.
    let initialStage: PhotosSaveStage?
    /// Space between the bottom edge of the view and the status card.
    var bottomInset: CGFloat = Space.l

    @EnvironmentObject private var library: Library
    @State private var stage: PhotosSaveStage?
    /// The last question shown, kept while its sheet animates away.
    @State private var question: PhotosSaveStage = .permission
    /// The recording being saved (kept after closing so a closing sheet keeps its content).
    @State private var target: Video?
    /// The request in progress, so a repeated request for the same video is ignored.
    @State private var activeID: UUID?
    /// Changes with every request and every ending: work started for an earlier one stops mattering.
    @State private var token = UUID()
    /// The system's Photos prompt is up.
    @State private var isAsking = false
    @State private var copyJob: ShareCopyJob?
    /// Saving has taken a while, so the card says why.
    @State private var isSlow = false
    @State private var usedInitialStage = false
    @State private var isFrozen = false
    @State private var savedToken = UUID()
    @State private var shareInstead: Video?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) { statusOverlay }
            .sheet(isPresented: questionPresented) { questionSheet }
            .shareVideo($shareInstead)
            .onAppear { startIfRequested() }
            .onChange(of: video?.id) { _ in startIfRequested() }
    }

    // MARK: Views

    private var statusOverlay: some View {
        SharingCardOverlay(isPresented: stage.map { !$0.asksQuestion } ?? false, bottomInset: bottomInset) {
            if let stage, let target { card(stage, target) }
        }
    }

    @ViewBuilder private func card(_ stage: PhotosSaveStage, _ video: Video) -> some View {
        switch stage {
        case .preparing(let progress):
            SharingStatusCard(video: video,
                              title: video.kind == .screen ? "Finishing the sound" : "Getting the video ready",
                              detail: SharingStatusCard.detail(progress: progress, of: video),
                              progress: progress, showsBar: true,
                              actionTitle: "Cancel", actionHint: "Stops saving to Photos",
                              action: { close() })
        case .saved:
            SharingStatusCard(video: video, title: "Saved to Photos", detail: video.title, isDone: true,
                              actionTitle: "Open Photos", actionHint: "Opens the Photos app",
                              action: { openPhotos() })
        default:
            // Photos doesn't say how far it is, so the bar doesn't pretend to know.
            SharingStatusCard(video: video, title: "Saving to Photos\u{2026}",
                              detail: isSlow ? "\(Format.bytes(video.fileSize)), this can take a minute" : video.title,
                              showsBar: true)
        }
    }

    @ViewBuilder private var questionSheet: some View {
        if let target {
            PhotosQuestionSheet(stage: question, video: target,
                                onPrimary: { primaryTapped() }, onSecondary: { close() })
                .environmentObject(library)
        }
    }

    private var questionPresented: Binding<Bool> {
        Binding(get: { stage?.asksQuestion ?? false },
                set: { presented in
                    // Swiped away by the person: same as "Not now".
                    if !presented, stage?.asksQuestion == true { close() }
                })
    }

    // MARK: Flow

    private var isBusy: Bool { stage != nil || isAsking }

    private func startIfRequested() {
        guard let requested = video, activeID != requested.id || !isBusy else { return }
        activeID = requested.id
        token = UUID()
        copyJob = nil
        let current = library.video(requested.id) ?? requested
        target = current
        if let initialStage, !usedInitialStage {
            usedInitialStage = true
            isFrozen = true
            if initialStage.asksQuestion {
                // Give a screen that is still being presented time to settle first.
                showQuestion(initialStage, after: 0.6)
            } else {
                show(initialStage)
            }
            return
        }
        isFrozen = false
        begin(current)
    }

    private func begin(_ video: Video, again: Bool = false) {
        if video.isAudioOnly {
            Haptics.warning()
            showQuestion(.audioOnly)
            return
        }
        if case .failed = video.state {
            Haptics.error()
            showQuestion(.failed(.other("This recording isn't saved yet, so there's nothing to add to Photos.")))
            return
        }
        // Photos can't tell Snapreel what it already has (add-only access), so Snapreel remembers.
        if !again, video.photosSaveCount > 0 {
            showQuestion(.alreadySaved(video.photosSaveCount))
            return
        }
        switch Permissions.currentState(.photosAdd) {
        case .granted: save(video)
        case .notDetermined: showQuestion(.permission)
        case .denied: showQuestion(.denied)
        }
    }

    private func primaryTapped() {
        guard let current = stage, let target else { return }
        isFrozen = false
        switch current {
        case .permission:
            requestAccess(for: target)
        case .alreadySaved:
            retry(target, again: true)
        case .denied:
            close()
            Permissions.openSettings()
        case .audioOnly:
            close()
            shareInstead = target
        case .failed(.missingFile):
            close()
        case .failed:
            retry(target)
        case .preparing, .saving, .saved:
            break
        }
    }

    private func requestAccess(for video: Video) {
        isAsking = true
        stage = nil // closes the explanation; the system prompt follows
        let mine = token
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            let state = await Permissions.request(.photosAdd)
            isAsking = false
            guard token == mine else { return }
            if state == .granted {
                save(video)
            } else {
                Haptics.warning()
                show(.denied)
            }
        }
    }

    private func retry(_ video: Video, again: Bool = false) {
        isAsking = true
        stage = nil
        let mine = token
        Task { @MainActor in
            // Let the sheet finish closing before anything else is shown.
            try? await Task.sleep(nanoseconds: 400_000_000)
            isAsking = false
            guard token == mine else { return }
            begin(library.video(video.id) ?? video, again: again)
        }
    }

    private func save(_ video: Video) {
        let mine = token
        isSlow = false
        // Says something at once, whatever has to happen first.
        show(.saving)
        Task { @MainActor in
            do {
                let file = try await readyFile(video, token: mine)
                guard token == mine else { return }
                try await add(file, token: mine)
            } catch {
                guard token == mine else { return }
                failed(with: error)
            }
        }
    }

    private struct ReadyFile {
        var video: Video
        var url: URL
        /// Made for this save, so Photos takes it over instead of copying it.
        var isCopy: Bool
    }

    /// The file Photos gets: the recording's own once it is finished, or a copy where its file
    /// can't go as it is.
    private func readyFile(_ requested: Video, token mine: UUID) async throws -> ReadyFile {
        var video = library.video(requested.id) ?? requested
        let saver = RecordingSaver.shared
        if saver.isFileChanging(video.id) {
            let progress = Task { @MainActor in
                while !Task.isCancelled, token == mine {
                    show(.preparing(saver.fileProgress(video.id)))
                    try? await Task.sleep(nanoseconds: 150_000_000)
                }
            }
            await saver.waitUntilFileSettled(video.id)
            progress.cancel()
            guard token == mine else { throw MovieRewriteError.cancelled }
            guard let settled = library.video(video.id) else { throw ShareFlowProblem.missing }
            video = settled
            target = settled
        }
        guard video.state.isReady else { throw ShareFlowProblem.notSaved }
        let source = library.fileURL(for: video)
        guard FileManager.default.fileExists(atPath: source.path) else { throw ShareFlowProblem.missing }
        // Photos keeps its own copy, so it needs about the file's size free.
        if DiskSpace.available > 0, !DiskSpace.hasRoom(for: video.fileSize) { throw MovieRewriteError.noSpace }

        let plan = try? await MoviePlan.make(for: source, isScreenRecording: video.kind == .screen)
        guard token == mine else { throw MovieRewriteError.cancelled }
        guard let plan, plan.needsRewrite else { return ReadyFile(video: video, url: source, isCopy: false) }
        do {
            for attempt in 0... {
                let job = ShareCopies.shared.job(for: video, source: source, kind: .complete(plan), root: library.media.root)
                copyJob = job
                show(.preparing(nil))
                let progress = Task { @MainActor in
                    while !Task.isCancelled, token == mine {
                        show(.preparing(job.progress))
                        try? await Task.sleep(nanoseconds: 150_000_000)
                    }
                }
                defer { progress.cancel() }
                do {
                    let url = try await job.value()
                    guard token == mine else { throw MovieRewriteError.cancelled }
                    return ReadyFile(video: video, url: url, isCopy: true)
                } catch MovieRewriteError.interrupted where attempt < 2 && token == mine {
                    await BackgroundTime.waitUntilActive()
                    guard token == mine else { throw MovieRewriteError.cancelled }
                }
            }
        } catch MovieRewriteError.failed, MovieRewriteError.unreadable {
            // As it is, then: Photos says so if it can't read it either.
        }
        return ReadyFile(video: video, url: source, isCopy: false)
    }

    private func add(_ file: ReadyFile, token mine: UUID) async throws {
        target = file.video
        show(.saving)
        UIAccessibility.post(notification: .announcement, argument: "Saving to Photos")
        let background = BackgroundTime("Saving to Photos") {}
        defer { background.end() }
        let slow = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled, token == mine { isSlow = true }
        }
        defer { slow.cancel() }
        let started = Date()
        let name = ShareFileLink.fileName(for: file.video.title, pathExtension: file.url.pathExtension)
        let useName = file.url.lastPathComponent
        ShareFilesInUse.add(useName)
        defer { ShareFilesInUse.remove(useName) }
        try await PhotosLibraryWriter.addVideo(at: file.url, originalFilename: name, created: file.video.createdAt,
                                               movesFile: file.isCopy)
        library.recordSavedToPhotos(file.video.id)
        // Keep the progress card up long enough to read, even for a short clip.
        let elapsed = Date().timeIntervalSince(started)
        if elapsed < 0.8 { try? await Task.sleep(nanoseconds: UInt64((0.8 - elapsed) * 1_000_000_000)) }
        guard token == mine else { return }
        Haptics.success()
        UIAccessibility.post(notification: .announcement, argument: "Saved to Photos")
        show(.saved)
        let shown = UUID()
        savedToken = shown
        // Long enough to read it and reach Open Photos.
        let seconds: UInt64 = UIAccessibility.isVoiceOverRunning ? 12 : 7
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            if stage == .saved, savedToken == shown, !isFrozen { close() }
        }
    }

    private func failed(with error: Error) {
        switch error {
        case MovieRewriteError.cancelled:
            close()
            return
        case ShareFlowProblem.missing: showFailure(.failed(.missingFile))
        case ShareFlowProblem.notSaved:
            showFailure(.failed(.other("This recording isn't saved yet, so there's nothing to add to Photos.")))
        case MovieRewriteError.noSpace: showFailure(.failed(.outOfSpace))
        case MovieRewriteError.interrupted:
            showFailure(.failed(.other("Snapreel was stopped while it finished this recording. Try again and stay in Snapreel until it's saved.")))
        default: showFailure(PhotosLibraryWriter.stage(for: error))
        }
    }

    private func showFailure(_ stage: PhotosSaveStage) {
        Haptics.error()
        showQuestion(stage)
    }

    private func show(_ newStage: PhotosSaveStage) {
        if newStage.asksQuestion { question = newStage }
        stage = newStage
    }

    /// Shows a question sheet after a short pause, so a sheet or menu the caller closed in the
    /// same tap has finished closing (two sheets can't animate at once).
    private func showQuestion(_ newStage: PhotosSaveStage, after delay: Double = 0.3) {
        let requestID = activeID
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard requestID != nil, activeID == requestID else { return }
            show(newStage)
        }
    }

    private func openPhotos() {
        Haptics.tap()
        if let url = URL(string: "photos-redirect://") {
            UIApplication.shared.open(url)
        }
        close()
    }

    private func close() {
        token = UUID()
        copyJob?.cancel()
        copyJob = nil
        stage = nil
        activeID = nil
        isAsking = false
        isFrozen = false
        video = nil
    }
}

// MARK: - Writing to the Photos library

enum PhotosLibraryWriter {
    /// Adds the file as a new video in Photos, dated when it was recorded. The library keeps its own
    /// file unless `movesFile`. Works with add-only access.
    static func addVideo(at fileURL: URL, originalFilename: String, created: Date? = nil,
                         movesFile: Bool = false) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = movesFile
                options.originalFilename = originalFilename
                let request = PHAssetCreationRequest.forAsset()
                request.creationDate = created
                request.addResource(with: .video, fileURL: fileURL, options: options)
            }, completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? CocoaError(.fileWriteUnknown))
                }
            })
        }
    }

    /// What to tell the person when saving failed.
    static func stage(for error: Error) -> PhotosSaveStage {
        stage(for: error, accessDenied: Permissions.currentState(.photosAdd) == .denied)
    }

    static func stage(for error: Error, accessDenied: Bool) -> PhotosSaveStage {
        let ns = error as NSError
        // PHPhotosErrorDomain codes, by number because several are newer than iOS 16's SDK names:
        // 3072 cancelled, 3114/3142/3143 the library is busy or moving, 3164/3169 needs the network,
        // 3301 interrupted, 3302 invalid resource, 3303 missing resource, 3305 not enough space,
        // 3310 access restricted, 3311 access denied by the person.
        let code = ns.domain == "PHPhotosErrorDomain" ? ns.code : 0
        if DiskSpace.isOutOfSpace(error) || code == 3305 { return .failed(.outOfSpace) }
        if code == 3310 || code == 3311 || accessDenied { return .denied }
        switch code {
        case 3114, 3142, 3143:
            return .failed(.other("Photos is busy with its library right now. Try again in a moment."))
        case 3164, 3169:
            return .failed(.other("Photos needs a connection to iCloud for this. Check your connection, then try again."))
        case 3301:
            return .failed(.other("iOS stopped the save before it was done. Try again and stay in Snapreel until it's saved."))
        case 3302, 3303:
            return .failed(.other("Photos couldn't read this recording's file. Share the recording to Files instead, or try again in a moment."))
        default:
            return .failed(.other("Photos couldn't add the recording just now. Try again in a moment."))
        }
    }
}
