import CoreGraphics
import Foundation
import SwiftUI

// MARK: - Recipe
//
// An edit is a small recipe, never a changed file. The source recording stays as it is; the
// recipe says which parts of it to keep (in order, each at a speed), how to frame it, and what
// to draw and play over it. Drafts are recipes waiting in the library (`EditDraft`); saving
// renders the recipe into a new recording (`EditRenderer`, through `RecordingSaver`).
//
// Two clocks:
// - source seconds: a moment in the original recording (sections, transcript, filler words);
// - output seconds: a moment in the edited video (text, shapes, blur, voice-over, thumbnail).
// Sections never overlap and stay in source order, so the edit is always a subsequence of the
// recording; that keeps every mapping between the clocks simple and exact.
//
// Overlays stay on the moment they were placed on: cutting, trimming or changing the speed of
// what comes before them moves them along (`followContent`), so a blur stays on the password it
// hides and an arrow on what it points at.

/// One kept section of the source, played at `speed`.
struct EditSegment: Codable, Hashable, Identifiable {
    var id = UUID()
    /// Source seconds.
    var start: Double
    var end: Double
    var speed: Double = 1

    var sourceLength: Double { max(0, end - start) }
    var outputLength: Double { sourceLength / max(speed, 0.1) }
}

/// Frame shapes offered by the crop tool.
enum EditAspect: String, Codable, CaseIterable, Identifiable {
    case original
    case free
    case portrait
    case square
    case fourFive
    case landscape

    var id: String { rawValue }

    var label: String {
        switch self {
        case .original: return "Original"
        case .free: return "Free"
        case .portrait: return "9:16"
        case .square: return "1:1"
        case .fourFive: return "4:5"
        case .landscape: return "16:9"
        }
    }

    /// Width over height, nil when any shape goes.
    var ratio: CGFloat? {
        switch self {
        case .original, .free: return nil
        case .portrait: return 9.0 / 16.0
        case .square: return 1
        case .fourFive: return 4.0 / 5.0
        case .landscape: return 16.0 / 9.0
        }
    }
}

struct EditCrop: Codable, Equatable {
    var aspect: EditAspect = .original
    /// Normalised rect (0...1, top-left origin) inside the upright source picture.
    var rect = CGRect(x: 0, y: 0, width: 1, height: 1)

    var isFullFrame: Bool {
        abs(rect.minX) < 0.001 && abs(rect.minY) < 0.001 && abs(rect.width - 1) < 0.001 && abs(rect.height - 1) < 0.001
    }
}

/// Colours offered for text and shapes. Picture content, so fixed (they don't follow the
/// appearance) and not limited to the app's accent.
enum EditColor: String, Codable, CaseIterable, Identifiable {
    case white, black, red, yellow, green, blue

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .white: return Color(hex: 0xFFFFFF)
        case .black: return Color(hex: 0x13141B)
        case .red: return Color(hex: 0xF04850)
        case .yellow: return Color(hex: 0xFFD43B)
        case .green: return Color(hex: 0x37C871)
        case .blue: return Color(hex: 0x3D8BFF)
        }
    }

    /// Text drawn on a box of this colour.
    var contrasting: Color {
        switch self {
        case .white, .yellow, .green: return Color(hex: 0x13141B)
        case .black, .red, .blue: return Color.white
        }
    }

    var label: String { rawValue.capitalized }
}

enum EditTextStyle: String, Codable, CaseIterable, Identifiable {
    case plain, box, outline, bar

    var id: String { rawValue }

    var label: String {
        switch self {
        case .plain: return "Plain"
        case .box: return "Box"
        case .outline: return "Outline"
        case .bar: return "Caption bar"
        }
    }
}

/// Text over the video, in output time.
struct EditText: Codable, Equatable, Identifiable {
    var id = UUID()
    var text: String
    var style: EditTextStyle = .box
    var color: EditColor = .white
    /// Normalised centre in the output picture (top-left origin).
    var center = CGPoint(x: 0.5, y: 0.4)
    var scale: Double = 1
    var start: Double
    var end: Double
}

enum EditStickerKind: String, Codable, CaseIterable, Identifiable {
    case arrow, circle, box, highlight, emoji

