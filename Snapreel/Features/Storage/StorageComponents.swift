import SwiftUI

// MARK: - Usage card

/// "Snapreel uses 2.1 GB of 128 GB" with a bar: Snapreel (red), everything else (grey), free.
struct StorageUsageCard: View {
    let snapreelBytes: Int64
    let disk: DiskUsageSnapshot

    private var otherBytes: Int64 { max(0, disk.total - disk.free - snapreelBytes) }
    private var isLow: Bool { disk.free > 0 && disk.free < DiskSpace.lowThreshold }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Snapreel uses \(Format.bytes(snapreelBytes))")
                    .font(.srTitle3)
                    .foregroundStyle(Color.srText)
                Text(disk.total > 0 ? "of \(Format.bytes(disk.total)) on this iPhone" : "on this iPhone")
                    .font(.srSubheadline)
                    .foregroundStyle(Color.srTextSecondary)
            }
            .accessibilityElement(children: .combine)
            if disk.total > 0 {
                StorageBar(snapreel: snapreelBytes, other: otherBytes, free: disk.free)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Snapreel \(Format.bytes(snapreelBytes)), other apps and iOS \(Format.bytes(otherBytes)), free \(Format.bytes(disk.free))")
                VStack(spacing: Space.xs) {
                    legendRow(color: .srRed, title: "Snapreel recordings", value: snapreelBytes)
                    legendRow(color: .srTextTertiary, title: "Other apps and iOS", value: otherBytes)
                    legendRow(color: .srFill, title: "Free", value: disk.free, outlined: true)
                }
                .accessibilityHidden(true)
            }
            if isLow {
                lowSpaceNote
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srCard()
    }

    private func legendRow(color: Color, title: String, value: Int64, outlined: Bool = false) -> some View {
        HStack(spacing: Space.xs) {
            Circle()
                .fill(color)
                .overlay(Circle().strokeBorder(outlined ? Color.srLine : Color.clear, lineWidth: 1))
                .frame(width: 10, height: 10)
            Text(title)
                .font(.srSubheadline)
                .foregroundStyle(Color.srText)
            Spacer(minLength: Space.xs)
            Text(Format.bytes(value))
                .font(.srSubheadline)
                .monospacedDigit()
                .foregroundStyle(Color.srTextSecondary)
        }
    }

    private var lowSpaceNote: some View {
        HStack(alignment: .top, spacing: Space.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.srRed)
            Text("Your iPhone is almost full. New recordings may not save until you free up some space.")
                .font(.srFootnote)
                .foregroundStyle(Color.srText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).fill(Color.srRedSoft))
        .accessibilityElement(children: .combine)
    }
}

/// Three-part capacity bar. Each used part keeps a minimum width so a small share stays visible.
struct StorageBar: View {
    let snapreel: Int64
    let other: Int64
    let free: Int64

    private let gap: CGFloat = 2
    private let minimum: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            let widths = segmentWidths(total: proxy.size.width)
            HStack(spacing: gap) {
                Rectangle().fill(Color.srRed).frame(width: widths.snapreel)
                Rectangle().fill(Color.srTextTertiary).frame(width: widths.other)
                Rectangle().fill(Color.srFill).frame(width: widths.free)
            }
        }
        .frame(height: 14)
        .clipShape(Capsule())
    }

    private func segmentWidths(total width: CGFloat) -> (snapreel: CGFloat, other: CGFloat, free: CGFloat) {
        let sum = Double(max(1, snapreel + other + free))
        let usable = max(0, width - gap * 2)
        let snapreelShare = CGFloat(Double(snapreel) / sum)
        let otherShare = CGFloat(Double(other) / sum)
        let red: CGFloat = snapreel > 0 ? max(minimum, usable * snapreelShare) : 0
        let grey: CGFloat = other > 0 ? max(minimum, usable * otherShare) : 0
        let rest: CGFloat = max(0, usable - red - grey)
        return (red, grey, rest)
    }
}

// MARK: - Kind tile

struct StorageKindTile: View {
    let kind: RecordingKind
    let count: Int
    let bytes: Int64

    var body: some View {
        HStack(spacing: Space.s) {
            IconTile(systemName: kind.systemImage, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.label)
                    .font(.srSubheadlineStrong)
                    .foregroundStyle(Color.srText)
                Text(count == 0 ? "None" : "\(count) \u{00B7} \(Format.bytes(bytes))")
                    .font(.srFootnote)
                    .foregroundStyle(Color.srTextSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).fill(Color.srCanvas))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(count == 0
                            ? "\(kind.label): no recordings"
                            : "\(kind.label): \(count) \(count == 1 ? "recording" : "recordings"), \(Format.bytes(bytes))")
    }
}

// MARK: - Largest recording row

@MainActor
struct LargestVideoRow: View {
    let video: Video
    let onDelete: @MainActor () -> Void

    var body: some View {
        HStack(spacing: Space.s) {
            VideoThumbnail(video: video, cornerRadius: Radius.s, showsDuration: false)
                .frame(width: 72)
            VStack(alignment: .leading, spacing: 2) {
                Text(video.title)
                    .font(.srSubheadlineStrong)
                    .foregroundStyle(Color.srText)
                    .lineLimit(2)
                Text("\(Format.clock(video.duration)) \u{00B7} \(Format.date(video.createdAt))")
                    .font(.srFootnote)
                    .foregroundStyle(Color.srTextSecondary)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: Space.xs)
            Text(Format.bytes(video.fileSize))
                .font(.srSubheadlineStrong)
                .monospacedDigit()
                .foregroundStyle(Color.srText)
            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.srRedText)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.srRedSoft))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Delete \(video.title)")
        }
        .padding(.vertical, Space.xxs)
    }
}
