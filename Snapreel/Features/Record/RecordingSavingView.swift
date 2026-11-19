import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// Saving progress, then failed (Retry, Delete) or out of space (Free up space, Retry, Delete).
/// Watches the video's state in the library and moves on to review when it is ready.
struct RecordingSavingView: View {
    let videoID: UUID
    let close: @MainActor () -> Void

    @EnvironmentObject private var model: RecorderModel
    @EnvironmentObject private var library: Library
    @State private var confirmsDelete = false

    var body: some View {
        Group {
            if let video = library.video(videoID) {
                content(video)
            } else {
                EmptyStateView(systemImage: "questionmark.folder", title: "This recording is gone",
                               message: "It may have been deleted.", onDark: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { checkReady() }
        .onChange(of: library.video(videoID)?.state) { _ in checkReady() }
        .confirmationDialog("Delete this recording?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete recording", role: .destructive) { model.deleteRecording(videoID) }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("It hasn't been saved yet, so it will be gone for good.")
        }
    }

    private func checkReady() {
        if library.video(videoID)?.state.isReady == true {
            model.savingFinished(videoID)
        }
    }

    @ViewBuilder private func content(_ video: Video) -> some View {
        switch video.state {
        case .saving(let progress):
            saving(progress)
        case .failed(let reason, let outOfSpace):
            if outOfSpace {
                noSpace(video)
            } else {
                failed(reason)
            }
        case .ready:
            // Saved: the model is about to show review. If that ever doesn't happen, the
            // person still has a way on instead of a spinner that never ends.
            saved
                .task { model.savingFinished(videoID) }
        }
    }

    private var saved: some View {
        VStack(spacing: Space.l) {
            Spacer()
            stateIcon("checkmark.circle.fill")
            Text("Saved to your library")
                .font(.srTitle)
                .foregroundStyle(.white)
            Spacer()
            Button("Continue") { model.savingFinished(videoID) }
                .buttonStyle(.srPrimary)
                .padding(.horizontal, Space.l)
            .padding(.bottom, Space.l)
        }
    }

    // MARK: States

    private func saving(_ progress: Double) -> some View {
        VStack(spacing: Space.l) {
            Spacer()
            ZStack {
                ProgressRing(progress: progress, lineWidth: 8)
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            .frame(width: 128, height: 128)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Saving, \(Int((progress * 100).rounded())) percent")
            VStack(spacing: Space.xs) {
                Text("Saving your recording")
                    .font(.srTitle)
                    .foregroundStyle(.white)
                Text("This only takes a moment. If you close the recorder, saving carries on, and picks up next time if Snapreel is closed.")
                    .font(.srCallout)
                    .foregroundStyle(Color.srOnDarkSecondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Space.xl)
            Spacer()
            Button("Close and keep saving") { close() }
                .buttonStyle(.srSecondary)
                .padding(.horizontal, Space.l)
                .padding(.bottom, Space.l)
        }
    }

    private func failed(_ reason: String) -> some View {
        VStack(spacing: Space.l) {
            Spacer()
            stateIcon("exclamationmark.triangle.fill")
            VStack(spacing: Space.xs) {
                Text("Couldn't save this recording")
                    .font(.srTitle)
                    .foregroundStyle(.white)
                Text(reason)
                    .font(.srCallout)
                    .foregroundStyle(Color.srOnDarkSecondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Space.xl)
            Spacer()
            VStack(spacing: Space.s) {
                Button("Try again") { model.retrySave(videoID) }
                    .buttonStyle(.srPrimary)
                Button("Delete recording") { confirmsDelete = true }
                    .buttonStyle(.srTertiary)
            }
            .padding(.horizontal, Space.l)
            .padding(.bottom, Space.l)
        }
    }

    private func noSpace(_ video: Video) -> some View {
        let needed = max(video.fileSize, 50_000_000) + 200_000_000
        return VStack(spacing: Space.l) {
            Spacer()
            stateIcon("externaldrive.fill.badge.exclamationmark")
            VStack(spacing: Space.xs) {
                Text("Your iPhone is full")
                    .font(.srTitle)
                    .foregroundStyle(.white)
                Text("Snapreel needs about \(Format.bytes(needed)) free to save this recording. It's kept safe until then. Free up some space, then try again.")
                    .font(.srCallout)
                    .foregroundStyle(Color.srOnDarkSecondary)
                // Shown when it explains the problem (always, on a phone that is really full).
                if DiskSpace.available < needed {
                    Text("Free now: \(Format.bytes(DiskSpace.available))")
                        .font(.srFootnote)
                        .foregroundStyle(Color.srOnDarkTertiary)
                        .padding(.top, Space.xxs)
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Space.xl)
            Spacer()
            VStack(spacing: Space.s) {
                Button("Free up space") { model.sheet = .storage }
                    .buttonStyle(.srPrimary)
                Button("Try again") { model.retrySave(videoID) }
                    .buttonStyle(.srSecondary)
                Button("Delete recording") { confirmsDelete = true }
                    .buttonStyle(.srTertiary)
            }
            .padding(.horizontal, Space.l)
            .padding(.bottom, Space.l)
        }
    }

    private func stateIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 30, weight: .semibold))
            .foregroundStyle(Color.srRed)
            .frame(width: 80, height: 80)
            .background(Circle().fill(Color.srInkControl))
            .accessibilityHidden(true)
    }
}

// MARK: - Import

/// Copying a video in from the photo library.
struct RecorderImportProgressView: View {
    let progress: Double
    @EnvironmentObject private var model: RecorderModel

    var body: some View {
        VStack(spacing: Space.l) {
            Spacer()
            ZStack {
                ProgressRing(progress: progress, lineWidth: 8)
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 128, height: 128)
            .accessibilityHidden(true)
            VStack(spacing: Space.xs) {
                Text("Copying your video")
                    .font(.srTitle)
                    .foregroundStyle(.white)
                Text("\(Int((progress * 100).rounded()))% · The original stays in Photos.")
                    .font(.srCallout)
                    .foregroundStyle(Color.srOnDarkSecondary)
                    .monospacedDigit()
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
            Spacer()
            Button("Cancel") { model.cancelImport() }
                .buttonStyle(.srSecondary)
                .padding(.horizontal, Space.l)
                .padding(.bottom, Space.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A video chosen in the photo picker, copied to a temporary file Snapreel owns.
/// The picker runs out of process, so no Photos permission is needed.
struct RecorderPickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("SnapreelImports", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let copy = folder.appendingPathComponent("\(UUID().uuidString).\(ext)")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return RecorderPickedMovie(url: copy)
        }
    }
}
