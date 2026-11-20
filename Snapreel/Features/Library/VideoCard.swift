import SwiftUI

// Session D. The recording cards shared by Home, Library, folders, watch lists and search.

/// Where a card is shown; changes its second line.
enum VideoCardContext: Equatable {
    /// "Screen · 2h ago", notes, reactions and folder.
    case library
    /// Same, without the folder (you're already in it).
    case folder
    /// "Added 2h ago".
    case watchLater
    /// "Watched 2h ago" and a progress bar.
    case history
    /// Title with the matching words highlighted.
    case search(String)
}

/// A recording as a horizontal card: thumbnail with duration, title, when, note and reaction
/// counts, and a "…" button. Saving and failed recordings show their state, failed ones with
/// Try again, Free up space (when the phone was full) and Delete.
struct VideoCard: View {
    let video: Video
    let actions: LibraryActionsModel
    var context: VideoCardContext = .library
    /// Runs before the recording opens (search uses it to remember the query).
    var onOpen: (@MainActor () -> Void)? = nil

    @EnvironmentObject private var library: Library
    @EnvironmentObject private var router: AppRouter

    private let thumbnailWidth: CGFloat = 120

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .top, spacing: 0) {
                Button {
                    open()
                } label: {
                    mainContent
                }
                .buttonStyle(PressScaleStyle(scale: 0.98))
                .accessibilityLabel(accessibilitySummary)
                .accessibilityHint(accessibilityHint)
                LibraryMoreButton(video: video, actions: actions)
                    .padding(.top, -6)
                    .padding(.trailing, -6)
            }
            if case .failed(_, let outOfSpace) = video.state {
                failedActions(outOfSpace: outOfSpace)
            }
        }
        .padding(Space.s)
        .srCard()
        .contextMenu {
            LibraryVideoMenu(video: video, actions: actions, library: library, router: router)
        }
    }

    private var mainContent: some View {
        HStack(alignment: .top, spacing: Space.s) {
            VStack(spacing: 6) {
                VideoThumbnail(video: video, cornerRadius: Radius.s)
                if context == .history {
                    BrowseProgressBar(progress: video.browseWatchedFraction)
                }
            }
            .frame(width: thumbnailWidth)
            info
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            BrowseHighlight.text(video.title, query: highlightQuery)
                .font(.srSubheadlineStrong)
                .foregroundColor(Color.srText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(verbatim: metaText)
                .font(.srFootnote)
                .foregroundStyle(Color.srTextSecondary)
                .lineLimit(1)
            statusLine
        }
        .padding(.top, 1)
    }

    @ViewBuilder private var statusLine: some View {
        switch video.state {
        case .ready:
            VideoCardBadges(video: video, showsFolder: context == .library, showsWatched: context == .history)
        case .saving(let progress):
            HStack(spacing: Space.xxs) {
                ProgressView()
                    .controlSize(.mini)
                Text(verbatim: "Saving · \(Int((progress * 100).rounded()))%")
            }
            .font(.srCaption)
            .foregroundStyle(Color.srTextSecondary)
        case .failed(let reason, _):
            Text(verbatim: reason)
                .font(.srCaption)
                .foregroundStyle(Color.srRedText)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func failedActions(outOfSpace: Bool) -> some View {
        HStack(spacing: Space.xs) {
            if outOfSpace {
                CardPillButton(title: "Free up space", systemImage: "externaldrive", prominent: true) {
                    actions.showStorage()
                }
            }
            CardPillButton(title: "Try again", systemImage: "arrow.clockwise", prominent: !outOfSpace) {
                actions.retry(video.id, library: library, router: router)
            }
            CardPillButton(title: "Delete", systemImage: "trash", prominent: false, showsTitle: !outOfSpace) {
                actions.requestDelete(video.id)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Behaviour

    private func open() {
        switch video.state {
        case .ready:
            Haptics.tap()
            onOpen?()
            router.play(video.id)
        case .saving:
            Haptics.warning()
            router.showToast("Still saving. It'll be ready in a moment.", systemImage: "hourglass")
        case .failed:
            actions.showActions(video.id)
        }
    }

    // MARK: Wording

    private var highlightQuery: String? {
        if case .search(let query) = context { return query }
        return nil
    }

    private var metaText: String {
        switch context {
        case .watchLater:
            return "Added \(BrowseText.age(video.watchLaterAddedAt ?? video.createdAt))"
        case .history:
            return "Watched \(BrowseText.age(video.lastWatchedAt ?? video.createdAt))"
        case .library, .folder, .search:
            return "\(video.kind.label) · \(Format.age(video.createdAt))"
        }
    }

    private var accessibilitySummary: String {
        var parts: [String] = [video.title, "\(video.kind.label) recording", Format.duration(video.duration), metaText]
        switch video.state {
        case .ready:
            let notes = library.notes.filter { $0.videoID == video.id }.count
            let reactions = library.reactions.filter { $0.videoID == video.id }.count
            if notes > 0 { parts.append(BrowseText.count(notes, "note", "notes")) }
            if reactions > 0 { parts.append(BrowseText.count(reactions, "reaction", "reactions")) }
            if context == .history { parts.append(video.browseWatchedLabel) }
            if video.needsTitle { parts.append("Needs a title") }
        case .saving:
            parts.append("Still saving")
        case .failed(let reason, _):
            parts.append("Not saved. \(reason)")
        }
        return parts.joined(separator: ", ")
    }

    private var accessibilityHint: String {
        switch video.state {
        case .ready: return "Plays the recording"
        case .saving: return ""
        case .failed: return "Shows what you can do with it"
        }
    }
}

/// Counts under a card title: needs-a-title flag, notes, reactions, folder, watched.
struct VideoCardBadges: View {
    let video: Video
    var showsFolder = true
    var showsWatched = false

    @EnvironmentObject private var library: Library
    @ObservedObject private var shareLinks: ShareLinks = .shared
    @ObservedObject private var uploader: Uploader = .shared

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // A shared recording says so on a line of its own ("Shared · 12 views").
            if let link = library.link(for: video.id) {
                SharedBadge(link: link, state: shareLinks.state(for: video.id))
                    .fixedSize()
            }
            counts
        }
    }

    private var counts: some View {
        HStack(spacing: Space.s) {
            if video.editedFrom != nil {
                HStack(spacing: 3) {
                    Image(systemName: "scissors")
                        .font(.system(size: 10, weight: .bold))
                    Text("Edited")
                }
                .font(.srCaption)
                .foregroundStyle(Color.srTextSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.srFill))
                .accessibilityLabel("Edited copy")
            }
            if video.needsTitle {
                HStack(spacing: 3) {
                    Image(systemName: "pencil")
                        .font(.system(size: 10, weight: .bold))
                    Text("Needs a title")
                }
                .font(.srCaption)
                .foregroundStyle(Color.srRedText)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.srRedSoft))
            }
            if showsWatched {
                Text(verbatim: video.browseWatchedLabel)
                    .font(.srCaption)
                    .foregroundStyle(Color.srTextSecondary)
            }
            if noteCount > 0 {
                badge("text.bubble", "\(noteCount)")
            }
            if reactionCount > 0 {
                badge("face.smiling", "\(reactionCount)")
            }
            if showsFolder, let name = folderName {
                badge("folder", name)
            }
        }
        .lineLimit(1)
    }

    private var noteCount: Int { library.notes.filter { $0.videoID == video.id }.count }
    private var reactionCount: Int { library.reactions.filter { $0.videoID == video.id }.count }
    private var folderName: String? { video.folderID.flatMap { library.folder($0)?.name } }

    private func badge(_ systemImage: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(verbatim: text)
                .lineLimit(1)
        }
        .font(.srCaption)
        .foregroundStyle(Color.srTextSecondary)
    }
}

