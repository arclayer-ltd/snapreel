import SwiftUI

/// Settings › Account › Shared links: uploads that are running, waiting or stopped (with Try
/// again), then every share link with its views and comments. A link opens its settings.
struct SharedLinksView: View {
    @EnvironmentObject private var library: Library
    @ObservedObject private var uploader = Uploader.shared
    @ObservedObject private var links = ShareLinks.shared
    @ObservedObject private var auth = AuthService.shared

    /// Uploads to list: running or stopped ones, and those finished in the last day.
    private var uploads: [UUID] {
        var ids = uploader.sortedJobs.map(\.videoID)
        #if DEBUG
        for id in uploader.debugPhases.keys where !ids.contains(id) { ids.append(id) }
        #endif
        return ids.filter { id in
            if case .done? = uploader.phase(for: id) { return library.link(for: id) != nil }
            return true
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                if !uploads.isEmpty {
                    uploadsGroup
                }
                if library.links.isEmpty {
                    EmptyStateView(systemImage: "link",
                                   title: "No share links yet",
                                   message: "Tap Copy link on any recording. Snapreel uploads it and puts a link on your clipboard that plays in any browser.")
                        .padding(.top, Space.xl)
                } else {
                    linksGroup
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.s)
            .padding(.bottom, Space.xxl)
        }
        .background(Color.srCanvas.ignoresSafeArea())
        .navigationTitle("Shared links")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await links.refresh(force: true) }
        .task { await links.refresh() }
    }

    // MARK: Uploads

    private var uploadsGroup: some View {
        SettingsGroup(title: "Uploads",
                      footnote: "Uploads carry on when you leave Snapreel or lock your iPhone, and pick up where they stopped after a lost connection. Preparing a video needs Snapreel open.") {
            ForEach(Array(uploads.enumerated()), id: \.element) { index, id in
                if index > 0 { SettingsDivider(inset: Space.m + 64 + Space.s) }
                UploadRow(videoID: id)
            }
        }
    }

    // MARK: Links

    private var linksGroup: some View {
        SettingsGroup(title: "Your links", footnote: usageNote) {
            ForEach(Array(library.sortedLinks.enumerated()), id: \.element.id) { index, link in
                if index > 0 { SettingsDivider(inset: Space.m + 64 + Space.s) }
                NavigationLink(value: SettingsPage.linkSettings(link.videoID)) {
                    LinkRow(link: link)
                }
                .buttonStyle(SettingsRowStyle())
                .contextMenu {
                    Button {
                        ShareLinks.shared.copyToPasteboard(link, video: library.video(link.videoID))
                        AppEnvironment.shared.router.showToast("Link copied", systemImage: "link")
                    } label: {
                        Label("Copy link", systemImage: "doc.on.doc")
                    }
                    Button {
                        ShareLinks.shared.open(link)
                    } label: {
                        Label("Open in Safari", systemImage: "safari")
                    }
                }
            }
        }
    }

    private var usageNote: String? {
        guard !auth.isPro else { return nil }
        let used = auth.me?.usage.activeLinks ?? library.links.count
        return "\(used) of \(CloudConfig.freeLinkLimit) free links used. Stop sharing one to free a space, or get Pro for unlimited links."
    }
}

/// One upload: thumbnail, title, where it is, a progress bar, and Try again when it stopped.
private struct UploadRow: View {
    let videoID: UUID

    @EnvironmentObject private var library: Library
    @ObservedObject private var uploader = Uploader.shared
    @ObservedObject private var links = ShareLinks.shared

    var body: some View {
        let state = links.state(for: videoID)
        HStack(alignment: .center, spacing: Space.s) {
            thumbnail
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.srSubheadlineStrong)
                    .foregroundStyle(Color.srText)
                    .lineLimit(1)
                Text(label(state))
                    .font(.srFootnote.monospacedDigit())
                    .foregroundStyle(isFailed(state) ? Color.srRedText : Color.srTextSecondary)
                    .lineLimit(3)
                if let fraction = fraction(state) {
                    LinkProgressBar(fraction: fraction)
                }
                if isFailed(state) {
                    // Under the reason, so a long reason keeps the row's width.
                    Button {
                        Haptics.tap()
                        ShareLinks.shared.retry(videoID)
                    } label: {
                        Label("Try again", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.srPrimaryCompact)
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: Space.xs)
            if state == .ready {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.srRed)
            }
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
    }

    private var title: String {
        library.video(videoID)?.title ?? library.link(for: videoID)?.title ?? uploader.jobs[videoID]?.title ?? "Recording"
    }

    @ViewBuilder private var thumbnail: some View {
        if let video = library.video(videoID) {
            VideoThumbnail(video: video, cornerRadius: Radius.s, showsDuration: false)
                .frame(width: 64)
        } else {
            RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
                .fill(Color.srFill)
                .frame(width: 64, height: 36)
                .overlay(Image(systemName: "link").foregroundStyle(Color.srTextTertiary))
        }
    }

    private func isFailed(_ state: LinkState) -> Bool {
        if case .failed = state { return true }
        return false
    }

    private func fraction(_ state: LinkState) -> Double? {
        switch state {
        case .uploading(let value), .waitingForNetwork(let value): return value
        case .preparing: return uploader.progress(for: videoID)?.prepared
        default: return nil
        }
    }

    private func label(_ state: LinkState) -> String {
        switch state {
        case .creating: return "Making the link…"
        case .preparing:
            let progress = uploader.progress(for: videoID)
            return [UploadText.preparing(progress), UploadText.preparingDetail(progress)].compactMap { $0 }.joined(separator: "\n")
        case .uploading(let value):
            return ["Uploading · \(Int((value * 100).rounded()))%", UploadText.uploadingDetail(uploader.progress(for: videoID))]
                .compactMap { $0 }.joined(separator: "\n")
        case .waitingForNetwork(let value):
            return ["Waiting for a connection · \(Int((value * 100).rounded()))%", UploadText.waitingDetail(uploader.progress(for: videoID))]
                .compactMap { $0 }.joined(separator: "\n")
        case .finishing: return "Finishing…"
        case .ready: return "Uploaded · ready to watch"
        case .failed(let message): return message
        case .notShared: return "Not shared"
        }
    }
}

/// One link: thumbnail, title, views, comments and when it was shared.
private struct LinkRow: View {
    let link: CloudLink

    @EnvironmentObject private var library: Library
    @ObservedObject private var links = ShareLinks.shared

    var body: some View {
        HStack(alignment: .center, spacing: Space.s) {
            if let video = library.video(link.videoID) {
                VideoThumbnail(video: video, cornerRadius: Radius.s, showsDuration: false)
                    .frame(width: 64)
            } else {
                RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
                    .fill(Color.srFill)
                    .frame(width: 64, height: 36)
                    .overlay(Image(systemName: "link").foregroundStyle(Color.srTextTertiary))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(link.title)
                    .font(.srSubheadlineStrong)
                    .foregroundStyle(Color.srText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(meta)
                    .font(.srFootnote)
                    .foregroundStyle(Color.srTextSecondary)
                    .lineLimit(1)
                if library.video(link.videoID) == nil {
                    Text("Not on this iPhone")
                        .font(.srCaption)
                        .foregroundStyle(Color.srTextTertiary)
                }
            }
            Spacer(minLength: Space.xs)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.srTextTertiary)
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
        .contentShape(Rectangle())
    }

    private var meta: String {
        var parts = [ProText.views(link.views)]
        if link.commentCount > 0 { parts.append(ProText.comments(link.commentCount)) }
        parts.append(Format.age(link.createdAt))
        return parts.joined(separator: " · ")
    }
}
