import AVFoundation
import SwiftUI

/// After a recording or import is saved: watch it back, name it, send it, or delete it.
struct RecordingReviewView: View {
    let videoID: UUID
    let done: @MainActor () -> Void

    @EnvironmentObject private var model: RecorderModel
    @EnvironmentObject private var library: Library
    @State private var confirmsDelete: Bool
    @State private var editsTitle: Bool
    @State private var shareTarget: Video?
    @State private var photosTarget: Video?
    @State private var pendingShare: Bool

    init(videoID: UUID, initialPanel: RecorderReviewPanel?, done: @escaping @MainActor () -> Void) {
        self.videoID = videoID
        self.done = done
        _confirmsDelete = State(initialValue: initialPanel == .delete)
        _editsTitle = State(initialValue: initialPanel == .title)
        _pendingShare = State(initialValue: initialPanel == .share)
    }

    var body: some View {
        Group {
            if let video = library.video(videoID) {
                content(video)
            } else {
                Color.clear
            }
        }
        .shareVideo($shareTarget)
        .saveToPhotos($photosTarget)
        .onAppear {
            if pendingShare {
                pendingShare = false
                shareTarget = library.video(videoID)
            }
        }
    }

    private func content(_ video: Video) -> some View {
        VStack(spacing: Space.m) {
            if let note = model.reviewNote {
                ReviewNoteBanner(text: note)
            }
            ReviewPlayerView(video: video, url: library.fileURL(for: video), autoplay: !model.isStatic)
            ReviewTitleBlock(video: video) { editsTitle = true }
            actions(video)
            Button {
                done()
            } label: {
                Text("Done")
            }
            .buttonStyle(.srPrimary)
        }
        .padding(.horizontal, Space.m)
        .padding(.top, Space.xs)
        .padding(.bottom, Space.xs)
        .sheet(isPresented: $editsTitle) {
            TitleEditorSheet(initialTitle: video.needsTitle ? "" : video.title, heading: "Title", onStage: true,
                             onSave: { title in
                                 model.renameRecording(video.id, to: title)
                                 editsTitle = false
                             },
                             onCancel: { editsTitle = false })
                .presentationDetents([.height(220)])
        }
        .confirmationDialog("Delete this recording?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete recording", role: .destructive) { model.deleteRecording(video.id) }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("It will be removed from this iPhone. You can't undo this.")
        }
    }

    private func actions(_ video: Video) -> some View {
        HStack(spacing: 0) {
            ReviewActionButton(systemImage: "trash", title: "Delete", tint: Color.srStageRed) {
                confirmsDelete = true
            }
            ReviewActionButton(systemImage: "character.cursor.ibeam", title: "Title", tint: Color.srStageText) {
                editsTitle = true
            }
            ReviewActionButton(systemImage: "square.and.arrow.up", title: "Share", tint: Color.srStageText) {
                shareTarget = library.video(video.id)
            }
            if !video.isAudioOnly {
                ReviewActionButton(systemImage: "square.and.arrow.down", title: "Save to Photos", tint: Color.srStageText) {
                    photosTarget = library.video(video.id)
                }
            }
        }
    }
}

private struct ReviewNoteBanner: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Space.xs) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Color.srStageRed)
            Text(text)
                .font(.srFootnote)
                .foregroundStyle(Color.srStageText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.s)
        .background(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).fill(Color.srStageControl))
        .accessibilityElement(children: .combine)
    }
}

/// Title (tap to edit) and what the recording is.
private struct ReviewTitleBlock: View {
    let video: Video
    let edit: @MainActor () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            edit()
        } label: {
            HStack(alignment: .center, spacing: Space.s) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(video.needsTitle ? "Add a title" : video.title)
                        .font(.srTitle3)
                        .foregroundStyle(video.needsTitle ? Color.srStageTextSecondary : Color.srStageText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(details)
                        .font(.srFootnote)
                        .foregroundStyle(Color.srStageTextTertiary)
                }
                Spacer(minLength: Space.xs)
                Image(systemName: "pencil")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.srStageTextSecondary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.srStageControl))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(video.needsTitle ? "Add a title" : "Title, \(video.title)")
        .accessibilityHint("Edits the title")
    }

    private var details: String {
        var parts = [video.kind.label, Format.clock(video.duration)]
        if video.fileSize > 0 { parts.append(Format.bytes(video.fileSize)) }
        return parts.joined(separator: " · ")
    }
}

