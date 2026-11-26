import AVFoundation
import Combine
import SwiftUI
import UIKit

/// The tools along the bottom of the editor, in the order they appear.
enum EditorTool: String, CaseIterable, Identifiable {
    case trim, transcript, speed, crop, text, shapes, captions, voice, sound, blur, thumbnail

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trim: return "Trim"
        case .transcript: return "Transcript"
        case .speed: return "Speed"
        case .crop: return "Crop"
        case .text: return "Text"
        case .shapes: return "Shapes"
        case .captions: return "Captions"
        case .voice: return "Voice-over"
        case .sound: return "Sound"
        case .blur: return "Blur"
        case .thumbnail: return "Thumbnail"
        }
    }

    var systemImage: String {
        switch self {
        case .trim: return "scissors"
        case .transcript: return "text.alignleft"
        case .speed: return "speedometer"
        case .crop: return "crop"
        case .text: return "textformat"
        case .shapes: return "arrow.up.right.circle"
        case .captions: return "captions.bubble"
        case .voice: return "mic"
        case .sound: return "speaker.wave.2"
        case .blur: return "drop"
        case .thumbnail: return "photo"
        }
    }

    /// Tools that make sense for a voice recording (no picture).
    var worksWithoutPicture: Bool {
        switch self {
        case .trim, .transcript, .speed, .voice, .sound: return true
        default: return false
        }
    }

    /// Tools that open a sheet instead of a panel.
    var opensSheet: Bool { self == .transcript || self == .speed }
}

/// What is selected on the timeline or the picture.
enum EditorSelection: Equatable {
    case segment(UUID)
    case text(UUID)
    case sticker(UUID)
    case blur(UUID)
    case voice(UUID)
}

extension EditorSelection {
    var isPinchableOverlay: Bool {
        switch self {
        case .text, .sticker: return true
        default: return false
        }
    }
}

enum EditorSheet: String, Identifiable {
    case transcript, speed, export, discard, captionWords, emoji

    var id: String { rawValue }
}

/// Full-screen states over the editor.
enum EditorPhase: Equatable {
    case editing
    /// A draft was found: "Pick up where you left off?"
    case restorePrompt
    /// Saving as a new recording (its id); progress, failure and success come from the library row.
    case rendering(UUID)
    /// The person stopped the save.
    case cancelled
}

/// The voice-over tool's steps.
enum VoicePhase: Equatable {
    case ready
    /// Microphone access not asked yet.
    case primer
    case denied
    case countdown(Int)
    case recording(start: Double)
    case review(VoiceTake)
}

struct VoiceTake: Equatable {
    var fileName: String
    var start: Double
    var duration: Double
    /// Seconds of the file before the video started moving.
    var lead: Double = 0
}

enum NoisePhase: Equatable {
    case idle
    case working(Double)
    case ready
    case failed
}

enum TrimEdge: Equatable {
    case start, end
    /// The whole overlay moves in time, its length kept.
    case whole
}

/// A handle being dragged on the timeline.
struct TrimDrag: Equatable {
    var target: TrimTarget
    var edge: TrimEdge
    /// How far the finger moved, in output seconds (negative to the left).
    var offset: Double
}

enum TrimTarget: Equatable {
    case segment(UUID)
    case text(UUID)
    case sticker(UUID)
    case blur(UUID)
}

/// A filler word the transcript tool offers to cut.
struct EditFiller: Identifiable, Hashable {
    var id: String
    var text: String
    /// Source seconds.
    var start: Double
    var end: Double
    var before: String
    var after: String
}

/// The editor's state: the recipe, its history, the playhead, what is selected and which tool
/// is open. Views change the recipe only through `apply` (or a live change for drags), so
/// every change can be undone, saved as a draft and shown in the preview.
@MainActor
final class EditorModel: ObservableObject {
    let source: Video
    let library: Library
    let sourceURL: URL
    let editFolder: URL
    /// Debug screenshots: the poster stands in for the player, nothing plays or records.
    let isStatic: Bool

    @Published private(set) var recipe: EditRecipe {
        didSet {
            if oldValue.segments != recipe.segments || oldValue.captions != recipe.captions { captionCache = nil }
            updateMoment()
        }
    }
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    /// The playhead. Views that move with it observe `clock` (or `clock.seconds`), never the model.
    let clock = EditorClock()
    /// What is on the picture at the playhead.
    let moment = EditorMomentStore()
    var playhead: Double {
        get { clock.time }
        set {
            guard newValue != clock.time else { return }
            clock.time = newValue
            updateMoment()
        }
    }
    @Published private(set) var isPlaying = false
    /// The recording is still being put together (a screen recording just made) or opened.
    @Published private(set) var isPreparing = false
    /// The recording can't be opened for editing.
    @Published private(set) var loadFailed = false
    @Published var selection: EditorSelection?
    @Published private(set) var tool: EditorTool?
    @Published var sheet: EditorSheet?
    @Published var phase: EditorPhase = .editing
    @Published var toast: ToastMessage?

    @Published private(set) var poster: UIImage?
    let filmstrip = EditorFilmstrip()
    /// Sound levels by file name (the recording's under "source"), for drawing it.
    @Published private(set) var levels: [String: [Float]] = [:]
    @Published private(set) var pictureSize: CGSize
    @Published var pointsPerSecond: CGFloat = 0
    @Published var trimDrag: TrimDrag?
    @Published var showsTrimCoach: Bool
    @Published var confirmsSectionDelete = false

    /// Text being typed (keyboard up), with the item it edits.
    @Published var textEntry: EditText?
    @Published var voice: VoicePhase = .ready
    @Published var voiceLevel: Float = 0
    @Published var noise: NoisePhase = .idle
    @Published var hearsOriginalSound = false
    /// Shown briefly after "Use this frame".
    @Published var thumbnailJustChosen = false

    // Debug overrides for states CI can't reach on a simulator.
    @Published var transcriptPhaseOverride: TranscriptPhase?
    var availableBytesOverride: Int64?

    let playback = EditorPlayback()
    var player: AVPlayer { playback.player }
    private var sourceInfo: EditSource?
    private var undoStack: [EditRecipe] = []
    private var redoStack: [EditRecipe] = []
    private var liveStart: EditRecipe?
    /// What the player in front plays, so a change rebuilds only the part it touches.
    private var built: (structure: String, picture: String, sound: String)?
    private var currentBuild: EditBuild?
    private var buildTask: Task<Void, Never>?
    private var pictureTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var displayLink: CADisplayLink?
    private var observers: [NSObjectProtocol] = []
    private var lastSeek: (time: Double, at: CFTimeInterval)?
    private var isScrubbing = false
    /// The player shows the recording itself, so a trim handle can show the frame under it.
    private var trimPreview: EditRecipe?
    private var trimTimeValue = 0.0
    private var trimPreviewIsShown = false
    private var pinchStart: (scale: Double, rotation: Double)?
    private var sessionIsActive = false
    private let recorder = VoiceOverRecorder()
    private var countdownTask: Task<Void, Never>?
    private var levelTask: Task<Void, Never>?
    private var takePlayer: AVAudioPlayer?
    private var takeTask: Task<Void, Never>?
    private var noiseTask: Task<Void, Never>?
    private var pendingDraft: EditDraft?
    private var isClosed = false
    private var captionCache: (stamp: String, lines: [EditCaptionLine], pieces: [EditCaptionLine])?
    private var fillerCache: (stamp: String, all: [EditFiller])?

    static let trimCoachKey = "editor.trimCoachSeen"

    init(videoID: UUID, library: Library, isStatic: Bool = false) {
        let video = library.video(videoID) ?? Video(title: "", createdAt: Date(), kind: .camera, fileName: "",
                                                     duration: 0, fileSize: 0, pixelWidth: 0, pixelHeight: 0)
        self.source = video
        self.library = library
        self.sourceURL = library.fileURL(for: video)
        self.editFolder = library.media.editFolder(video.id)
        self.isStatic = isStatic
        self.recipe = EditRecipe.original(sourceID: video.id, duration: video.duration)
        self.pictureSize = CGSize(width: max(1, video.pixelWidth), height: max(1, video.pixelHeight))
        self.showsTrimCoach = !UserDefaults.standard.bool(forKey: Self.trimCoachKey)
        if let draft = library.draft(for: video.id), !draft.recipe.isUntouched {
            pendingDraft = draft
            phase = .restorePrompt
        }
        playback.onPlayingChanged = { [weak self] playing in self?.playerChanged(playing) }
    }