    var id: String { rawValue }

    var label: String {
        switch self {
        case .arrow: return "Arrow"
        case .circle: return "Circle"
        case .box: return "Box"
        case .highlight: return "Highlight"
        case .emoji: return "Emoji"
        }
    }

    var systemImage: String {
        switch self {
        case .arrow: return "arrow.up.right"
        case .circle: return "circle"
        case .box: return "square"
        case .highlight: return "highlighter"
        case .emoji: return "face.smiling"
        }
    }
}

/// A shape or emoji over the video, in output time.
struct EditSticker: Codable, Equatable, Identifiable {
    var id = UUID()
    var kind: EditStickerKind
    var emoji: String?
    var color: EditColor = .red
    var center = CGPoint(x: 0.5, y: 0.5)
    var scale: Double = 1
    /// Degrees, clockwise.
    var rotation: Double = 0
    var start: Double
    var end: Double
}

/// A blurred rectangle over the video (passwords, emails, faces), in output time.
struct EditBlur: Codable, Equatable, Identifiable {
    var id = UUID()
    /// Normalised rect in the output picture (top-left origin).
    var rect = CGRect(x: 0.25, y: 0.35, width: 0.5, height: 0.18)
    var start: Double
    var end: Double
}

enum EditCaptionStyle: String, Codable, CaseIterable, Identifiable {
    case classic, box, bar

    var id: String { rawValue }

    var label: String {
        switch self {
        case .classic: return "Classic"
        case .box: return "Box"
        case .bar: return "Bar"
        }
    }
}

/// Captions from the transcript, burned in on export.
struct EditCaptions: Codable, Hashable {
    var style: EditCaptionStyle = .box
    /// Corrected text, by transcript segment id.
    var edits: [String: String] = [:]
    /// Transcript segment ids whose caption is switched off.
    var hidden: Set<String> = []
}

/// Narration recorded in the editor, in output time. Its file is in the draft's folder.
struct EditVoiceClip: Codable, Hashable, Identifiable {
    var id = UUID()
    var fileName: String
    var start: Double
    var duration: Double
    /// Seconds of the file before the video started moving under it (nil in older drafts).
    var lead: Double?
}

/// The recording's own sound and the narration's level.
struct EditAudio: Codable, Hashable {
    /// 0...1.
    var volume: Double = 1
    var muted = false
    var fadeIn = false
    var fadeOut = false
    /// 0...1.
    var voiceVolume: Double = 1
    var reducesNoise = false

    static let fadeLength: Double = 1
}

enum ExportQuality: String, Codable, CaseIterable, Identifiable {
    case hd720
    case hd1080
    case original

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hd720: return "720p"
        case .hd1080: return "1080p"
        case .original: return "Original"
        }
    }

    var helper: String {
        switch self {
        case .hd720: return "Smallest file. Good for messages and quick replies."
        case .hd1080: return "Sharp on every screen. The best choice for most videos."
        case .original: return "Same size as your recording. Largest file."
        }
    }

    /// Short side in pixels; nil keeps the recording's own size.
    var shortSide: CGFloat? {
        switch self {
        case .hd720: return 720
        case .hd1080: return 1080
        case .original: return nil
        }
    }
}

struct EditRecipe: Codable, Equatable {
    var sourceID: UUID
    /// Length of the source recording, seconds.
    var sourceDuration: Double
    var segments: [EditSegment]
    var crop = EditCrop()
    /// Clockwise quarter turns, 0...3.
    var quarterTurns = 0
    var flipped = false
    var texts: [EditText] = []
    var stickers: [EditSticker] = []
    var blurs: [EditBlur] = []
    var captions: EditCaptions?
    var voiceClips: [EditVoiceClip] = []
    var audio = EditAudio()
    /// Output seconds of the library card's frame; nil picks one automatically.
    var thumbnailTime: Double?
    var quality: ExportQuality = .hd1080
    var updatedAt = Date()

    /// The whole recording, untouched.
    static func original(sourceID: UUID, duration: Double) -> EditRecipe {
        EditRecipe(sourceID: sourceID, sourceDuration: duration,
                   segments: [EditSegment(start: 0, end: max(duration, 0.1))])
    }

