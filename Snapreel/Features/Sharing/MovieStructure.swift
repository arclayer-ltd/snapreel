import Foundation

/// How a movie file is laid out, read from its box headers only (a few small reads, whatever the
/// file's size). Nil when the file isn't an MP4 or QuickTime movie.
struct MovieStructure: Equatable {
    /// "qt  " for QuickTime, "isom", "mp42"… for MP4.
    var brand: String
    /// Written in pieces that each have their own index (a recording that was cut off). Players that
    /// expect one index, and several apps, can't open it or see only its first seconds.
    var isFragmented: Bool
    /// The index comes before the pictures, so a web player can start before the whole file is there.
    var indexIsFirst: Bool
    /// The index is there and the last box ends where the file ends.
    var isComplete: Bool

    static func read(_ url: URL) -> MovieStructure? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd(), end >= 16 else { return nil }

        var brand = ""
        var fragmented = false
        var index: UInt64?
        var media: UInt64?
        var position: UInt64 = 0
        var known = false
        // An ordinary movie has a handful of boxes. A fragmented one shows itself in the first few,
        // so there is no need to walk thousands of pieces.
        for _ in 0..<64 {
            guard let box = box(at: position, end: end, handle) else { break }
            switch box.type {
            case "ftyp":
                known = true
                brand = string(at: box.body, count: 4, handle) ?? ""
            case "moov":
                known = true
                index = index ?? position
                if contains("mvex", from: box.body, to: min(box.next, end), handle) { fragmented = true }
            case "mdat":
                known = true
                media = media ?? position
            case "moof":
                known = true
                fragmented = true
            default:
                break
            }
            position = box.next
            if position >= end || (fragmented && index != nil) { break }
        }
        guard known else { return nil }
        let complete = index != nil && (fragmented || position == end)
        return MovieStructure(brand: brand, isFragmented: fragmented,
                              indexIsFirst: index.map { $0 < (media ?? .max) } ?? false, isComplete: complete)
    }

    // MARK: - Boxes

    private struct Box {
        var type: String
        var body: UInt64
        var next: UInt64
    }

    private static func box(at position: UInt64, end: UInt64, _ handle: FileHandle) -> Box? {
        guard position + 8 <= end, let header = bytes(at: position, count: 8, handle) else { return nil }
        var size = number(header, 0, 4)
        guard let type = String(bytes: header[4..<8], encoding: .isoLatin1) else { return nil }
        var headerSize: UInt64 = 8
        if size == 1 {
            guard let large = bytes(at: position + 8, count: 8, handle) else { return nil }
            size = number(large, 0, 8)
            headerSize = 16
        } else if size == 0 {
            size = end - position
        }
        guard size >= headerSize, size <= UInt64.max - position else { return nil }
        return Box(type: type, body: position + headerSize, next: position + size)
    }

    private static func contains(_ type: String, from start: UInt64, to end: UInt64, _ handle: FileHandle) -> Bool {
        var position = start
        for _ in 0..<64 {
            guard let box = box(at: position, end: end, handle) else { return false }
            if box.type == type { return true }
            position = box.next
        }
        return false
    }

    private static func string(at position: UInt64, count: Int, _ handle: FileHandle) -> String? {
        bytes(at: position, count: count, handle).flatMap { String(bytes: $0, encoding: .isoLatin1) }
    }

    private static func bytes(at position: UInt64, count: Int, _ handle: FileHandle) -> [UInt8]? {
        guard (try? handle.seek(toOffset: position)) != nil,
              let data = try? handle.read(upToCount: count), data.count == count else { return nil }
        return [UInt8](data)
    }

    private static func number(_ bytes: [UInt8], _ start: Int, _ count: Int) -> UInt64 {
        bytes[start..<(start + count)].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }
}
