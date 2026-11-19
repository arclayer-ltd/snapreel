import SwiftUI
import UIKit

/// What the video area asks the player screen to do.
struct PlayerVideoActions {
    var minimise: @MainActor () -> Void
    var toggleFullscreen: @MainActor () -> Void
    /// Any touch on the controls; keeps them on screen a little longer.
    var interacted: @MainActor () -> Void
    var react: @MainActor (String) -> Void
    var moreReactions: @MainActor () -> Void
    var chooseSpeed: @MainActor (Double) -> Void
    var pictureInPicture: @MainActor () -> Void
    var restoreFromPictureInPicture: @MainActor () -> Void
    var retrySave: @MainActor () -> Void
    var deleteRecording: @MainActor () -> Void
}

/// The dark video area at the top of the player (and the whole of full screen): the video or
/// audio art, state messages, reaction bursts, the controls and the floating menus.
struct PlayerVideoArea: View {
    let video: Video
    @ObservedObject var session: PlaybackSession
    let reactions: [VideoReaction]
    let isFullscreen: Bool
    let controlInsets: EdgeInsets
    @Binding var controlsVisible: Bool
    @Binding var overlay: PlayerOverlay?
    let bursts: [ReactionBurst]
    let showsPictureInPicturePlaceholder: Bool
    let rate: Double
    let actions: PlayerVideoActions

    private var duration: Double { video.duration > 0 ? video.duration : session.itemDuration }
    private var isLoadedHere: Bool { session.videoID == video.id }

    private var canPlay: Bool {
        guard video.state.isReady else { return false }
        guard isLoadedHere else { return true }
        return session.loadState != .missingFile && session.loadState != .failed
    }

    var body: some View {
        ZStack {
            backdrop
            media
            stateCover
            if showsPictureInPicturePlaceholder {
                PictureInPicturePlaceholder(onRestore: { actions.restoreFromPictureInPicture() })
            }
            ReactionBurstLayer(bursts: bursts)
            // The auto-hide sets controlsVisible without a transaction; the fade is scoped here.
            controls
                .animation(Motion.standard, value: controlsVisible)
            if overlay == .speed {
                Color.black.opacity(0.35)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(Motion.quick) { overlay = nil } }
                    .accessibilityHidden(true)
            }
            if overlay == .reactions {
                ReactionGridOverlay(clock: session.clock,
                                    onReact: { actions.react($0) },
                                    onMore: { actions.moreReactions() },
                                    onClose: { withAnimation(Motion.standard) { overlay = nil } })
                    .transition(.opacity)
            }
        }
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture { toggleControls() }
        .onLongPressGesture(minimumDuration: 0.45) { openReactions() }
        .overlay(alignment: .topLeading) { speedMenu }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "React") { openReactions() }
        .accessibilityAction(named: controlsVisible ? "Hide controls" : "Show controls") { toggleControls() }
    }

    // MARK: - Layers

    @ViewBuilder private var backdrop: some View {
        // An audio recording has no picture, so its panel follows the appearance.
        video.isAudioOnly ? Color.srStageRaised : Color.srInkDeep
        if video.isPortrait && !video.isAudioOnly && !isFullscreen {
            PlayerBlurredPoster(video: video)
        }
    }

    @ViewBuilder private var media: some View {
        if video.isAudioOnly {
            PlayerAudioPanel(video: video, session: session, clock: session.clock)
        } else if video.state.isReady {
            PlayerSurface(session: session)
                .accessibilityLabel("Video")
        }
    }

    @ViewBuilder private var stateCover: some View {
        switch video.state {
        case .ready:
            if isLoadedHere && session.loadState == .missingFile {
                PlayerStateMessage(systemImage: "questionmark.folder",
                                   title: "The video file is missing",
                                   message: "Snapreel can't find this recording on your iPhone any more.",
                                   primaryTitle: "Delete recording", primary: actions.deleteRecording)
            } else if isLoadedHere && session.loadState == .failed {
                PlayerStateMessage(systemImage: "exclamationmark.triangle",
                                   title: "This recording won't play",
                                   message: "The file may be damaged. You can still share it or delete it.")
            }
        case .saving(let progress):
            PlayerSavingMessage(progress: progress)
        case .failed(let reason, let outOfSpace):
            PlayerStateMessage(systemImage: outOfSpace ? "externaldrive.badge.exclamationmark" : "exclamationmark.triangle",
                               title: outOfSpace ? "Not saved, your iPhone is full" : "This recording didn't save",
                               message: reason,
                               primaryTitle: "Try again", primary: actions.retrySave,
                               secondaryTitle: "Delete", secondary: actions.deleteRecording)
        }
    }

    @ViewBuilder private var controls: some View {
        if !canPlay || showsPictureInPicturePlaceholder {
            PlayerControlsOverlay(session: session, mode: .minimal, reactions: reactions, duration: duration,
                                  isFullscreen: isFullscreen, isAudio: video.isAudioOnly, insets: controlInsets,
                                  rate: rate, overlay: $overlay, actions: actions)
        } else if controlsVisible || overlay == .speed {
            PlayerControlsOverlay(session: session, mode: .full, reactions: reactions, duration: duration,
                                  isFullscreen: isFullscreen, isAudio: video.isAudioOnly, insets: controlInsets,
                                  rate: rate, overlay: $overlay, actions: actions)
                .transition(.opacity)
        } else {
            PlayerProgressLine(clock: session.clock, duration: duration, onPicture: !video.isAudioOnly)
                .transition(.opacity)
        }
    }

    @ViewBuilder private var speedMenu: some View {
        if overlay == .speed {
            SpeedMenu(current: rate, onChoose: { actions.chooseSpeed($0) })
                .padding(.top, controlInsets.top + Space.xs + 46)
                .padding(.leading, controlInsets.leading + Space.s + 46)
                .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .topLeading)))
        }
    }

    // MARK: - Gestures

    private func toggleControls() {
        if overlay != nil {
            withAnimation(Motion.quick) { overlay = nil }
            return
        }
        withAnimation(Motion.standard) { controlsVisible.toggle() }
        actions.interacted()
    }

    private func openReactions() {
        guard canPlay, !showsPictureInPicturePlaceholder else { return }
        Haptics.firm()
        withAnimation(Motion.standard) { overlay = .reactions }
    }
}

