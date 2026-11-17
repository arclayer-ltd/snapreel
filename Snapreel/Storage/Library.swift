import Foundation
import SwiftUI

/// The single source of truth for recordings, folders, notes, reactions, transcripts and the
/// notification feed. Views read it with `@EnvironmentObject var library: Library` and change
/// it only through these methods, which persist immediately.
@MainActor
final class Library: ObservableObject {
    @Published private(set) var videos: [Video] = []
    @Published private(set) var folders: [Folder] = []
    @Published private(set) var notes: [VideoNote] = []
    @Published private(set) var reactions: [VideoReaction] = []
    @Published private(set) var transcripts: [UUID: Transcript] = [:]
    @Published private(set) var notifications: [AppNotification] = []
    /// Last storage error in plain language, for a banner. Cleared by the view that shows it.
    @Published var lastError: String?

    let storage: LibraryStorage
    let media: MediaLocations

    init(storage: LibraryStorage) {
        self.storage = storage
        self.media = MediaLocations(root: storage.mediaRoot)
        reload()
    }

    func reload() {
        do {
            videos = try storage.all(Video.self)
            folders = try storage.all(Folder.self)
            notes = try storage.all(VideoNote.self)
            reactions = try storage.all(VideoReaction.self)
            let loadedTranscripts = try storage.all(Transcript.self)
            transcripts = Dictionary(loadedTranscripts.map { ($0.videoID, $0) }, uniquingKeysWith: { a, _ in a })
            notifications = try storage.all(AppNotification.self)
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Queries

    func video(_ id: UUID) -> Video? { videos.first { $0.id == id } }
    func folder(_ id: UUID) -> Folder? { folders.first { $0.id == id } }

    /// All videos, newest first.
    var allVideos: [Video] { videos.sorted { $0.createdAt > $1.createdAt } }

    /// Ready videos only (excludes ones still saving or failed), newest first.
    var readyVideos: [Video] { allVideos.filter { $0.state.isReady } }

    func videos(inFolder folderID: UUID?) -> [Video] {
        allVideos.filter { $0.folderID == folderID }
    }

    var sortedFolders: [Folder] { folders.sorted { $0.updatedAt > $1.updatedAt } }

    var watchLater: [Video] {
        videos.filter { $0.watchLaterAddedAt != nil }
            .sorted { ($0.watchLaterAddedAt ?? .distantPast) > ($1.watchLaterAddedAt ?? .distantPast) }
    }

    /// Videos watched at least once, most recent first.
    var history: [Video] {
        videos.filter { $0.lastWatchedAt != nil }
            .sorted { ($0.lastWatchedAt ?? .distantPast) > ($1.lastWatchedAt ?? .distantPast) }
    }

    func notes(for videoID: UUID) -> [VideoNote] {
        notes.filter { $0.videoID == videoID }.sorted { $0.time < $1.time }
    }

    func reactions(for videoID: UUID) -> [VideoReaction] {
        reactions.filter { $0.videoID == videoID }.sorted { $0.time < $1.time }
    }

    func transcript(for videoID: UUID) -> Transcript? { transcripts[videoID] }

    /// Feed newest first.
    var sortedNotifications: [AppNotification] { notifications.sorted { $0.createdAt > $1.createdAt } }
    var unreadNotificationCount: Int { notifications.filter { !$0.isRead }.count }

    /// Every tag in use, alphabetical.
    var allTags: [String] {
        Array(Set(videos.flatMap(\.tags))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func fileURL(for video: Video) -> URL { media.videoURL(video.fileName) }

    func thumbnailURL(for video: Video) -> URL? {
        video.thumbnailFileName.map { media.thumbnailURL($0) }
    }

    /// Bytes used by all recordings (sum of recorded file sizes).
    var totalVideoBytes: Int64 { videos.reduce(0) { $0 + $1.fileSize } }

    // MARK: - Videos

    func add(_ video: Video) {
        videos.removeAll { $0.id == video.id }
        videos.append(video)
        persist(video)
    }

    /// Change a video in place: `library.update(id) { $0.title = "New" }`.
    func update(_ id: UUID, _ change: (inout Video) -> Void) {
        guard let index = videos.firstIndex(where: { $0.id == id }) else { return }
        var video = videos[index]
        change(&video)
        videos[index] = video
        persist(video)
    }

    func rename(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        update(id) {
            $0.title = trimmed
            $0.needsTitle = false
        }
        // The recorder schedules a "still needs a title" reminder after each save.
        Notifier.shared.cancelScheduled(key: "needs-title-\(id.uuidString)")
    }

    /// Deletes the video, its files, notes, reactions, transcript and feed rows that point at it.
    func delete(_ id: UUID) {
        guard let video = self.video(id) else { return }
        let fm = FileManager.default
        try? fm.removeItem(at: fileURL(for: video))
        if let thumb = thumbnailURL(for: video) { try? fm.removeItem(at: thumb) }

        for note in notes where note.videoID == id { remove(VideoNote.self, id: note.recordID) }
        notes.removeAll { $0.videoID == id }
        for reaction in reactions where reaction.videoID == id { remove(VideoReaction.self, id: reaction.recordID) }
        reactions.removeAll { $0.videoID == id }
        if transcripts.removeValue(forKey: id) != nil { remove(Transcript.self, id: id.uuidString) }
        for item in notifications where item.videoID == id { remove(AppNotification.self, id: item.recordID) }
        notifications.removeAll { $0.videoID == id }

        videos.removeAll { $0.id == id }
        remove(Video.self, id: id.uuidString)
        Notifier.shared.cancelScheduled(key: "needs-title-\(id.uuidString)")
    }

    func toggleWatchLater(_ id: UUID) {
        update(id) { $0.watchLaterAddedAt = $0.watchLaterAddedAt == nil ? Date() : nil }
    }

    /// Call when playback starts from the beginning or after the video was closed.
    func recordPlayStarted(_ id: UUID) {
        update(id) {
            $0.playCount += 1
            $0.lastWatchedAt = Date()
        }
    }

    /// Call periodically while playing and when playback stops.
    func recordPlayback(_ id: UUID, position: Double) {
        update(id) { video in
            video.lastWatchedAt = Date()
            let duration = max(video.duration, 0.001)
            // Within the last 2 seconds counts as finished; resume from the start next time.
            let finished = position >= duration - 2
            video.resumePosition = finished ? 0 : max(0, position)
            video.furthestProgress = max(video.furthestProgress, min(1, finished ? 1 : position / duration))
        }
    }

    func recordShare(_ id: UUID) { update(id) { $0.shareCount += 1 } }
    func recordSavedToPhotos(_ id: UUID) { update(id) { $0.photosSaveCount += 1 } }

    func setTags(_ tags: [String], for id: UUID) {
        var seen = Set<String>()
        let cleaned = tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        update(id) { $0.tags = cleaned }
    }

    func move(_ id: UUID, toFolder folderID: UUID?) {
        update(id) { $0.folderID = folderID }
        if let folderID { touchFolder(folderID) }
    }

    // MARK: - Folders

    @discardableResult
    func createFolder(named name: String) -> Folder {
        let now = Date()
        let folder = Folder(name: name.trimmingCharacters(in: .whitespacesAndNewlines), createdAt: now, updatedAt: now)
        folders.append(folder)
        persist(folder)
        return folder
    }

    func renameFolder(_ id: UUID, to name: String) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        folders[index].updatedAt = Date()
        persist(folders[index])
    }

    /// Deletes the folder; its videos move back to "My videos" (they are not deleted).
    func deleteFolder(_ id: UUID) {
        for video in videos where video.folderID == id {
            update(video.id) { $0.folderID = nil }
        }
        folders.removeAll { $0.id == id }
        remove(Folder.self, id: id.uuidString)
    }

    private func touchFolder(_ id: UUID) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[index].updatedAt = Date()
        persist(folders[index])
    }

    // MARK: - Notes and reactions

    @discardableResult
    func addNote(to videoID: UUID, at time: Double, text: String) -> VideoNote {
        let now = Date()
        let note = VideoNote(videoID: videoID, time: max(0, time),
                             text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                             createdAt: now, updatedAt: now)
        notes.append(note)
        persist(note)
        return note
    }

    func updateNote(_ id: UUID, text: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        notes[index].updatedAt = Date()
        persist(notes[index])
    }

    func deleteNote(_ id: UUID) {
        notes.removeAll { $0.id == id }
        remove(VideoNote.self, id: id.uuidString)
    }

    @discardableResult
    func addReaction(_ emoji: String, to videoID: UUID, at time: Double) -> VideoReaction {
        let reaction = VideoReaction(videoID: videoID, time: max(0, time), emoji: emoji, createdAt: Date())
        reactions.append(reaction)
        persist(reaction)
        return reaction
    }

    func deleteReaction(_ id: UUID) {
        reactions.removeAll { $0.id == id }
        remove(VideoReaction.self, id: id.uuidString)
    }

    // MARK: - Transcripts

    func saveTranscript(_ transcript: Transcript) {
        transcripts[transcript.videoID] = transcript
        persist(transcript)
        update(transcript.videoID) { $0.transcriptStatus = .ready }
    }

    // MARK: - Notification feed (use `Notifier` to post; it also delivers the local notification)

    func appendNotification(_ item: AppNotification) {
        notifications.append(item)
        persist(item)
    }

    func markNotificationRead(_ id: UUID) {
        guard let index = notifications.firstIndex(where: { $0.id == id }), !notifications[index].isRead else { return }
        notifications[index].isRead = true
        persist(notifications[index])
    }

    func markAllNotificationsRead() {
        for index in notifications.indices where !notifications[index].isRead {
            notifications[index].isRead = true
            persist(notifications[index])
        }
    }

    func deleteNotification(_ id: UUID) {
        notifications.removeAll { $0.id == id }
        remove(AppNotification.self, id: id.uuidString)
    }

    // MARK: - Everything

    /// Settings › Storage › Delete all my data. Removes every recording, folder, note,
    /// reaction, transcript and feed row, and every file.
    func eraseEverything() {
        do {
            try storage.eraseEverything()
        } catch {
            lastError = error.localizedDescription
        }
        videos = []
        folders = []
        notes = []
        reactions = []
        transcripts = [:]
        notifications = []
        ThumbnailCache.shared.removeAll()
    }

    // MARK: - Persistence

    private func persist<T: StoredRecord>(_ record: T) {
        do {
            try storage.save(record)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func remove<T: StoredRecord>(_ type: T.Type, id: String) {
        do {
            try storage.delete(type, id: id)
        } catch {
            lastError = error.localizedDescription
        }
    }
}
