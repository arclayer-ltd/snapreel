import Foundation

/// A record type the storage layer can persist. Each is stored as JSON under (recordType, recordID).
protocol StoredRecord: Codable {
    static var recordType: String { get }
    var recordID: String { get }
}

extension Video: StoredRecord {
    static var recordType: String { "video" }
    var recordID: String { id.uuidString }
}

extension Folder: StoredRecord {
    static var recordType: String { "folder" }
    var recordID: String { id.uuidString }
}

extension VideoNote: StoredRecord {
    static var recordType: String { "note" }
    var recordID: String { id.uuidString }
}

extension VideoReaction: StoredRecord {
    static var recordType: String { "reaction" }
    var recordID: String { id.uuidString }
}

extension Transcript: StoredRecord {
    static var recordType: String { "transcript" }
    var recordID: String { videoID.uuidString }
}

extension AppNotification: StoredRecord {
    static var recordType: String { "notification" }
    var recordID: String { id.uuidString }
}

/// Where the library keeps its data. Two implementations:
/// - `OnDeviceStorage`: SQLite database plus media files in the App Group container (shipping).
/// - `FixtureStorage` (DEBUG only): in-memory sample data for screenshots and previews.
protocol LibraryStorage: AnyObject {
    /// Root folder for this storage's media; `MediaLocations` derives videos/ and thumbnails/.
    var mediaRoot: URL { get }
    func all<T: StoredRecord>(_ type: T.Type) throws -> [T]
    func save<T: StoredRecord>(_ record: T) throws
    func delete<T: StoredRecord>(_ type: T.Type, id: String) throws
    /// Erases every record and every media file.
    func eraseEverything() throws
}

/// Folders for media files under a storage's root.
struct MediaLocations {
    let root: URL

    var videos: URL { ensure(root.appendingPathComponent("Videos", isDirectory: true)) }
    var thumbnails: URL { ensure(root.appendingPathComponent("Thumbnails", isDirectory: true)) }
    /// Scratch space for recordings and imports while they are being written.
    var staging: URL { ensure(root.appendingPathComponent("Staging", isDirectory: true)) }

    func videoURL(_ fileName: String) -> URL { videos.appendingPathComponent(fileName) }
    func thumbnailURL(_ fileName: String) -> URL { thumbnails.appendingPathComponent(fileName) }

    private func ensure(_ url: URL) -> URL {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                     attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        }
        return url
    }
}