    /// Same edit, ignoring when it was last touched and the random ids of its sections.
    func sameEdit(as other: EditRecipe) -> Bool {
        guard segments.count == other.segments.count,
              zip(segments, other.segments).allSatisfy({ $0.start == $1.start && $0.end == $1.end && $0.speed == $1.speed })
        else { return false }
        var a = self, b = other
        a.segments = []
        b.segments = []
        a.updatedAt = .distantPast
        b.updatedAt = .distantPast
        return a == b
    }

    /// True when nothing about the recording would change. The export quality is a choice about
    /// the file, not an edit.
    var isUntouched: Bool {
        var original = EditRecipe.original(sourceID: sourceID, duration: sourceDuration)
        original.quality = quality
        return sameEdit(as: original)
    }

    /// A draft brought back for a recording whose length or files may have changed since: sections
    /// inside the recording, in order, and no voice-over whose file is gone.
    func repaired(duration: Double, hasVoiceFile: (String) -> Bool) -> EditRecipe {
        var copy = self
        if duration > 0 {
            copy.sourceDuration = duration
            var cursor = 0.0
            copy.segments = copy.segments.sorted { $0.start < $1.start }.compactMap { segment in
                var kept = segment
                kept.start = max(cursor, min(duration, segment.start))
                kept.end = min(duration, segment.end)
                kept.speed = min(4, max(0.25, segment.speed.isFinite ? segment.speed : 1))
                guard kept.end - kept.start >= 0.02 else { return nil }
                cursor = kept.end
                return kept
            }
            if copy.segments.isEmpty { copy.segments = [EditSegment(start: 0, end: max(duration, 0.1))] }
        }
        copy.voiceClips.removeAll { !hasVoiceFile($0.fileName) }
        copy.clampToDuration()
        return copy
    }
}

// MARK: - Clocks

extension EditRecipe {
    /// Length of the edited video, seconds.
    var outputDuration: Double { segments.reduce(0) { $0 + $1.outputLength } }

    /// Output seconds where segment `index` starts.
    func outputStart(ofSegment index: Int) -> Double {
        segments.prefix(index).reduce(0) { $0 + $1.outputLength }
    }

    func segmentIndex(_ id: UUID) -> Int? { segments.firstIndex { $0.id == id } }

    /// The segment playing at output time `t` (the last one at the very end).
    func segmentIndex(atOutput t: Double) -> Int? {
        guard !segments.isEmpty else { return nil }
        var cursor = 0.0
        for (index, segment) in segments.enumerated() {
            let next = cursor + segment.outputLength
            if t < next { return index }
            cursor = next
        }
        return segments.count - 1
    }

    /// Source seconds shown at output time `t`.
    func sourceTime(forOutput t: Double) -> Double {
        guard !segments.isEmpty else { return 0 }
        var cursor = 0.0
        for segment in segments {
            let next = cursor + segment.outputLength
            if t < next {
                return segment.start + max(0, t - cursor) * segment.speed
            }
            cursor = next
        }
        return segments[segments.count - 1].end
    }

    /// Output seconds of source time `t`, nil when that moment was cut.
    func outputTime(forSource t: Double) -> Double? {
        var cursor = 0.0
        for segment in segments {
            if t >= segment.start - 0.0001 && t <= segment.end + 0.0001 {
                return cursor + max(0, t - segment.start) / segment.speed
            }
            cursor += segment.outputLength
        }
        return nil
    }

    /// Output seconds of source time `t`, or of the next kept moment after it.
    func nearestOutputTime(forSource t: Double) -> Double {
        if let exact = outputTime(forSource: t) { return exact }
        var cursor = 0.0
        for segment in segments {
            if segment.start > t { return cursor }
            cursor += segment.outputLength
        }
        return cursor
    }

    /// The kept parts of a source range, as output ranges.
    func outputRanges(forSource range: ClosedRange<Double>) -> [ClosedRange<Double>] {
        var result: [ClosedRange<Double>] = []
        var cursor = 0.0
        for segment in segments {
            let lower = max(range.lowerBound, segment.start)
            let upper = min(range.upperBound, segment.end)
            if upper > lower {
                let a = cursor + (lower - segment.start) / segment.speed
                let b = cursor + (upper - segment.start) / segment.speed
                result.append(a...b)
            }
            cursor += segment.outputLength
        }
        return result
    }

