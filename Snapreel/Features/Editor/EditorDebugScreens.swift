#if DEBUG
import SwiftUI

extension DebugCatalog {
    /// The video editor: every screen and state in docs/plans/EDITOR-PLAN.md's Screens table.
    /// The editor runs "static" here: the recording's poster stands in for the player, and
    /// nothing plays, records or asks for the microphone.
    static var editorScreens: [DebugScreen] {
        entryScreens + homeScreens + cutScreens + pictureScreens + overlayScreens + soundScreens + saveScreens
    }

    private typealias IDs = FixtureStorage.IDs

    // MARK: - Entry

    private static var entryScreens: [DebugScreen] {
        [
            DebugScreen("edit.entry.player", "Editor entry [player actions]") {
                WatchDebugHost(videoID: IDs.checkout, prepare: { _ in }, initial: { _ in
                    var state = PlayerInitialState()
                    state.autoplay = false
                    state.position = 4
                    state.sheet = .actions(confirmingDelete: false)
                    return state
                })
            },
            .shell("edit.entry.library", "Editor entry [library actions]", tab: .library, configure: { _, _ in
                BrowseIntent.shared.libraryTab = .videos
                BrowseIntent.shared.librarySheet = .video(.actions(IDs.checkout))
            }),
            DebugScreen("edit.entry.review", "Editor entry [review after recording]") {
                RecordDebug.recorder(.screen) { $0.stage = .review(IDs.untitled) }
            },
            editor("edit.entry.audio", "Editor [voice recording, sound tools only]", video: IDs.launchMemo) { model, _ in
                model.seek(to: 22)
            },
        ]
    }

    // MARK: - Home and trim

    private static var homeScreens: [DebugScreen] {
        [
            editor("edit.home", "Editor [empty draft]") { model, _ in
                model.seek(to: 4)
            },
            editor("edit.home.coach", "Editor [first open, trim coach mark]", coach: true) { model, _ in
                model.seek(to: 2)
            },
            editor("edit.home.restored", "Editor [draft restored prompt]", prepare: { library in
                var recipe = EditRecipe.original(sourceID: IDs.checkout, duration: 125)
                recipe.remove(source: 40...56)
                recipe.texts = [EditText(text: "Coupon bug", start: 10, end: 14)]
                recipe.updatedAt = Date().addingTimeInterval(-2 * 3600)
                library.saveDraft(recipe)
            }) { model, _ in
                model.seek(to: 12)
            },
            editor("edit.home.edited", "Editor [sections, text, shapes, captions, voice]") { model, _ in
                richEdit(model)
                model.seek(to: 12)
            },
            editor("edit.trim", "Trim tool") { model, _ in
                model.open(.trim)
                model.seek(to: 30)
            },
            editor("edit.trim.dragging", "Trim tool [handle dragging]") { model, _ in
                model.open(.trim)
                model.seek(to: 100)
                if let last = model.recipe.segments.last {
                    model.beginTrim(.segment(last.id), edge: .end)
                    model.updateTrim(offset: -14.6)
                }
            },
            editor("edit.trim.selected", "Trim [part selected]") { model, _ in
                splitIntoParts(model)
                model.seek(to: 52)
                model.toggleSegment(atOutput: 52)
            },
            editor("edit.trim.delete", "Trim [delete confirm]") { model, _ in
                splitIntoParts(model)
                model.seek(to: 52)
                model.toggleSegment(atOutput: 52)
                model.confirmsSectionDelete = true
            },
        ]
    }

    // MARK: - Transcript and speed

    private static var cutScreens: [DebugScreen] {
        [
            editor("edit.transcript", "Cut by transcript") { model, _ in
                model.sheet = .transcript
            },
            editor("edit.transcript.struck", "Cut by transcript [sentences struck]") { model, library in
                if let transcript = library.transcript(for: IDs.checkout) {
                    model.toggleSentence(transcript.segments[3])
                    model.toggleSentence(transcript.segments[6])
                }
                model.sheet = .transcript
            },
            editor("edit.transcript.fillers", "Cut by transcript [filler word review]") { model, _ in
                EditorDebugState.opensFillerReview = true
                model.sheet = .transcript
            },
            editor("edit.transcript.none", "Cut by transcript [no transcript yet]", video: IDs.mitosis) { model, _ in
                model.sheet = .transcript
            },
            editor("edit.transcript.working", "Cut by transcript [transcribing]", video: IDs.mitosis) { model, _ in
                model.transcriptPhaseOverride = .working
                model.sheet = .transcript
            },
            editor("edit.speed", "Speed [whole video]") { model, _ in
                model.setSpeed(1.5, wholeVideo: true)
                model.sheet = .speed
            },
            editor("edit.speed.section", "Speed [one part]") { model, _ in
                splitIntoParts(model)
                model.seek(to: 52)
                model.toggleSegment(atOutput: 52)
                model.setSpeed(2, wholeVideo: false)
                model.sheet = .speed
            },
        ]
    }

