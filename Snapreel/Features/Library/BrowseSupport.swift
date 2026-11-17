import SwiftUI

// Session D. Small pieces shared by Home, Library and Search.

// MARK: - Library sections and sorting

/// The two sections of the Library tab.
enum LibraryTab: String, CaseIterable, Hashable {
    case videos
    case folders

    var title: String {
        switch self {
        case .videos: return "My videos"
        case .folders: return "Folders"
        }
    }
}

/// How lists of recordings are ordered. Remembered between launches.
enum LibrarySort: String, CaseIterable, Identifiable {
    case newest
    case oldest
    case longest
    case title

    static let storageKey = "library.sort"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .newest: return "Newest first"
        case .oldest: return "Oldest first"
        case .longest: return "Longest first"
        case .title: return "Title A–Z"
        }
    }

    var shortLabel: String {
        switch self {
        case .newest: return "Newest"
        case .oldest: return "Oldest"
        case .longest: return "Longest"
        case .title: return "A–Z"
        }
    }

    var systemImage: String {
        switch self {
        case .newest: return "arrow.down"
        case .oldest: return "arrow.up"
        case .longest: return "timer"
        case .title: return "textformat"
        }
    }

    func sorted(_ videos: [Video]) -> [Video] {
        switch self {
        case .newest:
            return videos.sorted { $0.createdAt > $1.createdAt }
        case .oldest:
            return videos.sorted { $0.createdAt < $1.createdAt }
        case .longest:
            return videos.sorted { $0.duration > $1.duration }
        case .title:
            return videos.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }
}

// MARK: - Requests between screens

/// A sheet the Library tab root should open once it is on screen.
enum LibrarySheetRequest: Equatable {
    case video(LibraryVideoSheet)
    case newFolder(name: String)
    case renameFolder(UUID)
}

/// Text to put in the search field, and whether to bring up the keyboard.
struct BrowseSearchRequest: Equatable {
    var query: String
    var focusesField: Bool
}

/// Requests to show a browse screen in a given state. Home's "See all" picks the Library
/// section this way, and DEBUG launch screens (`-screen <id>`) use it to open a sheet or fill
/// the search field. A view takes a request once and clears it.
@MainActor
final class BrowseIntent: ObservableObject {
    static let shared = BrowseIntent()

    /// Selected section of the Library tab; kept while switching tabs.
    @Published var libraryTab: LibraryTab = .videos
    /// A sheet to open on the Library tab root.
    @Published var librarySheet: LibrarySheetRequest?
    /// A query to run on the Search tab.
    @Published var search: BrowseSearchRequest?
}

// MARK: - Wording

enum BrowseText {
    static func count(_ number: Int, _ singular: String, _ plural: String) -> String {
        "\(number) \(number == 1 ? singular : plural)"
    }

    static func recordings(_ number: Int) -> String {
        count(number, "recording", "recordings")
    }

    /// `Format.age` for use inside a sentence: "just now", "yesterday", "2h ago", "12 Nov".
    static func age(_ date: Date) -> String {
        let age = Format.age(date)
        switch age {
        case "Just now": return "just now"
        case "Yesterday": return "yesterday"
        default: return age
        }
    }

    /// Total running time of `videos`, spoken style ("14 min").
    static func totalDuration(_ videos: [Video]) -> String {
        Format.duration(videos.reduce(0) { $0 + $1.duration })
    }
}

extension Video {
    /// How far through the recording you got, 0...1: the furthest point reached or the point
    /// playback resumes from, whichever is further.
    var browseWatchedFraction: Double {
        let resume = duration > 0 ? resumePosition / duration : 0
        return min(1, max(0, max(furthestProgress, resume)))
    }

    /// "82% watched" or "Watched to the end".
    var browseWatchedLabel: String {
        let fraction = browseWatchedFraction
        if fraction >= 0.98 { return "Watched to the end" }
        return "\(Int((fraction * 100).rounded()))% watched"
    }
}

// MARK: - Layout

@MainActor
enum BrowseLayout {
    /// Space under scrolling content so the last card clears the mini player.
    static func bottomPadding(_ router: AppRouter) -> CGFloat {
        router.player?.isMinimized == true ? 104 : Space.xxl
    }
}

/// Thin red bar showing how far through a recording you got.
struct BrowseProgressBar: View {
    var progress: Double
    var track: Color = .srFill

