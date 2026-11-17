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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var stage: PhotosSaveStage?
    /// The last question shown, kept while its sheet animates away.
    @State private var question: PhotosSaveStage = .permission
    /// The recording being saved (kept after closing so a closing sheet keeps its content).
    @State private var target: Video?
    /// The request in progress, so a repeated request for the same video is ignored.
    @State private var activeID: UUID?
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
        ZStack(alignment: .bottom) {
            if let stage, !stage.asksQuestion, let target {
                PhotosStatusCard(video: target, isSaved: stage == .saved, onOpenPhotos: { openPhotos() })
                    .padding(.horizontal, Space.gutter)
                    .padding(.bottom, bottomInset)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : Motion.standard, value: stage)
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

    private func startIfRequested() {
        guard let requested = video, activeID != requested.id else { return }
        activeID = requested.id
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

    private func begin(_ video: Video) {
        if video.isAudioOnly {
            Haptics.warning()
            showQuestion(.audioOnly)
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
        case .saving, .saved:
            break
        }
    }

    private func requestAccess(for video: Video) {
        stage = nil // closes the explanation; the system prompt follows
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            let state = await Permissions.request(.photosAdd)
            if state == .granted {
                save(video)
            } else {
                Haptics.warning()
                show(.denied)
            }
        }
    }

    private func retry(_ video: Video) {
        stage = nil
        Task { @MainActor in
            // Let the sheet finish closing before anything else is shown.
            try? await Task.sleep(nanoseconds: 400_000_000)
            begin(video)
        }
    }

    private func save(_ video: Video) {
        let source = library.fileURL(for: video)
        guard FileManager.default.fileExists(atPath: source.path) else {
            Haptics.error()
            showQuestion(.failed(.missingFile))
            return
        }
        // Photos keeps its own copy, so it needs about the file's size free.
        if DiskSpace.available > 0, !DiskSpace.hasRoom(for: video.fileSize) {
            Haptics.error()
            showQuestion(.failed(.outOfSpace))
            return
        }
        show(.saving)
        UIAccessibility.post(notification: .announcement, argument: "Saving to Photos")
        let fileName = ShareFile.fileName(for: video.title, pathExtension: source.pathExtension)
        let videoID = video.id
        let store = library
        Task { @MainActor in
            let started = Date()
            var failure: PhotosSaveStage?
            do {
                try await PhotosLibraryWriter.addVideo(at: source, originalFilename: fileName)
            } catch {
                failure = PhotosLibraryWriter.stage(for: error)
            }
            // Keep the progress card up long enough to read, even for a short clip.
            let elapsed = Date().timeIntervalSince(started)
            if elapsed < 0.8 {
                try? await Task.sleep(nanoseconds: UInt64((0.8 - elapsed) * 1_000_000_000))
            }
            if let failure {
                Haptics.error()
                show(failure)
                return
            }
            store.recordSavedToPhotos(videoID)
            Haptics.success()
            UIAccessibility.post(notification: .announcement, argument: "Saved to Photos")
            show(.saved)
            let token = UUID()
            savedToken = token
            let seconds: UInt64 = UIAccessibility.isVoiceOverRunning ? 8 : 4
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            if stage == .saved, savedToken == token, !isFrozen { close() }
        }
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
        stage = nil
        activeID = nil
        isFrozen = false
        video = nil
    }
}

// MARK: - Writing to the Photos library

enum PhotosLibraryWriter {
    /// Adds the file as a new video in Photos. The library keeps its own file
    /// (`shouldMoveFile = false`); works with add-only access.
    static func addVideo(at fileURL: URL, originalFilename: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = false
                options.originalFilename = originalFilename
                let request = PHAssetCreationRequest.forAsset()
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
        let ns = error as NSError
        // PHPhotosErrorDomain codes: 3305 not enough space, 3302 invalid resource,
        // 3310 access restricted, 3311 access denied by the person.
        let isPhotosError = ns.domain == "PHPhotosErrorDomain"
        if DiskSpace.isOutOfSpace(error) || (isPhotosError && ns.code == 3305) {
            return .failed(.outOfSpace)
        }
        if (isPhotosError && (ns.code == 3310 || ns.code == 3311)) || Permissions.currentState(.photosAdd) == .denied {
            return .denied
        }
        if isPhotosError && ns.code == 3302 {
            return .failed(.other("Photos couldn't read this recording's file. It may still be finishing, so try again in a moment."))
        }
        return .failed(.other("Photos couldn't add the recording just now. Try again in a moment."))
    }
}
