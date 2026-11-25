import SwiftUI
import UIKit

/// One recording on its way to the share sheet. Says at once what it's doing (a card with real
/// progress and Cancel when there is something to wait for), then opens the sheet, and always ends:
/// whatever happens, the next tap on Share works.
@MainActor
final class ShareFlow: ObservableObject {
    enum Phase: Equatable {
        case idle
        /// Something is being waited for or made.
        case preparing
        /// The sheet is about to be presented.
        case opening
        case sheet
    }

    /// What the card says while something is prepared.
    struct Card: Equatable {
        enum Step: Equatable {
            case saving, sound, packing, shrinking

            var title: String {
                switch self {
                case .saving: return "Finishing the recording"
                case .sound: return "Finishing the sound"
                case .packing: return "Getting the video ready"
                case .shrinking: return "Making a smaller copy"
                }
            }
        }

        var video: Video
        var step: Step
        /// 0...1, or nil while there is nothing to measure yet.
        var progress: Double?
    }

    @Published private(set) var card: Card?
    @Published var toast: ToastMessage?
    private(set) var phase: Phase = .idle

    private let ports: ShareFlowPorts
    private var active: UUID?
    private var token = UUID()
    private var work: Task<Void, Never>?
    private var watcher: Task<Void, Never>?
    private var job: ShareCopyJob?
    private var sheet: ShareSheetHandle?
    private var openedAt = Date.distantPast
    private(set) var startedAt = Date.distantPast
    private var onEnd: (() -> Void)?
    private var keepsAwake = false

    /// Work shorter than this never shows its card.
    static let quiet: TimeInterval = 0.25
    /// A movie up to this size is also offered as an MP4, made while the share sheet is up.
    static let largestQuickCopy: Int64 = 600_000_000

    init(ports: ShareFlowPorts? = nil) {
        self.ports = ports ?? .live
    }

    /// True while a request for `id` is really in progress. A request that lost its sheet is not.
    func isBusy(with id: UUID) -> Bool {
        guard active == id else { return false }
        switch phase {
        case .idle: return false
        case .preparing: return true
        case .opening: return Date().timeIntervalSince(openedAt) < 8
        case .sheet: return sheet?.isOnScreen ?? false
        }
    }

    /// Starts sharing `video`. `onEnd` runs once, when it is over for whatever reason.
    func start(_ video: Video, library: Library, onEnd: @escaping () -> Void) {
        if isBusy(with: video.id) { return }
        abandon()
        self.onEnd = onEnd
        active = video.id
        startedAt = Date()
        phase = .preparing
        let mine = UUID()
        token = mine
        work = Task { @MainActor [weak self] in
            await self?.run(video, library: library, smaller: nil, token: mine)
        }
    }

    /// The person's Cancel on the card.
    func cancel() {
        guard phase == .preparing else { return }
        finish()
    }

    /// The screen it was started on has gone: nothing pops up later over another one.
    func screenDisappeared() {
        guard phase == .preparing else { return }
        finish()
    }

    /// Debug: shows a card and stays there.
    func freeze(_ frozen: Card) {
        card = frozen
        phase = .preparing
        active = frozen.video.id
    }

    // MARK: - Steps

    private func run(_ requested: Video, library: Library, smaller: SmallerCopyPlan?, token mine: UUID) async {
        do {
            let file = try await readyFile(requested, library: library, smaller: smaller, token: mine)
            guard token == mine else { return }
            open(file, library: library, token: mine)
        } catch {
            guard token == mine else { return }
            switch error {
            case ShareFlowProblem.notSaved: stop(saying: "This recording isn't saved, so there's nothing to share yet")
            case ShareFlowProblem.missing: stop(saying: "This recording's file is missing")
            case ShareFlowProblem.declined, MovieRewriteError.cancelled: finish()
            case MovieRewriteError.noSpace:
                await ports.tell("Not enough space",
                                 "There isn't room on this iPhone to make the copy. Free up some space, then try again.")
                if token == mine { finish() }
            case MovieRewriteError.interrupted:
                await ports.tell("Keep Snapreel open",
                                 "iOS only lets Snapreel do this while it's on screen. Try again and stay in Snapreel until it's done.")
                if token == mine { finish() }
            default:
                await ports.tell("Couldn't make the copy",
                                 "Something went wrong while preparing this recording. Share the full video instead, or try again.")
                if token == mine { finish() }
            }
        }
    }