// MARK: - Controls

/// Top bar, centre transport and scrubber. `.minimal` keeps only the way out (minimise or
/// leave full screen), for state messages and picture in picture. There's no picture under
/// `.minimal`, so it has no scrim and its button follows the appearance; `.full` sits on the
/// video, so its scrims and glass buttons stay dark.
struct PlayerControlsOverlay: View {
    enum Mode { case full, minimal }

    @ObservedObject var session: PlaybackSession
    let mode: Mode
    let reactions: [VideoReaction]
    let duration: Double
    let isFullscreen: Bool
    let isAudio: Bool
    let insets: EdgeInsets
    let rate: Double
    @Binding var overlay: PlayerOverlay?
    let actions: PlayerVideoActions

    /// Full controls over a video: scrims, glass buttons, white text. An audio recording's
    /// panel (and `.minimal`) has no picture, so the controls take the stage colours instead.
    private var onPicture: Bool { mode == .full && !isAudio }

    var body: some View {
        ZStack {
            scrims
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                if mode == .full { centre }
                Spacer(minLength: 0)
                if mode == .full { scrubber }
            }
            .padding(insets)
        }
    }

    private var scrims: some View {
        VStack(spacing: 0) {
            if onPicture {
                LinearGradient(colors: [Color.black.opacity(0.55), Color.black.opacity(0)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 96)
            }
            Spacer(minLength: 0)
            if onPicture {
                LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.6)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 110)
            }
        }
        .background(onPicture ? Color.black.opacity(0.12) : Color.clear, ignoresSafeAreaEdges: [])
        .allowsHitTesting(false)
    }

    private var topBar: some View {
        HStack(spacing: Space.xs) {
            CircleIconButton(systemName: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "chevron.down",
                             label: isFullscreen ? "Leave full screen" : "Minimise player",
                             tone: onPicture ? .glass : .stage, size: 38) {
                if isFullscreen { actions.toggleFullscreen() } else { actions.minimise() }
            }
            if mode == .full { speedPill }
            Spacer(minLength: Space.xs)
            if mode == .full {
                if PlaybackSession.showsPictureInPictureButton && !isAudio {
                    CircleIconButton(systemName: "pip.enter", label: "Picture in picture", tone: .glass, size: 38) {
                        actions.pictureInPicture()
                    }
                }
                if !isFullscreen && !isAudio {
                    CircleIconButton(systemName: "arrow.up.left.and.arrow.down.right", label: "Full screen",
                                     tone: .glass, size: 38) {
                        actions.toggleFullscreen()
                    }
                }
            }
        }
        .padding(.horizontal, Space.s)
        .padding(.top, Space.xs)
    }

    private var speedPill: some View {
        Button {
            Haptics.tap()
            actions.interacted()
            withAnimation(Motion.quick) { overlay = overlay == .speed ? nil : .speed }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "speedometer")
                    .font(.system(size: 13, weight: .semibold))
                Text(PlaybackSpeed.label(rate))
                    .font(.srTimerSmall)
            }
            .foregroundStyle(onPicture ? Color.white : Color.srStageText)
            .padding(.horizontal, Space.s)
            .frame(height: 38)
            .background(Capsule().fill(onPicture ? Color.black.opacity(0.38) : Color.srStageControl))
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel("Playback speed")
        .accessibilityValue(PlaybackSpeed.spoken(rate))
    }

    private var centre: some View {
        HStack(spacing: isFullscreen ? 64 : 44) {
            TransportButton(systemName: "gobackward.5", label: "Back 5 seconds", size: 26, onPicture: onPicture) {
                session.skip(by: -5)
                actions.interacted()
            }
            playButton
            TransportButton(systemName: "goforward.5", label: "Forward 5 seconds", size: 26, onPicture: onPicture) {
                session.skip(by: 5)
                actions.interacted()
            }
        }
    }

    private var playButton: some View {
        let symbol = session.hasEnded ? "arrow.counterclockwise" : (session.isPlaying ? "pause.fill" : "play.fill")
        let label = session.hasEnded ? "Play again" : (session.isPlaying ? "Pause" : "Play")
        return Button {
            Haptics.tap()
            session.togglePlayPause()
            actions.interacted()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(onPicture ? Color.white : Color.srStageText)
                .frame(width: 68, height: 68)
                .background(Circle().fill(onPicture ? Color.black.opacity(0.35) : Color.srStageControl))
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.9))
        .accessibilityLabel(label)
    }

    private var scrubber: some View {
        PlayerScrubber(clock: session.clock, duration: duration, reactions: reactions, onPicture: onPicture,
                       onBegin: {
                           session.beginScrubbing()
                           actions.interacted()
                       },
                       onScrub: { session.scrub(to: $0) },
                       onEnd: {
                           session.endScrubbing(at: $0)
                           actions.interacted()
                       },
                       onSeek: {
                           session.seek(to: $0)
                           actions.interacted()
                       })
            .padding(.horizontal, Space.m)
            .padding(.bottom, Space.xs)
    }
}

