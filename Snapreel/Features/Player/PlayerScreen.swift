import SwiftUI
import UIKit

/// Full-screen player, presented by the shell while `router.player` is set and not
/// minimised. Video with its controls at the top; date, title and details below; the Notes /
/// Transcript switch; reactions and the add-note button docked at the bottom. It follows the
/// appearance; only the video area and full-screen playback stay dark. Playback lives in
/// `PlaybackSession.shared`, so it carries on when the player is minimised.
struct PlayerScreen: View {
    let presentation: PlayerPresentation
    let initial: PlayerInitialState

    @EnvironmentObject private var library: Library
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var session: PlaybackSession = .shared
    @ObservedObject private var transcripts: TranscriptService = .shared
    @ObservedObject private var shareLinks: ShareLinks = .shared
    @ObservedObject private var uploader: Uploader = .shared

    @State private var panel: PlayerPanel
    @State private var showsDetails: Bool
    @State private var isFullscreen: Bool
    @State private var overlay: PlayerOverlay?
    @State private var sheet: PlayerSheet?
    @State private var followUp: PlayerFollowUp?
    @State private var controlsVisible = true
    @State private var controlsNudge = 0
    @State private var bursts: [ReactionBurst]
    @State private var showsPiPPlaceholder: Bool
    @State private var showsResume = false
    @State private var toast: ToastMessage?
    @State private var shareTarget: Video?
    @State private var photosTarget: Video?
    @State private var hasStarted = false
    @State private var fullscreenRotation: Double = 90
    /// How far the page has been dragged down towards minimising.
    @State private var swipeOffset: CGFloat = 0
    @State private var isSwipeMinimising = false
    @GestureState private var isSwiping = false
    /// Viewers' comments and reactions on the recording's share link.
    @State private var activity: CloudActivity?
    @State private var activityFailed = false
    /// The comment whose delete-or-block choice is open.
    @State private var moderating: CloudComment?

    init(presentation: PlayerPresentation) {
        var initial = PlayerInitialState()
        if presentation.startsPaused { initial.autoplay = false }
        if presentation.opensTranscript {
            // From a "transcript ready" notification: land on what it announced.
            initial.panel = .transcript
            initial.scrollsToPanel = true
        }
        if presentation.opensComments {
            // From a comment on the share link: land on the comments.
            initial.panel = .comments
            initial.scrollsToPanel = true
        }
        #if DEBUG
        if AppEnvironment.shared.debugScreenID == "video.swipe" {
            // Held part-way through a swipe down, over the tab shell it minimises into.
            initial.autoplay = false
            initial.position = 4
            initial.swipeOffset = 210
        }
        #endif
        self.init(presentation: presentation, initial: initial)
    }

    init(presentation: PlayerPresentation, initial: PlayerInitialState) {
        self.presentation = presentation
        self.initial = initial
        _panel = State(initialValue: initial.panel)
        _showsDetails = State(initialValue: initial.showsDetails)
        _isFullscreen = State(initialValue: initial.isFullscreen)
        _overlay = State(initialValue: initial.overlay)
        _sheet = State(initialValue: initial.sheet)
        _showsPiPPlaceholder = State(initialValue: initial.showsPictureInPicturePlaceholder)
        _showsResume = State(initialValue: initial.showsResumePill)
        _swipeOffset = State(initialValue: initial.swipeOffset)
        _activity = State(initialValue: initial.activity)
        let pinned: [ReactionBurst] = initial.pinnedBurst.map { [ReactionBurst(emoji: $0, isPinned: true)] } ?? []
        _bursts = State(initialValue: pinned)
    }

    private var currentVideo: Video? { library.video(presentation.videoID) }
    private var currentLink: CloudLink? { library.link(for: presentation.videoID) }

