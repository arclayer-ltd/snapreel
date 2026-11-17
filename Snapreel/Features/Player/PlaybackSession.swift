import AVFoundation
import AVKit
import Combine
import MediaPlayer
import UIKit

/// The current playback time, published on its own so only the views that show time
/// (scrubber, clock labels, transcript highlight) redraw four times a second.
@MainActor
final class PlaybackClock: ObservableObject {
    @Published var time: Double = 0
}

/// The view the player draws into: a UIView backed by an `AVPlayerLayer`. One instance lives as
/// long as the app, so the same layer moves between the full player, full screen and the mini
/// bar, and picture in picture keeps running while the player is minimised.
final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    init(player: AVPlayer) {
        super.init(frame: .zero)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// Owns the one `AVPlayer` so playback carries on across minimise, expand, full screen and
/// picture in picture. Records plays and progress in the library, keeps the audio session,
/// Now Playing info and lock-screen controls in step, and closes itself when the shell closes
/// the player.
@MainActor
final class PlaybackSession: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case loading
        case ready
        case missingFile
        case failed
    }

    static let shared = PlaybackSession()

    static var isPictureInPictureSupported: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    let player: AVPlayer
    let surface: PlayerLayerView
    let clock: PlaybackClock

    @Published private(set) var videoID: UUID?
    @Published private(set) var loadState: LoadState = .idle
    @Published private(set) var isPlaying = false
    @Published private(set) var hasEnded = false
    @Published private(set) var isPictureInPictureActive = false
    @Published private(set) var isPictureInPicturePossible = false
    @Published private(set) var rate: Double = 1
    @Published private(set) var itemDuration: Double = 0

    /// Length of the timeline: the recorded duration, or the file's own once loaded.
    var duration: Double { videoDuration > 0 ? videoDuration : itemDuration }

    private weak var library: Library?
    private var token: UUID?
    private var title = ""
    private var videoDuration: Double = 0
    private var countedPlay = false
    private var lastSaved = Date.distantPast
    private var isScrubbing = false
    private var resumeAfterScrub = false
    private var routerHadPlayer = false
    /// Start position asked for before the file was ready; applied again once it is.
    private var pendingStart: Double?
    private var timeObserver: Any?
    private var timeControlObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var pipPossibleObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var pipController: AVPictureInPictureController?
    private let pipBridge: PictureInPictureBridge
    private var subscriptions = Set<AnyCancellable>()

    private init() {
        player = AVPlayer()
        surface = PlayerLayerView(player: player)
        clock = PlaybackClock()
        pipBridge = PictureInPictureBridge()
        player.actionAtItemEnd = .pause
        pipBridge.session = self
        observePlayer()
        setUpPictureInPicture()
        setUpRemoteCommands()
        observeAppAndRouter()
    }

    // MARK: - Opening and closing

    /// Loads `video` (or, when it is already loaded, applies a new request for it: a new
    /// `token` with a `startAt` seeks there). `startAt` wins over the saved resume position.
    func open(_ video: Video, library: Library, startAt: Double?, token: UUID, autoplay: Bool, rate: Double) {
        self.library = library
        setRate(rate)
        if videoID == video.id, loadState != .idle {
            if self.token != token {
                self.token = token
                if let startAt {
                    seek(to: startAt)
                    if autoplay { play() }
                }
            }
            return
        }

        saveProgress()
        unloadItem()
        videoID = video.id
        self.token = token
        title = video.title
        videoDuration = video.duration
        itemDuration = 0
        countedPlay = false
        hasEnded = false
        isPlaying = false
        lastSaved = Date()
        clock.time = 0

        guard video.state.isReady else {
            loadState = .idle
            return
        }
        let url = library.fileURL(for: video)
        guard FileManager.default.fileExists(atPath: url.path) else {
            loadState = .missingFile
            return
        }
        loadState = .loading
        let item = AVPlayerItem(url: url)
        observe(item)
        player.replaceCurrentItem(with: item)
        let start = startAt ?? video.resumePosition
        pendingStart = nil
        if start > 0.5 {
            pendingStart = start
            performSeek(to: start)
        }
        if autoplay { play() }
        updateNowPlaying()
    }

    /// Stops playback and forgets the video, after saving how far you got.
    func close() {
        guard videoID != nil else { return }
        saveProgress()
        if isPictureInPictureActive { pipController?.stopPictureInPicture() }
        player.pause()
        unloadItem()
        videoID = nil
        token = nil
        loadState = .idle
        isPlaying = false
        hasEnded = false
        itemDuration = 0
        videoDuration = 0
        clock.time = 0
        deactivateAudioSession()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Transport

    func play() {
        guard videoID != nil, player.currentItem != nil, loadState != .failed else { return }
        if hasEnded {
            hasEnded = false
            seek(to: 0)
        }
        activateAudioSession()
        if !countedPlay, let id = videoID {
            countedPlay = true
            library?.recordPlayStarted(id)
        }
        player.defaultRate = Float(rate)
        player.play()
        isPlaying = true
        lastSaved = Date()
        updateNowPlaying()
    }

    func pause() {
        guard videoID != nil else { return }
        player.pause()
        isPlaying = false
        saveProgress()
        updateNowPlaying()
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    func seek(to seconds: Double, precise: Bool = true) {
        // A seek from the person replaces any start position still waiting for the file.
        pendingStart = nil
        performSeek(to: seconds, precise: precise)
    }

    private func performSeek(to seconds: Double, precise: Bool = true) {
        guard player.currentItem != nil, seconds.isFinite else { return }
        let upper = duration > 0 ? duration : max(0, seconds)
        let target = max(0, min(seconds, upper))
        if target < upper - 0.25 { hasEnded = false }
        clock.time = target
        let time = CMTime(seconds: target, preferredTimescale: 600)
        if precise {
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        } else {
            player.seek(to: time)
        }
        updateNowPlaying()
    }

    func skip(by seconds: Double) {
        seek(to: clock.time + seconds)
    }

    func setRate(_ newRate: Double) {
        rate = newRate
        player.defaultRate = Float(newRate)
        if isPlaying { player.rate = Float(newRate) }
        updateNowPlaying()
    }

    // MARK: - Scrubbing

    func beginScrubbing() {
        guard !isScrubbing else { return }
        isScrubbing = true
        resumeAfterScrub = isPlaying
        if isPlaying { player.pause() }
    }

    func scrub(to seconds: Double) {
        seek(to: seconds, precise: false)
    }

    func endScrubbing(at seconds: Double) {
        isScrubbing = false
        seek(to: seconds)
        if resumeAfterScrub { play() }
        resumeAfterScrub = false
    }

    // MARK: - Progress

    /// Saves the position (and how far through) for the current video. Only counts once
    /// playback has actually started, so opening a video without playing it isn't "watched".
    func saveProgress() {
        guard let id = videoID, countedPlay, let library else { return }
        lastSaved = Date()
        library.recordPlayback(id, position: clock.time)
    }

    // MARK: - Picture in picture

    /// Starts picture in picture (only ever from a tap). Returns false when it can't start now.
    @discardableResult
    func startPictureInPicture() -> Bool {
        guard let controller = pipController, isPictureInPicturePossible else { return false }
        activateAudioSession()
        controller.startPictureInPicture()
        return true
    }

    func stopPictureInPicture() {
        pipController?.stopPictureInPicture()
    }

    fileprivate func pictureInPictureChanged(active: Bool) {
        isPictureInPictureActive = active
    }

    /// The PiP window's restore button: bring the full player back.
    fileprivate func restoreFromPictureInPicture() {
        guard let id = videoID else { return }
        let router = AppEnvironment.shared.router
        if router.player?.videoID == id {
            router.expandPlayer()
        } else {
            router.play(id)
        }
    }

    // MARK: - Observation

    private func observePlayer() {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            let seconds = time.seconds
            Task { @MainActor in self?.tick(seconds) }
        }
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let playing = player.timeControlStatus != .paused
            Task { @MainActor in self?.timeControlChanged(playing: playing) }
        }
    }

    private func observe(_ item: AVPlayerItem) {
        let itemID = ObjectIdentifier(item)
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            let status = item.status
            let seconds = item.duration.seconds
            Task { @MainActor in self?.itemStatusChanged(status, duration: seconds, itemID: itemID) }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                             object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reachedEnd(itemID: itemID) }
        }
    }

    private func unloadItem() {
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player.replaceCurrentItem(with: nil)
    }

    private func isCurrent(_ itemID: ObjectIdentifier) -> Bool {
        guard let item = player.currentItem else { return false }
        return ObjectIdentifier(item) == itemID
    }

    private func tick(_ seconds: Double) {
        guard seconds.isFinite, !isScrubbing, videoID != nil else { return }
        if abs(clock.time - seconds) > 0.01 { clock.time = seconds }
        if isPlaying, Date().timeIntervalSince(lastSaved) >= 5 { saveProgress() }
    }

    private func timeControlChanged(playing: Bool) {
        guard videoID != nil, !isScrubbing, isPlaying != playing else { return }
        isPlaying = playing
        updateNowPlaying()
    }

    private func itemStatusChanged(_ status: AVPlayerItem.Status, duration seconds: Double, itemID: ObjectIdentifier) {
        guard isCurrent(itemID) else { return }
        switch status {
        case .readyToPlay:
            if seconds.isFinite, seconds > 0 { itemDuration = seconds }
            if loadState == .loading { loadState = .ready }
            if let start = pendingStart {
                pendingStart = nil
                let now = player.currentTime().seconds
                if !isScrubbing, !now.isFinite || abs(now - start) > 0.5 { performSeek(to: start) }
            }
            updateNowPlaying()
        case .failed:
            loadState = .failed
            isPlaying = false
        default:
            break
        }
    }

    private func reachedEnd(itemID: ObjectIdentifier) {
        guard isCurrent(itemID) else { return }
        hasEnded = true
        isPlaying = false
        clock.time = duration
        saveProgress()
        updateNowPlaying()
    }

    private func observeAppAndRouter() {
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor in self?.saveProgress() }
            }
            .store(in: &subscriptions)

        let router = AppEnvironment.shared.router
        // Whoever closes the player (mini bar, a deleted video, a notification), stop playing.
        router.$player
            .sink { [weak self] presentation in
                let hasPlayer = presentation != nil
                Task { @MainActor in self?.routerChanged(hasPlayer: hasPlayer) }
            }
            .store(in: &subscriptions)
        // Opening the recorder pauses playback so the two don't fight over the audio session.
        router.$recorder
            .sink { [weak self] launch in
                guard launch != nil else { return }
                Task { @MainActor in self?.pause() }
            }
            .store(in: &subscriptions)
    }

    private func routerChanged(hasPlayer: Bool) {
        if !hasPlayer, routerHadPlayer { close() }
        routerHadPlayer = hasPlayer
    }

    private func setUpPictureInPicture() {
        guard Self.isPictureInPictureSupported,
              let controller = AVPictureInPictureController(playerLayer: surface.playerLayer) else { return }
        // Picture in picture starts only when the person taps the button.
        controller.canStartPictureInPictureAutomaticallyFromInline = false
        controller.delegate = pipBridge
        pipPossibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] _, change in
            let possible = change.newValue ?? false
            Task { @MainActor in self?.isPictureInPicturePossible = possible }
        }
        pipController = controller
    }

    // MARK: - Audio session, Now Playing, lock screen

    private func activateAudioSession() {
        let audio = AVAudioSession.sharedInstance()
        try? audio.setCategory(.playback, mode: .moviePlayback, options: [])
        try? audio.setActive(true)
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func updateNowPlaying() {
        guard videoID != nil else { return }
        let info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: "Snapreel",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: clock.time,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? rate : 0.0,
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func setUpRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        _ = center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.play() }
            return .success
        }
        _ = center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        _ = center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [5]
        _ = center.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skip(by: 5) }
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [5]
        _ = center.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skip(by: -5) }
            return .success
        }
        _ = center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor in self?.seek(to: position) }
            return .success
        }
    }
}

/// Receives AVKit's picture-in-picture callbacks (which may arrive off the main actor) and
/// hands them to the session on the main actor.
final class PictureInPictureBridge: NSObject, AVPictureInPictureControllerDelegate {
    weak var session: PlaybackSession?

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor [weak self] in self?.session?.pictureInPictureChanged(active: true) }
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor [weak self] in self?.session?.pictureInPictureChanged(active: false) }
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    failedToStartPictureInPictureWithError error: Error) {
        Task { @MainActor [weak self] in self?.session?.pictureInPictureChanged(active: false) }
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        Task { @MainActor [weak self] in
            self?.session?.restoreFromPictureInPicture()
            completionHandler(true)
        }
    }
}