    // MARK: - Picture

    private static var pictureScreens: [DebugScreen] {
        [
            editor("edit.crop", "Crop [free]") { model, _ in
                model.open(.crop)
                model.setAspect(.free)
                model.setDisplayCrop(CGRect(x: 0.08, y: 0.18, width: 0.84, height: 0.5), live: false)
            },
            editor("edit.crop.preset", "Crop [1:1 preset]") { model, _ in
                model.open(.crop)
                model.setAspect(.square)
            },
            editor("edit.crop.rotate", "Crop [rotated and flipped]") { model, _ in
                model.open(.crop)
                model.rotate()
                model.flip()
            },
            editor("edit.crop.result", "Editor [cropped to 4:5]") { model, _ in
                model.setAspect(.fourFive)
                model.seek(to: 6)
            },
            editor("edit.blur.drawing", "Blur [placing a box]") { model, _ in
                model.seek(to: 20)
                model.open(.blur)
                model.addBlur()
            },
            editor("edit.blur.timing", "Blur [timing on the track]") { model, _ in
                model.seek(to: 20)
                model.open(.blur)
                model.addBlur()
                if let blur = model.selectedBlur {
                    model.beginTrim(.blur(blur.id), edge: .end)
                    model.updateTrim(offset: 3)
                }
            },
            editor("edit.thumbnail", "Thumbnail [scrubbing]") { model, _ in
                model.open(.thumbnail)
                model.seek(to: 41)
            },
            editor("edit.thumbnail.chosen", "Thumbnail [chosen]") { model, _ in
                model.open(.thumbnail)
                model.seek(to: 41)
                model.chooseThumbnail()
            },
        ]
    }

    // MARK: - Text, shapes, captions

    private static var overlayScreens: [DebugScreen] {
        [
            editor("edit.text.keyboard", "Text [keyboard up]", wait: 4) { model, _ in
                model.seek(to: 14)
                model.open(.text)
                model.addText()
                model.textEntry?.text = "Total doesn't update"
            },
            editor("edit.text.style", "Text [style picker]") { model, _ in
                model.seek(to: 14)
                model.open(.text)
                model.addText()
                model.textEntry?.text = "Total doesn't update"
                model.textEntry?.color = .yellow
                model.textEntry?.center = CGPoint(x: 0.5, y: 0.3)
                model.commitTextEntry()
            },
            editor("edit.text.timing", "Text [timing handles on the track]") { model, _ in
                model.seek(to: 14)
                model.open(.text)
                model.addText()
                model.textEntry?.text = "Total doesn't update"
                model.commitTextEntry()
                if let text = model.selectedText {
                    model.beginTrim(.text(text.id), edge: .end)
                    model.updateTrim(offset: 2.4)
                }
            },
            editor("edit.sticker", "Shapes and emoji") { model, _ in
                model.seek(to: 33)
                model.open(.shapes)
            },
            editor("edit.sticker.emoji", "Shapes [emoji picker]") { model, _ in
                model.seek(to: 33)
                model.open(.shapes)
                model.sheet = .emoji
            },
            editor("edit.sticker.placing", "Shapes [arrow placed]") { model, _ in
                model.seek(to: 33)
                model.open(.shapes)
                model.addSticker(.arrow)
                if let id = model.selectedSticker?.id {
                    model.updateSticker(id) { $0.center = CGPoint(x: 0.42, y: 0.55) }
                }
            },
            editor("edit.captions.start", "Captions [add from transcript]") { model, _ in
                model.seek(to: 20)
                model.open(.captions)
            },
            editor("edit.captions", "Captions [style picker]") { model, _ in
                model.seek(to: 20)
                model.open(.captions)
                model.addCaptions()
                model.setCaptionStyle(.box)
            },
            editor("edit.captions.generating", "Captions [making the transcript]", video: IDs.mitosis) { model, _ in
                model.transcriptPhaseOverride = .working
                model.open(.captions)
            },
            editor("edit.captions.words", "Captions [editing words]") { model, _ in
                model.addCaptions()
                model.sheet = .captionWords
            },
            editor("edit.captions.nospeech", "Captions [no speech]", video: IDs.mapBug) { model, _ in
                model.transcriptPhaseOverride = .unavailable(.noSpeech)
                model.open(.captions)
            },
        ]
    }