/// Small capsule buttons under a failed card.
private struct CardPillButton: View {
    let title: String
    let systemImage: String
    var prominent = false
    /// Icon only when three pills share a narrow card.
    var showsTitle = true
    let action: @MainActor () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .bold))
                if showsTitle {
                    Text(title)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .font(.srCaption)
            .foregroundStyle(prominent ? Color.white : Color.srText)
            .padding(.horizontal, showsTitle ? 10 : Space.s)
            .frame(height: 30)
            .background(Capsule().fill(prominent ? Color.srRed : Color.srFill))
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle(scale: 0.95))
        .accessibilityLabel(title)
    }
}

// MARK: - Rail card

/// A recording as a vertical card for Home's horizontal rails.
struct VideoRailCard: View {
    let video: Video
    let actions: LibraryActionsModel
    var showsProgress = false

    @EnvironmentObject private var library: Library
    @EnvironmentObject private var router: AppRouter

    static let width: CGFloat = 228

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            Button {
                Haptics.tap()
                router.play(video.id)
            } label: {
                artwork
            }
            .buttonStyle(PressScaleStyle(scale: 0.98))
            .accessibilityLabel(accessibilitySummary)
            .accessibilityHint("Plays the recording")
            HStack(alignment: .center, spacing: Space.xxs) {
                Text(verbatim: footnote)
                    .font(.srFootnote)
                    .foregroundStyle(Color.srTextSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                LibraryMoreButton(video: video, actions: actions)
                    .padding(.trailing, -6)
            }
            .padding(.top, -6)
            .padding(.bottom, -8)
        }
        .padding(10)
        .frame(width: Self.width)
        .srCard()
        .contextMenu {
            LibraryVideoMenu(video: video, actions: actions, library: library, router: router)
        }
    }

    private var artwork: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            VideoThumbnail(video: video, cornerRadius: Radius.m)
            if showsProgress {
                BrowseProgressBar(progress: video.browseWatchedFraction)
            }
            Text(verbatim: video.title)
                .font(.srSubheadlineStrong)
                .foregroundStyle(Color.srText)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 2)
        }
        .contentShape(Rectangle())
    }

    private var footnote: String {
        if showsProgress {
            return "\(video.browseWatchedLabel) · \(BrowseText.age(video.lastWatchedAt ?? video.createdAt))"
        }
        let notes = library.notes.filter { $0.videoID == video.id }.count
        if notes > 0 {
            return "\(Format.age(video.createdAt)) · \(BrowseText.count(notes, "note", "notes"))"
        }
        return "\(Format.age(video.createdAt)) · \(video.kind.label)"
    }

    private var accessibilitySummary: String {
        [video.title, "\(video.kind.label) recording", Format.duration(video.duration), footnote].joined(separator: ", ")
    }
}