    /// How much of a source range is kept, 0...1.
    func keptFraction(ofSource range: ClosedRange<Double>) -> Double {
        let length = range.upperBound - range.lowerBound
        guard length > 0 else { return 0 }
        var kept = 0.0
        var index = firstSegment(endingAfter: range.lowerBound)
        while index < segments.count, segments[index].start < range.upperBound {
            kept += max(0, min(range.upperBound, segments[index].end) - max(range.lowerBound, segments[index].start))
            index += 1
        }
        return min(1, kept / length)
    }

    /// Index of the first section that ends after source time `t` (sections are in order), or the
    /// number of sections.
    private func firstSegment(endingAfter t: Double) -> Int {
        var low = 0, high = segments.count
        while low < high {
            let middle = (low + high) / 2
            if segments[middle].end > t { high = middle } else { low = middle + 1 }
        }
        return low
    }

    /// The sections as they are played: neighbours that touch at the same speed (a split that cut
    /// nothing) are one, so playing over the split never stutters.
    var playedSegments: [EditSegment] {
        var result: [EditSegment] = []
        for segment in segments {
            if var last = result.last, abs(last.end - segment.start) < 0.0005, last.speed == segment.speed {
                last.end = segment.end
                result[result.count - 1] = last
            } else {
                result.append(segment)
            }
        }
        return result
    }
}

// MARK: - Cutting

extension EditRecipe {
    /// Shortest section the editor keeps (shorter leftovers are dropped).
    static let minimumSection: Double = 0.1
    /// Shortest edit that can be saved: the library takes nothing shorter as a recording.
    static let minimumSave: Double = 0.5
    /// Shortest the Trim handles make a part.
    static let minimumTrim: Double = 0.5

    /// Splits the section under output time `t` in two. False when `t` is too close to an edge.
    @discardableResult
    mutating func split(atOutput t: Double) -> Bool {
        guard let index = segmentIndex(atOutput: t) else { return false }
        let segment = segments[index]
        let cut = sourceTime(forOutput: t)
        guard cut - segment.start >= 0.2, segment.end - cut >= 0.2 else { return false }
        var left = segment
        left.end = cut
        var right = segment
        right.id = UUID()
        right.start = cut
        segments.replaceSubrange(index...index, with: [left, right])
        return true
    }

    /// Removes a whole section; what follows moves up to close the gap.
    mutating func removeSegment(_ id: UUID) {
        guard segments.count > 1 else { return }
        let old = self
        segments.removeAll { $0.id == id }
        followContent(from: old)
    }

    /// Cuts a source range out of every section it touches.
    mutating func remove(source range: ClosedRange<Double>) {
        let old = self
        var result: [EditSegment] = []
        for segment in segments {
            if segment.end <= range.lowerBound || segment.start >= range.upperBound {
                result.append(segment)
                continue
            }
            if range.lowerBound - segment.start >= Self.minimumSection {
                var left = segment
                left.end = range.lowerBound
                result.append(left)
            }
            if segment.end - range.upperBound >= Self.minimumSection {
                var right = segment
                right.id = UUID()
                right.start = range.upperBound
                result.append(right)
            }
        }
        // Never cut everything: keep the recipe playable.
        guard !result.isEmpty else { return }
        segments = result
        followContent(from: old)
    }

