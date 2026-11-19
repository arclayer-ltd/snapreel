import SwiftUI

/// What this iPhone knows about a recording: plays, how far you got, last watched, shares,
/// saves to Photos, and the file facts. Counted here and never sent anywhere.
struct PlayerStatsSheet: View {
    let video: Video
    let onClose: @MainActor () -> Void

    private let columns = [GridItem(.flexible(), spacing: Space.s), GridItem(.flexible(), spacing: Space.s)]

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Stats", trailingTitle: "Done", trailingAction: { onClose() }, onStage: true)
            ScrollView {
                VStack(alignment: .leading, spacing: Space.m) {
                    Label("Counted on this iPhone. Nobody else sees these.", systemImage: "lock.fill")
                        .font(.srFootnote)
                        .foregroundStyle(Color.srStageTextSecondary)
                    LazyVGrid(columns: columns, spacing: Space.s) {
                        StatTile(title: "Times played", value: "\(video.playCount)", systemImage: "play.fill")
                        StatTile(title: "Times shared", value: "\(video.shareCount)", systemImage: "square.and.arrow.up")
                        StatTile(title: "Saved to Photos", value: "\(video.photosSaveCount)", systemImage: "photo")
                        StatTile(title: "Last watched", value: lastWatched, systemImage: "clock", isCompact: true)
                    }
                    progressCard
                    facts
                    Text("A play counts each time you start this recording after opening it. Shares count when the share sheet finishes sending. How far through is the furthest point you've reached.")
                        .font(.srFootnote)
                        .foregroundStyle(Color.srStageTextTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Space.gutter)
                .padding(.top, Space.xs)
                .padding(.bottom, Space.xxl)
            }
        }
        .background(Color.srStageRaised.ignoresSafeArea())
    }

    private var lastWatched: String {
        guard let date = video.lastWatchedAt else { return "Not yet" }
        return Format.age(date)
    }

    private var progressCard: some View {
        let fraction = min(1, max(0, video.furthestProgress))
        return VStack(alignment: .leading, spacing: Space.s) {
            Text("How far through")
                .font(.srSubheadline)
                .foregroundStyle(Color.srStageTextSecondary)
            Text(PlayerStatsText.percent(fraction))
                .font(.srStat)
                .foregroundStyle(Color.srStageText)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.srStageText.opacity(0.12))
                    Capsule().fill(Color.srRed)
                        .frame(width: max(fraction > 0 ? 8 : 0, proxy.size.width * CGFloat(fraction)))
                }
            }
            .frame(height: 8)
            Text(progressCaption(fraction))
                .font(.srFootnote)
                .foregroundStyle(Color.srStageTextTertiary)
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(Color.srStageControl))
        .accessibilityElement(children: .combine)
    }

    private func progressCaption(_ fraction: Double) -> String {
        if fraction >= 0.999 { return "You've watched it to the end." }
        if fraction <= 0 { return "You haven't watched any of it yet." }
        return "Furthest point: \(Format.clock(fraction * video.duration)) of \(Format.clock(video.duration))."
    }

    private var facts: some View {
        VStack(spacing: 0) {
            StatFactRow(title: "Length", value: Format.clock(video.duration))
            StatFactRow(title: "File size", value: Format.bytes(video.fileSize))
            StatFactRow(title: "Resolution", value: Format.resolution(width: video.pixelWidth, height: video.pixelHeight))
            StatFactRow(title: video.kind == .imported ? "Added" : "Recorded", value: Format.dateTime(video.createdAt))
        }
        .padding(.horizontal, Space.m)
        .background(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(Color.srStageControl))
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let systemImage: String
    var isCompact = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Label(title, systemImage: systemImage)
                .font(.srFootnote)
                .foregroundStyle(Color.srStageTextSecondary)
            Text(value)
                .font(isCompact ? Font.srTitle : Font.srStat)
                .foregroundStyle(Color.srStageText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(Color.srStageControl))
        .accessibilityElement(children: .combine)
    }
}

private struct StatFactRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title).foregroundStyle(Color.srStageTextSecondary)
            Spacer(minLength: Space.s)
            Text(value).foregroundStyle(Color.srStageText).multilineTextAlignment(.trailing)
        }
        .font(.srSubheadline)
        .padding(.vertical, Space.s)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.srStageLine).frame(height: 0.5) }
        .accessibilityElement(children: .combine)
    }
}