    // MARK: - Sound

    private static var soundScreens: [DebugScreen] {
        [
            editor("edit.voice.primer", "Voice-over [microphone primer]") { model, _ in
                model.seek(to: 10)
                model.open(.voice)
                model.voice = .primer
            },
            editor("edit.voice.denied", "Voice-over [microphone off]") { model, _ in
                model.seek(to: 10)
                model.open(.voice)
                model.voice = .denied
            },
            editor("edit.voice.countdown", "Voice-over [countdown]") { model, _ in
                model.seek(to: 10)
                model.open(.voice)
                model.voice = .countdown(2)
            },
            editor("edit.voice.recording", "Voice-over [recording]") { model, _ in
                model.seek(to: 10)
                model.open(.voice)
                model.voice = .recording(start: 10)
                model.seek(to: 16.4)
                model.voiceLevel = 0.62
            },
            editor("edit.voice.review", "Voice-over [take review]") { model, _ in
                model.seek(to: 10)
                model.open(.voice)
                model.voice = .review(VoiceTake(fileName: "debug-take.m4a", start: 10, duration: 6.4))
            },
            editor("edit.audio", "Sound [volume, mute, fade]") { model, _ in
                model.apply { recipe in
                    recipe.voiceClips = [EditVoiceClip(fileName: "debug-voice.m4a", start: 8, duration: 9)]
                    recipe.audio.volume = 0.7
                    recipe.audio.fadeIn = true
                }
                model.open(.sound)
            },
            editor("edit.audio.noise", "Sound [noise reduction on]") { model, _ in
                model.apply { $0.audio.reducesNoise = true }
                model.open(.sound)
                model.noise = .ready
            },
            editor("edit.audio.cleaning", "Sound [cleaning up the sound]") { model, _ in
                model.apply { $0.audio.reducesNoise = true }
                model.open(.sound)
                model.noise = .working(0.42)
            },
        ]
    }

    // MARK: - Saving and leaving

    private static var saveScreens: [DebugScreen] {
        let output = UUID(uuidString: "33333333-0000-4000-8000-000000000001")!
        return [
            editor("edit.export", "Export [quality and size]") { model, _ in
                model.remove(sentence: 3)
                model.sheet = .export
            },
            editor("edit.export.nospace", "Export [not enough space]") { model, _ in
                model.remove(sentence: 3)
                model.availableBytesOverride = 150_000_000
                model.sheet = .export
            },
            editor("edit.rendering", "Saving [progress]", prepare: { library in
                addOutput(output, state: .saving(progress: 0.46), to: library)
            }) { model, _ in
                model.remove(sentence: 3)
                model.phase = .rendering(output)
            },
            editor("edit.rendering.failed", "Saving [failed, try again]", prepare: { library in
                addOutput(output, state: .failed(reason: EditRenderError.interrupted.message, outOfSpace: false), to: library)
            }) { model, _ in
                model.phase = .rendering(output)
            },
            editor("edit.rendering.cancelled", "Saving [cancelled]") { model, _ in
                model.phase = .cancelled
            },
            editor("edit.rendering.done", "Saving [saved as a new recording]", prepare: { library in
                addOutput(output, state: .ready, to: library)
            }) { model, _ in
                model.remove(sentence: 3)
                model.phase = .rendering(output)
            },
            editor("edit.discard", "Leave the editor [keep draft or discard]") { model, _ in
                model.remove(sentence: 3)
                model.sheet = .discard
            },
            .shell("edit.library.badge", "Library [edited copy with its badge]", tab: .library, configure: { _, library in
                addOutput(output, state: .ready, to: library)
                BrowseIntent.shared.libraryTab = .videos
            }),
            DebugScreen("edit.original", "Player [edited copy, link to the original]") {
                WatchDebugHost(videoID: output, prepare: { library in addOutput(output, state: .ready, to: library) },
                               initial: { _ in
                                   var state = PlayerInitialState()
                                   state.autoplay = false
                                   state.position = 3
                                   state.showsDetails = true
                                   return state
                               })
            },
        ]
    }

    // MARK: - Helpers

