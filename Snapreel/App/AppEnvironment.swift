import SwiftUI
import UserNotifications

/// Owns the long-lived objects and picks the storage: on-device normally, fixtures when a
/// DEBUG build is launched with `-screen <id>` (see `DebugCatalog`).
@MainActor
final class AppEnvironment: ObservableObject {
    static let shared = AppEnvironment()

    let library: Library
    let settings: AppSettings
    let router: AppRouter
    /// The debug screen requested at launch, if any (DEBUG builds only).
    let debugScreenID: String?

    private init() {
        router = AppRouter()
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-screen"), index + 1 < arguments.count {
            let id = arguments[index + 1]
            let fixture = DebugCatalog.screen(id)?.fixture ?? .filled
            let defaults = UserDefaults(suiteName: "snapreel.debug.fixtures") ?? .standard
            defaults.removePersistentDomain(forName: "snapreel.debug.fixtures")
            let fixtureSettings = AppSettings(defaults: defaults)
            fixtureSettings.hasCompletedOnboarding = fixture != .fresh
            fixtureSettings.hasCompletedTour = fixture != .fresh
            let fixtureLibrary = Library(storage: FixtureStorage(set: fixture))
            Notifier.shared.configure(library: fixtureLibrary, settings: fixtureSettings, deliversSystemNotifications: false)
            settings = fixtureSettings
            library = fixtureLibrary
            debugScreenID = id
            return
        }
        if arguments.contains("-dumpScreens") {
            DebugCatalog.writeList()
        }
        #endif
        settings = AppSettings()
        debugScreenID = nil
        do {
            library = Library(storage: try OnDeviceStorage())
        } catch {
            // The container should always open; if it doesn't, keep the app usable in memory and
            // tell the person rather than crash.
            library = Library(storage: InMemoryStorage())
            library.lastError = error.localizedDescription
        }
        Notifier.shared.configure(library: library, settings: settings, deliversSystemNotifications: true)
    }
}

/// Fallback when the on-device database can't open. Same behaviour, nothing persisted.
final class InMemoryStorage: LibraryStorage {
    let mediaRoot: URL
    private var records: [String: [String: Data]] = [:]

    init(mediaRoot: URL = FileManager.default.temporaryDirectory.appendingPathComponent("SnapreelMemory", isDirectory: true)) {
        self.mediaRoot = mediaRoot
        try? FileManager.default.createDirectory(at: mediaRoot, withIntermediateDirectories: true)
    }

    func all<T: StoredRecord>(_ type: T.Type) throws -> [T] {
        (records[T.recordType] ?? [:]).values.compactMap { try? JSONDecoder.snapreel.decode(T.self, from: $0) }
    }

    func save<T: StoredRecord>(_ record: T) throws {
        records[T.recordType, default: [:]][record.recordID] = try JSONEncoder.snapreel.encode(record)
    }

    func delete<T: StoredRecord>(_ type: T.Type, id: String) throws {
        records[T.recordType]?[id] = nil
    }

    func eraseEverything() throws {
        records = [:]
        for item in (try? FileManager.default.contentsOfDirectory(at: mediaRoot, includingPropertiesForKeys: nil)) ?? [] {
            try? FileManager.default.removeItem(at: item)
        }
    }
}