    var hasPicture: Bool { !source.isAudioOnly }
    var duration: Double { recipe.outputDuration }
    var tools: [EditorTool] { EditorTool.allCases.filter { hasPicture || $0.worksWithoutPicture } }
    var isDirty: Bool { !recipe.isUntouched }
    var draftDate: Date? { pendingDraft?.recipe.updatedAt }
    /// While a voice-over counts down or records, nothing else may move the video or change it.
    var isRecordingVoice: Bool {
        switch voice {
        case .countdown, .recording: return true
        default: return false
        }
    }
    var cleanedSoundURL: URL { editFolder.appendingPathComponent("clean-sound.m4a") }
    /// The picture as shown: cropped and turned.
    var outputPictureSize: CGSize { recipe.outputPictureSize(source: pictureSize) }

    // MARK: - Loading

    func load() async {
        guard sourceInfo == nil, !isClosed else { return }
        if pointsPerSecond == 0 { pointsPerSecond = Self.defaultPointsPerSecond(duration: duration) }
        if let url = library.thumbnailURL(for: source) {
            poster = await ThumbnailCache.shared.load(url)
        }
        if isStatic {
            filmstrip.still = poster?.cgImage
            updateMoment()
            return
        }
        isPreparing = true
        observe()
        // A screen recording's two sound tracks become one shortly after it is recorded, which
        // replaces its file; opening it before then would read a file that is about to change.
        await RecordingSaver.shared.waitUntilFinished(source.id)
        guard !isClosed else { return }
        do {
            let info = try await EditSource.load(sourceURL)
            guard !isClosed else { return }
            sourceInfo = info
            if info.hasVideo { pictureSize = info.uprightSize }
            if info.duration > 0, abs(info.duration - recipe.sourceDuration) > 0.05 {
                recipe = isDirty ? repaired(recipe)
                    : EditRecipe.original(sourceID: source.id, duration: info.duration)
                playhead = min(playhead, max(0, duration - 0.01))
            }
            await rebuildNow()
            isPreparing = false
            if info.hasVideo { filmstrip.start(info) } else { loadLevels("source", url: sourceURL) }
        } catch {
            isPreparing = false
            loadFailed = true
        }
    }

    private func repaired(_ recipe: EditRecipe) -> EditRecipe {
        let folder = editFolder
        return recipe.repaired(duration: sourceInfo?.duration ?? recipe.sourceDuration) {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
        }
    }

    private func loadLevels(_ name: String, url: URL) {
        guard !isStatic, levels[name] == nil else { return }
        Task { @MainActor [weak self] in
            let values = await EditorLevels.load(url)
            self?.levels[name] = values
        }
    }

    private func loadVoiceLevels() {
        for clip in recipe.voiceClips { loadLevels(clip.fileName, url: editFolder.appendingPathComponent(clip.fileName)) }
    }

    static func defaultPointsPerSecond(duration: Double) -> CGFloat {
        // About two screens for a short video; a long one scrolls, at least 12 points a second
        // so a few seconds of text or a shape still reads on its track.
        CGFloat(min(80, max(12, 700 / max(duration, 1))))
    }

    /// Zoomed all the way out, the whole edit is about half a screen wide.
    func zoomRange(width: CGFloat) -> ClosedRange<CGFloat> {
        let least = max(0.2, width * 0.6 / CGFloat(max(duration, 0.5)))
        return min(least, 240)...240
    }

    // MARK: - Still picture

    private var stillCache: (key: String, image: UIImage)?
    /// The poster with the recipe's crop, turn, flip and blur: what the preview shows before
    /// the player has a frame, and in debug screenshots.
    func stillImage(fullFrame: Bool) -> UIImage? {
        guard let poster, let cg = poster.cgImage else { return nil }
        // Blur boxes come and go with time; only screenshots need the still to follow them.
        let moment = isStatic && !recipe.blurs.isEmpty ? Int(playhead * 10) : 0
        // The crop tool shows the whole picture, so dragging the crop must not draw it again.
        let key = "\(fullFrame)|\(fullFrame ? .zero : recipe.crop.rect)|\(recipe.quarterTurns)|\(recipe.flipped)|"
            + "\(fullFrame ? [] : recipe.blurs.map(\.rect))|\(moment)"
        if let stillCache, stillCache.key == key { return stillCache.image }
        var shown = recipe
        if fullFrame {
            shown.crop = EditCrop()
            shown.blurs = []
        }
        let upright = CGSize(width: cg.width, height: cg.height)
        let size = shown.renderSize(source: upright, quality: .original)
        let untouched = shown.crop.isFullFrame && shown.quarterTurns % 4 == 0 && !shown.flipped && shown.blurs.isEmpty
        if untouched {
            stillCache = (key, poster)
            return poster
        }
        let pipeline = EditFramePipeline(recipe: shown, upright: size, showsBlur: !fullFrame)
        let frame = pipeline.draw(CIImage(cgImage: cg), at: playhead)
        guard let output = EditGraphics.managedContext.createCGImage(frame, from: CGRect(origin: .zero, size: size)) else { return poster }
        let image = UIImage(cgImage: output)
        stillCache = (key, image)
        return image
    }

    // MARK: - Draft

    func continueDraft() {
        if let draft = pendingDraft {
            recipe = repaired(draft.recipe)
            undoStack = []
            redoStack = []
            updateHistoryFlags()
            if recipe.audio.reducesNoise {
                if FileManager.default.fileExists(atPath: cleanedSoundURL.path) { noise = .ready } else { cleanSound() }
            }
            loadVoiceLevels()
            rebuild(force: true)
        }
        pendingDraft = nil
        phase = .editing
    }

    func startOver() {
        pendingDraft = nil
        library.deleteDraft(source.id)
        library.removeEditFilesIfUnused(source.id)
        phase = .editing
    }

    func keepDraft() {
        saveTask?.cancel()
        saveTask = nil
        if isDirty { library.saveDraft(stamped(recipe)) } else { library.deleteDraft(source.id) }
    }

    /// Leaving without the edits.
    func discardDraft() {
        saveTask?.cancel()
        saveTask = nil
        isClosed = true
        library.deleteDraft(source.id)
        library.removeEditFilesIfUnused(source.id)
    }

    /// The menu's "Discard draft": back to the recording, and nothing kept. Undo still brings the
    /// edits back until the editor closes, so voice-over files stay until then.
    func discardEdits() {
        revertToOriginal()
        keepDraft()
    }

    private func stamped(_ recipe: EditRecipe) -> EditRecipe {
        var copy = recipe
        copy.updatedAt = Date()
        return copy
    }

