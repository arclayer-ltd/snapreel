import AVFoundation
import SwiftUI

/// After a recording or import is saved: watch it back, name it, send it, or delete it.
struct RecordingReviewView: View {
    let videoID: UUID
    let done: @MainActor () -> Void

    @EnvironmentObject private var model: RecorderModel
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var router: AppRouter
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
        // Over the top of the picture, not over Edit and Done.
        .sharingCardsAtTop()
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
            ReviewPlayerView(video: video, url: library.fileURL(for: video), autoplay: !model.isStatic,
                             startAt: model.preset?.reviewPosition)
            ReviewTitleBlock(video: video) { editsTitle = true }
            actions(video)
            HStack(spacing: Space.s) {
                // Trim the start and end, cut sentences, add text: the edit is a new recording.
                Button {
                    Haptics.tap()
                    done()
                    router.edit(video.id, afterClosing: true)
                } label: {
                    Label("Edit", systemImage: "scissors")
                }
                .buttonStyle(SRButtonStyle(kind: .secondary, fullWidth: false))
                .disabled(!video.state.isReady)
                .accessibilityHint("Opens the editor. Your recording stays as it is.")
                Button {
                    done()
                } label: {
                    Text("Done")
                }
                .buttonStyle(.srPrimary)
            }
            // At the largest sizes Edit was cut to "E" beside Done.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
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
        HStack(alignment: .top, spacing: 0) {
            ReviewActionButton(systemImage: "trash", title: "Delete", tint: Color.srStageRed) {
                confirmsDelete = true
            }
            ReviewActionButton(systemImage: "character.cursor.ibeam", title: "Title", tint: Color.srStageText) {
                editsTitle = true
            }
            // Both wait for a screen recording's sound mix themselves, with a progress card
            // (`.shareVideo`, `.saveToPhotos`).
            ReviewActionButton(systemImage: "square.and.arrow.up", title: "Share", tint: Color.srStageText) {
                shareTarget = library.video(video.id)
            }
            ReviewActionButton(systemImage: "link", title: "Copy link", tint: Color.srStageRed) {
                ShareLinks.shared.copyLink(video.id)
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
                // The same size under every button: a longer title takes a second line instead of shrinking.
                Text(title)
                    .font(.srCaption)
                    .foregroundStyle(Color.srStageTextSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    // Five to a row: past this size the words break apart. Holding a button shows
                    // its name large instead.
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
        .accessibilityShowsLargeContentViewer {
            Label(title, systemImage: systemImage)
        }
    }
}

// MARK: - Player

/// Plays the recording once (no loop). Tap to pause or play. A video plays on black with its
/// controls on a scrim; a voice recording has no picture, so its panel follows the appearance
/// and its bars move with the recorded voice.
private struct ReviewPlayerView: View {
    let video: Video
    let url: URL
    let autoplay: Bool
    let startAt: Double?
    @StateObject private var player: RecorderReviewPlayer
    @State private var isOnScreen = false
    /// Plays by itself once: coming back from a share sheet or another screen leaves it as it was.
    @State private var hasStarted = false

    init(video: Video, url: URL, autoplay: Bool, startAt: Double? = nil) {
        self.video = video
        self.url = url
        self.autoplay = autoplay
        self.startAt = startAt
        _player = StateObject(wrappedValue: RecorderReviewPlayer(url: url, duration: video.duration))
    }

    var body: some View {
        ZStack {
            onPicture ? Color.black : Color.srStageRaised
            if video.isAudioOnly {
                AudioPlaybackBars(url: url, player: player.player, isPlaying: player.isPlaying,
                                  time: player.position)
            } else {
                RecorderPlayerLayer(player: player.player)
            }
            if !player.isPlaying {
                Image(systemName: "play.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(onPicture ? Color.white : Color.srStageText)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(onPicture ? Color.black.opacity(0.5) : Color.srStageControl))
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
        .onAppear {
            isOnScreen = true
            guard !hasStarted else { return }
            hasStarted = true
            if let startAt { player.seek(to: startAt) }
            guard autoplay else { return }
            if video.isAudioOnly {
                // The bars are ready before the sound starts: from the take itself, or read
                // from the file (a fraction of a second).
                Task { @MainActor in
                    _ = await AudioEnvelope.load(url)
                    if isOnScreen { player.play() }
                }
            } else {
                player.play()
            }
        }
        .onDisappear {
            isOnScreen = false
            player.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime,
                                                         object: player.player.currentItem)) { _ in
            player.reachedEnd()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(player.isPlaying ? "Playing your recording" : "Your recording, paused")
        .accessibilityHint("Double-tap to play or pause")
        .accessibilityAddTraits(.startsMediaSession)
    }

    private var onPicture: Bool { !video.isAudioOnly }

    private var progressBar: some View {
        HStack(spacing: Space.xs) {
            Text(Format.clock(player.position))
                .font(.srTimerSmall)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(onPicture ? Color.white.opacity(0.25) : Color.srStageText.opacity(0.18))
                    Capsule().fill(Color.srRed)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 4)
            Text(Format.clock(player.duration))
                .font(.srTimerSmall)
        }
        .foregroundStyle(onPicture ? Color.white : Color.srStageTextSecondary)
        .padding(.horizontal, Space.s)
        .padding(.vertical, Space.xs)
        .background(LinearGradient(colors: [.clear, onPicture ? Color.black.opacity(0.55) : Color.clear],
                                   startPoint: .top, endPoint: .bottom))
    }

    private var fraction: CGFloat {
        guard player.duration > 0 else { return 0 }
        return CGFloat(min(1, max(0, player.position / player.duration)))
    }
}

/// `isPlaying` follows what the player really does: iOS can pause it (another app's sound, a call,
/// a share sheet's activity), and then the Play button comes back and VoiceOver says "paused".
@MainActor
final class RecorderReviewPlayer: ObservableObject {
    let player: AVPlayer
    @Published private(set) var isPlaying = false
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    /// Play was asked for and the player hasn't been paused since (it may still be loading).
    private var wantsToPlay = false

    init(url: URL, duration: Double) {
        player = AVPlayer(url: url)
        player.actionAtItemEnd = .pause
        self.duration = duration
        observeTime()
        statusObservation = player.observe(\.timeControlStatus) { [weak self] _, _ in
            Task { @MainActor in self?.syncWithPlayer() }
        }
    }

    private func observeTime() {
        guard timeObserver == nil else { return }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
                                                      queue: .main) { [weak self] time in
            let seconds = time.seconds
            Task { @MainActor in self?.update(position: seconds) }
        }
    }

    /// Reads the player's own state, whenever it changes.
    func syncWithPlayer() {
        switch player.timeControlStatus {
        case .playing:
            isPlaying = true
        case .waitingToPlayAtSpecifiedRate:
            isPlaying = wantsToPlay
        case .paused:
            wantsToPlay = false
            isPlaying = false
        @unknown default:
            isPlaying = player.rate != 0
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
        observeTime()
        wantsToPlay = true
        player.play()
        isPlaying = true
    }

    func pause() {
        wantsToPlay = false
        player.pause()
        isPlaying = false
    }

    func toggle() {
        // What the player does now, not what was last asked: one tap always does what the button shows.
        syncWithPlayer()
        if isPlaying { pause() } else { play() }
    }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        position = seconds
    }

    func reachedEnd() {
        wantsToPlay = false
        isPlaying = false
        position = duration
    }

    func stop() {
        wantsToPlay = false
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
