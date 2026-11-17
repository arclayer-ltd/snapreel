import Foundation

/// Session E owns this file. Posts `.storageLow` (at most once a day) when free space is low.
@MainActor
enum StorageMonitor {
    static func check(library: Library) {}
}
