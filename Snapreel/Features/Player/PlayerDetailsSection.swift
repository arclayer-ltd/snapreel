import SwiftUI

/// Under the video: kind and date, title with share and more, a one-line summary with the
/// details toggle, the expanded details (and summary when there is one), and the stats row.
struct PlayerDetailsSection: View {
    let video: Video
    let folderName: String?
    let noteCount: Int
    let reactionCount: Int
    let transcript: Transcript?
    let isSummarizing: Bool
    @Binding var isExpanded: Bool
    let onShare: @MainActor () -> Void
    let onMore: @MainActor () -> Void
    let onEditTitle: @MainActor () -> Void
    let onStats: @MainActor () -> Void
    var onSaveToPhotos: (@MainActor () -> Void)? = nil
    var onToggleWatchLater: (@MainActor () -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            dateLine
            titleRow
            if video.needsTitle { titleHint }
            quickActions
            metaRow
            if isExpanded {
                PlayerFactsCard(video: video, folderName: folderName, transcript: transcript,
                                isSummarizing: isSummarizing)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            statsRow
        }
    }

    private var dateLine: some View {
        Label {
            Text("\(video.kind.titlePrefix) · \(Format.date(video.createdAt))")
        } icon: {
            Image(systemName: video.kind.systemImage)
        }
        .font(.srFootnote)
        .foregroundStyle(Color.srOnDarkSecondary)
    }

    private var titleRow: some View {
        HStack(alignment: .top, spacing: Space.xs) {
            Text(video.title)
                .font(.srTitle3)
                .foregroundStyle(Color.srOnDark)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            CircleIconButton(systemName: "square.and.arrow.up", label: "Share", tone: .dark, size: 36) {
                onShare()
            }
            CircleIconButton(systemName: "ellipsis", label: "More actions", tone: .dark, size: 36) {
                onMore()
            }
        }
    }

    /// The everyday actions in reach without opening the menu: equal tiles that always fit the width.
    private var quickActions: some View {
        HStack(spacing: Space.xs) {
            QuickActionChip(title: "Edit title", systemImage: "pencil") { onEditTitle() }
            if let onSaveToPhotos, video.kind != .audio {
                QuickActionChip(title: "Save to Photos", systemImage: "square.and.arrow.down") { onSaveToPhotos() }
            }
            if let onToggleWatchLater {
                QuickActionChip(title: video.isInWatchLater ? "In Watch later" : "Watch later",
                                systemImage: video.isInWatchLater ? "clock.fill" : "clock",
                                isOn: video.isInWatchLater) { onToggleWatchLater() }
            }
        }
    }

    private var titleHint: some View {
        Button {
            onEditTitle()
        } label: {
            Label("Give it a title so it's easy to find", systemImage: "character.cursor.ibeam")
                .font(.srSubheadlineStrong)
                .foregroundStyle(Color.srRedGlow)
        }
        .buttonStyle(.plain)
    }

    private var metaRow: some View {
        HStack(spacing: Space.s) {
            Text(summaryLine)
                .font(.srSubheadline)
                .foregroundStyle(Color.srOnDarkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: Space.xs)
            Button {
                Haptics.selection()
                withAnimation(Motion.standard) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Text(isExpanded ? "Less" : "Details")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .font(.srSubheadlineStrong)
                .foregroundStyle(Color.srRedGlow)
                .padding(.vertical, Space.xxs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Hide details" : "Show details")
        }
    }

    private var summaryLine: String {
        let notes = noteCount == 1 ? "1 note" : "\(noteCount) notes"
        let reactions = reactionCount == 1 ? "1 reaction" : "\(reactionCount) reactions"
        return [Format.clock(video.duration), notes, reactions].joined(separator: " · ")
    }

    private var statsRow: some View {
        Button {
            Haptics.tap()
            onStats()
        } label: {
            HStack(spacing: Space.s) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.srRed)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.srRed.opacity(0.16)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(PlayerStatsText.plays(video.playCount))
                        .font(.srSubheadlineStrong)
                        .foregroundStyle(Color.srOnDark)
                    Text(progressLine)
                        .font(.srFootnote)
                        .foregroundStyle(Color.srOnDarkSecondary)
                }
                Spacer(minLength: Space.xs)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.srOnDarkTertiary)
            }
            .padding(Space.s)
            .background(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).fill(Color.srInkRaised))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the stats for this recording")
    }

    private var progressLine: String {
        let watched = "\(PlayerStatsText.percent(video.furthestProgress)) watched"
        return "\(watched) · \(PlayerStatsText.shares(video.shareCount))"
    }
}