// MARK: - Folder card

/// A folder as a card: up to three thumbnails, name, count and when it last changed.
struct LibraryFolderCard: View {
    let folder: Folder
    let videos: [Video]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            GeometryReader { proxy in
                cover(size: proxy.size)
            }
            .aspectRatio(4 / 3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: folder.name)
                    .font(.srHeadline)
                    .foregroundStyle(Color.srText)
                    .lineLimit(1)
                Text(verbatim: BrowseText.recordings(videos.count))
                    .font(.srFootnote)
                    .foregroundStyle(Color.srTextSecondary)
                    .lineLimit(1)
                Text(verbatim: "Updated \(BrowseText.age(folder.updatedAt))")
                    .font(.srFootnote)
                    .foregroundStyle(Color.srTextTertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, Space.xxs)
            .padding(.bottom, Space.xxs)
        }
        .padding(Space.xs)
        .srCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(folder.name), \(BrowseText.recordings(videos.count)), updated \(BrowseText.age(folder.updatedAt))")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func cover(size: CGSize) -> some View {
        let shown = Array(videos.prefix(3))
        if shown.isEmpty {
            ZStack {
                Color.srRedSoft
                Image(systemName: "folder.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color.srRed.opacity(0.75))
            }
        } else if shown.count == 1 {
            VideoThumbnail(video: shown[0], cornerRadius: 0, showsDuration: false,
                           aspectRatio: ratio(size.width, size.height))
                .frame(width: size.width, height: size.height)
        } else {
            mosaic(shown, size: size)
        }
    }

    private func mosaic(_ shown: [Video], size: CGSize) -> some View {
        let gap: CGFloat = 3
        let mainWidth = max(1, (size.width - gap) * 0.62)
        let sideWidth = max(1, size.width - gap - mainWidth)
        let sideHeight = max(1, (size.height - gap) / 2)
        return HStack(spacing: gap) {
            VideoThumbnail(video: shown[0], cornerRadius: 0, showsDuration: false,
                           aspectRatio: ratio(mainWidth, size.height))
                .frame(width: mainWidth, height: size.height)
            VStack(spacing: gap) {
                VideoThumbnail(video: shown[1], cornerRadius: 0, showsDuration: false,
                               aspectRatio: ratio(sideWidth, sideHeight))
                    .frame(width: sideWidth, height: sideHeight)
                if shown.count > 2 {
                    VideoThumbnail(video: shown[2], cornerRadius: 0, showsDuration: false,
                                   aspectRatio: ratio(sideWidth, sideHeight))
                        .frame(width: sideWidth, height: sideHeight)
                } else {
                    Color.srFill
                        .frame(width: sideWidth, height: sideHeight)
                }
            }
        }
    }

    private func ratio(_ width: CGFloat, _ height: CGFloat) -> CGFloat {
        max(0.1, width / max(height, 1))
    }
}
