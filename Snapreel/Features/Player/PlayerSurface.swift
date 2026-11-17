import AVFoundation
import SwiftUI
import UIKit

/// Shows the session's video layer. Each new surface (player, full screen, mini bar) takes the
/// one layer view when it is created; it never takes it back on later updates, so two surfaces
/// on screen during a transition can't fight over it.
struct PlayerSurface: UIViewRepresentable {
    let session: PlaybackSession
    var gravity: AVLayerVideoGravity = .resizeAspect

    func makeUIView(context: Context) -> PlayerSurfaceContainer {
        let container = PlayerSurfaceContainer(frame: .zero)
        container.attach(session.surface, gravity: gravity)
        return container
    }

    func updateUIView(_ uiView: PlayerSurfaceContainer, context: Context) {
        if session.surface.superview === uiView {
            session.surface.playerLayer.videoGravity = gravity
        }
    }
}

final class PlayerSurfaceContainer: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        clipsToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func attach(_ surface: PlayerLayerView, gravity: AVLayerVideoGravity) {
        surface.removeFromSuperview()
        surface.playerLayer.videoGravity = gravity
        surface.frame = bounds
        surface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(surface)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        for view in subviews { view.frame = bounds }
    }
}