    private func scheduleDraftSave() {
        guard !isStatic else { return }
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard let self, !Task.isCancelled else { return }
            self.keepDraft()
        }
    }

    /// Writes a change still waiting to be saved (the app is leaving the screen).
    private func flushDraft() {
        guard saveTask != nil else { return }
        keepDraft()
    }

    // MARK: - Changes and history

    /// One undoable change.
    func apply(_ change: (inout EditRecipe) -> Void) {
        var next = recipe
        change(&next)
        guard next != recipe else { return }
        let old = recipe
        undoStack.append(recipe)
        if undoStack.count > 200 { undoStack.removeFirst() }
        redoStack.removeAll()
        recipe = next
        didChange(from: old)
    }

    /// Start of a drag or pinch: the whole gesture becomes one undo step.
    func beginLiveChange() {
        if liveStart == nil { liveStart = recipe }
    }

    func liveChange(_ change: (inout EditRecipe) -> Void) {
        beginLiveChange()
        var next = recipe
        change(&next)
        guard next != recipe else { return }
        recipe = next
        refreshSoon()
    }

    func endLiveChange() {
        guard let start = liveStart else { return }
        liveStart = nil
        guard start != recipe else { return }
        undoStack.append(start)
        if undoStack.count > 200 { undoStack.removeFirst() }
        redoStack.removeAll()
        didChange(from: start)
    }

    func undo() {
        guard !isRecordingVoice, let previous = undoStack.popLast() else { return }
        let old = recipe
        redoStack.append(recipe)
        recipe = previous
        Haptics.tap()
        didChange(from: old, keepsSelection: false)
    }

    func redo() {
        guard !isRecordingVoice, let next = redoStack.popLast() else { return }
        let old = recipe
        undoStack.append(recipe)
        recipe = next
        Haptics.tap()
        didChange(from: old, keepsSelection: false)
    }

    /// Back to the recording as it was. Undo brings the edit back.
    func revertToOriginal() {
        apply { recipe in
            let quality = recipe.quality
            recipe = EditRecipe.original(sourceID: recipe.sourceID, duration: recipe.sourceDuration)
            recipe.quality = quality
        }
        selection = nil
        tool = nil
        toast = ToastMessage(text: "Back to the original. Undo brings your edits back.", systemImage: "arrow.uturn.backward")
    }

    /// After any finished change. The playhead stays on the moment it was on when what comes
    /// before it got shorter or longer.
    private func didChange(from old: EditRecipe, keepsSelection: Bool = true) {
        updateHistoryFlags()
        if !keepsSelection || !selectionExists { selection = nil }
        if old.segments != recipe.segments {
            playhead = recipe.nearestOutputTime(forSource: old.sourceTime(forOutput: playhead))
        }
        playhead = min(max(0, playhead), max(0, duration - 0.01))
        if old.voiceClips != recipe.voiceClips { loadVoiceLevels() }
        scheduleDraftSave()
        rebuild()
    }

    private func updateHistoryFlags() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    private var selectionExists: Bool {
        switch selection {
        case .segment(let id): return recipe.segmentIndex(id) != nil
        case .text(let id): return recipe.texts.contains { $0.id == id }
        case .sticker(let id): return recipe.stickers.contains { $0.id == id }
        case .blur(let id): return recipe.blurs.contains { $0.id == id }
        case .voice(let id): return recipe.voiceClips.contains { $0.id == id }
        case nil: return true
        }
    }

    // MARK: - Preview

    /// Brings the player up to date with the recipe. Only what changed is touched: new levels and
    /// a new picture go straight onto what is playing; only different sections, voice-overs or
    /// sound make a new one, which comes forward when its picture is ready.
    func rebuild(force: Bool = false) {
        guard !isStatic, sourceInfo != nil, !isClosed else { return }
        if trimPreview != nil { return }
        let structure = structureKey
        if force || built == nil || built?.structure != structure {
            buildTask?.cancel()
            buildTask = Task { @MainActor [weak self] in await self?.rebuildNow() }
            return
        }
        refreshPlaying()
    }

    private func rebuildNow() async {
        guard let info = sourceInfo, !isClosed else { return }
        let recipe = self.recipe
        let structure = structureKey
        let picture = pictureKey
        let sound = soundKey
        let fullFrame = tool == .crop
        built = (structure, picture, sound)
        do {
            let build = try await EditCompositionBuilder.build(recipe: recipe, source: info, editFolder: editFolder,
                                                               cleanedAudio: cleanedSoundURL, originalSound: hearsOriginalSound)
            guard !Task.isCancelled, !isClosed else { return }
            let item = AVPlayerItem(asset: build.composition)
            item.audioMix = build.audioMix
            item.videoComposition = EditCompositionBuilder.previewVideoComposition(recipe: recipe, source: info, build: build,
                                                                                   fullFrame: fullFrame)
            item.audioTimePitchAlgorithm = .spectral
            guard await playback.show(item, hasPicture: info.hasVideo, place: { [weak self] in self?.playhead ?? 0 }) else {
                if item.status == .failed, !Task.isCancelled, !isClosed { playbackFailed() }
                return
            }
            currentBuild = build
            // What this item was made with; levels or the picture may have changed meanwhile.
            built = (structure, picture, sound)
            refreshPlaying()
            if isPlaying { playback.play() }
        } catch {
            if !Task.isCancelled, !isClosed { playbackFailed() }
        }
    }

    private func playbackFailed() {
        built = nil
        isPlaying = false
        stopDisplayLink()
        toast = ToastMessage(text: "This change can't be played. Undo brings the last one back.",
                             systemImage: "exclamationmark.circle.fill")
    }

    /// New levels and a new picture for what is playing.
    private func refreshPlaying() {
        guard let info = sourceInfo, let build = currentBuild, let item = player.currentItem, var built,
              !playback.isShowing else { return }
        let picture = pictureKey, sound = soundKey
        if sound != built.sound {
            built.sound = sound
            item.audioMix = EditCompositionBuilder.audioMix(recipe: recipe, build: build)
        }
        if picture != built.picture {
            built.picture = picture
            item.videoComposition = EditCompositionBuilder.previewVideoComposition(recipe: recipe, source: info, build: build,
                                                                                   fullFrame: tool == .crop)
        }
        self.built = built
    }

    /// During a drag: the blur or the level follows the finger, twenty times a second.
    private func refreshSoon() {
        guard !isStatic, pictureTask == nil, trimPreview == nil, built?.structure == structureKey else { return }
        pictureTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard let self else { return }
            self.pictureTask = nil
            if !self.isClosed, self.trimPreview == nil, self.built?.structure == self.structureKey { self.refreshPlaying() }
        }
    }

    private var structureKey: String {
        let sections = recipe.playedSegments.map { "\($0.start)-\($0.end)x\($0.speed)" }.joined(separator: ",")
        let voices = recipe.voiceClips.map { "\($0.fileName)@\($0.start)" }.joined(separator: ",")
        return "\(sections)|\(voices)|\(recipe.audio.reducesNoise && noise == .ready && !hearsOriginalSound)"
    }

    private var pictureKey: String {
        let fullFrame = tool == .crop
        let blurs = fullFrame ? "" : recipe.blurs.map { "\($0.rect)\($0.start)\($0.end)" }.joined()
        return "\(fullFrame ? "full" : "\(recipe.crop.rect)")|\(recipe.quarterTurns)\(recipe.flipped)|\(blurs)"
    }

    private var soundKey: String {
        let audio = recipe.audio
        return "\(audio.volume)|\(audio.muted)|\(audio.fadeIn)|\(audio.fadeOut)|\(audio.voiceVolume)"
    }

    private func observe() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        func on(_ name: Notification.Name, _ body: @escaping @MainActor (EditorModel, Notification) -> Void) {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    if let self { body(self, note) }
                }
            })
        }
        on(.AVPlayerItemDidPlayToEndTime) { model, note in
            guard (note.object as? AVPlayerItem) === model.player.currentItem, model.trimPreview == nil else { return }
            model.reachedEnd()
        }
        on(.AVPlayerItemFailedToPlayToEndTime) { model, note in
            guard (note.object as? AVPlayerItem) === model.player.currentItem else { return }
            model.pause()
            model.rebuild(force: true)
        }
        // A call, an alarm, Siri: the video stops, and a voice-over take ends where it was.
        on(AVAudioSession.interruptionNotification) { model, note in
            let kind = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            model.sessionIsActive = false
            if kind == .began { model.stopEverything() }
        }
        // Headphones unplugged: never carry on out loud.
        on(AVAudioSession.routeChangeNotification) { model, note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init)
            if reason == .oldDeviceUnavailable, !model.isRecordingVoice { model.pause() }
        }
        on(AVAudioSession.mediaServicesWereResetNotification) { model, _ in
            model.sessionIsActive = false
            model.stopEverything()
            model.rebuild(force: true)
        }
        on(UIApplication.willResignActiveNotification) { model, _ in model.flushDraft() }
        on(UIApplication.didEnterBackgroundNotification) { model, _ in model.stopEverything() }
        on(UIApplication.didBecomeActiveNotification) { model, _ in
            // Back from Settings with the microphone switched on.
            if model.tool == .voice, model.voice == .denied || model.voice == .primer { model.voice = model.voicePhaseForPermission() }
        }
        on(UIApplication.didReceiveMemoryWarningNotification) { model, _ in model.filmstrip.trim() }
    }

    private func stopEverything() {
        if case .countdown = voice { cancelCountdown() }
        if case .recording = voice { stopRecording() }
        pause()
    }

    private func reachedEnd() {
        isPlaying = false
        stopDisplayLink()
        playhead = duration
        if case .recording = voice { stopRecording() }
        takePlayer?.stop()
    }

    /// The player stopped by itself (a call, headphones unplugged).
    private func playerChanged(_ playing: Bool) {
        guard !isStatic, !playing, isPlaying, !playback.isShowing else { return }
        if abs(player.currentTime().seconds - duration) < 0.1 {
            reachedEnd()
        } else {
            isPlaying = false
            stopDisplayLink()
            takePlayer?.stop()
            if case .recording = voice { stopRecording() }
        }
    }

    func teardown() {
        isClosed = true
        saveTask?.cancel()
        stopDisplayLink()
        playback.stop()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        countdownTask?.cancel()
        levelTask?.cancel()
        takeTask?.cancel()
        noiseTask?.cancel()
        pictureTask?.cancel()
        takePlayer?.stop()
        recorder.cancel()
        buildTask?.cancel()
        filmstrip.stop()
        // Voice-over takes and cleaned sound nothing needs any more.
        library.removeEditFilesIfUnused(source.id)
        if sessionIsActive {
            sessionIsActive = false
            // Music that was playing before comes back. Not on the main thread: it can take a moment.
            DispatchQueue.global(qos: .utility).async {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
        }
    }

    // MARK: - Playback

    func togglePlay() {
        guard !isRecordingVoice else { return }
        isPlaying ? pause() : play()
    }

    func play() {
        guard !isStatic, sourceInfo != nil else { return }
        if playhead >= duration - 0.05 { seek(to: 0, exact: true) }
        activateSession()
        isPlaying = true
        filmstrip.isPaused = true
        if !playback.isShowing { playback.play() }
        startDisplayLink()
    }

    private func activateSession() {
        guard !sessionIsActive else { return }
        sessionIsActive = true
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    func pause() {
        let wasPlaying = isPlaying
        isPlaying = false
        stopDisplayLink()
        filmstrip.isPaused = false
        takePlayer?.stop()
        takeTask?.cancel()
        guard !isStatic else { return }
        playback.pause()
        if wasPlaying, trimPreview == nil, !playback.isShowing { playhead = min(max(0, player.currentTime().seconds), duration) }
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: DisplayLinkTarget { [weak self] in self?.tick() }, selector: #selector(DisplayLinkTarget.fire))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func tick() {
        guard isPlaying, !playback.isSeeking, !playback.isShowing, trimPreview == nil else { return }
        let time = player.currentTime().seconds
        guard time.isFinite else { return }
        playhead = min(max(0, time), duration)
    }

    /// Moves the playhead (and the picture) to output time `t`.
    func seek(to t: Double, exact: Bool = false) {
        let target = min(max(0, t), max(0, duration))
        playhead = target
        guard !isStatic, sourceInfo != nil, trimPreview == nil else { return }
        playback.seek(to: target, tolerance: exact ? 0 : scrubTolerance(target))
    }

    /// A fast scrub shows the nearest frame that is quick to get; a slow one the exact frame.
    private func scrubTolerance(_ target: Double) -> Double {
        let now = CACurrentMediaTime()
        defer { lastSeek = (target, now) }
        guard let last = lastSeek, now - last.at < 0.3 else { return 1.0 / 60 }
        return min(1, max(1.0 / 60, abs(target - last.time) * 0.8))
    }

    /// The timeline is being dragged.
    func beginScrub() {
        guard !isRecordingVoice else { return }
        pause()
        dismissTrimCoach()
        isScrubbing = true
        filmstrip.isPaused = true
    }

    func endScrub() {
        guard isScrubbing else { return }
        isScrubbing = false
        filmstrip.isPaused = false
        seek(to: playhead, exact: true)
    }

    // MARK: - What is on the picture now

    private func updateMoment() {
        let t = playhead
        var next = EditorMoment()
        for item in recipe.texts where t >= item.start && t <= item.end { next.overlays.insert(item.id) }
        for item in recipe.stickers where t >= item.start && t <= item.end { next.overlays.insert(item.id) }
        for item in recipe.blurs where t >= item.start && t <= item.end { next.overlays.insert(item.id) }
        if recipe.captions != nil { next.caption = caption(at: t)?.text }
        if next != moment.value { moment.value = next }
    }

    private func caption(at t: Double) -> EditCaptionLine? {
        let pieces = captions().pieces
        var low = 0, high = pieces.count
        while low < high {
            let middle = (low + high) / 2
            if pieces[middle].start <= t { low = middle + 1 } else { high = middle }
        }
        guard low > 0, t <= pieces[low - 1].end else { return nil }
        return pieces[low - 1]
    }

    /// Caption lines and the pieces they are shown in, worked out once per change.
    private func captions() -> (lines: [EditCaptionLine], pieces: [EditCaptionLine]) {
        let transcript = self.transcript
        let size = outputPictureSize
        let stamp = "\(transcript?.createdAt.timeIntervalSince1970 ?? 0)|\(transcript?.segments.count ?? 0)|\(Int(size.width))x\(Int(size.height))"
        if let captionCache, captionCache.stamp == stamp { return (captionCache.lines, captionCache.pieces) }
        let lines = recipe.captionLines(from: transcript)
        let limit = EditCaptionOverlayView.charactersPerCaption(size)
        let pieces = lines.filter { !$0.isHidden }.flatMap { $0.pieces(limit: limit) }.sorted { $0.start < $1.start }
        captionCache = (stamp, lines, pieces)
        return (lines, pieces)
    }

    // MARK: - Tools

    func open(_ next: EditorTool) {
        guard !isRecordingVoice else { return }
        let wasCrop = tool == .crop
        pause()
        dismissTrimCoachIfNeeded(for: next)
        switch next {
        case .transcript:
            sheet = .transcript
            return
        case .speed:
            sheet = .speed
            return
        case .voice:
            tool = .voice
            voice = voicePhaseForPermission()
        case .sound:
            tool = .sound
            if recipe.audio.reducesNoise && noise == .idle && FileManager.default.fileExists(atPath: cleanedSoundURL.path) {
                noise = .ready
            }
        case .trim:
            tool = .trim
            if case .segment = selection {} else { selection = nil }
        default:
            tool = next
            selection = nil
        }
        if wasCrop != (tool == .crop) { rebuild() }
    }

    func closeTool() {
        let wasCrop = tool == .crop
        tool = nil
        selection = nil
        textEntry = nil
        if case .review(let take) = voice { discardTake(take) }
        if case .recording = voice { stopRecording() }
        countdownTask?.cancel()
        recorder.cancel()
        voice = .ready
        if wasCrop { rebuild() }
    }

    func dismissTrimCoach() {
        guard showsTrimCoach else { return }
        showsTrimCoach = false
        if !isStatic { UserDefaults.standard.set(true, forKey: Self.trimCoachKey) }
    }

    private func dismissTrimCoachIfNeeded(for next: EditorTool) {
        if next != .trim { return }
        dismissTrimCoach()
    }

    // MARK: - Sections

    var selectedSegment: EditSegment? {
        guard case .segment(let id) = selection, let index = recipe.segmentIndex(id) else { return nil }
        return recipe.segments[index]
    }

    /// Selects the section under output time `t`, or clears it when it was already selected.
    func toggleSegment(atOutput t: Double) {
        guard !isRecordingVoice else { return }
        dismissTrimCoach()
        // The whole video is one part: there is nothing to pick, so tapping it opens Trim (its ends).
        if recipe.segments.count == 1 {
            if tool != .trim {
                selection = nil
                open(.trim)
            }
            return
        }
        guard let index = recipe.segmentIndex(atOutput: t) else { return }
        let id = recipe.segments[index].id
        if selection == .segment(id) {
            selection = nil
        } else {
            pause()
            selection = .segment(id)
            if tool != .trim { tool = nil }
        }
    }

    func splitAtPlayhead() {
        pause()
        var didSplit = false
        apply { didSplit = $0.split(atOutput: playhead) }
        if didSplit {
            Haptics.firm()
            if let index = recipe.segmentIndex(atOutput: playhead) { selection = .segment(recipe.segments[index].id) }
        } else {
            Haptics.warning()
            toast = ToastMessage(text: "Move the playhead away from the edge to split.", systemImage: "scissors")
        }
    }

    /// Everything before the playhead goes, or everything after it: the quick way to trim a long
    /// recording, without dragging a handle across minutes of it.
    func cutToPlayhead(_ edge: TrimEdge) {
        pause()
        dismissTrimCoach()
        var changed = false
        let at = playhead
        apply { changed = edge == .start ? $0.cut(beforeOutput: at) : $0.cut(afterOutput: at) }
        if changed {
            Haptics.success()
            selection = nil
            seek(to: edge == .start ? 0 : max(0, duration - 0.04), exact: true)
        } else {
            Haptics.warning()
            toast = ToastMessage(text: edge == .start ? "Move the playhead to where the video should start."
                                 : "Move the playhead to where the video should end.", systemImage: "scissors")
        }
    }

    func deleteSelectedSegment() {
        guard let segment = selectedSegment else { return }
        guard recipe.segments.count > 1 else {
            toast = ToastMessage(text: "This is the whole video. Split it first, or drag its ends to trim.",
                                 systemImage: "exclamationmark.circle.fill")
            confirmsSectionDelete = false
            return
        }
        let start = recipe.segmentIndex(segment.id).map { recipe.outputStart(ofSegment: $0) } ?? playhead
        apply { $0.removeSegment(segment.id) }
        confirmsSectionDelete = false
        selection = nil
        seek(to: min(start, max(0, duration - 0.04)), exact: true)
        Haptics.success()
        toast = ToastMessage(text: "Section deleted", systemImage: "trash.fill")
    }

    /// Output-time span of a section (for drawing and the duration badge).
    func outputSpan(of id: UUID) -> ClosedRange<Double>? {
        guard let index = recipe.segmentIndex(id) else { return nil }
        let start = recipe.outputStart(ofSegment: index)
        return start...(start + recipe.segments[index].outputLength)
    }

    // MARK: - Trim handles

    func beginTrim(_ target: TrimTarget, edge: TrimEdge) {
        guard !isRecordingVoice else { return }
        pause()
        beginLiveChange()
        trimDrag = TrimDrag(target: target, edge: edge, offset: 0)
        dismissTrimCoach()
        if case .segment(let id) = target, let segment = recipe.segments.first(where: { $0.id == id }) {
            showTrimPreview(at: edge == .start ? segment.start : segment.end - 0.03)
        }
    }

    /// While a section's handle is dragged the player shows the recording itself at the handle,
    /// also outside what is kept so far.
    private func showTrimPreview(at sourceTime: Double) {
        guard !isStatic, let info = sourceInfo, info.hasVideo else { return }
        var whole = recipe
        whole.segments = [EditSegment(start: 0, end: max(0.1, info.duration))]
        whole.voiceClips = []
        whole.blurs = []
        trimPreview = whole
        trimPreviewIsShown = false
        trimTime = sourceTime
        buildTask?.cancel()
        buildTask = Task { @MainActor [weak self] in
            guard let self,
                  let build = try? await EditCompositionBuilder.build(recipe: whole, source: info, editFolder: self.editFolder,
                                                                      cleanedAudio: nil, originalSound: true),
                  !Task.isCancelled, self.trimPreview != nil else { return }
            let item = AVPlayerItem(asset: build.composition)
            item.videoComposition = EditCompositionBuilder.previewVideoComposition(recipe: whole, source: info, build: build,
                                                                                   fullFrame: false)
            self.trimPreviewIsShown = await self.playback.show(item, hasPicture: true, place: { [weak self] in self?.trimTime ?? 0 })
        }
    }

    private var trimTime: Double {
        get { trimTimeValue }
        set {
            trimTimeValue = newValue
            if trimPreview != nil, trimPreviewIsShown { playback.seek(to: max(0, newValue), tolerance: 1.0 / 30) }
        }
    }

    func updateTrim(offset: Double) {
        guard var drag = trimDrag, let start = liveStart else { return }
        drag.offset = offset
        trimDrag = drag
        var next = start
        switch drag.target {
        case .segment(let id):
            guard let index = start.segmentIndex(id) else { return }
            let segment = start.segments[index]
            let sourceDelta = offset * segment.speed
            if drag.edge == .start {
                next.trim(id, start: segment.start + sourceDelta)
            } else {
                next.trim(id, end: segment.end + sourceDelta)
            }
            if let moved = next.segments.first(where: { $0.id == id }) {
                trimTime = drag.edge == .start ? moved.start : moved.end - 0.03
            }
        case .text(let id):
            guard let index = start.texts.firstIndex(where: { $0.id == id }) else { return }
            let span = adjusted(edge: drag.edge, offset: offset, from: (start.texts[index].start, start.texts[index].end),
                                total: start.outputDuration)
            next.texts[index].start = span.0
            next.texts[index].end = span.1
        case .sticker(let id):
            guard let index = start.stickers.firstIndex(where: { $0.id == id }) else { return }
            let span = adjusted(edge: drag.edge, offset: offset, from: (start.stickers[index].start, start.stickers[index].end),
                                total: start.outputDuration)
            next.stickers[index].start = span.0
            next.stickers[index].end = span.1
        case .blur(let id):
            guard let index = start.blurs.firstIndex(where: { $0.id == id }) else { return }
            let span = adjusted(edge: drag.edge, offset: offset, from: (start.blurs[index].start, start.blurs[index].end),
                                total: start.outputDuration)
            next.blurs[index].start = span.0
            next.blurs[index].end = span.1
        }
        if next != recipe { recipe = next }
    }

    /// An overlay's start and end with one end moved, kept inside the video and 0.3 s long at least.
    private func adjusted(edge: TrimEdge, offset: Double, from original: (Double, Double), total: Double) -> (Double, Double) {
        if edge == .whole {
            let length = original.1 - original.0
            let start = min(max(0, original.0 + offset), max(0, total - length))
            return (start, min(total, start + length))
        }
        if edge == .start {
            return (min(max(0, original.0 + offset), original.1 - 0.3), original.1)
        }
        return (original.0, max(min(total, original.1 + offset), original.0 + 0.3))
    }

    /// While a section's start handle is dragged, it and the sections after it are drawn this
    /// much later, so the handle follows the finger; letting go closes the gap.
    var trimShift: (index: Int, seconds: Double)? {
        guard let drag = trimDrag, drag.edge == .start, case .segment(let id) = drag.target,
              let start = liveStart, let before = start.segmentIndex(id), let now = recipe.segmentIndex(id) else { return nil }
        return (now, start.segments[before].outputLength - recipe.segments[now].outputLength)
    }

    func endTrim() {
        guard let drag = trimDrag else { return }
        trimDrag = nil
        let previewed = trimPreview != nil
        trimPreview = nil
        let changed = liveStart.map { $0 != recipe } ?? false
        endLiveChange()
        if changed, case .segment(let id) = drag.target, let span = outputSpan(of: id) {
            // The playhead goes to the edge that was set.
            playhead = drag.edge == .start ? span.lowerBound : max(span.lowerBound, span.upperBound - 0.04)
        }
        rebuild(force: previewed)
    }

    /// One step of a handle without dragging it (VoiceOver).
    func nudge(_ target: TrimTarget, edge: TrimEdge, by seconds: Double) {
        beginTrim(target, edge: edge)
        updateTrim(offset: seconds)
        endTrim()
    }

    var isTrimmingSection: Bool {
        if case .segment? = trimDrag?.target { return true }
        return false
    }

    /// Source time under a trim handle while it is dragged, for its time bubble.
    var trimBubble: String? {
        guard let drag = trimDrag else { return nil }
        switch drag.target {
        case .segment(let id):
            guard let segment = recipe.segments.first(where: { $0.id == id }) else { return nil }
            return EditorText.precise(drag.edge == .start ? segment.start : segment.end)
        case .text(let id):
            guard let item = recipe.texts.first(where: { $0.id == id }) else { return nil }
            return EditorText.precise(drag.edge == .end ? item.end : item.start)
        case .sticker(let id):
            guard let item = recipe.stickers.first(where: { $0.id == id }) else { return nil }
            return EditorText.precise(drag.edge == .end ? item.end : item.start)
        case .blur(let id):
            guard let item = recipe.blurs.first(where: { $0.id == id }) else { return nil }
            return EditorText.precise(drag.edge == .end ? item.end : item.start)
        }
    }

    // MARK: - Speed

    func setSpeed(_ speed: Double, wholeVideo: Bool) {
        let target = wholeVideo ? nil : selectedSegment?.id
        apply { $0.setSpeed(speed, segment: target) }
        Haptics.selection()
    }

    // MARK: - Transcript

    var transcript: Transcript? { library.transcript(for: source.id) }

    var transcriptPhase: TranscriptPhase {
        if let transcriptPhaseOverride { return transcriptPhaseOverride }
        if transcript != nil { return .ready }
        if TranscriptService.shared.isQueuedOrRunning(source.id) { return .working }
        let video = library.video(source.id) ?? source
        switch video.transcriptStatus {
        case .inProgress: return .working
        case .unavailable: return .unavailable(TranscriptService.shared.unavailableReason(for: source.id))
        case .ready, .notStarted: return .notStarted
        }
    }

    func requestTranscript() {
        Haptics.tap()
        let library = self.library
        let id = source.id
        Task { @MainActor in await TranscriptService.shared.requestTranscript(videoID: id, library: library) }
    }

    func isRemoved(_ segment: TranscriptSegment) -> Bool {
        recipe.keptFraction(ofSource: segment.start...(segment.start + max(0.2, segment.duration))) < 0.5
    }

    func toggleSentence(_ segment: TranscriptSegment) {
        let range = segment.start...(segment.start + max(0.2, segment.duration))
        if isRemoved(segment) {
            apply { $0.keep(source: range) }
        } else {
            guard recipe.keptFraction(ofSource: range) < 0.999 || recipe.outputDuration - segment.duration > 0.5 else {
                toast = ToastMessage(text: "Keep at least a moment of the video.", systemImage: "exclamationmark.circle.fill")
                return
            }
            apply { $0.remove(source: range) }
        }
        Haptics.selection()
    }

    /// Filler words still in the edit.
    var fillers: [EditFiller] {
        guard let transcript else { return [] }
        let stamp = "\(transcript.createdAt.timeIntervalSince1970)|\(transcript.segments.count)"
        if fillerCache?.stamp != stamp { fillerCache = (stamp, EditFillerFinder.find(in: transcript)) }
        return (fillerCache?.all ?? []).filter { filler in
            recipe.keptFraction(ofSource: filler.start...filler.end) >= 0.5
        }
    }

    func removeFillers(_ chosen: [EditFiller]) {
        guard !chosen.isEmpty else { return }
        apply { recipe in
            for filler in chosen { recipe.remove(source: max(0, filler.start - 0.02)...(filler.end + 0.02)) }
        }
        Haptics.success()
        toast = ToastMessage(text: chosen.count == 1 ? "1 filler word removed" : "\(chosen.count) filler words removed",
                             systemImage: "checkmark.circle.fill")
    }

    // MARK: - Crop, rotate, flip

    var geometry: EditFrameGeometry { EditFrameGeometry(quarterTurns: recipe.quarterTurns, flipped: recipe.flipped) }

    func setAspect(_ aspect: EditAspect) {
        apply { recipe in
            recipe.crop.aspect = aspect
            recipe.crop.rect = Self.centredCrop(aspect: aspect, upright: pictureSize, geometry: geometry,
                                                current: recipe.crop.rect)
        }
        Haptics.selection()
    }

    /// The largest rect of the aspect's shape, centred on the current crop.
    static func centredCrop(aspect: EditAspect, upright: CGSize, geometry: EditFrameGeometry, current: CGRect) -> CGRect {
        guard let ratio = aspect.ratio else {
            return aspect == .original ? CGRect(x: 0, y: 0, width: 1, height: 1) : current
        }
        let shown = geometry.displaySize(upright)
        // Width and height in display pixels, as large as fits.
        var width = shown.width
        var height = width / ratio
        if height > shown.height {
            height = shown.height
            width = height * ratio
        }
        let currentShown = geometry.toDisplay(current)
        let centre = CGPoint(x: currentShown.midX * shown.width, y: currentShown.midY * shown.height)
        var x = centre.x - width / 2
        var y = centre.y - height / 2
        x = min(max(0, x), shown.width - width)
        y = min(max(0, y), shown.height - height)
        let normalised = CGRect(x: x / shown.width, y: y / shown.height, width: width / shown.width, height: height / shown.height)
        return geometry.toSource(normalised)
    }

    /// Crop rect from the crop tool, in display coordinates.
    func setDisplayCrop(_ rect: CGRect, live: Bool) {
        let source = geometry.toSource(rect.standardized)
        if live {
            liveChange { $0.crop.rect = source }
        } else {
            apply { $0.crop.rect = source }
        }
    }

    func rotate() {
        apply { recipe in
            recipe.quarterTurns = (recipe.quarterTurns + 1) % 4
            // A fixed shape (9:16…) stays that shape as shown, so the crop is fitted again.
            if recipe.crop.aspect.ratio != nil {
                recipe.crop.rect = Self.centredCrop(aspect: recipe.crop.aspect, upright: pictureSize,
                                                    geometry: EditFrameGeometry(quarterTurns: recipe.quarterTurns,
                                                                                flipped: recipe.flipped),
                                                    current: recipe.crop.rect)
            }
        }
        Haptics.selection()
    }

    func flip() {
        apply { $0.flipped.toggle() }
        Haptics.selection()
    }

    func resetCrop() {
        apply { recipe in
            recipe.crop = EditCrop()
            recipe.quarterTurns = 0
            recipe.flipped = false
        }
    }

    // MARK: - Text

    var selectedText: EditText? {
        guard case .text(let id) = selection else { return nil }
        return recipe.texts.first { $0.id == id }
    }

    /// Opens the keyboard for a new text at the playhead.
    func addText() {
        guard !isRecordingVoice else { return }
        pause()
        let start = min(playhead, max(0, duration - 0.5))
        textEntry = EditText(text: "", start: start, end: min(duration, start + 3))
    }

    func editText(_ item: EditText) {
        pause()
        textEntry = item
    }

    /// Done with nothing typed asks for words, instead of closing with nothing to show for it; tapping
    /// beside the text then closes it.
    @Published var textEntryNeedsWords = false

    func commitTextEntry(leaving: Bool = false) {
        guard let entry = textEntry else { return }
        let trimmed = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let exists = recipe.texts.contains { $0.id == entry.id }
        if trimmed.isEmpty, !exists, !leaving {
            textEntryNeedsWords = true
            Haptics.warning()
            return
        }
        textEntry = nil
        textEntryNeedsWords = false
        if trimmed.isEmpty {
            if exists { deleteText(entry.id) }
            return
        }
        var item = entry
        item.text = trimmed
        apply { recipe in
            if let index = recipe.texts.firstIndex(where: { $0.id == item.id }) {
                recipe.texts[index] = item
            } else {
                recipe.texts.append(item)
            }
        }
        tool = .text
        selection = .text(item.id)
    }

    func updateText(_ id: UUID, _ change: (inout EditText) -> Void) {
        apply { recipe in
            if let index = recipe.texts.firstIndex(where: { $0.id == id }) { change(&recipe.texts[index]) }
        }
    }

    func deleteText(_ id: UUID) {
        apply { $0.texts.removeAll { $0.id == id } }
        if selection == .text(id) { selection = nil }
        Haptics.tap()
    }

    // MARK: - Shapes and emoji

    var selectedSticker: EditSticker? {
        guard case .sticker(let id) = selection else { return nil }
        return recipe.stickers.first { $0.id == id }
    }

    func addSticker(_ kind: EditStickerKind, emoji: String? = nil) {
        pause()
        let start = min(playhead, max(0, duration - 0.5))
        var item = EditSticker(kind: kind, emoji: emoji, start: start, end: min(duration, start + 3))
        switch kind {
        case .arrow: item.rotation = -35
        case .highlight: item.color = .yellow
        default: break
        }
        apply { $0.stickers.append(item) }
        tool = .shapes
        selection = .sticker(item.id)
        Haptics.tap()
    }

    func updateSticker(_ id: UUID, _ change: (inout EditSticker) -> Void) {
        apply { recipe in
            if let index = recipe.stickers.firstIndex(where: { $0.id == id }) { change(&recipe.stickers[index]) }
        }
    }

    func deleteSticker(_ id: UUID) {
        apply { $0.stickers.removeAll { $0.id == id } }
        if selection == .sticker(id) { selection = nil }
        Haptics.tap()
    }

    // MARK: - Blur

    var selectedBlur: EditBlur? {
        guard case .blur(let id) = selection else { return nil }
        return recipe.blurs.first { $0.id == id }
    }

    func addBlur() {
        pause()
        let start = min(playhead, max(0, duration - 0.5))
        let item = EditBlur(start: start, end: min(duration, start + 4))
        apply { $0.blurs.append(item) }
        tool = .blur
        selection = .blur(item.id)
        Haptics.tap()
    }

    func deleteBlur(_ id: UUID) {
        apply { $0.blurs.removeAll { $0.id == id } }
        if selection == .blur(id) { selection = nil }
    }

    /// Moves a live drag or pinch of an overlay (one undo step per gesture).
    func liveMove(_ selection: EditorSelection, center: CGPoint? = nil, scale: Double? = nil, rotation: Double? = nil,
                  rect: CGRect? = nil) {
        liveChange { recipe in
            switch selection {
            case .text(let id):
                guard let index = recipe.texts.firstIndex(where: { $0.id == id }) else { return }
                if let center { recipe.texts[index].center = center.clampedUnit }
                if let scale { recipe.texts[index].scale = min(4, max(0.4, scale)) }
            case .sticker(let id):
                guard let index = recipe.stickers.firstIndex(where: { $0.id == id }) else { return }
                if let center { recipe.stickers[index].center = center.clampedUnit }
                if let scale { recipe.stickers[index].scale = min(5, max(0.3, scale)) }
                if let rotation { recipe.stickers[index].rotation = rotation }
            case .blur(let id):
                guard let index = recipe.blurs.firstIndex(where: { $0.id == id }), let rect else { return }
                recipe.blurs[index].rect = rect.clampedUnit
            case .segment, .voice:
                break
            }
        }
    }

    /// Two fingers on the picture: size and turn of the selected text or shape, one undo step.
    func pinch(scale: Double?, degrees: Double?) {
        guard let selection, selection.isPinchableOverlay else { return }
        if pinchStart == nil {
            switch selection {
            case .text(let id):
                guard let item = recipe.texts.first(where: { $0.id == id }) else { return }
                pinchStart = (item.scale, 0)
            case .sticker(let id):
                guard let item = recipe.stickers.first(where: { $0.id == id }) else { return }
                pinchStart = (item.scale, item.rotation)
            default:
                return
            }
        }
        guard let start = pinchStart else { return }
        var turns: Double?
        if case .sticker(let id) = selection, let degrees,
           recipe.stickers.first(where: { $0.id == id })?.kind != .circle {
            turns = start.rotation + degrees
        }
        liveMove(selection, scale: scale.map { start.scale * $0 }, rotation: turns)
    }

    func endPinch() {
        guard pinchStart != nil else { return }
        pinchStart = nil
        endLiveChange()
    }

    /// Selects an overlay and moves the playhead into its time when it is out of view.
    func selectOverlay(_ next: EditorSelection) {
        guard !isRecordingVoice else { return }
        let wasCrop = tool == .crop
        defer { if wasCrop { rebuild() } }
        pause()
        selection = next
        let span: (Double, Double)?
        switch next {
        case .text(let id):
            span = recipe.texts.first { $0.id == id }.map { ($0.start, $0.end) }
            tool = .text
        case .sticker(let id):
            span = recipe.stickers.first { $0.id == id }.map { ($0.start, $0.end) }
            tool = .shapes
        case .blur(let id):
            span = recipe.blurs.first { $0.id == id }.map { ($0.start, $0.end) }
            tool = .blur
        case .voice(let id):
            span = recipe.voiceClips.first { $0.id == id }.map { ($0.start, $0.start + $0.duration) }
            tool = .voice
            voice = .ready
        case .segment:
            span = nil
        }
        if let span, playhead < span.0 || playhead > span.1 { seek(to: span.0 + 0.01, exact: true) }
    }

    // MARK: - Captions

    var captionLines: [EditCaptionLine] { captions().lines }

    func addCaptions() {
        apply { $0.captions = EditCaptions() }
        Haptics.success()
    }

    func setCaptionStyle(_ style: EditCaptionStyle) {
        apply { recipe in
            if recipe.captions == nil { recipe.captions = EditCaptions() }
            recipe.captions?.style = style
        }
        Haptics.selection()
    }

    func editCaption(_ id: String, text: String) {
        apply { recipe in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let original = transcript?.segments.first { $0.id.uuidString == id }
            if trimmed.isEmpty {
                // Nothing left to show: hidden, so it can be brought back with its words.
                recipe.captions?.edits[id] = nil
                recipe.captions?.hidden.insert(id)
            } else if let original, trimmed == recipe.keptText(of: original) {
                recipe.captions?.edits[id] = nil
            } else {
                recipe.captions?.edits[id] = trimmed
            }
        }
    }

    func toggleCaptionHidden(_ id: String) {
        apply { recipe in
            guard recipe.captions != nil else { return }
            if recipe.captions!.hidden.contains(id) {
                recipe.captions!.hidden.remove(id)
            } else {
                recipe.captions!.hidden.insert(id)
            }
        }
    }

    func removeCaptions() {
        apply { $0.captions = nil }
    }

    // MARK: - Voice-over

    private func voicePhaseForPermission() -> VoicePhase {
        if isStatic { return voice }
        switch Permissions.currentState(.microphone) {
        case .granted: return .ready
        case .denied: return .denied
        default: return .primer
        }
    }

    func requestMicrophone() {
        Task { @MainActor in
            let state = await Permissions.request(.microphone)
            voice = state == .granted ? .ready : .denied
        }
    }

    /// 3, 2, 1, then recording from the playhead with the video playing muted.
    func startCountdown() {
        guard playhead < duration - 0.3 else {
            toast = ToastMessage(text: "Move the playhead to where your voice should start.", systemImage: "mic.fill")
            return
        }
        pause()
        countdownTask?.cancel()
        let fileName = "voice-\(UUID().uuidString).m4a"
        let url = editFolder.appendingPathComponent(fileName)
        countdownTask = Task { @MainActor [weak self] in
            for count in stride(from: 3, through: 1, by: -1) {
                guard let self, !Task.isCancelled else { return }
                self.voice = .countdown(count)
                Haptics.tap()
                // The microphone gets ready during the count, so recording starts on time.
                if count == 2 {
                    do {
                        try self.recorder.prepare(url: url)
                    } catch {
                        self.microphoneFailed()
                        return
                    }
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            guard let self, !Task.isCancelled else { return }
            self.beginRecording()
        }
    }

    private func microphoneFailed() {
        recorder.cancel()
        sessionIsActive = false
        voice = .ready
        toast = ToastMessage(text: "The microphone couldn't start. End any call and try again.", systemImage: "mic.slash.fill")
    }

    func cancelCountdown() {
        countdownTask?.cancel()
        recorder.cancel()
        sessionIsActive = false
        voice = .ready
    }

    private func beginRecording() {
        guard recorder.record() else {
            microphoneFailed()
            return
        }
        sessionIsActive = true
        let start = playhead
        voice = .recording(start: start)
        playback.isMuted = true
        playback.play()
        isPlaying = true
        startDisplayLink()
        Haptics.firm()
        levelTask?.cancel()
        levelTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                self.voiceLevel = self.recorder.level
                try? await Task.sleep(nanoseconds: 60_000_000)
            }
        }
    }

    var recordingElapsed: Double {
        guard case .recording(let start) = voice else { return 0 }
        return max(0, playhead - start)
    }

    /// Ends a countdown or a take.
    func stopVoice() {
        if case .countdown = voice { cancelCountdown() } else { stopRecording() }
    }

    func stopRecording() {
        guard case .recording(let start) = voice else { return }
        levelTask?.cancel()
        voiceLevel = 0
        let played = max(0, player.currentTime().seconds - start)
        isPlaying = false
        stopDisplayLink()
        playback.pause()
        playback.isMuted = false
        sessionIsActive = false
        guard let take = recorder.stop(), take.duration > 0.3 else {
            voice = .ready
            toast = ToastMessage(text: "That take was too short.", systemImage: "mic.fill")
            return
        }
        playhead = min(max(0, player.currentTime().seconds), duration)
        // The microphone starts a moment before the video moves; that moment isn't part of the take.
        let lead = played > 0.3 ? min(0.8, max(0, take.duration - played)) : 0
        Haptics.success()
        voice = .review(VoiceTake(fileName: take.fileName, start: start,
                                  duration: min(take.duration - lead, duration - start), lead: lead))
    }

    /// Plays the take with the video from where it starts.
    func playTake(_ take: VoiceTake) {
        guard !isStatic else { return }
        if isPlaying {
            pause()
            return
        }
        takePlayer?.stop()
        takePlayer = try? AVAudioPlayer(contentsOf: editFolder.appendingPathComponent(take.fileName))
        takePlayer?.currentTime = take.lead
        seek(to: take.start, exact: true)
        activateSession()
        isPlaying = true
        startDisplayLink()
        playback.play()
        takePlayer?.play()
        takeTask?.cancel()
        takeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0.2, take.duration + 0.15) * 1_000_000_000))
            guard let self, !Task.isCancelled, case .review = self.voice else { return }
            self.pause()
        }
    }

    func keepTake(_ take: VoiceTake) {
        takePlayer?.stop()
        pause()
        let clip = EditVoiceClip(fileName: take.fileName, start: take.start, duration: take.duration, lead: take.lead)
        apply { $0.voiceClips.append(clip) }
        voice = .ready
        selection = .voice(clip.id)
        toast = ToastMessage(text: "Voice-over added", systemImage: "mic.fill")
    }

    func discardTake(_ take: VoiceTake) {
        takePlayer?.stop()
        pause()
        try? FileManager.default.removeItem(at: editFolder.appendingPathComponent(take.fileName))
        voice = .ready
    }

    func rerecord(_ take: VoiceTake) {
        discardTake(take)
        seek(to: take.start, exact: true)
        startCountdown()
    }

    func deleteVoiceClip(_ id: UUID) {
        apply { $0.voiceClips.removeAll { $0.id == id } }
        if selection == .voice(id) { selection = nil }
    }

    // MARK: - Sound

    func setVolume(_ value: Double, live: Bool) {
        if live { liveChange { $0.audio.volume = value } } else { apply { $0.audio.volume = value } }
    }

    func setVoiceVolume(_ value: Double, live: Bool) {
        if live { liveChange { $0.audio.voiceVolume = value } } else { apply { $0.audio.voiceVolume = value } }
    }

    func toggleMute() { apply { $0.audio.muted.toggle() } }
    func toggleFadeIn() { apply { $0.audio.fadeIn.toggle() } }
    func toggleFadeOut() { apply { $0.audio.fadeOut.toggle() } }

    func setNoiseReduction(_ on: Bool) {
        apply { $0.audio.reducesNoise = on }
        hearsOriginalSound = false
        guard on, !isStatic else { return }
        cleanSound()
    }

    private func cleanSound() {
        if case .working = noise { return }
        if FileManager.default.fileExists(atPath: cleanedSoundURL.path) {
            noise = .ready
            rebuild()
            return
        }
        guard EditEstimate.hasRoom(for: Int64(recipe.sourceDuration * 96_000 / 8)) else {
            noise = .idle
            apply { $0.audio.reducesNoise = false }
            toast = ToastMessage(text: "Not enough space to clean up the sound. Free up some and try again.",
                                 systemImage: "exclamationmark.circle.fill")
            return
        }
        noise = .working(0)
        let source = sourceURL
        let destination = cleanedSoundURL
        noiseTask = Task { @MainActor [weak self] in
            do {
                try await NoiseReducer.clean(source: source, to: destination) { fraction in
                    guard let self else { return }
                    if case .working(let shown) = self.noise, fraction > shown + 0.01 { self.noise = .working(fraction) }
                }
                guard let self, !Task.isCancelled else { return }
                self.noise = .ready
                self.rebuild()
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.noise = .failed
                self.apply { $0.audio.reducesNoise = false }
            }
        }
    }

    func setHearsOriginal(_ original: Bool) {
        hearsOriginalSound = original
        rebuild()
    }

    // MARK: - Thumbnail

    func chooseThumbnail() {
        apply { $0.thumbnailTime = playhead }
        thumbnailJustChosen = true
        Haptics.success()
    }

    // MARK: - Export

    func estimatedBytes(_ quality: ExportQuality) -> Int64 {
        EditEstimate.bytes(recipe: recipe, settings: exportSettings(quality))
    }

    func exportSettings(_ quality: ExportQuality) -> EditExportSettings {
        let video = library.video(source.id) ?? source
        let known = video.duration > 1 ? Double(video.fileSize) * 8 / video.duration : 0
        return EditExportSettings(recipe: recipe, picture: hasPicture ? pictureSize : nil,
                                  sourceBitRate: sourceInfo?.videoBitRate ?? known,
                                  frameRate: Double(sourceInfo?.frameRate ?? 30), quality: quality)
    }

    var availableBytes: Int64 { availableBytesOverride ?? DiskSpace.available }

    func hasRoom(for quality: ExportQuality) -> Bool {
        EditEstimate.hasRoom(for: estimatedBytes(quality), available: availableBytes)
    }

    func setQuality(_ quality: ExportQuality) {
        guard quality != recipe.quality else { return }
        // A choice about the file, not an edit: undo doesn't bring it back.
        recipe.quality = quality
        scheduleDraftSave()
        Haptics.selection()
    }

    func startExport() {
        pause()
        sheet = nil
        // Kept until the new recording is ready, whatever happens to the save.
        keepDraft()
        let id = EditRenderer.shared.begin(recipe: stamped(recipe), source: source, library: library)
        phase = .rendering(id)
    }

    func cancelExport(_ id: UUID) {
        EditRenderer.shared.cancel(id)
        RecordingSaver.shared.discard(id, library: library)
        phase = .cancelled
    }

    func retryExport(_ id: UUID) {
        RecordingSaver.shared.retry(id, library: library)
    }

    func backToEditing() {
        phase = .editing
    }
}