    var body: some View {
        ZStack {
            Color.srStage.ignoresSafeArea()
            if let video = currentVideo {
                if isFullscreen {
                    fullscreenLayout(video)
                        .transition(.opacity)
                } else {
                    standardLayout(video)
                        .transition(.opacity)
                }
            } else {
                PlayerMissingView(onClose: { closePlayer() })
            }
        }
        .offset(y: swipeOffset)
        .statusBar(hidden: isFullscreen)
        .toast($toast, bottomInset: 120)
        .sheet(item: $sheet, onDismiss: { runFollowUp() }) { item in
            sheetContent(item)
                .environmentObject(library)
                .environmentObject(settings)
                .environmentObject(router)
                .presentationDragIndicator(.visible)
        }
        .shareVideo($shareTarget)
        .saveToPhotos($photosTarget, initialStage: initial.photosStage)
        .onAppear { startIfNeeded() }
        .onChange(of: presentation.token) { _ in restart() }
        .onChange(of: currentVideo?.state.isReady ?? false) { ready in
            if ready { start() }
        }
        .onChange(of: session.isPlaying) { playing in
            if playing { withAnimation(Motion.quick) { showsResume = false } }
        }
        .onChange(of: isSwiping) { swiping in
            // A drag that was cancelled (not ended) still has to spring back.
            if !swiping && !isSwipeMinimising && swipeOffset > 0 {
                withAnimation(SwipeDismiss.springBack) { swipeOffset = 0 }
            }
        }
        .task(id: autoHideKey) { await autoHideControls() }
        .task(id: currentLink?.serverID) { await loadActivity() }
        .confirmationDialog(moderating.map { "Comment by \($0.authorName)" } ?? "Comment",
                            isPresented: moderationShown, titleVisibility: .visible, presenting: moderating) { comment in
            if comment.isHeld {
                Button("Approve comment") { approve(comment) }
            }
            Button("Delete comment", role: .destructive) { moderate(comment, block: false) }
            Button("Delete and block \(comment.authorName)", role: .destructive) { moderate(comment, block: true) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Blocking stops this viewer commenting or reacting on any of your videos.")
        }
    }

    // MARK: - Layouts

    /// The video at the top, the details and notes scrolling under it (in a UIKit scroll view,
    /// see `PlayerScroller`), and the reaction dock at the bottom. Drag the video down, or pull
    /// the details down past their top, to minimise.
    private func standardLayout(_ video: Video) -> some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                videoArea(video, fullscreen: false, insets: EdgeInsets())
                    .frame(height: PlayerLayout.videoHeight(for: video, width: proxy.size.width,
                                                            available: proxy.size.height))
                    // The band behind the status bar is the page's, so the clock reads in both
                    // appearances; the video area itself stays dark. A colour background reaches
                    // into the safe area by itself (run 30 still showed a dark band in Light
                    // mode), so it is kept inside the video area explicitly.
                    .background(Color.srInkDeep, ignoresSafeAreaEdges: [])
                    .simultaneousGesture(swipeToMinimise)
                    // Normally under the details, which are drawn later and so win the touch:
                    // build 25's constant zIndex(1) let the portrait poster's overflow take their
                    // taps and drags. Raised only while the speed menu is open, because on a
                    // landscape video (211 points tall) the menu reaches about 100 points below.
                    .zIndex(overlay == .speed ? 1 : 0)
                belowVideo(video)
                    .overlay(alignment: .bottom) { resumePill }
                ReactionDock(onReact: { react($0) },
                             onMore: { openEmojiPicker() },
                             onAddNote: { openComposer() })
            }
        }
    }

    private func fullscreenLayout(_ video: Video) -> some View {
        GeometryReader { proxy in
            let rotates = video.pixelWidth > video.pixelHeight
            let width = rotates ? proxy.size.height : proxy.size.width
            let height = rotates ? proxy.size.width : proxy.size.height
            videoArea(video, fullscreen: true, insets: PlayerLayout.fullscreenInsets(rotated: rotates))
                .frame(width: width, height: height)
                .rotationEffect(.degrees(rotates ? fullscreenRotation : 0))
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .ignoresSafeArea()
        .background(Color.black.ignoresSafeArea())
        .persistentSystemOverlays(.hidden)
        .onAppear { UIDevice.current.beginGeneratingDeviceOrientationNotifications() }
        .onDisappear { UIDevice.current.endGeneratingDeviceOrientationNotifications() }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            updateRotation(animated: true)
        }
    }

    private func videoArea(_ video: Video, fullscreen: Bool, insets: EdgeInsets) -> some View {
        PlayerVideoArea(video: video,
                        session: session,
                        reactions: library.reactions(for: video.id),
                        isFullscreen: fullscreen,
                        controlInsets: insets,
                        controlsVisible: $controlsVisible,
                        overlay: $overlay,
                        bursts: bursts,
                        showsPictureInPicturePlaceholder: showsPiPPlaceholder || session.isPictureInPictureActive,
                        rate: settings.playbackRate,
                        actions: videoActions,
                        viewerReactions: activity?.reactions ?? [])
    }

    private func belowVideo(_ video: Video) -> some View {
        PlayerScroller(content: AnyView(scrollContent(video)),
                       opensOnPanel: initial.scrollsToPanel,
                       onPulledDown: { pulledPastTop() })
    }

    /// What scrolls under the video. Hosted in UIKit, so everything it needs comes in as values
    /// and callbacks rather than from the environment.
    private func scrollContent(_ video: Video) -> some View {
        VStack(alignment: .leading, spacing: Space.l) {
            details(video)
            panelHeader
                .background(GeometryReader { header in
                    Color.clear.preference(key: PlayerPanelTopKey.self,
                                           value: header.frame(in: .named(Self.contentSpace)).minY)
                })
            panelBody(video)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.m)
        .padding(.bottom, Space.xxxl)
        .coordinateSpace(name: Self.contentSpace)
    }

    private static let contentSpace = "player.content"

    // MARK: - Swipe down to minimise

    /// Drag the video down: the page follows the finger, and letting go far enough (or with a
    /// flick) minimises the player into the bar above the tab bar.
    private var swipeToMinimise: some Gesture {
        DragGesture(minimumDistance: 14, coordinateSpace: .global)
            .updating($isSwiping) { _, swiping, _ in swiping = true }
            .onChanged { value in
                guard !isSwipeMinimising, overlay == nil else { return }
                if swipeOffset == 0 && !SwipeDismiss.isDownward(value) { return }
                swipeOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                guard !isSwipeMinimising, swipeOffset > 0 else { return }
                if SwipeDismiss.commits(value) {
                    minimiseBySwipe()
                } else {
                    withAnimation(SwipeDismiss.springBack) { swipeOffset = 0 }
                }
            }
    }

    /// The details were pulled down past their top and let go.
    private func pulledPastTop() {
        guard !isSwipeMinimising, swipeOffset == 0, sheet == nil, !isFullscreen else { return }
        minimiseBySwipe()
    }

    private func minimiseBySwipe() {
        isSwipeMinimising = true
        Haptics.tap()
        overlay = nil
        withAnimation(SwipeDismiss.slideAway) { swipeOffset = SwipeDismiss.offscreen }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            router.minimizePlayer()
        }
    }

    private func details(_ video: Video) -> some View {
        PlayerDetailsSection(video: video,
                             folderName: video.folderID.flatMap { library.folder($0)?.name },
                             noteCount: library.notes(for: video.id).count,
                             reactionCount: library.reactions(for: video.id).count,
                             transcript: library.transcript(for: video.id),
                             isSummarizing: transcripts.summarizingIDs.contains(video.id),
                             isExpanded: $showsDetails,
                             onShare: { shareTarget = video },
                             onMore: { sheet = .actions(confirmingDelete: false) },
                             onEditTitle: { sheet = .title },
                             onEditVideo: { router.edit(video.id) },
                             onStats: { sheet = .stats },
                             onSaveToPhotos: { photosTarget = video },
                             onToggleWatchLater: { chooseAction(.toggleWatchLater) },
                             link: currentLink,
                             linkState: shareLinks.state(for: video.id),
                             onCopyLink: { ShareLinks.shared.copyLink(video.id) },
                             onLinkTapped: { ProPresenter.shareLink(video.id) },
                             original: video.editedFrom.flatMap { library.video($0) },
                             onOpenOriginal: { if let id = video.editedFrom { router.play(id) } })
    }

    private var panelHeader: some View {
        HStack {
            PillSwitch(options: panels, selection: $panel, title: { $0.title })
            Spacer(minLength: Space.xs)
            if panel == .notes {
                Button {
                    openComposer()
                } label: {
                    if panels.count > 2 {
                        // Three tabs leave room for the icon only.
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.srStageRed)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color.srStageControl))
                    } else {
                        Label("Add note", systemImage: "plus")
                            .font(.srSubheadlineStrong)
                            .foregroundStyle(Color.srStageRed)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add note")
            }
        }
    }

    @ViewBuilder
    private func panelBody(_ video: Video) -> some View {
        switch panel {
        case .notes:
            NotesPanel(notes: library.notes(for: video.id),
                       reactions: library.reactions(for: video.id),
                       onSeek: { seekAndPlay($0) },
                       onEdit: { sheet = .editNote($0.id) },
                       onDelete: { deleteNote($0) },
                       onDeleteReaction: { deleteReaction($0) },
                       onAddNote: { openComposer() })
        case .comments:
            CommentsPanel(activity: activity,
                          failed: activityFailed,
                          commentsAllowed: currentLink?.detail?.allowComments ?? true,
                          onSeek: { seekAndPlay($0) },
                          onModerate: { moderating = $0 },
                          onApprove: { approve($0) },
                          onRetry: { Task { await loadActivity() } },
                          onSettings: { ProPresenter.linkSettings(video.id) })
        case .transcript:
            TranscriptPanel(video: video,
                            transcript: library.transcript(for: video.id),
                            clock: session.clock,
                            service: transcripts,
                            phaseOverride: initial.transcriptPhase,
                            onSeek: { seekAndPlay($0) },
                            onRequest: { requestTranscript(video.id) },
                            onCopy: { copyTranscript(video.id) })
        }
    }

    @ViewBuilder private var resumePill: some View {
        if showsResume {
            HStack(spacing: 0) {
                Button {
                    Haptics.tap()
                    session.play()
                    withAnimation(Motion.quick) { showsResume = false }
                } label: {
                    Label("Keep watching", systemImage: "play.fill")
                        .font(.srSubheadlineStrong)
                        .foregroundStyle(Color.white)
                        .padding(.leading, Space.m)
                        .padding(.trailing, Space.s)
                        .frame(height: 42)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Rectangle().fill(Color.white.opacity(0.35)).frame(width: 1, height: 22)
                Button {
                    withAnimation(Motion.quick) { showsResume = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 42, height: 42)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stay paused")
            }
            .background(Capsule().fill(Color.srRed))
            .shadow(color: Color.black.opacity(0.35), radius: 12, y: 4)
            .padding(.bottom, Space.m)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Sheets

    @ViewBuilder
    private func sheetContent(_ item: PlayerSheet) -> some View {
        switch item {
        case .compose(let time):
            NoteComposerSheet(mode: .new(time: time),
                              onSave: { saveNewNote($0, at: time) },
                              onCancel: { sheet = nil })
                .presentationDetents([.height(210)])
        case .editNote(let id):
            if let note = library.notes.first(where: { $0.id == id }) {
                NoteComposerSheet(mode: .edit(note),
                                  onSave: { updateNote(id, text: $0) },
                                  onDelete: { deleteNoteFromSheet(note) },
                                  onCancel: { sheet = nil })
                    .presentationDetents([.height(260)])
            }
        case .emoji:
            EmojiPickerSheet(onPick: { pickEmoji($0) }, onClose: { sheet = nil })
                .presentationDetents([.medium, .large])
        case .actions(let confirming):
            if let video = currentVideo {
                PlayerActionsSheet(video: video, isShared: currentLink != nil,
                                   editCount: library.edits(of: video.id).count, startsConfirmingDelete: confirming,
                                  onChoose: { chooseAction($0) },
                                  onClose: { sheet = nil })
                    .presentationDetents([.height((currentLink != nil ? 690 : 630) + (video.state.isReady ? 64 : 0)), .large])
            }
        case .title:
            if let video = currentVideo {
                TitleEditorSheet(initialTitle: video.title, heading: "Edit title", onStage: true,
                                 onSave: { saveTitle($0) },
                                 onCancel: { sheet = nil })
                    .presentationDetents([.height(220)])
            }
        case .stats:
            if let video = currentVideo {
                PlayerStatsSheet(video: video, link: currentLink, onClose: { sheet = nil })
                    .presentationDetents([.large])
            }
        }
    }

    // MARK: - Starting

    private func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        start()
        updateRotation(animated: false)
        if initial.photosStage != nil, let video = currentVideo {
            photosTarget = video
        }
    }

    /// A new request arrived while the player is open (another video, or a time to jump to).
    private func restart() {
        overlay = nil
        showsResume = false
        controlsVisible = true
        if isFullscreen { isFullscreen = false }
        start()
    }

    private func start() {
        guard let video = currentVideo else { return }
        session.open(video, library: library,
                     startAt: initial.position ?? presentation.startAt,
                     token: presentation.token,
                     autoplay: initial.autoplay,
                     rate: settings.playbackRate)
        TranscriptService.shared.reconcile(videoID: video.id, library: library)
        TranscriptService.shared.summarizeIfPossible(videoID: video.id, library: library)
    }

    // MARK: - Video area

    private var videoActions: PlayerVideoActions {
        PlayerVideoActions(minimise: { minimise() },
                           toggleFullscreen: { toggleFullscreen() },
                           interacted: { controlsNudge += 1 },
                           react: { react($0) },
                           moreReactions: { openEmojiPicker() },
                           chooseSpeed: { chooseSpeed($0) },
                           pictureInPicture: { startPictureInPicture() },
                           restoreFromPictureInPicture: { restoreFromPictureInPicture() },
                           retrySave: { PendingImports.resumeInterruptedSaves(in: library) },
                           deleteRecording: { sheet = .actions(confirmingDelete: true) })
    }

    private func minimise() {
        overlay = nil
        router.minimizePlayer()
    }

    private func closePlayer() {
        session.close()
        router.closePlayer()
    }

    private func toggleFullscreen() {
        overlay = nil
        updateRotation(animated: false)
        controlsVisible = true
        withAnimation(Motion.standard) { isFullscreen.toggle() }
    }

    /// Landscape videos in full screen turn to match how the iPhone is held (the app itself
    /// stays portrait).
    private func updateRotation(animated: Bool) {
        let next: Double
        switch UIDevice.current.orientation {
        case .landscapeLeft: next = 90
        case .landscapeRight: next = -90
        default: return
        }
        guard next != fullscreenRotation else { return }
        if animated {
            withAnimation(Motion.standard) { fullscreenRotation = next }
        } else {
            fullscreenRotation = next
        }
    }

    private func chooseSpeed(_ rate: Double) {
        Haptics.selection()
        settings.playbackRate = rate
        session.setRate(rate)
        withAnimation(Motion.quick) { overlay = nil }
        controlsNudge += 1
    }

    private func startPictureInPicture() {
        overlay = nil
        if !session.isPlaying { session.play() }
        if !session.startPictureInPicture() {
            toast = ToastMessage(text: "Picture in picture isn't available right now", systemImage: "pip")
        }
    }

    private func restoreFromPictureInPicture() {
        if session.isPictureInPictureActive { session.stopPictureInPicture() }
        withAnimation(Motion.standard) { showsPiPPlaceholder = false }
    }

    private func seekAndPlay(_ time: Double) {
        Haptics.tap()
        session.seek(to: time)
        session.play()
        withAnimation(Motion.standard) { controlsVisible = true }
        controlsNudge += 1
    }

    // MARK: - Auto-hiding controls

    private struct AutoHideKey: Equatable {
        var visible: Bool
        var playing: Bool
        var nudge: Int
        var overlayOpen: Bool
    }

    private var autoHideKey: AutoHideKey {
        AutoHideKey(visible: controlsVisible, playing: session.isPlaying, nudge: controlsNudge, overlayOpen: overlay != nil)
    }

    /// Controls fade three seconds after the last touch while playing (never with VoiceOver on).
    private func autoHideControls() async {
        guard controlsVisible, session.isPlaying, overlay == nil, !UIAccessibility.isVoiceOverRunning else { return }
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        guard !Task.isCancelled, session.isPlaying, overlay == nil else { return }
        // Not wrapped in withAnimation: the fade is scoped to the controls (PlayerVideoArea), so
        // nothing else on the page animates while someone is scrolling the notes.
        controlsVisible = false
    }

    // MARK: - Reactions

    private func react(_ emoji: String) {
        guard let video = currentVideo else { return }
        let time = session.videoID == video.id ? session.clock.time : 0
        library.addReaction(emoji, to: video.id, at: time)
        EmojiRecents.record(emoji)
        Haptics.firm()
        let burst = ReactionBurst(emoji: emoji)
        bursts.append(burst)
        UIAccessibility.post(notification: .announcement,
                             argument: "Reacted with \(EmojiCatalog.name(for: emoji)) at \(Format.stamp(time))")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            bursts.removeAll { $0.id == burst.id }
        }
    }

    private func openEmojiPicker() {
        overlay = nil
        sheet = .emoji
    }

    private func pickEmoji(_ emoji: String) {
        followUp = .react(emoji)
        sheet = nil
    }

    private func deleteReaction(_ reaction: VideoReaction) {
        library.deleteReaction(reaction.id)
        Haptics.success()
        toast = ToastMessage(text: "Reaction removed", systemImage: "face.dashed")
    }

    // MARK: - Notes

    private func openComposer() {
        guard currentVideo != nil else { return }
        let wasPlaying = session.isPlaying
        session.pause()
        overlay = nil
        withAnimation(Motion.quick) { showsResume = wasPlaying }
        sheet = .compose(time: session.clock.time)
    }

    private func saveNewNote(_ text: String, at time: Double) {
        guard let video = currentVideo else { return }
        library.addNote(to: video.id, at: time, text: text)
        withAnimation(Motion.standard) { panel = .notes }
        sheet = nil
        toast = ToastMessage(text: "Note added at \(Format.stamp(time))", systemImage: "note.text")
    }

    private func updateNote(_ id: UUID, text: String) {
        library.updateNote(id, text: text)
        sheet = nil
        toast = ToastMessage(text: "Note saved", systemImage: "checkmark.circle.fill")
    }

    private func deleteNote(_ note: VideoNote) {
        library.deleteNote(note.id)
        Haptics.success()
        toast = ToastMessage(text: "Note deleted", systemImage: "trash.fill")
    }

    private func deleteNoteFromSheet(_ note: VideoNote) {
        sheet = nil
        deleteNote(note)
    }

    // MARK: - Transcript

    private func requestTranscript(_ videoID: UUID) {
        Haptics.tap()
        let library = self.library
        Task { @MainActor in
            await TranscriptService.shared.requestTranscript(videoID: videoID, library: library)
        }
    }

    private func copyTranscript(_ videoID: UUID) {
        guard let transcript = library.transcript(for: videoID) else { return }
        UIPasteboard.general.string = transcript.segments.map(\.text).joined(separator: "\n")
        Haptics.success()
        toast = ToastMessage(text: "Transcript copied", systemImage: "doc.on.doc.fill")
    }

    // MARK: - Actions sheet

    private func chooseAction(_ action: PlayerActionsSheet.Action) {
        guard let video = currentVideo else { return }
        switch action {
        case .editTitle: followUp = .editTitle
        case .saveToPhotos: followUp = .saveToPhotos
        case .share: followUp = .share
        case .stats: followUp = .stats
        case .delete: followUp = .delete
        case .copyLink: followUp = .copyLink
        case .linkSettings: followUp = .linkSettings
        case .editVideo: followUp = .editVideo
        case .deleteWithEdits: followUp = .deleteWithEdits
        case .toggleWatchLater:
            library.toggleWatchLater(video.id)
            let added = library.video(video.id)?.isInWatchLater ?? false
            Haptics.success()
            toast = ToastMessage(text: added ? "Added to Watch later" : "Removed from Watch later",
                                 systemImage: added ? "clock.fill" : "clock")
        }
        sheet = nil
    }

    private func saveTitle(_ title: String) {
        guard let video = currentVideo else { return }
        library.rename(video.id, to: title)
        sheet = nil
        toast = ToastMessage(text: "Title saved", systemImage: "checkmark.circle.fill")
    }

    /// Runs what was chosen in a sheet once the sheet has gone.
    private func runFollowUp() {
        guard let action = followUp else { return }
        followUp = nil
        guard let video = currentVideo else { return }
        switch action {
        case .share: shareTarget = video
        case .saveToPhotos: photosTarget = video
        case .editTitle: present(.title)
        case .stats: present(.stats)
        case .delete: deleteRecording(video)
        case .react(let emoji): react(emoji)
        case .copyLink: ShareLinks.shared.copyLink(video.id)
        case .linkSettings: ProPresenter.linkSettings(video.id)
        case .editVideo: router.edit(video.id)
        case .deleteWithEdits: deleteRecording(video, withEdits: true)
        }
    }

    // MARK: - Comments (share link)

    /// Notes and Transcript, plus Comments once the recording is shared as a link.
    private var panels: [PlayerPanel] {
        currentLink == nil ? [.notes, .transcript] : PlayerPanel.allCases
    }

    private var moderationShown: Binding<Bool> {
        Binding(get: { moderating != nil }, set: { if !$0 { moderating = nil } })
    }

    private func loadActivity() async {
        guard let link = currentLink else {
            if panel == .comments { panel = .notes }
            return
        }
        do {
            activity = try await APIClient.shared.activity(link.serverID)
            activityFailed = false
        } catch {
            activityFailed = activity == nil
        }
    }

    /// Deletes a viewer's comment, and when blocking, stops that viewer commenting or reacting on
    /// any of your videos (App Review guideline 1.2).
    private func moderate(_ comment: CloudComment, block: Bool) {
        moderating = nil
        Task { @MainActor in
            do {
                if block { try await APIClient.shared.block(commentID: comment.id) }
                try await APIClient.shared.deleteComment(comment.id)
                withAnimation(Motion.standard) {
                    activity?.comments.removeAll { $0.id == comment.id || $0.parentId == comment.id }
                }
                Haptics.success()
                toast = ToastMessage(text: block ? "Deleted and blocked \(comment.authorName)" : "Comment deleted",
                                     systemImage: block ? "hand.raised.fill" : "trash.fill")
            } catch {
                Haptics.error()
                toast = ToastMessage(text: (error as? CloudError)?.message ?? "That didn't work. Try again.",
                                     systemImage: "exclamationmark.circle.fill")
            }
        }
    }

    /// Publishes a comment the word filter held, so viewers see it on the watch page.
    private func approve(_ comment: CloudComment) {
        moderating = nil
        Task { @MainActor in
            do {
                let approved = try await APIClient.shared.approveComment(comment.id)
                withAnimation(Motion.standard) {
                    if let index = activity?.comments.firstIndex(where: { $0.id == comment.id }) {
                        activity?.comments[index] = approved
                    }
                }
                Haptics.success()
                toast = ToastMessage(text: "Comment approved", systemImage: "checkmark.circle.fill")
            } catch {
                Haptics.error()
                toast = ToastMessage(text: (error as? CloudError)?.message ?? "That didn't work. Try again.",
                                     systemImage: "exclamationmark.circle.fill")
            }
        }
    }

    private func present(_ next: PlayerSheet) {
        Task { @MainActor in sheet = next }
    }

    private func deleteRecording(_ video: Video, withEdits: Bool = false) {
        Haptics.success()
        session.close()
        router.closePlayer()
        let edits = withEdits ? library.edits(of: video.id) : []
        for edit in edits { library.delete(edit.id) }
        library.delete(video.id)
        router.showToast(edits.isEmpty ? "Recording deleted" : "Recording and its edits deleted", systemImage: "trash.fill")
    }
}

/// Sizes for the player layouts.
enum PlayerLayout {
    /// Landscape videos fill the width; portrait ones get a taller area (centred on a blurred
    /// fill) capped so the details stay in view; audio gets a waveform panel.
    static func videoHeight(for video: Video, width: CGFloat, available: CGFloat) -> CGFloat {
        let maxHeight = max(200, available * 0.46)
        if video.isAudioOnly { return min(width * 0.62, maxHeight) }
        let aspect = CGFloat(video.pixelWidth) / CGFloat(max(1, video.pixelHeight))
        let natural = width / max(aspect, 0.1)
        return min(max(natural, width * 9 / 16), maxHeight)
    }

    /// Keeps controls clear of the notch and home indicator in full screen.
    static func fullscreenInsets(rotated: Bool) -> EdgeInsets {
        rotated
            ? EdgeInsets(top: Space.xs, leading: 44, bottom: Space.s, trailing: 44)
            : EdgeInsets(top: 50, leading: 0, bottom: 30, trailing: 0)
    }
}

/// The video was deleted while the player was open.
struct PlayerMissingView: View {
    let onClose: @MainActor () -> Void

    var body: some View {
        VStack {
            HStack {
                CircleIconButton(systemName: "chevron.down", label: "Close player", tone: .stage) { onClose() }
                Spacer()
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.xs)
            Spacer()
            EmptyStateView(systemImage: "film",
                           title: "This recording isn't here any more",
                           message: "It may have been deleted from your library.",
                           onStage: true)
            Spacer()
        }
    }
}