private struct TransportButton: View {
    let systemName: String
    let label: String
    let size: CGFloat
    var onPicture = true
    let action: @MainActor () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(onPicture ? Color.white : Color.srStageText)
                .frame(width: 52, height: 52)
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.88))
        .accessibilityLabel(label)
    }
}

// MARK: - Scrubber

/// Timeline with reaction markers above it, a draggable thumb, and elapsed / remaining time.
struct PlayerScrubber: View {
    @ObservedObject var clock: PlaybackClock
    let duration: Double
    let reactions: [VideoReaction]
    /// Over a video (white on the scrim) or on an audio panel (stage colours).
    var onPicture = true
    let onBegin: @MainActor () -> Void
    let onScrub: @MainActor (Double) -> Void
    let onEnd: @MainActor (Double) -> Void
    let onSeek: @MainActor (Double) -> Void

    @State private var dragFraction: Double?

    private var fraction: Double {
        if let dragFraction { return dragFraction }
        guard duration > 0 else { return 0 }
        return min(1, max(0, clock.time / duration))
    }

    private var shownTime: Double { fraction * duration }

    var body: some View {
        VStack(spacing: 2) {
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    markerRow(width: proxy.size.width)
                        .frame(height: 22)
                    track(width: proxy.size.width)
                        .frame(height: 26)
                }
            }
            .frame(height: 48)
            timeRow
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(Format.clock(shownTime)) of \(Format.clock(duration))")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onSeek(min(duration, clock.time + 5))
            case .decrement: onSeek(max(0, clock.time - 5))
            @unknown default: break
            }
        }
    }

    private func markerRow(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(reactions) { reaction in
                Button {
                    Haptics.tap()
                    onSeek(reaction.time)
                } label: {
                    Text(reaction.emoji)
                        .font(.system(size: 15))
                        .frame(width: 26, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleStyle(scale: 0.8))
                .position(x: xPosition(reaction.time, width: width), y: 11)
            }
        }
        .frame(width: width)
    }

    private func track(width: CGFloat) -> some View {
        let dragging = dragFraction != nil
        let lineHeight: CGFloat = dragging ? 5 : 3
        let thumb: CGFloat = dragging ? 18 : 13
        let filled = CGFloat(fraction) * width
        return ZStack(alignment: .leading) {
            Capsule()
                .fill(onPicture ? Color.white.opacity(0.28) : Color.srStageText.opacity(0.18))
                .frame(height: lineHeight)
            Capsule()
                .fill(Color.srRed)
                .frame(width: max(0, filled), height: lineHeight)
            Circle()
                .fill(Color.srRed)
                .frame(width: thumb, height: thumb)
                .shadow(color: Color.black.opacity(0.35), radius: 3)
                .offset(x: min(max(0, filled - thumb / 2), max(0, width - thumb)))
        }
        .frame(width: width, height: 26)
        .contentShape(Rectangle())
        .animation(Motion.quick, value: dragging)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let next = Double(min(max(0, value.location.x / max(1, width)), 1))
                    if dragFraction == nil { onBegin() }
                    dragFraction = next
                    onScrub(next * duration)
                }
                .onEnded { value in
                    let next = Double(min(max(0, value.location.x / max(1, width)), 1))
                    dragFraction = nil
                    onEnd(next * duration)
                }
        )
    }

    private var timeRow: some View {
        HStack {
            Text(Format.clock(shownTime))
            Spacer()
            Text(Format.remaining(duration - shownTime))
        }
        .font(.srTimerSmall)
        .foregroundStyle(onPicture ? Color.white.opacity(0.9) : Color.srStageTextSecondary)
    }

    private func xPosition(_ time: Double, width: CGFloat) -> CGFloat {
        guard duration > 0 else { return 13 }
        let x = CGFloat(min(1, max(0, time / duration))) * width
        return min(max(13, x), max(13, width - 13))
    }
}