    /// Puts a source range back where it was cut, at the speed of what it joins.
    mutating func keep(source range: ClosedRange<Double>) {
        let old = self
        let lower = max(0, range.lowerBound)
        let upper = min(sourceDuration, range.upperBound)
        guard upper > lower else { return }
        var gaps: [ClosedRange<Double>] = []
        var cursor = lower
        for segment in segments.sorted(by: { $0.start < $1.start }) where segment.end > cursor && segment.start < upper {
            if segment.start > cursor { gaps.append(cursor...min(segment.start, upper)) }
            cursor = max(cursor, segment.end)
        }
        if cursor < upper { gaps.append(cursor...upper) }
        for gap in gaps where gap.upperBound - gap.lowerBound >= 0.02 {
            // Touching neighbours grow instead of adding a new section.
            if let index = segments.firstIndex(where: { abs($0.end - gap.lowerBound) < 0.001 }) {
                segments[index].end = gap.upperBound
            } else if let index = segments.firstIndex(where: { abs($0.start - gap.upperBound) < 0.001 }) {
                segments[index].start = gap.lowerBound
            } else {
                let speeds = Set(segments.map(\.speed))
                let speed = speeds.count == 1 ? (speeds.first ?? 1) : 1
                segments.append(EditSegment(start: gap.lowerBound, end: gap.upperBound, speed: speed))
                segments.sort { $0.start < $1.start }
            }
        }
        segments.sort { $0.start < $1.start }
        mergeTouchingFragments()
        followContent(from: old)
    }

    /// New in or out point for a section, kept between its neighbours.
    mutating func trim(_ id: UUID, start newStart: Double? = nil, end newEnd: Double? = nil) {
        guard let index = segmentIndex(id) else { return }
        let old = self
        let previousEnd = index > 0 ? segments[index - 1].end : 0
        let nextStart = index + 1 < segments.count ? segments[index + 1].start : sourceDuration
        var segment = segments[index]
        // Never shorter than half a second of the edit (or the part as it was, if already shorter).
        let shortest = min(Self.minimumTrim * segment.speed, segment.sourceLength)
        if let newStart {
            segment.start = min(max(previousEnd, newStart), segment.end - shortest)
        }
        if let newEnd {
            segment.end = max(min(nextStart, newEnd), segment.start + shortest)
        }
        segments[index] = segment
        followContent(from: old)
    }

    /// Everything before output time `t` goes ("Start here"). False when there is nothing to cut
    /// or too little would be left.
    @discardableResult
    mutating func cut(beforeOutput t: Double) -> Bool {
        guard t > 0.05, outputDuration - t >= 0.2 else { return false }
        remove(source: 0...sourceTime(forOutput: t))
        return true
    }

    /// Everything after output time `t` goes ("End here").
    @discardableResult
    mutating func cut(afterOutput t: Double) -> Bool {
        guard t >= 0.2, outputDuration - t > 0.05 else { return false }
        remove(source: sourceTime(forOutput: t)...max(sourceDuration, segments.last?.end ?? 0))
        return true
    }

    mutating func setSpeed(_ speed: Double, segment id: UUID? = nil) {
        let old = self
        for index in segments.indices where id == nil || segments[index].id == id {
            segments[index].speed = speed
        }
        followContent(from: old)
    }

    /// Moves overlays, voice-overs and the thumbnail with the moment they were on after the
    /// sections changed. A blur whose moment was cut goes with it; text and shapes whose moment
    /// was cut stay, at the cut, so nothing the person wrote disappears.
    mutating func followContent(from old: EditRecipe) {
        guard segments != old.segments else { return }
        let total = outputDuration
        func moved(_ start: Double, _ end: Double) -> (Double, Double)? {
            let from = old.sourceTime(forOutput: start)
            let to = old.sourceTime(forOutput: max(start, end - 0.001))
            let pieces = outputRanges(forSource: min(from, to)...max(from, to))
            guard let first = pieces.first, let last = pieces.last,
                  last.upperBound - first.lowerBound > 0.04 else { return nil }
            return (first.lowerBound, last.upperBound + 0.001)
        }
        func kept(_ start: Double, _ end: Double) -> (Double, Double) {
            let length = end - start
            if let span = moved(start, end) {
                // A sliver left of a title isn't readable: keep it up for up to a second.
                return (span.0, max(span.1, min(span.0 + min(length, 1), total)))
            }
            let at = nearestOutputTime(forSource: old.sourceTime(forOutput: start))
            return (at, at + min(length, 3))
        }
        for index in texts.indices {
            (texts[index].start, texts[index].end) = kept(texts[index].start, texts[index].end)
        }
        for index in stickers.indices {
            (stickers[index].start, stickers[index].end) = kept(stickers[index].start, stickers[index].end)
        }
        blurs = blurs.compactMap { blur in
            guard let span = moved(blur.start, blur.end) else { return nil }
            var copy = blur
            (copy.start, copy.end) = span
            return copy
        }
        for index in voiceClips.indices {
            voiceClips[index].start = nearestOutputTime(forSource: old.sourceTime(forOutput: voiceClips[index].start))
        }
        if let time = thumbnailTime {
            thumbnailTime = nearestOutputTime(forSource: old.sourceTime(forOutput: time))
        }
        clampToDuration()
    }

