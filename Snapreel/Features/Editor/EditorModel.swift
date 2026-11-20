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
}

enum NoisePhase: Equatable {
    case idle
    case working(Double)
    case ready
    case failed
}

enum TrimEdge: Equatable { case start, end }

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

/// One picture of the filmstrip.
struct EditFilmFrame: Identifiable {
    var id: Double { time }
    /// Source seconds.
    var time: Double
    var image: UIImage
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

    @Published private(set) var recipe: EditRecipe
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    @Published var playhead: Double = 0
    @Published private(set) var isPlaying = false
    @Published var selection: EditorSelection?
    @Published private(set) var tool: EditorTool?
    @Published var sheet: EditorSheet?
    @Published var phase: EditorPhase = .editing
    @Published var toast: ToastMessage?

    @Published private(set) var poster: UIImage?
    @Published private(set) var filmFrames: [EditFilmFrame] = []
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

    let player = AVPlayer()
    private var sourceInfo: EditSource?
    private var undoStack: [EditRecipe] = []
    private var redoStack: [EditRecipe] = []
    private var liveStart: EditRecipe?
    private var builtKey: String?
    private var buildTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var seekTarget: Double?
    private var isSeeking = false
    private let recorder = VoiceOverRecorder()
    private var countdownTask: Task<Void, Never>?
    private var levelTask: Task<Void, Never>?
    private var takePlayer: AVAudioPlayer?
    private var pendingDraft: EditDraft?

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
        player.actionAtItemEnd = .pause
    }

    var hasPicture: Bool { !source.isAudioOnly }
    var duration: Double { recipe.outputDuration }
    var tools: [EditorTool] { EditorTool.allCases.filter { hasPicture || $0.worksWithoutPicture } }
    var isDirty: Bool { !recipe.isUntouched }
    var draftDate: Date? { pendingDraft?.recipe.updatedAt }
    var cleanedSoundURL: URL { editFolder.appendingPathComponent("clean-sound.m4a") }
    /// The picture as shown: cropped and turned.
    var outputPictureSize: CGSize { recipe.outputPictureSize(source: pictureSize) }

    // MARK: - Loading

    func load() async {
        if pointsPerSecond == 0 { pointsPerSecond = Self.defaultPointsPerSecond(duration: duration) }
        if let url = library.thumbnailURL(for: source) {
            poster = await ThumbnailCache.shared.load(url)
        }
        if isStatic {
            if let poster { filmFrames = Self.staticFilm(poster, duration: recipe.sourceDuration) }
            return
        }
        observePlayer()
        do {
            let info = try await EditSource.load(sourceURL)
            sourceInfo = info
            if info.hasVideo { pictureSize = info.uprightSize }
            if info.duration > 0, abs(info.duration - recipe.sourceDuration) > 0.05, !isDirty {
                recipe = EditRecipe.original(sourceID: source.id, duration: info.duration)
            }
            rebuild(force: true)
            if info.hasVideo { await makeFilmstrip(info) }
        } catch {
            toast = ToastMessage(text: "This recording can't be opened for editing.", systemImage: "exclamationmark.circle.fill")
        }
    }

    static func defaultPointsPerSecond(duration: Double) -> CGFloat {
        // About two screens for the whole video, within a readable range.
        CGFloat(min(80, max(6, 700 / max(duration, 1))))
    }

    private static func staticFilm(_ poster: UIImage, duration: Double) -> [EditFilmFrame] {
        stride(from: 0.0, to: max(duration, 1), by: max(duration, 1) / 24).map { EditFilmFrame(time: $0, image: poster) }
    }

    private func makeFilmstrip(_ info: EditSource) async {
        let count = Int(min(48, max(8, info.duration / 2)))
        let step = info.duration / Double(count)
        let times = (0..<count).map { CMTime(seconds: Double($0) * step + step / 2, preferredTimescale: 600) }
        let generator = AVAssetImageGenerator(asset: info.asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 160)
        generator.requestedTimeToleranceBefore = CMTime(seconds: step / 2, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: step / 2, preferredTimescale: 600)
        var frames: [EditFilmFrame] = []
        for await result in generator.images(for: times) {
            guard let image = try? result.image else { continue }
            frames.append(EditFilmFrame(time: result.requestedTime.seconds, image: UIImage(cgImage: image)))
            if frames.count % 6 == 0 { filmFrames = frames.sorted { $0.time < $1.time } }
        }
        filmFrames = frames.sorted { $0.time < $1.time }
    }

    /// The filmstrip picture nearest to source time `t`.
    func filmImage(atSource t: Double) -> UIImage? {
        guard !filmFrames.isEmpty else { return poster }
        var best = filmFrames[0]
        for frame in filmFrames where abs(frame.time - t) < abs(best.time - t) { best = frame }
        return best.image
    }

    // MARK: - Still picture

    private var stillCache: (key: String, image: UIImage)?
    private let stillContext = CIContext(options: [.cacheIntermediates: false])

    /// The poster with the recipe's crop, turn, flip and blur: what the preview shows before
    /// the player has a frame, and in debug screenshots.
    func stillImage(fullFrame: Bool) -> UIImage? {
        guard let poster, let cg = poster.cgImage else { return nil }
        // Blur boxes come and go with time; only screenshots need the still to follow them.
        let moment = isStatic && !recipe.blurs.isEmpty ? Int(playhead * 10) : 0
        let key = "\(fullFrame)|\(recipe.crop.rect)|\(recipe.quarterTurns)|\(recipe.flipped)|\(recipe.blurs.map(\.rect))|\(moment)"
        if let stillCache, stillCache.key == key { return stillCache.image }
        var shown = recipe
        if fullFrame {
            shown.crop = EditCrop()
            shown.blurs = []
        }
        let upright = CGSize(width: cg.width, height: cg.height)
        let size = shown.renderSize(source: upright, quality: .original)
        let pipeline = EditFramePipeline(recipe: shown, naturalSize: upright, orientation: .up, renderSize: size,
                                         showsBlur: !fullFrame, overlays: [])
        let frame = pipeline.render(CIImage(cgImage: cg), at: playhead)
        guard let output = stillContext.createCGImage(frame, from: CGRect(origin: .zero, size: size)) else { return poster }
        let image = UIImage(cgImage: output)
        stillCache = (key, image)
        return image
    }

    // MARK: - Draft

    func continueDraft() {
        if let draft = pendingDraft {
            recipe = draft.recipe
            undoStack = []
            redoStack = []
            updateHistoryFlags()
            if draft.recipe.audio.reducesNoise, FileManager.default.fileExists(atPath: cleanedSoundURL.path) { noise = .ready }
            rebuild(force: true)
        }
        pendingDraft = nil
        phase = .editing
    }

    func startOver() {
        pendingDraft = nil
        library.deleteDraft(source.id)
        phase = .editing
    }

    func keepDraft() {
        saveTask?.cancel()
        if isDirty { library.saveDraft(stamped(recipe)) } else { library.deleteDraft(source.id) }
    }

    func discardDraft() {
        saveTask?.cancel()
        library.deleteDraft(source.id)
        library.removeEditFilesIfUnused(source.id)
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
            if self.isDirty { self.library.saveDraft(self.stamped(self.recipe)) } else { self.library.deleteDraft(self.source.id) }
        }
    }

    // MARK: - Changes and history

    /// One undoable change.
    func apply(_ change: (inout EditRecipe) -> Void) {
        var next = recipe
        change(&next)
        guard next != recipe else { return }
        undoStack.append(recipe)
        if undoStack.count > 200 { undoStack.removeFirst() }
        redoStack.removeAll()
        recipe = next
        didChange()
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
    }

    func endLiveChange() {
        guard let start = liveStart else { return }
        liveStart = nil
        guard start != recipe else { return }
        undoStack.append(start)
        redoStack.removeAll()
        didChange()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(recipe)
        recipe = previous
        Haptics.tap()
        didChange(keepsSelection: false)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(recipe)
        recipe = next
        Haptics.tap()
        didChange(keepsSelection: false)
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

    private func didChange(keepsSelection: Bool = true) {
        updateHistoryFlags()
        if !keepsSelection || !selectionExists { selection = nil }
        playhead = min(playhead, max(0, duration - 0.01))
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

    /// Rebuilds the player's composition when something it plays changed.
    func rebuild(force: Bool = false) {
        guard !isStatic, let info = sourceInfo else { return }
        let fullFrame = tool == .crop
        let key = previewKey(fullFrame: fullFrame)
        guard force || key != builtKey else { return }
        builtKey = key
        let recipe = self.recipe
        let folder = editFolder
        let cleaned = cleanedSoundURL
        let original = hearsOriginalSound
        buildTask?.cancel()
        buildTask = Task { @MainActor [weak self] in
            guard let build = try? await EditCompositionBuilder.build(recipe: recipe, source: info, editFolder: folder,
                                                                     cleanedAudio: cleaned,
                                                                     purpose: .preview(fullFrame: fullFrame, originalSound: original)),
                  let self, !Task.isCancelled else { return }
            let item = AVPlayerItem(asset: build.composition)
            item.audioMix = build.audioMix
            item.videoComposition = build.videoComposition
            item.audioTimePitchAlgorithm = .spectral
            let wasPlaying = self.isPlaying
            self.player.replaceCurrentItem(with: item)
            self.seek(to: self.playhead, exact: true)
            if wasPlaying { self.player.play() }
        }
    }

    private func previewKey(fullFrame: Bool) -> String {
        var parts: [String] = []
        parts.append(recipe.segments.map { "\($0.start)-\($0.end)x\($0.speed)" }.joined(separator: ","))
        parts.append(fullFrame ? "full" : "\(recipe.crop.rect)")
        parts.append("\(recipe.quarterTurns)\(recipe.flipped)")
        parts.append(fullFrame ? "" : recipe.blurs.map { "\($0.rect)\($0.start)\($0.end)" }.joined())
        parts.append("\(recipe.audio)")
        parts.append(recipe.voiceClips.map { "\($0.fileName)\($0.start)" }.joined())
        parts.append("\(hearsOriginalSound)\(noise == .ready)")
        return parts.joined(separator: "|")
    }

    private func observePlayer() {
        guard timeObserver == nil else { return }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self, self.isPlaying, !self.isSeeking else { return }
                self.playhead = min(max(0, time.seconds), self.duration)
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil,
                                                             queue: .main) { [weak self] note in
            Task { @MainActor in
                guard let self, (note.object as? AVPlayerItem) === self.player.currentItem else { return }
                self.isPlaying = false
                self.playhead = self.duration
                if case .recording = self.voice { self.stopRecording() }
            }
        }
    }

    func teardown() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        countdownTask?.cancel()
        levelTask?.cancel()
        takePlayer?.stop()
        recorder.cancel()
        buildTask?.cancel()
    }

    // MARK: - Playback

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard !isStatic else { return }
        if playhead >= duration - 0.05 { seek(to: 0, exact: true) }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        takePlayer?.stop()
        isPlaying = false
    }

    /// Moves the playhead (and the picture) to output time `t`.
    func seek(to t: Double, exact: Bool = false) {
        let target = min(max(0, t), max(0, duration))
        playhead = target
        guard !isStatic, player.currentItem != nil else { return }
        seekTarget = target
        guard !isSeeking else { return }
        performSeek(exact: exact)
    }

    private func performSeek(exact: Bool) {
        guard let target = seekTarget else { return }
        seekTarget = nil
        isSeeking = true
        let tolerance = exact ? CMTime.zero : CMTime(value: 1, timescale: 30)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: tolerance,
                    toleranceAfter: tolerance) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isSeeking = false
                if self.seekTarget != nil { self.performSeek(exact: exact) }
            }
        }
    }

    // MARK: - Tools

    func open(_ next: EditorTool) {
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
        dismissTrimCoach()
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

    func deleteSelectedSegment() {
        guard let segment = selectedSegment else { return }
        guard recipe.segments.count > 1 else {
            toast = ToastMessage(text: "Keep at least one section. Trim it instead.", systemImage: "exclamationmark.circle.fill")
            confirmsSectionDelete = false
            return
        }
        let start = recipe.segmentIndex(segment.id).map { recipe.outputStart(ofSegment: $0) } ?? playhead
        apply { $0.removeSegment(segment.id) }
        confirmsSectionDelete = false
        selection = nil
        seek(to: min(start, duration))
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
        pause()
        beginLiveChange()
        trimDrag = TrimDrag(target: target, edge: edge, offset: 0)
        dismissTrimCoach()
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
        trimDrag = nil
        endLiveChange()
        rebuild()
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
            return EditorText.precise(drag.edge == .start ? item.start : item.end)
        case .sticker(let id):
            guard let item = recipe.stickers.first(where: { $0.id == id }) else { return nil }
            return EditorText.precise(drag.edge == .start ? item.start : item.end)
        case .blur(let id):
            guard let item = recipe.blurs.first(where: { $0.id == id }) else { return nil }
            return EditorText.precise(drag.edge == .start ? item.start : item.end)
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
        return EditFillerFinder.find(in: transcript).filter { filler in
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
        pause()
        let start = min(playhead, max(0, duration - 0.5))
        textEntry = EditText(text: "", start: start, end: min(duration, start + 3))
    }

    func editText(_ item: EditText) {
        pause()
        textEntry = item
    }

    func commitTextEntry() {
        guard let entry = textEntry else { return }
        textEntry = nil
        let trimmed = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let exists = recipe.texts.contains { $0.id == entry.id }
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

    /// Selects an overlay and moves the playhead into its time when it is out of view.
    func selectOverlay(_ next: EditorSelection) {
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

    var captionLines: [EditCaptionLine] { recipe.captionLines(from: transcript) }

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
            if let original, trimmed == recipe.keptText(of: original) {
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
        countdownTask = Task { @MainActor [weak self] in
            for count in stride(from: 3, through: 1, by: -1) {
                guard let self, !Task.isCancelled else { return }
                self.voice = .countdown(count)
                Haptics.tap()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            guard let self, !Task.isCancelled else { return }
            self.beginRecording()
        }
    }

    func cancelCountdown() {
        countdownTask?.cancel()
        voice = .ready
    }

    private func beginRecording() {
        let fileName = "voice-\(UUID().uuidString).m4a"
        let url = editFolder.appendingPathComponent(fileName)
        do {
            try recorder.start(url: url)
        } catch {
            voice = .ready
            toast = ToastMessage(text: "The microphone couldn't start. Try again.", systemImage: "mic.slash.fill")
            return
        }
        let start = playhead
        voice = .recording(start: start)
        player.isMuted = true
        player.play()
        isPlaying = true
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

    func stopRecording() {
        guard case .recording(let start) = voice else { return }
        levelTask?.cancel()
        voiceLevel = 0
        player.pause()
        isPlaying = false
        player.isMuted = false
        guard let take = recorder.stop(), take.duration > 0.3 else {
            voice = .ready
            toast = ToastMessage(text: "That take was too short.", systemImage: "mic.fill")
            return
        }
        Haptics.success()
        voice = .review(VoiceTake(fileName: take.fileName, start: start, duration: min(take.duration, duration - start)))
    }

    /// Plays the take with the video from where it starts.
    func playTake(_ take: VoiceTake) {
        guard !isStatic else { return }
        takePlayer?.stop()
        takePlayer = try? AVAudioPlayer(contentsOf: editFolder.appendingPathComponent(take.fileName))
        seek(to: take.start, exact: true)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        player.play()
        isPlaying = true
        takePlayer?.play()
    }

    func keepTake(_ take: VoiceTake) {
        takePlayer?.stop()
        pause()
        let clip = EditVoiceClip(fileName: take.fileName, start: take.start, duration: take.duration)
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
        if FileManager.default.fileExists(atPath: cleanedSoundURL.path) {
            noise = .ready
            rebuild()
            return
        }
        noise = .working(0)
        let source = sourceURL
        let destination = cleanedSoundURL
        Task { @MainActor [weak self] in
            do {
                try await NoiseReducer.clean(source: source, to: destination) { fraction in
                    guard let self else { return }
                    if case .working = self.noise { self.noise = .working(fraction) }
                }
                self?.noise = .ready
                self?.rebuild()
            } catch {
                self?.noise = .failed
                self?.apply { $0.audio.reducesNoise = false }
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
        EditEstimate.bytes(recipe: recipe, picture: hasPicture ? pictureSize : nil, quality: quality)
    }

    var availableBytes: Int64 { availableBytesOverride ?? DiskSpace.available }

    func hasRoom(for quality: ExportQuality) -> Bool {
        availableBytes - estimatedBytes(quality) > 200_000_000
    }

    func setQuality(_ quality: ExportQuality) {
        guard quality != recipe.quality else { return }
        apply { $0.quality = quality }
        Haptics.selection()
    }

    func startExport() {
        pause()
        sheet = nil
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

/// File size of an edit before it is made: the encoder's usual rate for the picture size, plus sound.
enum EditEstimate {
    static func bytes(recipe: EditRecipe, picture: CGSize?, quality: ExportQuality) -> Int64 {
        let seconds = recipe.outputDuration
        var bitsPerSecond = 128_000.0
        if let picture {
            let size = recipe.renderSize(source: picture, quality: quality)
            bitsPerSecond += Double(size.width * size.height) * 30 * 0.13
        }
        return Int64(bitsPerSecond * seconds / 8)
    }
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
