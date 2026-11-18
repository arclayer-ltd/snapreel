import AVFoundation
import Combine
import Foundation
import Speech

/// On-device transcription. Session B calls `enqueue` after a recording or import is saved;
/// the Transcript tab calls `requestTranscript` when the person asks for one. Jobs run one at a
/// time. Audio never leaves the iPhone: recognition runs only where the recogniser supports
/// on-device recognition, and otherwise the video is marked unavailable.
@MainActor
final class TranscriptService: ObservableObject {
    static let shared = TranscriptService()

    /// The video being transcribed right now.
    @Published private(set) var activeVideoID: UUID?
    /// Waiting their turn, oldest first.
    @Published private(set) var queuedIDs: [UUID] = []
    /// Progress of the active job, 0...1 (by finished pieces of audio).
    @Published private(set) var progress: Double = 0
    /// Videos whose summary is being written by the on-device model.
    @Published private(set) var summarizingIDs: Set<UUID> = []

    private var isRunning = false
    private var summaryAttempts = Set<UUID>()
    private var currentTask: SFSpeechRecognitionTask?
    private let defaults = UserDefaults.standard

    /// Recognition of a single request can stop after about a minute, so longer recordings are
    /// split into pieces of this length.
    nonisolated private static let pieceLength: Double = 50

    // MARK: - Asking for transcripts

    /// Automatic transcription after a recording or import is saved. Runs only when speech
    /// recognition is already allowed; it never shows the permission prompt.
    func enqueue(videoID: UUID, library: Library) {
        guard Permissions.currentState(.speech) == .granted else { return }
        add(videoID, library: library)
    }

    /// The person tapped "Make a transcript" or "Try again". Shows the speech permission prompt
    /// the first time.
    func requestTranscript(videoID: UUID, library: Library) async {
        var state = Permissions.currentState(.speech)
        if state == .notDetermined {
            state = await Permissions.request(.speech)
        }
        guard state == .granted else {
            markUnavailable(videoID, reason: .permissionDenied, library: library)
            return
        }
        add(videoID, library: library)
    }

    func isQueuedOrRunning(_ videoID: UUID) -> Bool {
        activeVideoID == videoID || queuedIDs.contains(videoID)
    }

    /// A transcript left "in progress" by an earlier launch (the app was closed mid-way) starts
    /// again when allowed, or goes back to "not started".
    func reconcile(videoID: UUID, library: Library) {
        guard let video = library.video(videoID), !isQueuedOrRunning(videoID) else { return }
        switch video.transcriptStatus {
        case .inProgress:
            if Permissions.currentState(.speech) == .granted {
                add(videoID, library: library)
            } else {
                library.update(videoID) { $0.transcriptStatus = .notStarted }
            }
        case .ready:
            if library.transcript(for: videoID) == nil {
                library.update(videoID) { $0.transcriptStatus = .notStarted }
            }
        case .notStarted, .unavailable:
            break
        }
    }

    /// Why the video has no transcript, for the Transcript tab's message.
    func unavailableReason(for videoID: UUID) -> TranscriptUnavailableReason {
        let permission = Permissions.currentState(.speech)
        if permission == .denied { return .permissionDenied }
        if let raw = defaults.string(forKey: Self.reasonKey(videoID)),
           let stored = TranscriptUnavailableReason(rawValue: raw) {
            // Permission was turned back on since: offer to try again.
            if stored == .permissionDenied { return .failed }
            return stored
        }
        return Self.makeRecognizer() == nil ? .languageUnsupported : .noSpeech
    }

    // MARK: - Summary

    /// Writes a short summary with Apple's on-device model, when this iPhone has it. Does
    /// nothing otherwise, and the player hides the summary block.
    func summarizeIfPossible(videoID: UUID, library: Library) {
        guard OnDeviceSummarizer.isAvailable,
              !summaryAttempts.contains(videoID),
              let transcript = library.transcript(for: videoID),
              transcript.summary == nil else { return }
        let lines = transcript.segments.map(\.text)
        let wordCount = lines.joined(separator: " ").split(separator: " ").count
        // A few words don't need a summary.
        guard wordCount >= 40 else { return }
        summaryAttempts.insert(videoID)
        summarizingIDs.insert(videoID)
        Task { @MainActor in
            let summary = await OnDeviceSummarizer.summary(of: lines)
            self.summarizingIDs.remove(videoID)
            guard let summary, var latest = library.transcript(for: videoID) else { return }
            latest.summary = summary
            library.saveTranscript(latest)
        }
    }

    // MARK: - Queue