    private struct ReadyFile {
        var video: Video
        /// The file to hand over, as it is.
        var source: URL
        /// An MP4 of it that is being made meanwhile.
        var copy: ShareCopyOutcome?
        var isSmaller = false
    }

    private func readyFile(_ requested: Video, library: Library, smaller: SmallerCopyPlan?, token mine: UUID) async throws -> ReadyFile {
        var video = library.video(requested.id) ?? requested
        if case .failed = video.state { throw ShareFlowProblem.notSaved }

        // Still being saved, or its two sounds are being made one: the finished file is shared.
        if ports.isFileChanging(video.id) {
            show(video, video.state.isReady ? .sound : .saving, token: mine) { [ports, weak library] in
                if case .saving(let progress)? = library?.video(video.id)?.state { return progress }
                return ports.fileProgress(video.id)
            }
            await ports.waitUntilFileSettled(video.id)
            guard token == mine else { throw MovieRewriteError.cancelled }
            guard let settled = library.video(video.id) else { throw ShareFlowProblem.missing }
            video = settled
        }
        guard video.state.isReady else { throw ShareFlowProblem.notSaved }
        let source = library.fileURL(for: video)
        guard FileManager.default.fileExists(atPath: source.path) else { throw ShareFlowProblem.missing }

        if let smaller {
            let url = try await copy(video, source: source, kind: .smaller(smaller), step: .shrinking,
                                     root: library.media.root, token: mine)
            return ReadyFile(video: video, source: url, isSmaller: true)
        }
        if video.isAudioOnly { return ReadyFile(video: video, source: source) }

        show(video, .packing, token: mine) { nil }
        let isScreen = video.kind == .screen
        // A file that can't be read is still handed over: someone may be able to repair it.
        let plan = try? await ports.plan(source, isScreen)
        guard token == mine else { throw MovieRewriteError.cancelled }
        guard let plan, plan.needsRewrite else {
            return ReadyFile(video: video, source: source, copy: quickCopy(video, source: source, plan: plan, library: library))
        }
        guard ShareCopies.hasRoom(for: video.fileSize) else {
            guard await ports.ask("Not enough space to finish the sound",
                                  "Without room for a finished copy, some apps may play only part of this recording's sound. Free up about \(Format.bytes(video.fileSize)) for all of it.",
                                  "Share anyway") else { throw ShareFlowProblem.declined }
            return ReadyFile(video: video, source: source)
        }
        do {
            let step: Card.Step = plan.reasons.contains(.twoSounds) ? .sound : .packing
            let url = try await copy(video, source: source, kind: .complete(plan), step: step,
                                     root: library.media.root, token: mine)
            return ReadyFile(video: video, source: url)
        } catch MovieRewriteError.failed, MovieRewriteError.unreadable {
            // The original is better than nothing.
            return ReadyFile(video: video, source: source)
        }
    }

    /// An MP4 of a QuickTime recording, for apps and people outside Apple's world, made in the
    /// background while the share sheet is up. Skipped when it would take long or much space.
    private func quickCopy(_ video: Video, source: URL, plan: MoviePlan?, library: Library) -> ShareCopyOutcome? {
        guard let plan, source.pathExtension.lowercased() == "mov", video.kind == .screen || video.kind == .camera,
              video.fileSize <= Self.largestQuickCopy, ShareCopies.hasRoom(for: video.fileSize, times: 4) else { return nil }
        let job = ports.copy(video, source, .complete(plan), library.media.root)
        self.job = job
        return job.outcome
    }

    /// Makes a copy with its progress on the card. Interrupted by leaving Snapreel, it starts again
    /// when the person is back, twice at most.
    private func copy(_ video: Video, source: URL, kind: ShareCopies.Kind, step: Card.Step, root: URL,
                      token mine: UUID) async throws -> URL {
        stayAwake(true)
        defer { stayAwake(false) }
        for attempt in 0... {
            let job = ports.copy(video, source, kind, root)
            self.job = job
            show(video, step, token: mine) { [weak job] in job?.progress }
            do {
                let url = try await job.value()
                guard token == mine else { throw MovieRewriteError.cancelled }
                return url
            } catch MovieRewriteError.interrupted {
                guard attempt < 2, token == mine else { throw MovieRewriteError.interrupted }
                await ports.waitUntilActive()
                guard token == mine else { throw MovieRewriteError.cancelled }
            }
        }
        throw MovieRewriteError.failed
    }

