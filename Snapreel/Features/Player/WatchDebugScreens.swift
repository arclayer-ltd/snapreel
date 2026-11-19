#if DEBUG
import SwiftUI

extension DebugCatalog {
    /// Session C owns this list: player and its states, notes, transcript, reactions, stats.
    /// Each opens the player exactly as the shell presents it, already in the named state.
    static var watchScreens: [DebugScreen] {
        let checkout = FixtureStorage.IDs.checkout
        let landscape = FixtureStorage.IDs.onboardingFeedback
        return [
            // Checkout is a portrait screen recording, so the video has its blurred poster; the
            // probe logs that touches under the video reach the details (debug-trace.txt).
            watchPlayer("video.player", "Player", checkout) { _ in
                watchState { $0.position = 4 }
            }.settling(.probeTouches),
            watchPlayer("video.fullscreen", "Fullscreen player", landscape) { _ in
                watchState {
                    $0.position = 3
                    $0.isFullscreen = true
                }
            },
            watchPlayer("video.pip", "Picture-in-picture state", checkout) { _ in
                watchState {
                    $0.position = 4
                    $0.showsPictureInPicturePlaceholder = true
                }
            },
            watchPlayer("video.speed", "Speed menu", checkout) { _ in
                watchState {
                    $0.position = 4
                    $0.overlay = .speed
                }
            },
            // A landscape video area is about 211 points tall, so the open speed menu reaches
            // below it over the details: its lowest rates must still draw on top and take the
            // touch (the probe's "middle" column should hit the menu, "right" the details).
            watchPlayer("video.speed.landscape", "Speed menu [landscape video]", landscape) { _ in
                watchState {
                    $0.position = 3
                    $0.overlay = .speed
                }
            }.settling(.probeTouches),
            watchPlayer("video.notes", "Notes tab", checkout) { _ in
                watchState {
                    $0.position = 4
                    $0.scrollsToPanel = true
                }
            },
            // The details and notes scroller (UIKit since build 25) scrolled to its very end.
            watchPlayer("video.notes.bottom", "Notes tab [scrolled to the end]", checkout) { _ in
                watchState { $0.position = 4 }
            }.settling(.scroll(1)),
            watchPlayer("video.notes.empty", "Notes tab [empty]", landscape) { _ in
                watchState { $0.scrollsToPanel = true }
            },
            watchPlayer("video.transcript", "Transcript tab", checkout) { _ in
                watchState {
                    $0.position = 4
                    $0.panel = .transcript
                    $0.scrollsToPanel = true
                }
            },
            watchPlayer("video.transcript.none", "Transcript tab [none available]", FixtureStorage.IDs.mapBug) { _ in
                watchState {
                    $0.panel = .transcript
                    $0.transcriptPhase = .unavailable(.noSpeech)
                    $0.scrollsToPanel = true
                }
            },
            watchPlayer("video.transcript.start", "Transcript tab [not started]", FixtureStorage.IDs.mitosis) { _ in
                watchState {
                    $0.panel = .transcript
                    $0.transcriptPhase = .notStarted
                    $0.scrollsToPanel = true
                }
            },
            watchPlayer("video.transcript.working", "Transcript tab [transcribing]", FixtureStorage.IDs.untitled) { _ in
                watchState {
                    $0.panel = .transcript
                    $0.transcriptPhase = .working
                    $0.scrollsToPanel = true
                }
            },
            watchPlayer("video.details", "Details and summary", checkout) { _ in
                watchState {
                    $0.position = 4
                    $0.showsDetails = true
                }
            },
            watchPreparedPlayer("video.details.summary", "Details and summary [with summary]", checkout,
                                prepare: { library in addSampleSummary(to: checkout, in: library) }) { _ in
                watchState {
                    $0.position = 4
                    $0.showsDetails = true
                }
            },
            watchPlayer("video.note.compose", "Note composer", checkout) { _ in
                watchState {
                    $0.position = 4
                    $0.sheet = .compose(time: 14)
                }
            },
            watchPlayer("video.note.edit", "Edit note", checkout) { library in
                let noteID = library.notes(for: checkout).first?.id
                return watchState {
                    $0.position = 4
                    $0.sheet = noteID.map { PlayerSheet.editNote($0) }
                }
            },
            watchPlayer("video.reaction", "Reaction overlay", checkout) { _ in
                watchState {
                    $0.position = 4
                    $0.overlay = .reactions
                    $0.pinnedBurst = "🔥"
                }
            },
            watchPreparedPlayer("video.note.compose.typed", "Note composer [typed]", checkout,
                                prepare: { _ in
                                    NoteComposerDebug.draft = "Apple Pay sits below the fold on smaller phones."
                                }) { _ in
                watchState {
                    $0.position = 14
                    $0.sheet = .compose(time: 14)
                }
            },
            watchPreparedPlayer("video.notes.added", "Notes tab [note just added]", checkout,
                                prepare: { library in
                                    _ = library.addNote(to: checkout, at: 14,
                                                        text: "Apple Pay sits below the fold on smaller phones.")
                                }) { _ in
                watchState {
                    $0.position = 14
                    $0.scrollsToPanel = true
                    $0.showsResumePill = true
                }
            },
            watchPreparedPlayer("video.reaction.sent", "Reaction overlay [sent]", checkout,
                                prepare: { library in _ = library.addReaction("🔥", to: checkout, at: 4) }) { _ in
                watchState {
                    $0.position = 4
                    $0.pinnedBurst = "🔥"
                }
            },
            watchPreparedPlayer("video.speed.changed", "Player [speed changed]", checkout,
                                prepare: { _ in AppEnvironment.shared.settings.playbackRate = 1.5 }) { _ in
                watchState { $0.position = 4 }
            },
            watchPlayer("video.photos.alert", "Save to Photos [system prompt]", checkout, wait: 4) { _ in
                watchState { $0.position = 4 }
            }.settling(.photosPrompt),
            watchPlayer("video.emoji", "Emoji picker", checkout) { _ in
                watchState {
                    $0.position = 4
                    $0.sheet = .emoji
                }
            },
            watchPlayer("video.actions", "Video actions", checkout) { _ in
                watchState {
                    $0.position = 4
                    $0.sheet = .actions(confirmingDelete: false)
                }
            },
            watchPlayer("video.actions.delete", "Video actions [delete]", checkout) { _ in
                watchState {
                    $0.position = 4
                    $0.sheet = .actions(confirmingDelete: true)
                }
            },
            watchPlayer("video.photos.permission", "Save to Photos [permission]", checkout, wait: 4) { _ in
                watchState {
                    $0.position = 4
                    $0.photosStage = .permission
                }
            },
            watchPlayer("video.photos.progress", "Save to Photos [progress]", checkout) { _ in
                watchState {
                    $0.position = 4
                    $0.photosStage = .saving
                }
            },
            watchPlayer("video.photos.saved", "Save to Photos [saved]", checkout) { _ in
                watchState {
                    $0.position = 4
                    $0.photosStage = .saved
                }
            },
            watchPlayer("video.stats", "Stats", checkout) { _ in
                watchState {
                    $0.position = 4
                    $0.sheet = .stats
                }
            },
            watchPlayer("video.audio", "Player [audio recording]", FixtureStorage.IDs.launchMemo) { _ in
                watchState {
                    $0.position = 4
                    $0.panel = .transcript
                }
            },
            watchPreparedPlayer("video.saving", "Player [still saving]", FixtureStorage.IDs.untitled,
                                prepare: { library in
                                    library.update(FixtureStorage.IDs.untitled) { $0.state = .saving(progress: 0.62) }
                                }) { _ in
                watchState { $0.autoplay = false }
            },
            .shell("video.mini", "Mini player", tab: .home) { router, _ in
                router.player = PlayerPresentation(videoID: checkout, startAt: 4, isMinimized: true)
            },
            // Build 23: the player follows a swipe down on the video and minimises; the tab
            // shell shows through above it.
            .shell("video.swipe", "Player [swiped down to minimise]", tab: .home) { router, _ in
                router.player = PlayerPresentation(videoID: checkout, startAt: 4)
            },
        ]
    }