/// Thin progress line along the bottom of the video while the controls are hidden.
struct PlayerProgressLine: View {
    @ObservedObject var clock: PlaybackClock
    let duration: Double
    var onPicture = true

    var body: some View {
        GeometryReader { proxy in
            let fraction = duration > 0 ? min(1, max(0, clock.time / duration)) : 0
            ZStack(alignment: .leading) {
                Rectangle().fill(onPicture ? Color.white.opacity(0.18) : Color.srStageText.opacity(0.12))
                Rectangle().fill(Color.srRed).frame(width: proxy.size.width * CGFloat(fraction))
            }
        }
        .frame(height: 2)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Speed menu

/// The speed list that drops from the speed pill. The choice is remembered for every video.
struct SpeedMenu: View {
    let current: Double
    let onChoose: @MainActor (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Playback speed")
                .font(.srCaption)
                .foregroundStyle(Color.srStageTextTertiary)
                .padding(.horizontal, Space.m)
                .padding(.top, Space.s)
                .padding(.bottom, Space.xxs)
            ForEach(PlaybackSpeed.rates, id: \.self) { rate in
                row(rate)
                if rate != PlaybackSpeed.rates.last {
                    Rectangle().fill(Color.srStageLine).frame(height: 0.5).padding(.leading, Space.m)
                }
            }
        }
        .padding(.bottom, Space.xxs)
        .frame(width: 216)
        .background(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).fill(Color.srStageRaised))
        .overlay(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).strokeBorder(Color.srStageLine, lineWidth: 0.5))
        .shadow(color: Color.black.opacity(0.45), radius: 20, y: 8)
    }

    private func row(_ rate: Double) -> some View {
        let selected = abs(rate - current) < 0.01
        return Button {
            onChoose(rate)
        } label: {
            HStack {
                Text(PlaybackSpeed.label(rate))
                    .font(selected ? Font.srHeadline : Font.srBody)
                    .foregroundStyle(Color.srStageText)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.srRed)
                }
            }
            .padding(.horizontal, Space.m)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(PlaybackSpeed.label(rate))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Reactions over the video

