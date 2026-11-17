import SwiftUI

/// The bar above the tab bar while the player is minimised: the live video (or audio art),
/// title, time, play/pause and close. Tap it to bring the full player back.
struct MiniPlayerBar: View {
    let videoID: UUID
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var session: PlaybackSession = .shared

    var body: some View {
        if let video = library.video(videoID) {
            bar(video)
                .onAppear { loadIfNeeded(video) }
        } else {
            // The video was deleted while minimised.
            Color.clear
                .frame(height: 0)
                .onAppear { close() }
        }
    }

    private func bar(_ video: Video) -> some View {
        HStack(spacing: Space.s) {
            artwork(video)
                .frame(width: 64, height: 40)
                .background(Color.srInkDeep)
                .clipShape(RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(video.title)
                    .font(.srSubheadlineStrong)
                    .foregroundStyle(Color.srOnDark)
                    .lineLimit(1)
                MiniPlayerTime(clock: session.clock, duration: video.duration,
                               isPlaying: session.isPlaying && session.videoID == videoID,
                               isPictureInPicture: session.isPictureInPictureActive)
            }
            Spacer(minLength: Space.xxs)
            Button {
                Haptics.tap()
                if session.videoID != videoID { loadIfNeeded(video) }
                session.togglePlayPause()
            } label: {
                Image(systemName: session.isPlaying && session.videoID == videoID ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel(session.isPlaying ? "Pause" : "Play")
            Button {
                Haptics.tap()
                close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.srOnDarkSecondary)
                    .frame(width: 36, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel("Close player")
        }
        .padding(.leading, Space.xs)
        .padding(.trailing, Space.xxs)
        .padding(.vertical, Space.xs)
        .background(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(Color.srInk))
        .overlay(alignment: .bottom) {
            MiniPlayerProgress(clock: session.clock, duration: video.duration)
                .padding(.horizontal, Space.m)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
        .shadow(color: Color.black.opacity(0.22), radius: 14, y: 6)
        .contentShape(RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
        .onTapGesture {
            Haptics.tap()
            router.expandPlayer()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Now playing: \(video.title)")
        .accessibilityAction(named: "Open player") { router.expandPlayer() }
    }

    @ViewBuilder
    private func artwork(_ video: Video) -> some View {
        if video.isAudioOnly {
            AudioArtwork(seed: PlayerArtSeed.of(video.id))
        } else if session.isPictureInPictureActive {
            Image(systemName: "pip")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.srOnDarkTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if session.videoID == videoID {
            PlayerSurface(session: session, gravity: .resizeAspectFill)
        } else {
            VideoThumbnail(video: video, cornerRadius: 0, showsDuration: false)
        }
    }

    /// The shell can show the bar before the full player ever opened (and debug screens do):
    /// make sure the session has this video, paused.
    private func loadIfNeeded(_ video: Video) {
        guard session.videoID != video.id else { return }
        let presentation = router.player
        session.open(video, library: library,
                     startAt: presentation?.startAt,
                     token: presentation?.token ?? UUID(),
                     autoplay: false,
                     rate: settings.playbackRate)
    }

    private func close() {
        session.close()
        router.closePlayer()
    }
}

private struct MiniPlayerTime: View {
    @ObservedObject var clock: PlaybackClock
    let duration: Double
    let isPlaying: Bool
    let isPictureInPicture: Bool

    var body: some View {
        Text(line)
            .font(.srTimerSmall)
            .foregroundStyle(Color.srOnDarkSecondary)
            .lineLimit(1)
    }

    private var line: String {
        let time = "\(Format.clock(clock.time)) / \(Format.clock(duration))"
        if isPictureInPicture { return "Picture in picture · \(time)" }
        return isPlaying ? time : "Paused · \(time)"
    }
}

private struct MiniPlayerProgress: View {
    @ObservedObject var clock: PlaybackClock
    let duration: Double

    var body: some View {
        GeometryReader { proxy in
            let fraction = duration > 0 ? min(1, max(0, clock.time / duration)) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(Color.srRed).frame(width: proxy.size.width * CGFloat(fraction))
            }
        }
        .frame(height: 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