    var body: some View {
        GeometryReader { proxy in
            let fraction: CGFloat = CGFloat(min(1, max(0, progress)))
            let filled: CGFloat = max(4, proxy.size.width * fraction)
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(Color.srRed)
                    .frame(width: filled)
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

/// Lays children out in rows, wrapping to the next row when one is full (tag chips).
struct BrowseFlowLayout: Layout {
    var spacing: CGFloat = Space.xs
    var lineSpacing: CGFloat = Space.xs

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = fittedSize(subview, maxWidth: maxWidth)
            if x > 0 && x + size.width > maxWidth {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            widest = max(widest, x + size.width)
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        let width = proposal.width ?? widest
        return CGSize(width: width, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = fittedSize(subview, maxWidth: bounds.width)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += lineHeight + lineSpacing
                x = bounds.minX
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }

    private func fittedSize(_ subview: LayoutSubview, maxWidth: CGFloat) -> CGSize {
        let ideal = subview.sizeThatFits(.unspecified)
        guard ideal.width > maxWidth, maxWidth.isFinite else { return ideal }
        return subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
    }
}

/// A wrapping row of chips. Calls the layout explicitly so call sites read like a stack.
struct BrowseChipFlow<Content: View>: View {
    var spacing: CGFloat = Space.xs
    @ViewBuilder var content: () -> Content

    var body: some View {
        BrowseFlowLayout(spacing: spacing, lineSpacing: spacing).callAsFunction(content)
    }
}

/// A tag as a capsule. `.removable` shows a cross, `.suggestion` a plus.
struct BrowseTagChip: View {
    enum Style {
        case plain
        case suggestion
        case removable
    }

    let text: String
    var style: Style = .plain
    var count: Int? = nil
    let action: @MainActor () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            chipBody
        }
        .buttonStyle(PressScaleStyle(scale: 0.95))
        .accessibilityLabel(accessibilityText)
    }

    private var chipBody: some View {
        HStack(spacing: 5) {
            Image(systemName: style == .suggestion ? "plus" : "number")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(style == .removable ? Color.srRedDeep : Color.srTextTertiary)
            Text(verbatim: text)
                .font(.srSubheadlineStrong)
                .foregroundStyle(style == .removable ? Color.srRedDeep : Color.srText)
                .lineLimit(1)
            if let count {
                Text("\(count)")
                    .font(.srCaption)
                    .foregroundStyle(Color.srTextTertiary)
            }
            if style == .removable {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.srRedDeep)
            }
        }
        .padding(.horizontal, Space.s)
        .frame(minHeight: 34)
        .background(Capsule().fill(style == .removable ? Color.srRedSoft : Color.srSurface))
        .overlay(Capsule().strokeBorder(style == .removable ? Color.clear : Color.srLine, lineWidth: 1))
        .contentShape(Capsule())
    }

    private var accessibilityText: String {
        switch style {
        case .plain:
            if let count { return "Tag \(text), \(BrowseText.recordings(count))" }
            return "Tag \(text)"
        case .suggestion: return "Add tag \(text)"
        case .removable: return "Remove tag \(text)"
        }
    }
}

// MARK: - Matching and highlighting

/// Case- and diacritic-insensitive matching shared by search and the tag editor.
enum BrowseMatch {
    static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    /// True when `text` contains the whole query, or every word of a multi-word query.
    static func matches(_ text: String, _ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if text.range(of: trimmed, options: options) != nil { return true }
        let words = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard words.count > 1 else { return false }
        return words.allSatisfy { text.range(of: $0, options: options) != nil }
    }

    /// The part of `text` to highlight for `query`: the whole query, else its first word found.
    static func highlightRange(in text: String, for query: String) -> Range<String.Index>? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let range = text.range(of: trimmed, options: options) { return range }
        for word in trimmed.split(whereSeparator: { $0.isWhitespace }) {
            if let range = text.range(of: String(word), options: options) { return range }
        }
        return nil
    }
}

@MainActor
enum BrowseHighlight {
    /// `text` with the part matching `query` in bold red.
    static func text(_ text: String, query: String?) -> Text {
        guard let query, let range = BrowseMatch.highlightRange(in: text, for: query) else {
            return Text(verbatim: text)
        }
        let before = Text(verbatim: String(text[text.startIndex..<range.lowerBound]))
        let match = Text(verbatim: String(text[range]))
            .foregroundColor(Color.srRedDeep)
            .fontWeight(.bold)
        let after = Text(verbatim: String(text[range.upperBound...]))
        return before + match + after
    }
}