/// Text helpers for the editor.
enum EditorText {
    /// "0:04.2"
    static func precise(_ seconds: Double) -> String {
        let value = max(0, seconds)
        let whole = Int(value)
        let tenths = Int(((value - Double(whole)) * 10).rounded(.down))
        return String(format: "%d:%02d.%d", whole / 60, whole % 60, tenths)
    }

    /// "12.4s"
    static func length(_ seconds: Double) -> String {
        seconds >= 60 ? Format.clock(seconds) : String(format: "%.1fs", max(0, seconds))
    }

    static func speed(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))×" : String(format: "%g×", value)
    }
}

/// Calls a closure from a display link (which would keep its target alive).
final class DisplayLinkTarget: NSObject {
    private let body: @MainActor () -> Void

    init(_ body: @escaping @MainActor () -> Void) {
        self.body = body
    }

    @objc func fire() { MainActor.assumeIsolated { body() } }
}

/// Finds filler words in a transcript: hesitation sounds always, and verbal fillers ("like,",
/// "you know,") when a comma sets them apart.
enum EditFillerFinder {
    static let sounds: Set<String> = ["um", "umm", "uh", "uhh", "uhm", "erm", "er", "ah", "hmm", "mm", "eh"]
    static let words: Set<String> = ["like", "basically", "literally", "actually", "so"]
    static let pairs: Set<String> = ["you know", "i mean", "sort of", "kind of"]

