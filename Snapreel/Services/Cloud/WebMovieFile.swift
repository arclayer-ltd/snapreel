import CoreMedia
import Foundation

/// Writes an MP4 from samples that are already compressed, so that:
/// - the file is laid out for streaming (its index, `moov`, comes before the media) without a second pass or a
///   second copy on a phone that may be nearly full: room for the index is reserved at the start and filled last;
/// - every byte after that room is final the moment it is committed, so it can be sent while the rest is still
///   being encoded;
/// - preparing can stop at any commit and carry on later, also after Snapreel was closed.
///
/// One video track and at most one audio track. Frame times are kept as they are (screen recordings have an uneven
/// frame rate), and each track keeps its own length (the sound may end before the picture).
final class WebMovieFile {
    enum Failure: Error {
        /// The index needs more room than was reserved.
        case indexTooLarge
        case damaged
    }

    struct Sample {
        var isVideo: Bool
        var isSync: Bool
        /// In the track's own time scale, counted from the start of the movie (the first video frame).
        var dts: Int64
        var pts: Int64
        var data: Data
    }

    struct Record: Equatable {
        var isVideo: Bool
        var isSync: Bool
        var size: UInt32
        var dts: Int64
        var pts: Int64

        static let byteCount = 24
    }

    /// What the index says about a track, besides its samples.
    struct Track {
        var timescale: Int32
        /// The sample entry (`avc1…`, `mp4a…`), as Core Media writes it.
        var entry: Data
        /// Video only: the size before `transform`, and the turn to show it upright.
        var width: Double = 0
        var height: Double = 0
        var transform = CGAffineTransform.identity
        /// Where the track's media starts in the movie, in seconds (negative: it starts before the first frame).
        var start: Double = 0
        /// Audio only: encoder delay at the start that must not be heard, in the track's time scale.
        var trim: Int64 = 0
        /// Where the last sample ends, in the track's time scale (0: guess from the sample before).
        var end: Int64 = 0
    }

    let url: URL
    private let tablesURL: URL
    /// The first media byte's place: the reserved room plus the media box's own header.
    let headerEnd: Int64
    private(set) var records: [Record] = []
    private(set) var committedRecords = 0
    private(set) var length: Int64
    private var handle: FileHandle
    private var tables: FileHandle
    private var buffer = Data()

    static let videoTimescale: Int32 = 90_000
    private static let mediaHeader: Int64 = 16

    /// Room for the index of `duration` seconds: worst case for 4-byte sizes, uneven durations and offsets.
    static func reserve(duration: Double, frameRate: Double) -> Int64 {
        let seconds = max(1, duration) + 5
        let frames = seconds * max(30, frameRate) * 1.15
        let audio = seconds * 48
        let chunks = seconds * 6
        let bytes = frames * 22 + audio * 6 + chunks * 18 + 8_192
        return (Int64(bytes) / 4_096 + 1) * 4_096
    }

