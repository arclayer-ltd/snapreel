import Foundation
import UIKit

// The files other apps get: links with a readable name, and copies made for sharing. All of them
// live in "Sharing" in the media folder and are temporary.

// MARK: - Shared file names

/// Recordings are stored as "<id>.mp4". Before sharing, Snapreel makes a hard link named after
/// the title ("Checkout flow walkthrough.mp4"), so whoever receives it sees a real name. A hard
/// link takes no extra space and leaves the original untouched.
enum ShareFileLink {
    static func directory(root: URL) -> URL {
        root.appendingPathComponent("Sharing", isDirectory: true)
    }

    /// A link to `source` named after `title`. When a link can't be made, a copy (which iOS makes
    /// without using space where it can), and as a last resort `source` itself. Safe from any thread.
    static func prepare(_ source: URL, title: String, root: URL) -> URL {
        let fm = FileManager.default
        let folder = directory(root: root).appendingPathComponent(UUID().uuidString, isDirectory: true)
        let target = folder.appendingPathComponent(fileName(for: title, pathExtension: source.pathExtension))
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            ShareFilesInUse.add(folder.lastPathComponent)
            do {
                try fm.linkItem(at: source, to: target)
            } catch {
                guard DiskSpace.hasRoom(for: MediaInspector.fileSize(source)) else { throw error }
                try fm.copyItem(at: source, to: target)
            }
            return target
        } catch {
            ShareFilesInUse.remove(folder.lastPathComponent)
            try? fm.removeItem(at: folder)
            return source
        }
    }

    /// The share sheet that handed `url` over has gone. Whoever got the file may still be reading it
    /// (a large AirDrop, Mail Drop, a copy to iCloud Drive), so it stays until `cleanUp` finds it old.
    static func released(_ url: URL) {
        ShareFilesInUse.remove(url.deletingLastPathComponent().lastPathComponent)
    }

    /// Nothing was shared: the link goes now.
    static func discard(_ url: URL, root: URL) {
        released(url)
        let folder = url.deletingLastPathComponent()
        guard folder.deletingLastPathComponent().lastPathComponent == directory(root: root).lastPathComponent,
              UUID(uuidString: folder.lastPathComponent) != nil else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    /// "Bug: map pins jump on zoom" → "Bug map pins jump on zoom.mp4".
    static func fileName(for title: String, pathExtension: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
            .union(.newlines)
            .union(.controlCharacters)
        var name = title.components(separatedBy: invalid).joined(separator: " ")
        while name.contains("  ") { name = name.replacingOccurrences(of: "  ", with: " ") }
        name = name.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".")))
        if name.count > 80 { name = String(name.prefix(80)) }
        // A file name holds at most 255 bytes: 80 letters of some scripts and emoji are more.
        while name.utf8.count > 200 { name.removeLast() }
        name = name.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { name = "Snapreel recording" }
        return pathExtension.isEmpty ? name : "\(name).\(pathExtension)"
    }

    // MARK: Cleaning up

    /// How long a link is kept after it was made.
    enum Keep {
        /// The recording is still in the library, so the link takes no space: a day, which is longer
        /// than any transfer.
        static let linked: TimeInterval = 24 * 60 * 60
        /// The link is the only thing holding the file's space (the recording was deleted, or it is
        /// a copy made for sharing).
        static let alone: TimeInterval = 3 * 60 * 60
    }

    /// Whether a link that is `age` seconds old goes.
    static func isStale(age: TimeInterval, linkCount: Int, inUse: Bool, copyAge: TimeInterval) -> Bool {
        if inUse { return false }
        return age > (linkCount > 1 ? Keep.linked : max(copyAge, Keep.alone))
    }

    /// Removes what is left of shares that finished a while ago. Runs each time Snapreel comes to the
    /// foreground. Copies made for sharing go after `age` seconds (their links keep what is still
    /// being read).
    static func cleanUp(olderThan age: TimeInterval, root: URL, now: Date = Date()) {
        let fm = FileManager.default
        let folder = directory(root: root)
        let keys: [URLResourceKey] = [.creationDateKey, .contentModificationDateKey]
        guard let items = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) else { return }
        func ageOf(_ url: URL) -> TimeInterval {
            let values = try? url.resourceValues(forKeys: Set(keys))
            let dates = [values?.creationDate, values?.contentModificationDate].compactMap { $0 }
            return dates.max().map { now.timeIntervalSince($0) } ?? .greatestFiniteMagnitude
        }
        for item in items {
            if item.lastPathComponent == ShareCopies.folderName {
                for copy in (try? fm.contentsOfDirectory(at: item, includingPropertiesForKeys: keys)) ?? []
                where !ShareFilesInUse.contains(copy.lastPathComponent) && ageOf(copy) > age {
                    try? fm.removeItem(at: copy)
                }
                continue
            }
            let file = (try? fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil))?.first
            let links = file.flatMap { try? fm.attributesOfItem(atPath: $0.path)[.referenceCount] as? Int } ?? 1
            if isStale(age: ageOf(item), linkCount: links, inUse: ShareFilesInUse.contains(item.lastPathComponent),
                       copyAge: age) {
                try? fm.removeItem(at: item)
            }
        }
    }

    static func removeAll(root: URL) {
        try? FileManager.default.removeItem(at: directory(root: root))
    }
}

/// Links and copies a share sheet or a save is using right now (by folder or file name).
enum ShareFilesInUse {
    private static let lock = NSLock()
    private static var names = Set<String>()

    static func add(_ name: String) {
        lock.lock()
        names.insert(name)
        lock.unlock()
    }

    static func remove(_ name: String) {
        lock.lock()
        names.remove(name)
        lock.unlock()
    }

    static func contains(_ name: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return names.contains(name)
    }
}

// MARK: - Background time

/// A little longer to run after Snapreel leaves the screen. `onExpire` runs when iOS ends it.
@MainActor
final class BackgroundTime {
    private var task = UIBackgroundTaskIdentifier.invalid

    init(_ name: String, onExpire: @escaping @MainActor () -> Void) {
        task = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            // Called on the main thread; iOS suspends the app as soon as it returns, so this can't
            // wait for a new main-actor turn.
            MainActor.assumeIsolated {
                onExpire()
                self?.end()
            }
        }
    }

    func end() {
        guard task != .invalid else { return }
        UIApplication.shared.endBackgroundTask(task)
        task = .invalid
    }

    /// Returns once Snapreel is on screen again.
    static func waitUntilActive() async {
        while UIApplication.shared.applicationState != .active, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
    }
}