    /// Overlays end inside the (possibly shorter) video.
    mutating func clampToDuration() {
        let total = outputDuration
        func fit(_ span: (Double, Double)) -> (Double, Double) {
            let start = min(max(0, span.0), max(0, total - 0.3))
            return (start, min(max(start + 0.3, span.1), total))
        }
        for index in texts.indices {
            let span = fit((texts[index].start, texts[index].end))
            texts[index].start = span.0
            texts[index].end = span.1
        }
        for index in stickers.indices {
            let span = fit((stickers[index].start, stickers[index].end))
            stickers[index].start = span.0
            stickers[index].end = span.1
        }
        for index in blurs.indices {
            let span = fit((blurs[index].start, blurs[index].end))
            blurs[index].start = span.0
            blurs[index].end = span.1
        }
        voiceClips.removeAll { $0.start >= total - 0.05 }
        if let time = thumbnailTime, time > total { thumbnailTime = max(0, total - 0.1) }
    }

    /// Two touching pieces of the same section at one speed, left behind by keep/remove pairs.
    private mutating func mergeTouchingFragments() {
        var merged: [EditSegment] = []
        for segment in segments {
            if var last = merged.last, abs(last.end - segment.start) < 0.001, last.speed == segment.speed,
               segment.end - segment.start < 0.5 || last.end - last.start < 0.5 {
                last.end = segment.end
                merged[merged.count - 1] = last
            } else {
                merged.append(segment)
            }
        }
        segments = merged
    }
}

// MARK: - Picture size

extension EditRecipe {
    /// Size of the edited picture in source pixels: the crop, turned.
    func outputPictureSize(source: CGSize) -> CGSize {
        let width = max(2, source.width * crop.rect.width)
        let height = max(2, source.height * crop.rect.height)
        return quarterTurns % 2 == 0 ? CGSize(width: width, height: height) : CGSize(width: height, height: width)
    }

    /// Render size for the chosen quality: never larger than the picture, even numbers.
    func renderSize(source: CGSize, quality: ExportQuality) -> CGSize {
        let picture = outputPictureSize(source: source)
        var scale: CGFloat = 1
        if let shortSide = quality.shortSide {
            scale = min(1, shortSide / max(1, min(picture.width, picture.height)))
        }
        func even(_ value: CGFloat) -> CGFloat { max(2, (value * scale / 2).rounded() * 2) }
        return CGSize(width: even(picture.width), height: even(picture.height))
    }
}

// MARK: - Captions and transcript

/// One caption line in output time.
struct EditCaptionLine: Identifiable, Hashable {
    /// Transcript segment id.
    var id: String
    var text: String
    var start: Double
    var end: Double
    var isHidden: Bool
}

extension EditCaptionLine {
    /// The line as it is shown: a long sentence in pieces of at most about `limit` characters, one
    /// after another, so no words are cut off with "…". Time is shared out by length.
    func pieces(limit: Int) -> [EditCaptionLine] {
        let words = text.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
        guard text.count > limit, words.count > 1 else { return [self] }
        let count = max(2, Int((Double(text.count) / Double(limit)).rounded(.up)))
        let target = Double(text.count) / Double(count)
        var groups: [String] = []
        var current = ""
        for word in words {
            let joined = current.isEmpty ? word : current + " " + word
            if !current.isEmpty, joined.count > limit || (Double(joined.count) > target * 1.15 && groups.count < count - 1) {
                groups.append(current)
                current = word
            } else {
                current = joined
            }
        }
        if !current.isEmpty { groups.append(current) }
        let total = Double(max(1, groups.reduce(0) { $0 + $1.count }))
        var cursor = start
        return groups.enumerated().map { index, group in
            let length = (end - start) * Double(group.count) / total
            defer { cursor += length }
            return EditCaptionLine(id: "\(id)-\(index)", text: group, start: cursor,
                                   end: index == groups.count - 1 ? end : cursor + length, isHidden: isHidden)
        }
    }
}