    /// Opens the file: new, or as it was after `records` committed samples.
    init(url: URL, tablesURL: URL, reserve: Int64, resume: (records: Int, length: Int64)? = nil) throws {
        self.url = url
        self.tablesURL = tablesURL
        headerEnd = reserve
        let manager = FileManager.default
        if let resume, resume.records > 0,
           let saved = try? Data(contentsOf: tablesURL), saved.count >= resume.records * Record.byteCount,
           MediaInspector.fileSize(url) >= resume.length {
            records = Self.decode(saved, count: resume.records)
            committedRecords = resume.records
            length = resume.length
            let total = records.reduce(reserve) { $0 + Int64($1.size) }
            guard total == resume.length else { throw Failure.damaged }
            handle = try FileHandle(forUpdating: url)
            tables = try FileHandle(forUpdating: tablesURL)
            try handle.truncate(atOffset: UInt64(resume.length))
            try tables.truncate(atOffset: UInt64(resume.records * Record.byteCount))
        } else {
            for file in [url, tablesURL] {
                try? manager.removeItem(at: file)
                guard manager.createFile(atPath: file.path, contents: nil,
                                         attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]) else {
                    throw CocoaError(.fileWriteUnknown)
                }
            }
            handle = try FileHandle(forUpdating: url)
            tables = try FileHandle(forUpdating: tablesURL)
            length = reserve
            try handle.truncate(atOffset: UInt64(reserve))
        }
        try handle.seek(toOffset: UInt64(length))
        try tables.seek(toOffset: UInt64(committedRecords * Record.byteCount))
    }

    deinit {
        try? handle.close()
        try? tables.close()
    }

    func append(_ sample: Sample) throws {
        guard !sample.data.isEmpty else { return }
        buffer.append(sample.data)
        records.append(Record(isVideo: sample.isVideo, isSync: sample.isSync, size: UInt32(sample.data.count),
                              dts: sample.dts, pts: sample.pts))
        length += Int64(sample.data.count)
        if buffer.count > 1_048_576 { try flush() }
    }

    private func flush() throws {
        guard !buffer.isEmpty else { return }
        try handle.write(contentsOf: buffer)
        buffer.removeAll(keepingCapacity: true)
    }

    /// Everything appended so far is on disk for good.
    func commit() throws {
        try flush()
        if committedRecords < records.count {
            try tables.write(contentsOf: Self.encode(records[committedRecords...]))
            committedRecords = records.count
        }
        try handle.synchronize()
        try tables.synchronize()
    }

    /// Writes the index into the reserved room. The file is complete after this.
    func finish(video: Track, audio: Track?) throws {
        try commit()
        var header = Self.fileType()
        let movie = Self.movieBox(records: records, mediaStart: headerEnd, video: video, audio: audio)
        header.append(movie)
        let room = headerEnd - Self.mediaHeader - Int64(header.count)
        guard room == 0 || room >= 8 else { throw Failure.indexTooLarge }
        if room >= 8 {
            header.u32(UInt32(room))
            header.ascii("free")
            header.append(Data(count: Int(room) - 8))
        }
        // The media box, with a 64-bit length.
        header.u32(1)
        header.ascii("mdat")
        header.u64(UInt64(length - headerEnd + Self.mediaHeader))
        guard Int64(header.count) == headerEnd else { throw Failure.indexTooLarge }
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: header)
        try handle.synchronize()
        try handle.seek(toOffset: UInt64(length))
    }

    // MARK: - Journal

    private static func encode(_ records: ArraySlice<Record>) -> Data {
        var data = Data(capacity: records.count * Record.byteCount)
        for record in records {
            data.append(record.isVideo ? 1 : 0)
            data.append(record.isSync ? 1 : 0)
            data.u16(0)
            data.u32(record.size)
            data.u64(UInt64(bitPattern: record.dts))
            data.u64(UInt64(bitPattern: record.pts))
        }
        return data
    }

    private static func decode(_ data: Data, count: Int) -> [Record] {
        let bytes = [UInt8](data.prefix(count * Record.byteCount))
        func number(_ at: Int, _ length: Int) -> UInt64 {
            var value: UInt64 = 0
            for index in at..<(at + length) { value = value << 8 | UInt64(bytes[index]) }
            return value
        }
        return (0..<count).map { index in
            let at = index * Record.byteCount
            return Record(isVideo: bytes[at] == 1, isSync: bytes[at + 1] == 1, size: UInt32(number(at + 4, 4)),
                          dts: Int64(bitPattern: number(at + 8, 8)), pts: Int64(bitPattern: number(at + 16, 8)))
        }
    }

    // MARK: - The index

    private static let movieTimescale: UInt32 = 90_000

    private static func fileType() -> Data {
        var payload = Data()
        payload.ascii("isom")
        payload.u32(512)
        for brand in ["isom", "iso2", "avc1", "mp41", "mp42"] { payload.ascii(brand) }
        return box("ftyp", payload)
    }

    /// `moov` for these samples, whose data lies one after another from `mediaStart`.
    static func movieBox(records: [Record], mediaStart: Int64, video: Track, audio: Track?) -> Data {
        let videoTable = SampleTable(records: records, mediaStart: mediaStart, isVideo: true, track: video)
        let audioTable = audio.map { SampleTable(records: records, mediaStart: mediaStart, isVideo: false, track: $0) }
        var tracks: [Data] = []
        var duration: UInt64 = 0
        if !videoTable.isEmpty {
            let edits = videoEdits(video, videoTable)
            duration = max(duration, edits.duration)
            tracks.append(trackBox(id: 1, track: video, table: videoTable, edits: edits, isVideo: true))
        }
        if let audio, let audioTable, !audioTable.isEmpty {
            let edits = audioEdits(audio, audioTable)
            duration = max(duration, edits.duration)
            tracks.append(trackBox(id: 2, track: audio, table: audioTable, edits: edits, isVideo: false))
        }
        var header = Data()
        header.u32(1 << 24)                       // version 1
        header.u64(0)
        header.u64(0)
        header.u32(movieTimescale)
        header.u64(duration)
        header.u32(0x0001_0000)                   // rate 1.0
        header.u16(0x0100)                        // volume 1.0
        header.append(Data(count: 10))
        header.matrix(.identity)
        header.append(Data(count: 24))
        header.u32(UInt32(tracks.count + 1))
        return box("moov", tracks.reduce(box("mvhd", header)) { $0 + $1 })
    }

    private struct Edits {
        /// In the movie's time scale; media time -1 is an empty stretch.
        var entries: [(duration: UInt64, mediaTime: Int64)]
        var duration: UInt64
    }

    private static func ticks(_ seconds: Double) -> UInt64 {
        UInt64(max(0, (seconds * Double(movieTimescale)).rounded()))
    }

    /// The picture starts with its first shown frame (reordered frames put that a little after the first decoded one).
    private static func videoEdits(_ track: Track, _ table: SampleTable) -> Edits {
        let shown = Double(table.duration) / Double(track.timescale)
        var entries: [(UInt64, Int64)] = []
        if table.firstShown > 0 { entries.append((ticks(shown), table.firstShown)) }
        return Edits(entries: entries, duration: ticks(shown))
    }

    /// The sound: an empty stretch when it starts after the picture, and without the encoder's delay.
    private static func audioEdits(_ track: Track, _ table: SampleTable) -> Edits {
        let scale = Double(track.timescale)
        var mediaTime = track.trim
        var begins = track.start + Double(track.trim) / scale
        if begins < 0 {
            mediaTime += Int64((-begins * scale).rounded())
            begins = 0
        }
        let heard = max(0, Double(table.duration - mediaTime)) / scale
        var entries: [(UInt64, Int64)] = []
        var total: UInt64 = 0
        if begins > 0.001 {
            entries.append((ticks(begins), -1))
            total += ticks(begins)
        }
        if !entries.isEmpty || mediaTime > 0 { entries.append((ticks(heard), mediaTime)) }
        return Edits(entries: entries, duration: total + ticks(heard))
    }

    private static func trackBox(id: UInt32, track: Track, table: SampleTable, edits: Edits, isVideo: Bool) -> Data {
        var header = Data()
        header.u32(1 << 24 | 7)                   // version 1, enabled in movie and preview
        header.u64(0)
        header.u64(0)
        header.u32(id)
        header.u32(0)
        header.u64(edits.duration)
        header.append(Data(count: 8))
        header.u16(0)
        header.u16(isVideo ? 0 : 1)               // the two tracks are no alternatives of each other
        header.u16(isVideo ? 0 : 0x0100)
        header.u16(0)
        header.matrix(track.transform)
        header.u32(UInt32((track.width * 65_536).rounded()))
        header.u32(UInt32((track.height * 65_536).rounded()))

        var children = box("tkhd", header)
        if !edits.entries.isEmpty {
            var list = Data()
            list.u32(1 << 24)
            list.u32(UInt32(edits.entries.count))
            for entry in edits.entries {
                list.u64(entry.duration)
                list.u64(UInt64(bitPattern: entry.mediaTime))
                list.u32(0x0001_0000)
            }
            children += box("edts", box("elst", list))
        }

        var mediaHeader = Data()
        mediaHeader.u32(1 << 24)
        mediaHeader.u64(0)
        mediaHeader.u64(0)
        mediaHeader.u32(UInt32(track.timescale))
        mediaHeader.u64(UInt64(max(0, table.duration)))
        mediaHeader.u16(0x55C4)                   // language: undetermined
        mediaHeader.u16(0)

        var handler = Data()
        handler.u32(0)
        handler.u32(0)
        handler.ascii(isVideo ? "vide" : "soun")
        handler.append(Data(count: 12))
        handler.append(Data((isVideo ? "Video" : "Sound").utf8))
        handler.append(0)

        var kind = Data()
        if isVideo {
            kind.u32(1)
            kind.append(Data(count: 8))
        } else {
            kind.u32(0)
            kind.append(Data(count: 4))
        }
        var reference = Data()
        reference.u32(0)
        reference.u32(1)
        var selfReference = Data()
        selfReference.u32(1)                      // the media is in this file
        reference.append(box("url ", selfReference))

        var description = Data()
        description.u32(0)
        description.u32(1)
        description.append(track.entry)

        var samples = box("stsd", description)
        samples += table.boxes()
        let information = box(isVideo ? "vmhd" : "smhd", kind) + box("dinf", box("dref", reference)) + box("stbl", samples)
        children += box("mdia", box("mdhd", mediaHeader) + box("hdlr", handler) + box("minf", information))
        return box("trak", children)
    }

    fileprivate static func box(_ type: String, _ payload: Data) -> Data {
        var data = Data(capacity: payload.count + 8)
        data.u32(UInt32(payload.count + 8))
        data.ascii(type)
        data.append(payload)
        return data
    }

    /// One track's samples in the shapes the index wants.
    private struct SampleTable {
        private let sizes: [UInt32]
        private let durations: [(count: UInt32, ticks: UInt32)]
        private let offsets: [(count: UInt32, ticks: Int32)]
        private let hasOffsets: Bool
        private let syncs: [UInt32]
        private let chunks: [(offset: Int64, count: UInt32)]
        private let isVideo: Bool
        /// The track's media length.
        let duration: Int64
        /// Where the first shown frame is in the media.
        let firstShown: Int64

        var isEmpty: Bool { sizes.isEmpty }

        init(records: [Record], mediaStart: Int64, isVideo: Bool, track: Track) {
            self.isVideo = isVideo
            var sizes: [UInt32] = []
            var syncs: [UInt32] = []
            var chunks: [(offset: Int64, count: UInt32)] = []
            var times: [(dts: Int64, pts: Int64)] = []
            var at = mediaStart
            var inChunk = false
            for record in records {
                if record.isVideo == isVideo {
                    if inChunk, let last = chunks.indices.last, chunks[last].count < 64 {
                        chunks[last].count += 1
                    } else {
                        chunks.append((at, 1))
                    }
                    inChunk = true
                    sizes.append(record.size)
                    times.append((record.dts, record.pts))
                    if record.isSync { syncs.append(UInt32(sizes.count)) }
                } else {
                    inChunk = false
                }
                at += Int64(record.size)
            }
            self.sizes = sizes
            self.syncs = syncs
            self.chunks = chunks
            let base = times.first?.dts ?? 0
            var durations: [(count: UInt32, ticks: UInt32)] = []
            var offsets: [(count: UInt32, ticks: Int32)] = []
            var hasOffsets = false
            var total: Int64 = 0
            var previous: Int64 = 0
            for index in times.indices {
                let length: Int64
                if index + 1 < times.count {
                    length = max(1, times[index + 1].dts - times[index].dts)
                } else if track.end > times[index].pts {
                    length = track.end - max(times[index].dts, times[index].pts)
                } else {
                    length = max(1, previous)
                }
                previous = length
                total += length
                let ticks = UInt32(clamping: length)
                if let last = durations.indices.last, durations[last].ticks == ticks { durations[last].count += 1 } else { durations.append((1, ticks)) }
                let offset = Int32(clamping: times[index].pts - times[index].dts)
                if offset != 0 { hasOffsets = true }
                if let last = offsets.indices.last, offsets[last].ticks == offset { offsets[last].count += 1 } else { offsets.append((1, offset)) }
            }
            self.durations = durations
            self.offsets = offsets
            self.hasOffsets = hasOffsets
            duration = total
            firstShown = max(0, (times.prefix(16).map(\.pts).min() ?? base) - base)
        }

        func boxes() -> Data {
            var result = Data()
            var list = Data()
            list.u32(0)
            list.u32(UInt32(durations.count))
            for item in durations {
                list.u32(item.count)
                list.u32(item.ticks)
            }
            result += WebMovieFile.box("stts", list)
            if hasOffsets {
                list = Data()
                list.u32(offsets.contains { $0.ticks < 0 } ? 1 << 24 : 0)
                list.u32(UInt32(offsets.count))
                for item in offsets {
                    list.u32(item.count)
                    list.u32(UInt32(bitPattern: item.ticks))
                }
                result += WebMovieFile.box("ctts", list)
            }
            if isVideo {
                list = Data()
                list.u32(0)
                list.u32(UInt32(syncs.count))
                for number in syncs { list.u32(number) }
                result += WebMovieFile.box("stss", list)
            }
            var runs: [(first: UInt32, count: UInt32)] = []
            for (index, chunk) in chunks.enumerated() where runs.last?.count != chunk.count {
                runs.append((UInt32(index + 1), chunk.count))
            }
            list = Data()
            list.u32(0)
            list.u32(UInt32(runs.count))
            for run in runs {
                list.u32(run.first)
                list.u32(run.count)
                list.u32(1)
            }
            result += WebMovieFile.box("stsc", list)
            list = Data()
            list.u32(0)
            list.u32(0)
            list.u32(UInt32(sizes.count))
            for size in sizes { list.u32(size) }
            result += WebMovieFile.box("stsz", list)
            list = Data()
            list.u32(0)
            list.u32(UInt32(chunks.count))
            // Files stay under 2 GB, so 32-bit places do.
            for chunk in chunks { list.u32(UInt32(clamping: chunk.offset)) }
            result += WebMovieFile.box("stco", list)
            return result
        }
    }
}