    private func open(_ file: ReadyFile, library: Library, token mine: UUID) {
        hideCard()
        phase = .opening
        openedAt = Date()
        let root = library.media.root
        let title = file.video.title
        let link = ShareFileLink.prepare(file.source, title: title, root: root)
        let id = file.video.id
        var shared = false
        let request = ShareSheetRequest(
            file: link, copy: file.copy, title: title, thumbnailURL: library.thumbnailURL(for: file.video),
            isAudio: file.video.isAudioOnly, root: root,
            smaller: file.isSmaller ? nil : SmallerCopyPlan.make(for: file.video),
            onShown: { [weak self] in
                guard let self, self.token == mine else { return }
                self.phase = .sheet
                #if DEBUG
                DebugTrace.log(String(format: "share: sheet shown %.2f s after the tap", Date().timeIntervalSince(self.startedAt)))
                #endif
            },
            onFailed: { [weak self] in
                ShareFileLink.discard(link, root: root)
                guard let self, self.token == mine else { return }
                self.stop(saying: "The share sheet didn't open. Try again")
            },
            onComplete: { [weak library] activity in
                shared = true
                // "Save Video" in the share sheet puts it in Photos; count it there, not as a share.
                if activity == .saveToCameraRoll {
                    library?.recordSavedToPhotos(id)
                } else {
                    library?.recordShare(id)
                }
                Haptics.success()
            },
            onClosed: { [weak self, weak library] wantsSmaller in
                if shared {
                    ShareFileLink.released(link)
                } else {
                    ShareFileLink.discard(link, root: root)
                }
                guard let self, self.token == mine else { return }
                if let wantsSmaller, let library {
                    self.startSmaller(file.video, plan: wantsSmaller, library: library)
                } else {
                    if !shared, file.copy != nil { self.job?.cancel() }
                    self.finish()
                }
            })
        sheet = ports.present(request)
    }

    /// "Smaller copy" was chosen in the share sheet: make it, then open the sheet again with it.
    private func startSmaller(_ video: Video, plan: SmallerCopyPlan, library: Library) {
        job?.cancel()
        job = nil
        sheet = nil
        guard ShareCopies.hasRoom(for: plan.estimatedBytes, times: 2) else {
            Task { @MainActor in
                await ports.tell("Not enough space",
                                 "A smaller copy needs about \(Format.bytes(plan.estimatedBytes * 2)) free while it's made. Free up some space, then try again.")
            }
            finish()
            return
        }
        phase = .preparing
        let mine = UUID()
        token = mine
        work = Task { @MainActor [weak self] in
            await self?.run(video, library: library, smaller: plan, token: mine)
        }
    }

    // MARK: - Card