    /// The editor on `video` (checkout walkthrough by default), with filler words in its
    /// transcript, after `prepare` adjusted the library and `configure` the editor.
    private static func editor(_ id: String, _ title: String, video: UUID = IDs.checkout, wait: Double = 3,
                               coach: Bool = false,
                               prepare: @escaping @MainActor (Library) -> Void = { _ in },
                               configure: @escaping @MainActor (EditorModel, Library) -> Void) -> DebugScreen {
        DebugScreen(id, title, fixture: .filled, wait: wait) {
            EditorDebugHost(videoID: video, coach: coach, prepare: prepare, configure: configure)
        }
    }

    /// Three parts: 0–40, 40–64, 64–end.
    @MainActor
    private static func splitIntoParts(_ model: EditorModel) {
        model.seek(to: 40)
        model.splitAtPlayhead()
        model.seek(to: 64)
        model.splitAtPlayhead()
        model.selection = nil
    }

    @MainActor
    private static func richEdit(_ model: EditorModel) {
        splitIntoParts(model)
        model.apply { recipe in
            recipe.texts = [EditText(text: "Coupon bug", style: .box, color: .yellow,
                                     center: CGPoint(x: 0.5, y: 0.22), start: 9, end: 16)]
            recipe.stickers = [EditSticker(kind: .arrow, color: .red, center: CGPoint(x: 0.36, y: 0.52),
                                           rotation: -35, start: 11, end: 18),
                               EditSticker(kind: .emoji, emoji: "🔥", center: CGPoint(x: 0.72, y: 0.66),
                                           start: 30, end: 36)]
            recipe.captions = EditCaptions(style: .box)
            recipe.voiceClips = [EditVoiceClip(fileName: "debug-voice.m4a", start: 20, duration: 12)]
        }
        model.selection = nil
    }

    /// An edited copy of the checkout walkthrough in the library.
    @MainActor
    static func addOutput(_ id: UUID, state: VideoState, to library: Library) {
        guard let source = library.video(IDs.checkout) else { return }
        var video = source
        video.id = id
        video.title = "Checkout flow walkthrough (edited)"
        video.createdAt = Date().addingTimeInterval(-60)
        video.duration = 98
        video.fileSize = state.isReady ? 46_200_000 : 0
        video.editedFrom = source.id
        video.state = state
        video.playCount = 0
        video.lastWatchedAt = nil
        video.watchLaterAddedAt = nil
        video.furthestProgress = 0
        video.shareCount = 0
        video.photosSaveCount = 0
        library.add(video)
    }
}

extension EditorModel {
    /// Debug: cuts transcript sentence `index`.
    func remove(sentence index: Int) {
        guard let transcript, transcript.segments.indices.contains(index) else { return }
        toggleSentence(transcript.segments[index])
    }
}

/// The editor for a debug screen, built once with the fixture library.
struct EditorDebugHost: View {
    @StateObject private var model: EditorModel

    init(videoID: UUID, coach: Bool, prepare: @MainActor (Library) -> Void,
         configure: @MainActor (EditorModel, Library) -> Void) {
        let library = AppEnvironment.shared.library
        EditorDebugFixtures.addFillerTranscript(to: library)
        prepare(library)
        let model = EditorModel(videoID: videoID, library: library, isStatic: true)
        model.showsTrimCoach = coach
        model.pointsPerSecond = EditorModel.defaultPointsPerSecond(duration: model.duration)
        configure(model, library)
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        EditorView(model: model, onClose: {}, onOpen: { _ in })
    }
}

enum EditorDebugFixtures {
    /// The checkout walkthrough's transcript with ums and uhs, and word times.
    @MainActor
    static func addFillerTranscript(to library: Library) {
        let lines = [
            "Okay, um, this is the new checkout on the staging build.",
            "I'm adding two items to the basket and, uh, going straight to checkout.",
            "Here's the coupon field. I'll apply the welcome code.",
            "If I remove it again, watch the total. It doesn't change, so that's a bug.",
            "Address autocomplete is, like, really quick now, nice work on that.",
            "Payment comes next. Um, Apple Pay sits under the card form at the moment.",
            "I think it should be first, you know, but let's ask Sam.",
            "Last step is the summary. Uh, everything else looks good to ship.",
        ]
        let step = 125.0 / Double(lines.count)
        let segments = lines.enumerated().map { index, text -> TranscriptSegment in
            var segment = TranscriptSegment(start: Double(index) * step + 0.4, duration: step - 1.2, text: text)
            segment.words = EditFillerFinder.estimatedWords(segment)
            return segment
        }
        library.saveTranscript(Transcript(videoID: FixtureStorage.IDs.checkout, localeIdentifier: "en-GB",
                                          segments: segments, createdAt: Date().addingTimeInterval(-7200), summary: nil))
    }
}
#endif