/// Grid of quick reactions over the dimmed video (long-press the video to open it).
struct ReactionGridOverlay: View {
    @ObservedObject var clock: PlaybackClock
    let onReact: @MainActor (String) -> Void
    let onMore: @MainActor () -> Void
    let onClose: @MainActor () -> Void

    private let columns = Array(repeating: GridItem(.fixed(56), spacing: 12), count: 4)

    var body: some View {
        ZStack {
            Color.black.opacity(0.62)
                .contentShape(Rectangle())
                .onTapGesture { onClose() }
            VStack(spacing: Space.s) {
                HStack {
                    Text("React at \(Format.clock(clock.time))")
                        .font(.srSubheadlineStrong)
                        .foregroundStyle(Color.srOnDark)
                    Spacer()
                    CircleIconButton(systemName: "xmark", label: "Close reactions", tone: .glass, size: 30) {
                        onClose()
                    }
                }
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(EmojiCatalog.quick, id: \.self) { emoji in
                        Button {
                            onReact(emoji)
                        } label: {
                            Text(emoji)
                                .font(.system(size: 30))
                                .frame(width: 54, height: 54)
                                .background(Circle().fill(Color.white.opacity(0.14)))
                        }
                        .buttonStyle(PressScaleStyle(scale: 0.85))
                        .accessibilityLabel("React with \(EmojiCatalog.name(for: emoji))")
                    }
                    Button {
                        onMore()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .frame(width: 54, height: 54)
                            .background(Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 1.5))
                    }
                    .buttonStyle(PressScaleStyle(scale: 0.85))
                    .accessibilityLabel("More reactions")
                }
            }
            .frame(width: 4 * 56 + 3 * 12)
        }
    }
}

/// Large emoji that pop and rise over the video when you react.
struct ReactionBurstLayer: View {
    let bursts: [ReactionBurst]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(bursts) { burst in
                    ReactionBurstView(burst: burst, size: proxy.size)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ReactionBurstView: View {
    let burst: ReactionBurst
    let size: CGSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var popped = false
    @State private var risen = false

    var body: some View {
        Text(burst.emoji)
            .font(.system(size: 76))
            .shadow(color: Color.black.opacity(0.3), radius: 10, y: 4)
            .scaleEffect(burst.isPinned || popped ? 1.1 : 0.3)
            .opacity(burst.isPinned ? 1 : (risen ? 0 : 1))
            .position(x: size.width * CGFloat(burst.xFraction), y: yPosition)
            .onAppear(perform: animate)
    }

    private var yPosition: CGFloat {
        if burst.isPinned { return size.height * 0.38 }
        if reduceMotion { return size.height * 0.5 }
        return risen ? size.height * 0.18 : size.height * 0.62
    }

    private func animate() {
        guard !burst.isPinned else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) { popped = true }
        withAnimation(.easeIn(duration: 0.95).delay(0.3)) { risen = true }
    }
}

// MARK: - Audio

/// An audio recording's panel: bars from the file's loudness that move with playback.
private struct PlayerAudioPanel: View {
    let video: Video
    @ObservedObject var session: PlaybackSession
    @ObservedObject var clock: PlaybackClock
    @EnvironmentObject private var library: Library