extension EditRecipe {
    /// Caption lines for the kept speech, with the person's corrections.
    func captionLines(from transcript: Transcript?) -> [EditCaptionLine] {
        guard let transcript, let captions else { return [] }
        return transcript.segments.compactMap { segment in
            let range = segment.start...(segment.start + max(0.2, segment.duration))
            let pieces = outputRanges(forSource: range)
            guard let first = pieces.first, let last = pieces.last,
                  keptFraction(ofSource: range) >= 0.35 else { return nil }
            let key = segment.id.uuidString
            let kept = keptText(of: segment)
            guard !kept.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            // A line whose words were all deleted by hand is a hidden line, so it can come back.
            let edited = captions.edits[key]?.trimmingCharacters(in: .whitespaces)
            let emptied = edited?.isEmpty == true
            return EditCaptionLine(id: key, text: emptied ? kept : (edited ?? kept), start: first.lowerBound, end: last.upperBound,
                                   isHidden: emptied || captions.hidden.contains(key))
        }
    }

    /// A transcript line without the words that were cut (filler words), when word times are known.
    func keptText(of segment: TranscriptSegment) -> String {
        guard let words = segment.words, !words.isEmpty else { return segment.text }
        let kept = words.filter { word in
            keptFraction(ofSource: word.start...(word.start + max(0.05, word.duration))) >= 0.5
        }
        if kept.count == words.count { return segment.text }
        return kept.map(\.text).joined(separator: " ")
    }

    /// The source transcript moved onto the edited video's clock, for the new recording.
    func retimedTranscript(_ transcript: Transcript, for videoID: UUID) -> Transcript {
        var lines: [TranscriptSegment] = []
        for line in transcript.segments {
            let range = line.start...(line.start + max(0.2, line.duration))
            guard keptFraction(ofSource: range) >= 0.35 else { continue }
            let pieces = outputRanges(forSource: range)
            guard let first = pieces.first, let last = pieces.last else { continue }
            let edited = captions?.edits[line.id.uuidString]?.trimmingCharacters(in: .whitespaces)
            let text = edited.flatMap { $0.isEmpty ? nil : $0 } ?? keptText(of: line)
            let words = line.words?.compactMap { word -> TranscriptWord? in
                guard let start = outputTime(forSource: word.start) else { return nil }
                let speed = keptSegment(atSource: word.start)?.speed ?? 1
                return TranscriptWord(text: word.text, start: start, duration: word.duration / speed)
            }
            lines.append(TranscriptSegment(start: first.lowerBound,
                                           duration: max(0.2, last.upperBound - first.lowerBound),
                                           text: text, words: words))
        }
        return Transcript(videoID: videoID, localeIdentifier: transcript.localeIdentifier, segments: lines,
                          createdAt: Date(), summary: nil)
    }

    private func keptSegment(atSource t: Double) -> EditSegment? {
        segments.first { t >= $0.start && t <= $0.end }
    }
}

// MARK: - Stored records

/// The editor's work in progress for one recording, kept until it is saved or discarded.
struct EditDraft: Codable, Equatable {
    var recipe: EditRecipe
}

extension EditDraft: StoredRecord {
    static var recordType: String { "editdraft" }
    var recordID: String { recipe.sourceID.uuidString }
}

/// The recipe behind an edited recording, kept while it renders so a closed app or a failure
/// can render it again.
struct EditOutput: Codable, Equatable {
    var videoID: UUID
    var recipe: EditRecipe
}

extension EditOutput: StoredRecord {
    static var recordType: String { "editoutput" }
    var recordID: String { videoID.uuidString }
}

extension MediaLocations {
    /// Voice-over takes and cleaned-up sound for the edits of one recording.
    func editFolder(_ sourceID: UUID) -> URL {
        let url = root.appendingPathComponent("Edits", isDirectory: true)
            .appendingPathComponent(sourceID.uuidString, isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                     attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        }
        return url
    }
}