    private func add(_ videoID: UUID, library: Library) {
        guard !isQueuedOrRunning(videoID),
              let video = library.video(videoID), video.state.isReady else { return }
        defaults.removeObject(forKey: Self.reasonKey(videoID))
        queuedIDs.append(videoID)
        library.update(videoID) { $0.transcriptStatus = .inProgress }
        runNext(library: library)
    }

    private func runNext(library: Library) {
        guard !isRunning else { return }
        guard !queuedIDs.isEmpty else { return }
        let videoID = queuedIDs.removeFirst()
        guard let video = library.video(videoID) else {
            runNext(library: library)
            return
        }
        isRunning = true
        activeVideoID = videoID
        progress = 0
        let url = library.fileURL(for: video)
        let duration = video.duration
        let scratch = library.media.staging
        Task { @MainActor in
            let outcome = await self.transcribe(url: url, duration: duration, scratch: scratch)
            self.finish(videoID, outcome: outcome, library: library)
            self.isRunning = false
            self.activeVideoID = nil
            self.progress = 0
            self.runNext(library: library)
        }
    }

    private func finish(_ videoID: UUID, outcome: TranscriptionOutcome, library: Library) {
        // Deleted while it was being transcribed.
        guard let video = library.video(videoID) else { return }
        switch outcome {
        case .success(let segments, let localeIdentifier):
            let transcript = Transcript(videoID: videoID, localeIdentifier: localeIdentifier,
                                        segments: segments, createdAt: Date(), summary: nil)
            library.saveTranscript(transcript)
            Notifier.shared.post(.transcriptReady, title: "Transcript ready",
                                 body: "\u{201C}\(video.title)\u{201D} can now be read and searched.",
                                 videoID: videoID)
            summarizeIfPossible(videoID: videoID, library: library)
        case .unavailable(let reason):
            markUnavailable(videoID, reason: reason, library: library)
        }
    }

    private func markUnavailable(_ videoID: UUID, reason: TranscriptUnavailableReason, library: Library) {
        defaults.set(reason.rawValue, forKey: Self.reasonKey(videoID))
        library.update(videoID) { $0.transcriptStatus = .unavailable }
    }

    private static func reasonKey(_ videoID: UUID) -> String {
        "player.transcriptUnavailable.\(videoID.uuidString)"
    }

    // MARK: - Recognition

    private enum TranscriptionOutcome {
        case success(segments: [TranscriptSegment], localeIdentifier: String)
        case unavailable(TranscriptUnavailableReason)
    }

    private struct Piece {
        var start: Double
        /// Nil means "to the end of the file".
        var length: Double?
    }

    private func transcribe(url: URL, duration: Double, scratch: URL) async -> TranscriptionOutcome {
        guard let recognizer = Self.makeRecognizer() else { return .unavailable(.languageUnsupported) }
        let asset = AVURLAsset(url: url)
        guard let audioTracks = try? await asset.loadTracks(withMediaType: .audio), !audioTracks.isEmpty else {
            return .unavailable(.noSpeech)
        }
        var total = duration
        if total <= 0, let loaded = try? await asset.load(.duration) {
            total = loaded.seconds.isFinite ? loaded.seconds : 0
        }
        let pieces = Self.pieces(total: total)
        var segments: [TranscriptSegment] = []
        var interrupted = false

        for (index, piece) in pieces.enumerated() {
            let pieceURL = scratch.appendingPathComponent("transcript-\(UUID().uuidString).m4a")
            do {
                try await Self.exportAudio(from: asset, piece: piece, to: pieceURL)
                let words = try await recognize(url: pieceURL, with: recognizer)
                segments += Self.lines(from: words, offset: piece.start)
            } catch RecognitionError.noSpeech {
                // Silence in this piece; carry on with the next.
            } catch {
                interrupted = true
            }
            try? FileManager.default.removeItem(at: pieceURL)
            progress = Double(index + 1) / Double(pieces.count)
        }

        if segments.isEmpty {
            return .unavailable(interrupted ? .failed : .noSpeech)
        }
        return .success(segments: segments, localeIdentifier: recognizer.locale.identifier)
    }

