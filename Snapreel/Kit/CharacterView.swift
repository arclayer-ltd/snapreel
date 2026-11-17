import AVFoundation
import SwiftUI
import UIKit

/// The eight illustrated character clips (five original characters). Used sparingly: welcome,
/// the three intro slides, the tour, notification permission, and two empty states.
/// Files: `char_<rawValue>.mp4` (looping, silent) and `char_<rawValue>.png` (poster, also used
/// when Reduce Motion is on).
enum CharacterClip: String, CaseIterable {
    case welcome
    case introRecord = "intro_record"
    case introLibrary = "intro_library"
    case introSend = "intro_send"
    case tour
    case notify
    case emptyLibrary = "empty_library"
    case emptyWatch = "empty_watch"

    var fileName: String { "char_\(rawValue)" }

    /// The flat background baked into the clip; the view fills its frame with it so the clip
    /// edges disappear. Updated to the colour sampled from the encoded files.
    var background: Color {
        switch self {
        case .welcome, .introRecord, .introLibrary, .introSend: return Color(hex: 0x16171E)
        case .tour, .notify, .emptyLibrary, .emptyWatch: return Color(hex: 0xF3EEE6)
        }
    }

    var aspectRatio: CGFloat { self == .welcome ? 4 / 3 : 1 }

    var accessibilityLabel: String {
        switch self {
        case .welcome: return "Five friends walking together, one holding up a phone"
        case .introRecord: return "A woman filming herself with her phone"
        case .introLibrary: return "A man sorting video cards into a tote bag"
        case .introSend: return "A paper plane flying from one phone to a friend"
        case .tour: return "A man waving hello"
        case .notify: return "A man holding up a phone with a notification"
        case .emptyLibrary: return "A woman setting up her phone on a tripod"
        case .emptyWatch: return "A man relaxing on a beanbag watching his phone"
        }
    }
}

/// Plays a character clip on loop, muted. Falls back to the poster image when Reduce Motion is
/// on or the clip is missing, and to a neutral panel when both are missing.
struct CharacterView: View {
    let clip: CharacterClip
    var cornerRadius: CGFloat = Radius.xl

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            clip.background
            if !reduceMotion, let url = Bundle.main.url(forResource: clip.fileName, withExtension: "mp4") {
                LoopingVideoView(url: url)
            } else if let poster {
                Image(uiImage: poster).resizable().scaledToFit()
            } else {
                Image("BrandMark").resizable().scaledToFit().frame(width: 64).opacity(0.5)
            }
        }
        .aspectRatio(clip.aspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel(clip.accessibilityLabel)
        .accessibilityAddTraits(.isImage)
    }

    private var poster: UIImage? {
        Bundle.main.path(forResource: clip.fileName, ofType: "png").flatMap(UIImage.init(contentsOfFile:))
    }
}

/// Silent looping video backed by AVPlayerLooper. Pauses when off screen.
struct LoopingVideoView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> LoopingPlayerView {
        LoopingPlayerView(url: url)
    }

    func updateUIView(_ uiView: LoopingPlayerView, context: Context) {}

    static func dismantleUIView(_ uiView: LoopingPlayerView, coordinator: ()) {
        uiView.stop()
    }
}

final class LoopingPlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?

    init(url: URL) {
        super.init(frame: .zero)
        backgroundColor = .clear
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.allowsExternalPlayback = false
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { player.pause() } else { player.play() }
    }

    func stop() {
        player.pause()
        looper?.disableLooping()
        looper = nil
    }
}