    var body: some View {
        let isHere = session.videoID == video.id
        AudioPlaybackBars(url: library.fileURL(for: video), player: session.player,
                          isPlaying: isHere && session.isPlaying, time: isHere ? clock.time : 0)
    }
}

// MARK: - States

/// Shown in the video area while picture in picture is running.
struct PictureInPicturePlaceholder: View {
    let onRestore: @MainActor () -> Void

    var body: some View {
        ZStack {
            Color.srStageDeep
            VStack(spacing: Space.s) {
                Image(systemName: "pip")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Color.srStageTextTertiary)
                Text("Playing in picture in picture")
                    .font(.srSubheadlineStrong)
                    .foregroundStyle(Color.srStageText)
                Text("Carry on with anything else. The video stays on top.")
                    .font(.srFootnote)
                    .foregroundStyle(Color.srStageTextSecondary)
                    .multilineTextAlignment(.center)
                Button {
                    onRestore()
                } label: {
                    Label("Bring it back here", systemImage: "pip.exit")
                }
                .buttonStyle(.srSecondaryCompact)
                .padding(.top, Space.xxs)
            }
            .padding(.horizontal, Space.xxl)
        }
    }
}

/// A message in place of the video (missing file, failed save, can't play).
struct PlayerStateMessage: View {
    let systemImage: String
    let title: String
    let message: String
    var primaryTitle: String? = nil
    var primary: (@MainActor () -> Void)? = nil
    var secondaryTitle: String? = nil
    var secondary: (@MainActor () -> Void)? = nil

    var body: some View {
        ZStack {
            Color.srStageDeep
            VStack(spacing: Space.xs) {
                Image(systemName: systemImage)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Color.srStageRed)
                Text(title)
                    .font(.srHeadline)
                    .foregroundStyle(Color.srStageText)
                Text(message)
                    .font(.srFootnote)
                    .foregroundStyle(Color.srStageTextSecondary)
                    .lineLimit(3)
                HStack(spacing: Space.s) {
                    if let primaryTitle, let primary {
                        Button(primaryTitle) { primary() }
                            .buttonStyle(.srPrimaryCompact)
                    }
                    if let secondaryTitle, let secondary {
                        Button(secondaryTitle) { secondary() }
                            .buttonStyle(.srSecondaryCompact)
                    }
                }
                .padding(.top, Space.xxs)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, Space.xxl)
            .padding(.top, 40)
        }
    }
}

/// The recording is still being written into the library.
struct PlayerSavingMessage: View {
    let progress: Double

    var body: some View {
        ZStack {
            Color.srStageDeep
            VStack(spacing: Space.s) {
                SpinningRing(lineWidth: 4, track: Color.srStageText.opacity(0.25))
                    .frame(width: 44, height: 44)
                Text("Still saving")
                    .font(.srHeadline)
                    .foregroundStyle(Color.srStageText)
                Text("It plays here as soon as it's in your library. You can close the player meanwhile.")
                    .font(.srFootnote)
                    .foregroundStyle(Color.srStageTextSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Space.xxl)
            .padding(.top, 40)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A blurred copy of the thumbnail behind portrait videos.
struct PlayerBlurredPoster: View {
    let video: Video
    @EnvironmentObject private var library: Library
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { proxy in
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .blur(radius: 30)
                    .overlay(Color.black.opacity(0.45))
                    .clipped()
            }
        }
        .task(id: video.thumbnailFileName) {
            guard let url = library.thumbnailURL(for: video) else {
                image = nil
                return
            }
            image = ThumbnailCache.shared.cached(url)
            if image == nil { image = await ThumbnailCache.shared.load(url) }
        }
        // Only a picture, never a touch target. `.clipped()` hides the filled image beyond the
        // video area but SwiftUI still hit-tests it: for a portrait recording it reached about
        // 230 points down over the title, buttons and notes, so taps there went to the video
        // (builds 22 to 25: "nothing is responding", notes that wouldn't scroll back down).
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