    private func recognize(url: URL, with recognizer: SFSpeechRecognizer) async throws -> [RecognizedWord] {
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        request.taskHint = .dictation
        let gate = ResumeGate()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[RecognizedWord], Error>) in
            currentTask = recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    let words = Self.words(from: result)
                    if gate.claim() { continuation.resume(returning: words) }
                } else if let error {
                    let mapped = Self.map(error)
                    if gate.claim() { continuation.resume(throwing: mapped) }
                }
            }
        }
    }

    /// The device language when this iPhone can recognise it on device, otherwise US English
    /// on device, otherwise nothing (Snapreel never sends audio away).
    nonisolated static func makeRecognizer() -> SFSpeechRecognizer? {
        for locale in [Locale.current, Locale(identifier: "en-US")] {
            if let recognizer = SFSpeechRecognizer(locale: locale), recognizer.supportsOnDeviceRecognition {
                return recognizer
            }
        }
        return nil
    }

    nonisolated private static func pieces(total: Double) -> [Piece] {
        guard total > pieceLength + 8 else { return [Piece(start: 0, length: nil)] }
        var result: [Piece] = []
        var start = 0.0
        while start < total {
            let remaining = total - start
            // Fold a short tail into the last piece rather than recognising a few seconds alone.
            if remaining <= pieceLength + 8 {
                result.append(Piece(start: start, length: remaining))
                break
            }
            result.append(Piece(start: start, length: pieceLength))
            start += pieceLength
        }
        return result
    }

    nonisolated private static func exportAudio(from asset: AVAsset, piece: Piece, to url: URL) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw RecognitionError.failed
        }
        session.outputURL = url
        session.outputFileType = .m4a
        if let length = piece.length {
            session.timeRange = CMTimeRange(start: CMTime(seconds: piece.start, preferredTimescale: 600),
                                            duration: CMTime(seconds: length, preferredTimescale: 600))
        }
        // The session is only read again inside its own completion handler.
        let box = ExportSessionBox(session: session)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            box.session.exportAsynchronously {
                if box.session.status == .completed {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: box.session.error ?? RecognitionError.failed)
                }
            }
        }
    }

    nonisolated private static func words(from result: SFSpeechRecognitionResult) -> [RecognizedWord] {
        let transcription = result.bestTranscription
        let formatted = transcription.formattedString as NSString
        return transcription.segments.map { segment in
            let range = segment.substringRange
            let text = (range.location != NSNotFound && NSMaxRange(range) <= formatted.length)
                ? formatted.substring(with: range) : segment.substring
            return RecognizedWord(text: text, start: segment.timestamp, duration: segment.duration,
                                  location: range.location, length: range.length, formatted: formatted)
        }
    }

    nonisolated private static func map(_ error: Error) -> RecognitionError {
        let code = (error as NSError).code
        // 1110: no speech detected; 203: nothing recognised.
        return (code == 1110 || code == 203) ? .noSpeech : .failed
    }

    /// Groups recognised words into sentence-sized lines with start times.
    nonisolated private static func lines(from words: [RecognizedWord], offset: Double) -> [TranscriptSegment] {
        var result: [TranscriptSegment] = []
        var current: [RecognizedWord] = []

        func flush() {
            guard let first = current.first, let last = current.last else { return }
            let text = lineText(first: first, last: last, words: current)
            let start = offset + first.start
            let end = offset + last.start + last.duration
            if !text.isEmpty {
                result.append(TranscriptSegment(start: start, duration: max(0.2, end - start), text: text))
            }
            current.removeAll()
        }

        for word in words {
            if let previous = current.last, current.count >= 3,
               word.start - (previous.start + previous.duration) > 1.2 {
                flush()
            }
            current.append(word)
            let endsSentence = word.text.last.map { ".?!\u{3002}\u{FF1F}\u{FF01}".contains($0) } ?? false
            if (endsSentence && current.count >= 4) || current.count >= 18 {
                flush()
            }
        }
        flush()
        return result
    }

    /// The line's text as the recogniser formatted it (keeps its spacing and punctuation).
    nonisolated private static func lineText(first: RecognizedWord, last: RecognizedWord, words: [RecognizedWord]) -> String {
        let formatted = first.formatted
        if first.location != NSNotFound, last.location != NSNotFound, last.location >= first.location {
            let length = last.location + last.length - first.location
            if length > 0, first.location + length <= formatted.length {
                return formatted.substring(with: NSRange(location: first.location, length: length))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return words.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// One recognised word with its time inside the piece of audio.
private struct RecognizedWord {
    var text: String
    var start: Double
    var duration: Double
    var location: Int
    var length: Int
    var formatted: NSString
}

private enum RecognitionError: Error {
    case noSpeech
    case failed
}

/// Makes sure a continuation is resumed once, whichever callback arrives first.
private final class ResumeGate {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}

/// Carries an export session into its own completion handler, the only other place it is read.
private struct ExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession
}
