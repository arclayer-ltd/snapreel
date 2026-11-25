import AVFoundation
import Foundation
import UIKit

/// Makes the copies other apps get when a recording's own file won't do: one with its two sounds
/// mixed, an MP4 instead of a QuickTime movie, or a smaller one. A copy that is being made is shared
/// by whoever asks for it, and a finished one is used again until it's cleaned up.
@MainActor
final class ShareCopies {
    static let shared = ShareCopies()
    nonisolated static let folderName = "Prepared"

    enum Kind: Equatable {
        /// The whole recording, its picture untouched, as an MP4.
        case complete(MoviePlan)
        case smaller(SmallerCopyPlan)

        var tag: String {
            switch self {
            case .complete: return "full"
            case .smaller: return "small"
            }
        }
    }

    private var jobs: [String: ShareCopyJob] = [:]

    /// The copy of `video`, finished, being made, or starting now.
    func job(for video: Video, source: URL, kind: Kind, root: URL) -> ShareCopyJob {
        let folder = Self.folder(root: root)
        let key = Self.key(for: video.id, source: source, tag: kind.tag)
        // One that was stopped and is still winding down is no use.
        if let running = jobs[key], !running.isStopped { return running }
        let target = folder.appendingPathComponent("\(key).mp4")
        removeOthers(in: folder, keeping: target.lastPathComponent)
        let job = ShareCopyJob(source: source, target: target, kind: kind)
        jobs[key] = job
        job.start { [weak self] in
            if self?.jobs[key] === job { self?.jobs[key] = nil }
        }
        return job
    }

    /// Whether there is room for a copy of `bytes`, with `times` such files for a moment (writing the
    /// index first writes the file twice).
    nonisolated static func hasRoom(for bytes: Int64, times: Int64 = 1) -> Bool {
        DiskSpace.available <= 0 || DiskSpace.hasRoom(for: bytes * times)
    }

    /// The index goes first only where the second writing is quick and fits easily.
    nonisolated static func putsIndexFirst(bytes: Int64) -> Bool {
        bytes < 400_000_000 && hasRoom(for: bytes, times: 3)
    }

    nonisolated static func folder(root: URL) -> URL {
        ShareFileLink.directory(root: root).appendingPathComponent(folderName, isDirectory: true)
    }

    /// Changes with the file, so a copy of an earlier version (before the sound was mixed) isn't used.
    /// Read through `FileManager`: a URL remembers its size and dates for a while.
    nonisolated static func key(for id: UUID, source: URL, tag: String) -> String {
        let attributes = try? FileManager.default.attributesOfItem(atPath: source.path)
        let modified = Int(((attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0) * 1_000)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let file = (attributes?[.systemFileNumber] as? NSNumber)?.int64Value ?? 0
        return "\(id.uuidString)-\(size)-\(file)-\(modified)-\(tag)"
    }

    /// Copies take real space, so there is only ever one finished one. Whoever still reads an older
    /// one has its own link to it.
    private func removeOthers(in folder: URL, keeping name: String) {
        let busy = Set(jobs.values.flatMap { [$0.target.lastPathComponent, $0.partial.lastPathComponent] })
        let fm = FileManager.default
        for item in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        where item.lastPathComponent != name && !busy.contains(item.lastPathComponent)
            && !ShareFilesInUse.contains(item.lastPathComponent) {
            try? fm.removeItem(at: item)
        }
    }
}

/// One copy being made.
@MainActor
final class ShareCopyJob: ObservableObject {
    /// 0...1.
    @Published private(set) var progress: Double = 0
    let target: URL
    let partial: URL
    /// The result, for threads that can't await (`ShareItemProvider`).
    nonisolated let outcome = ShareCopyOutcome()

    private let source: URL
    private let kind: ShareCopies.Kind
    private var control: MovieRewriteControl?
    private var task: Task<URL, Error>?

    init(source: URL, target: URL, kind: ShareCopies.Kind) {
        self.source = source
        self.target = target
        self.kind = kind
        partial = target.deletingLastPathComponent().appendingPathComponent("\(UUID().uuidString).partial.mp4")
    }

    /// The finished copy's file.
    func value() async throws -> URL {
        guard let task else { throw MovieRewriteError.failed }
        return try await task.value
    }

    func cancel() { control?.cancel() }

    var isStopped: Bool { control?.stopped != nil }

    fileprivate func start(onEnd: @escaping @MainActor () -> Void) {
        let control = MovieRewriteControl { [weak self] value in
            Task { @MainActor in self?.progress = value }
        }
        self.control = control
        ShareFilesInUse.add(partial.lastPathComponent)
        let background = BackgroundTime("Preparing a recording to share") { control.interrupt() }
        task = Task { @MainActor in
            defer {
                background.end()
                ShareFilesInUse.remove(partial.lastPathComponent)
                onEnd()
            }
            do {
                let url = try await make(control)
                outcome.set(.success(url))
                return url
            } catch {
                outcome.set(.failure(error))
                throw error
            }
        }
    }

    private func make(_ control: MovieRewriteControl) async throws -> URL {
        let fm = FileManager.default
        if fm.fileExists(atPath: target.path) {
            progress = 1
            return target
        }
        do {
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            switch kind {
            case .complete(let plan):
                let first = ShareCopies.putsIndexFirst(bytes: MediaInspector.fileSize(source))
                try await MovieRewrite.run(source, to: partial, plan: plan, fileType: .mp4, indexFirst: first,
                                           control: control)
            case .smaller(let plan):
                try await SmallerCopy.write(source, to: partial, plan: plan, control: control)
            }
            try fm.moveItem(at: partial, to: target)
            return target
        } catch {
            try? fm.removeItem(at: partial)
            let reason = MoviePump.explain(error, control: control)
            // Off screen, iOS can refuse the encoder with any of several errors.
            if reason == .failed, UIApplication.shared.applicationState == .background { throw MovieRewriteError.interrupted }
            throw reason
        }
    }
}

/// A result a background thread can wait for.
final class ShareCopyOutcome: @unchecked Sendable {
    private let condition = NSCondition()
    private var result: Result<URL, Error>?

    func set(_ value: Result<URL, Error>) {
        condition.lock()
        if result == nil { result = value }
        condition.broadcast()
        condition.unlock()
    }

    /// The finished copy, waiting for it at most `seconds`. Nil when it isn't there by then or failed.
    /// Never waits on the main thread, which the work needs.
    func url(waiting seconds: TimeInterval) -> URL? {
        condition.lock()
        defer { condition.unlock() }
        let limit = Date().addingTimeInterval(Thread.isMainThread ? 0 : seconds)
        while result == nil, Date() < limit {
            if !condition.wait(until: limit) { break }
        }
        guard case .success(let url)? = result else { return nil }
        return url
    }
}