    /// Puts up the card for `step`, unless it is over within a quarter of a second.
    private func show(_ video: Video, _ step: Card.Step, token mine: UUID, progress: @escaping @MainActor () -> Double?) {
        watcher?.cancel()
        let wasUp = card != nil
        if wasUp { card = Card(video: video, step: step, progress: progress()) }
        watcher = Task { @MainActor [weak self] in
            if !wasUp { try? await Task.sleep(nanoseconds: UInt64(Self.quiet * 1_000_000_000)) }
            var announced = wasUp
            while !Task.isCancelled {
                guard let self, self.token == mine, self.phase == .preparing else { return }
                let next = Card(video: video, step: step, progress: progress())
                if self.card != next { self.card = next }
                if !announced {
                    announced = true
                    UIAccessibility.post(notification: .announcement, argument: step.title)
                }
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
    }

    private func hideCard() {
        watcher?.cancel()
        watcher = nil
        if card != nil { card = nil }
    }

    /// The screen stays on while a copy is made: locking the phone would stop it.
    private func stayAwake(_ on: Bool) {
        if on {
            guard !keepsAwake, !UIApplication.shared.isIdleTimerDisabled else { return }
            keepsAwake = true
            UIApplication.shared.isIdleTimerDisabled = true
        } else if keepsAwake {
            keepsAwake = false
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    // MARK: - Ending

    private func stop(saying text: String) {
        Haptics.error()
        toast = ToastMessage(text: text, systemImage: "exclamationmark.circle.fill")
        finish()
    }

    /// Ends this request: nothing it still does has an effect, and the next one starts fresh.
    private func finish() {
        let ended = onEnd
        abandon()
        ended?()
    }

    private func abandon() {
        token = UUID()
        work?.cancel()
        work = nil
        // Stopping the copy is right whether it was cancelled or the sheet closed without using it;
        // a finished one stays for the next time.
        if phase == .preparing { job?.cancel() }
        job = nil
        sheet = nil
        hideCard()
        stayAwake(false)
        phase = .idle
        active = nil
        onEnd = nil
    }
}

enum ShareFlowProblem: Error, Equatable {
    /// Not saved yet, or saving failed.
    case notSaved
    case missing
    /// The person chose not to share.
    case declined
}

/// What `ShareFlow` needs from the rest of the app (replaced in tests).
@MainActor
struct ShareFlowPorts {
    var isFileChanging: (UUID) -> Bool
    var fileProgress: (UUID) -> Double?
    var waitUntilFileSettled: (UUID) async -> Void
    var plan: (URL, _ isScreen: Bool) async throws -> MoviePlan
    var copy: (Video, URL, ShareCopies.Kind, _ root: URL) -> ShareCopyJob
    var waitUntilActive: () async -> Void
    var present: (ShareSheetRequest) -> ShareSheetHandle
    /// An alert with OK.
    var tell: (_ title: String, _ message: String) async -> Void
    /// An alert with a choice; false is Cancel.
    var ask: (_ title: String, _ message: String, _ accept: String) async -> Bool

    static var live: ShareFlowPorts {
        ShareFlowPorts(
            isFileChanging: { RecordingSaver.shared.isFileChanging($0) },
            fileProgress: { RecordingSaver.shared.fileProgress($0) },
            waitUntilFileSettled: { await RecordingSaver.shared.waitUntilFileSettled($0) },
            plan: { try await MoviePlan.make(for: $0, isScreenRecording: $1) },
            copy: { ShareCopies.shared.job(for: $0, source: $1, kind: $2, root: $3) },
            waitUntilActive: { await BackgroundTime.waitUntilActive() },
            present: { ShareSheetPresenter.present($0) },
            tell: { _ = await ShareSheetPresenter.alert(title: $0, message: $1, accept: nil) },
            ask: { await ShareSheetPresenter.alert(title: $0, message: $1, accept: $2) })
    }
}

// MARK: - .shareVideo

/// `.shareVideo($video)`: presents the system share sheet with the recording's file.
@MainActor
struct ShareVideoModifier: ViewModifier {
    @Binding var video: Video?
    /// Debug: shows this step's card and stays there.
    var frozen: (step: ShareFlow.Card.Step, progress: Double?)?
    /// Space between the bottom edge of the view and the card.
    var bottomInset: CGFloat = Space.l

    @EnvironmentObject private var library: Library
    @StateObject private var flow = ShareFlow()

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                SharingCardOverlay(isPresented: flow.card != nil, bottomInset: bottomInset) {
                    if let card = flow.card {
                        SharingStatusCard(video: card.video, title: card.step.title,
                                          detail: SharingStatusCard.detail(progress: card.progress, of: card.video),
                                          progress: card.progress, showsBar: true,
                                          actionTitle: "Cancel", actionHint: "Stops preparing this recording",
                                          action: { flow.cancel() })
                    }
                }
            }
            .toast($flow.toast, bottomInset: Space.xl)
            .onAppear { startIfRequested() }
            .onChange(of: video?.id) { _ in startIfRequested() }
            .onDisappear { flow.screenDisappeared() }
    }

    private func startIfRequested() {
        guard let requested = video else { return }
        if let frozen {
            return flow.freeze(ShareFlow.Card(video: requested, step: frozen.step, progress: frozen.progress))
        }
        guard !flow.isBusy(with: requested.id) else { return }
        Haptics.tap()
        flow.start(requested, library: library, onEnd: { video = nil })
    }
}