private struct ReviewActionButton: View {
    let systemImage: String
    let title: String
    let tint: Color
    let action: @MainActor () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Color.srStageControl))
                Text(title)
                    .font(.srCaption)
                    .foregroundStyle(Color.srStageTextSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Player

/// Plays the recording once (no loop). Tap to pause or play.
private struct ReviewPlayerView: View {
    let video: Video
    let url: URL
    let autoplay: Bool
    @StateObject private var player: RecorderReviewPlayer

    init(video: Video, url: URL, autoplay: Bool) {
        self.video = video
        self.url = url
        self.autoplay = autoplay
        _player = StateObject(wrappedValue: RecorderReviewPlayer(url: url, duration: video.duration))
    }

    var body: some View {
        ZStack {
            Color.black
            if video.isAudioOnly {
                AudioArtwork(seed: video.id.hashValue)
            } else {
                RecorderPlayerLayer(player: player.player)
            }
            if !player.isPlaying {
                Image(systemName: "play.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(Color.black.opacity(0.5)))
                    .transition(.opacity)
            }
            VStack {
                Spacer()
                progressBar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { player.toggle() }
        .animation(Motion.quick, value: player.isPlaying)
        .onAppear { if autoplay { player.play() } }
        .onDisappear { player.stop() }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime,
                                                         object: player.player.currentItem)) { _ in
            player.reachedEnd()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(player.isPlaying ? "Playing your recording" : "Your recording, paused")
        .accessibilityHint("Double-tap to play or pause")
        .accessibilityAddTraits(.startsMediaSession)
    }

    private var progressBar: some View {
        HStack(spacing: Space.xs) {
            Text(Format.clock(player.position))
                .font(.srTimerSmall)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.25))
                    Capsule().fill(Color.srRed)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 4)
            Text(Format.clock(player.duration))
                .font(.srTimerSmall)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Space.s)
        .padding(.vertical, Space.xs)
        .background(LinearGradient(colors: [.clear, Color.black.opacity(0.55)], startPoint: .top, endPoint: .bottom))
    }

    private var fraction: CGFloat {
        guard player.duration > 0 else { return 0 }
        return CGFloat(min(1, max(0, player.position / player.duration)))
    }
}

@MainActor
final class RecorderReviewPlayer: ObservableObject {
    let player: AVPlayer
    @Published private(set) var isPlaying = false
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double
    private var timeObserver: Any?

    init(url: URL, duration: Double) {
        player = AVPlayer(url: url)
        player.actionAtItemEnd = .pause
        self.duration = duration
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
                                                      queue: .main) { [weak self] time in
            let seconds = time.seconds
            Task { @MainActor in self?.update(position: seconds) }
        }
    }

    private func update(position: Double) {
        guard position.isFinite else { return }
        self.position = position
        if let itemDuration = player.currentItem?.duration.seconds, itemDuration.isFinite, itemDuration > 0 {
            duration = itemDuration
        }
    }

    func play() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        if duration > 0 && position >= duration - 0.15 {
            player.seek(to: .zero)
            position = 0
        }
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func toggle() {
        if isPlaying { pause() } else { play() }
    }

    func reachedEnd() {
        isPlaying = false
        position = duration
    }

    func stop() {
        player.pause()
        isPlaying = false
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }
}

/// AVPlayerLayer in a view, aspect fit.
struct RecorderPlayerLayer: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> RecorderPlayerLayerView {
        let view = RecorderPlayerLayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: RecorderPlayerLayerView, context: Context) {
        if uiView.playerLayer.player !== player { uiView.playerLayer.player = player }
    }
}

final class RecorderPlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        // layerClass guarantees the type.
        layer as! AVPlayerLayer
    }
}
