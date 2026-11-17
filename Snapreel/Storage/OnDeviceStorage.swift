import Foundation

/// The shipping storage: a SQLite database and media files inside the App Group container,
/// protected by iOS Data Protection. Nothing leaves the device.
final class OnDeviceStorage: LibraryStorage {
    let mediaRoot: URL
    private let database: SQLiteDatabase
    private let encoder = JSONEncoder.snapreel
    private let decoder = JSONDecoder.snapreel

    init(container: URL = AppGroup.containerURL) throws {
        let fm = FileManager.default
        let databaseFolder = container.appendingPathComponent("Database", isDirectory: true)
        let media = container.appendingPathComponent("Media", isDirectory: true)
        for folder in [databaseFolder, media] where !fm.fileExists(atPath: folder.path) {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true,
                                   attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        }
        self.mediaRoot = media
        self.database = try SQLiteDatabase(url: databaseFolder.appendingPathComponent("snapreel.sqlite"))
    }

    func all<T: StoredRecord>(_ type: T.Type) throws -> [T] {
        try database.rows(type: T.recordType).compactMap { data in
            // A record that no longer decodes (older format) is skipped rather than failing the
            // whole library.
            try? decoder.decode(T.self, from: data)
        }
    }

    func save<T: StoredRecord>(_ record: T) throws {
        try database.upsert(type: T.recordType, id: record.recordID, json: encoder.encode(record))
    }

    func delete<T: StoredRecord>(_ type: T.Type, id: String) throws {
        try database.delete(type: T.recordType, id: id)
    }

    func eraseEverything() throws {
        try database.deleteAll()
        let fm = FileManager.default
        if fm.fileExists(atPath: mediaRoot.path) {
            for item in try fm.contentsOfDirectory(at: mediaRoot, includingPropertiesForKeys: nil) {
                try? fm.removeItem(at: item)
            }
        }
        for folder in [AppGroup.inboxURL, AppGroup.inProgressURL] {
            for item in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
                try? fm.removeItem(at: item)
            }
        }
    }
}
