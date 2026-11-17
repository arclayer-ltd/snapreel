import SwiftUI

/// Session D. In-memory search over the library: recording titles, folder names, tags and the
/// words said (transcript lines). Case- and diacritic-insensitive. Nothing leaves the device.
@MainActor
enum LibrarySearch {
    struct FolderMatch: Identifiable {
        let folder: Folder
        let count: Int
        var id: UUID { folder.id }
    }

    struct TagMatch: Identifiable {
        let tag: String
        let count: Int
        var id: String { tag.lowercased() }
    }

    /// A transcript line that contains the query.
    struct SpokenMatch: Identifiable {
        let video: Video
        let segment: TranscriptSegment
        var id: String { "\(video.id.uuidString)-\(segment.id.uuidString)" }
    }

    struct Results {
        var videos: [Video] = []
        var folders: [FolderMatch] = []
        var tags: [TagMatch] = []
        var spoken: [SpokenMatch] = []

        var isEmpty: Bool { videos.isEmpty && folders.isEmpty && tags.isEmpty && spoken.isEmpty }
    }

    /// Lines shown per recording, and in total, in "Said in the video".
    static let spokenPerVideo = 3
    static let spokenTotal = 30

    /// Everything matching `query`. With `tag`, only recordings carrying that tag are searched
    /// (and an empty query lists all of them).
    static func run(query: String, tag: String?, in library: Library) -> Results {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var results = Results()
        let pool: [Video]
        if let tag {
            pool = library.allVideos.filter { video in
                video.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
            }
        } else {
            pool = library.allVideos
        }
        guard !trimmed.isEmpty else {
            results.videos = tag == nil ? [] : pool
            return results
        }
        results.videos = pool.filter { BrowseMatch.matches($0.title, trimmed) }
        if tag == nil {
            results.folders = library.sortedFolders
                .filter { BrowseMatch.matches($0.name, trimmed) }
                .map { FolderMatch(folder: $0, count: library.videos(inFolder: $0.id).count) }
            results.tags = tagCounts(in: library).filter { BrowseMatch.matches($0.tag, trimmed) }
        }
        results.spoken = spokenMatches(trimmed, in: pool, library: library)
        return results
    }

    /// Every tag in use with how many recordings carry it, alphabetical.
    static func tagCounts(in library: Library) -> [TagMatch] {
        var counts: [String: TagMatch] = [:]
        for video in library.allVideos {
            for tag in video.tags {
                let key = tag.lowercased()
                let current = counts[key]
                counts[key] = TagMatch(tag: current?.tag ?? tag, count: (current?.count ?? 0) + 1)
            }
        }
        return counts.values.sorted { $0.tag.localizedCaseInsensitiveCompare($1.tag) == .orderedAscending }
    }

    private static func spokenMatches(_ query: String, in videos: [Video], library: Library) -> [SpokenMatch] {
        var matches: [SpokenMatch] = []
        for video in videos {
            guard let transcript = library.transcript(for: video.id) else { continue }
            var found = 0
            for segment in transcript.segments where BrowseMatch.matches(segment.text, query) {
                matches.append(SpokenMatch(video: video, segment: segment))
                found += 1
                if found == spokenPerVideo || matches.count == spokenTotal { break }
            }
            if matches.count == spokenTotal { break }
        }
        return matches
    }
}

/// Searches you ran, newest first, kept on this iPhone (UserDefaults) and clearable.
@MainActor
final class RecentSearchStore: ObservableObject {
    static let shared = RecentSearchStore()

    @Published private(set) var items: [String]

    private let defaults: UserDefaults
    private let key = "search.recent"
    private let limit = 8

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.items = defaults.stringArray(forKey: "search.recent") ?? []
    }

    func add(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var updated = items.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        updated.insert(trimmed, at: 0)
        items = Array(updated.prefix(limit))
        save()
    }

    func remove(_ query: String) {
        items.removeAll { $0 == query }
        save()
    }

    /// Also call this when all data is deleted (Settings › Storage).
    func clear() {
        items = []
        save()
    }

    /// Replaces the list (used to set up screenshots in DEBUG).
    func replace(with queries: [String]) {
        items = Array(queries.prefix(limit))
        save()
    }

    private func save() {
        defaults.set(items, forKey: key)
    }
}