    /// The player in `initial`'s state over a black host, with `router.player` set as the shell
    /// would set it.
    private static func watchPlayer(_ id: String, _ title: String, _ videoID: UUID, wait: Double = 3,
                                    initial: @escaping @MainActor (Library) -> PlayerInitialState) -> DebugScreen {
        watchPreparedPlayer(id, title, videoID, wait: wait, prepare: { _ in }, initial: initial)
    }

    /// Same, after `prepare` has adjusted the fixture library.
    private static func watchPreparedPlayer(_ id: String, _ title: String, _ videoID: UUID, wait: Double = 3,
                                            prepare: @escaping @MainActor (Library) -> Void,
                                            initial: @escaping @MainActor (Library) -> PlayerInitialState) -> DebugScreen {
        DebugScreen(id, title, fixture: .filled, wait: wait) {
            WatchDebugHost(videoID: videoID, prepare: prepare, initial: initial)
        }
    }

    /// Paused (so the controls stay up for the screenshot), then `change` applied.
    private static func watchState(_ change: (inout PlayerInitialState) -> Void) -> PlayerInitialState {
        var state = PlayerInitialState()
        state.autoplay = false
        change(&state)
        return state
    }

    /// Debug only: a summary like the on-device model writes, so the summary block can be
    /// screenshotted on a simulator without Apple Intelligence.
    @MainActor
    private static func addSampleSummary(to videoID: UUID, in library: Library) {
        guard var transcript = library.transcript(for: videoID) else { return }
        transcript.summary = "A walkthrough of the new checkout on the staging build. Removing a coupon doesn't update the total, which is a bug, while address autocomplete now feels quick. The open question is whether Apple Pay should come before the card form."
        library.saveTranscript(transcript)
    }
}

/// Hosts `PlayerScreen` for a debug id: prepares the fixture library, sets `router.player`,
/// then shows the player in the requested state.
struct WatchDebugHost: View {
    let videoID: UUID
    let prepare: @MainActor (Library) -> Void
    let initial: @MainActor (Library) -> PlayerInitialState

    @EnvironmentObject private var library: Library
    @EnvironmentObject private var router: AppRouter
    @State private var presentation: PlayerPresentation?
    @State private var state: PlayerInitialState?

    var body: some View {
        ZStack {
            Color.srStage.ignoresSafeArea()
            if let presentation, let state {
                PlayerScreen(presentation: presentation, initial: state)
            }
        }
        .onAppear {
            guard presentation == nil else { return }
            prepare(library)
            state = initial(library)
            let next = PlayerPresentation(videoID: videoID)
            router.player = next
            presentation = next
        }
    }
}
#endif