private extension Data {
    mutating func u16(_ value: UInt16) { append(contentsOf: [UInt8(value >> 8), UInt8(truncatingIfNeeded: value)]) }
    mutating func u32(_ value: UInt32) {
        append(contentsOf: [UInt8(truncatingIfNeeded: value >> 24), UInt8(truncatingIfNeeded: value >> 16),
                            UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)])
    }
    mutating func u64(_ value: UInt64) {
        u32(UInt32(truncatingIfNeeded: value >> 32))
        u32(UInt32(truncatingIfNeeded: value))
    }
    mutating func ascii(_ text: String) { append(contentsOf: Array(text.utf8)) }
    /// A track matrix: 16.16 fixed point, the last column 2.30.
    mutating func matrix(_ transform: CGAffineTransform) {
        func fixed(_ value: CGFloat) -> UInt32 { UInt32(bitPattern: Int32((Double(value) * 65_536).rounded())) }
        u32(fixed(transform.a)); u32(fixed(transform.b)); u32(0)
        u32(fixed(transform.c)); u32(fixed(transform.d)); u32(0)
        u32(fixed(transform.tx)); u32(fixed(transform.ty)); u32(0x4000_0000)
    }
}

/// Core Media's own description of a track, as the bytes an MP4 wants.
enum SampleEntry {
    static func video(_ description: CMFormatDescription) -> Data? {
        var block: CMBlockBuffer?
        let status = CMVideoFormatDescriptionCopyAsBigEndianImageDescriptionBlockBuffer(
            allocator: kCFAllocatorDefault, videoFormatDescription: description,
            stringEncoding: CFStringGetSystemEncoding(), flavor: .isoFamily, blockBufferOut: &block)
        guard status == noErr, let block else { return nil }
        return tidy(block)
    }

    static func audio(_ description: CMFormatDescription) -> Data? {
        var block: CMBlockBuffer?
        let status = CMAudioFormatDescriptionCopyAsBigEndianSoundDescriptionBlockBuffer(
            allocator: kCFAllocatorDefault, audioFormatDescription: description, flavor: .isoFamily, blockBufferOut: &block)
        guard status == noErr, let block else { return nil }
        return tidy(block)
    }

    private static func tidy(_ block: CMBlockBuffer) -> Data? {
        guard var data = try? block.dataBytes(), data.count > 16 else { return nil }
        // The sample entry points at the track's first (only) data reference.
        data[data.startIndex + 14] = 0
        data[data.startIndex + 15] = 1
        return data
    }
}