    static func find(in transcript: Transcript) -> [EditFiller] {
        var result: [EditFiller] = []
        for segment in transcript.segments {
            let words = segment.words?.isEmpty == false ? segment.words! : estimatedWords(segment)
            let plain = words.map { normalised($0.text) }
            var index = 0
            while index < words.count {
                let word = words[index]
                let hasComma = word.text.hasSuffix(",")
                var length = 0
                if sounds.contains(plain[index]) {
                    length = 1
                } else if index + 1 < words.count, pairs.contains(plain[index] + " " + plain[index + 1]),
                          words[index + 1].text.hasSuffix(",") {
                    length = 2
                } else if self.words.contains(plain[index]), hasComma {
                    length = 1
                }
                if length > 0 {
                    let last = words[index + length - 1]
                    let before = words[max(0, index - 3)..<index].map(\.text).joined(separator: " ")
                    let after = words[min(words.count, index + length)..<min(words.count, index + length + 3)]
                        .map(\.text).joined(separator: " ")
                    result.append(EditFiller(id: "\(segment.id.uuidString)-\(index)",
                                             text: words[index..<(index + length)].map(\.text).joined(separator: " "),
                                             start: word.start, end: last.start + max(0.08, last.duration),
                                             before: before, after: after))
                    index += length
                } else {
                    index += 1
                }
            }
        }
        return result
    }

    static func normalised(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
    }

    /// Word times spread by length over the line, for transcripts made before word times were kept.
    static func estimatedWords(_ segment: TranscriptSegment) -> [TranscriptWord] {
        let pieces = segment.text.split(separator: " ").map(String.init)
        let total = Double(max(1, pieces.reduce(0) { $0 + $1.count + 1 }))
        var cursor = segment.start
        return pieces.map { piece in
            let length = segment.duration * Double(piece.count + 1) / total
            defer { cursor += length }
            return TranscriptWord(text: piece, start: cursor, duration: length)
        }
    }
}

extension CGPoint {
    var clampedUnit: CGPoint { CGPoint(x: min(max(0, x), 1), y: min(max(0, y), 1)) }
}

extension CGRect {
    /// Kept inside 0...1, at least 5% each way.
    var clampedUnit: CGRect {
        let width = min(1, max(0.05, size.width))
        let height = min(1, max(0.05, size.height))
        return CGRect(x: min(max(0, origin.x), 1 - width), y: min(max(0, origin.y), 1 - height), width: width, height: height)
    }
}