/// Shared wording for play and share counts.
enum PlayerStatsText {
    static func plays(_ count: Int) -> String {
        switch count {
        case 0: return "Not played yet"
        case 1: return "Played once"
        default: return "Played \(count) times"
        }
    }

    static func shares(_ count: Int) -> String {
        switch count {
        case 0: return "not shared yet"
        case 1: return "shared once"
        default: return "shared \(count) times"
        }
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((min(1, max(0, fraction)) * 100).rounded()))%"
    }
}

/// The expanded details: summary (only when the on-device model wrote one), then the facts.
struct PlayerFactsCard: View {
    let video: Video
    let folderName: String?
    let transcript: Transcript?
    let isSummarizing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if let summary = transcript?.summary {
                PlayerSummaryBlock(text: summary)
            } else if isSummarizing {
                PlayerSummaryPending()
            }
            VStack(spacing: 0) {
                FactRow(title: "Type", value: kindValue)
                FactRow(title: video.kind == .imported ? "Added" : "Recorded", value: Format.dateTime(video.createdAt))
                FactRow(title: "Length", value: Format.clock(video.duration))
                FactRow(title: "Resolution", value: Format.resolution(width: video.pixelWidth, height: video.pixelHeight))
                FactRow(title: "File size", value: Format.bytes(video.fileSize))
                FactRow(title: "Folder", value: folderName ?? "Not in a folder")
                tagsRow
            }
            .padding(.horizontal, Space.m)
            .background(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(Color.srInkRaised))
        }
    }

    private var kindValue: String {
        switch video.kind {
        case .camera: return "Camera recording"
        case .screen: return "Screen recording"
        case .audio: return "Audio recording"
        case .imported: return "Imported from Photos"
        }
    }

    private var tagsRow: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("Tags")
                .font(.srSubheadline)
                .foregroundStyle(Color.srOnDarkSecondary)
            if video.tags.isEmpty {
                Text("No tags yet. Add them from the recording in your Library.")
                    .font(.srFootnote)
                    .foregroundStyle(Color.srOnDarkTertiary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.xs) {
                        ForEach(video.tags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.srCaption)
                                .foregroundStyle(Color.srOnDark)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color.srInkControl))
                        }
                    }
                }
            }
        }
        .padding(.vertical, Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct FactRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(Color.srOnDarkSecondary)
            Spacer(minLength: Space.s)
            Text(value)
                .foregroundStyle(Color.srOnDark)
                .multilineTextAlignment(.trailing)
        }
        .font(.srSubheadline)
        .padding(.vertical, Space.s)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.srInkLine).frame(height: 0.5)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The summary written on this iPhone by Apple's on-device model.
struct PlayerSummaryBlock: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Label("Summary", systemImage: "sparkles")
                .font(.srSubheadlineStrong)
                .foregroundStyle(Color.srOnDark)
            Text(text)
                .font(.srCallout)
                .foregroundStyle(Color.srOnDarkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Written on this iPhone from the transcript")
                .font(.srCaption)
                .foregroundStyle(Color.srOnDarkTertiary)
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(Color.srInkRaised))
        .accessibilityElement(children: .combine)
    }
}

/// While the on-device model is writing the summary.
private struct PlayerSummaryPending: View {
    var body: some View {
        HStack(spacing: Space.s) {
            ProgressView()
                .tint(Color.srOnDarkSecondary)
            Text("Writing a summary on this iPhone…")
                .font(.srSubheadline)
                .foregroundStyle(Color.srOnDarkSecondary)
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(Color.srInkRaised))
        .accessibilityElement(children: .combine)
    }
}

/// One of the equal-width action tiles under the title: icon over a short label.
private struct QuickActionChip: View {
    let title: String
    let systemImage: String
    var isOn = false
    let action: @MainActor () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isOn ? Color.srRedGlow : Color.srOnDark)
                Text(title)
                    .font(.srFootnote.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(Color.srOnDark)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).fill(Color.white.opacity(0.09)))
            .overlay(RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
        }
        .buttonStyle(PressScaleStyle(scale: 0.95))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
