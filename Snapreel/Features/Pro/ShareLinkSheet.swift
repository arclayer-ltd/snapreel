import SwiftUI
import UIKit

/// After Copy link: the link (already on the clipboard) and where its upload is. One sheet for
/// every state: creating, uploading with progress, ready (copied, open, share), waiting for
/// the network, and failed with Try again. Link settings open from here.
struct ShareLinkSheet: View {
    let videoID: UUID
    let onClose: @MainActor () -> Void

    @EnvironmentObject private var library: Library
    @ObservedObject private var links = ShareLinks.shared
    @ObservedObject private var uploader = Uploader.shared
    @State private var copiedAgain = false
    /// Changes each time Snapreel comes back to the screen: the sheet is made again (see `body`).
    @State private var comeBack = 0

    private var video: Video? { library.video(videoID) }
    private var link: CloudLink? { library.link(for: videoID) }
    private var state: LinkState { links.state(for: videoID) }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    recordingHeader
                    if let link {
                        linkField(link)
                    }
                    statusCard
                    if link != nil {
                        if case .failed = state {
                            // The link still works for sharing, but says so: nothing plays yet.
                            Text("Anyone who opens the link now sees that the video is still uploading.")
                                .font(.srFootnote)
                                .foregroundStyle(Color.srTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.l)
                // Not on every percent: the numbers would cross-fade.
                .animation(Motion.standard, value: stateKind)
            }
            // Kept under the scrolling part, so at half height they sit above the home bar (they were under it).
            if link != nil {
                actions
                    .padding(.horizontal, Space.gutter)
                    .padding(.top, Space.xs)
                    .padding(.bottom, Space.s)
            }
        }
        // Back from the Home Screen, an open sheet kept showing "Preparing 0%" for good while its numbers moved on
        // underneath (tester t26-link2, iOS 16.4). Making it again draws it again.
        .id(comeBack)
        .background(Color.srCanvas.ignoresSafeArea())
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            comeBack += 1
        }
    }

    // MARK: Parts

    private var topBar: some View {
        HStack {
            Text(title)
                .font(.srTitle3)
                .foregroundStyle(Color.srText)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            CircleIconButton(systemName: "xmark", label: "Close", tone: .light, size: 30) { onClose() }
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.l)
        .padding(.bottom, Space.s)
    }

    /// The state without its numbers.
    private var stateKind: Int {
        switch state {
        case .notShared: return 0
        case .creating: return 1
        case .preparing: return 2
        case .uploading: return 3
        case .waitingForNetwork: return 4
        case .finishing: return 5
        case .ready: return 6
        case .failed: return 7
        }
    }

    /// "Link copied" only right after a copy and while the upload hasn't stopped; opened to check on it, it says so.
    private var title: String {
        switch state {
        case .creating: return "Making your link"
        case .failed: return link == nil ? "No link yet" : "Upload stopped"
        case .notShared: return "Share a link"
        default: return links.wasJustCopied(videoID) ? "Link copied" : "Your link"
        }
    }

    private var recordingHeader: some View {
        HStack(spacing: Space.s) {
            if let video {
                VideoThumbnail(video: video, cornerRadius: Radius.s, showsDuration: false)
                    .frame(width: 84)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(video?.title ?? link?.title ?? "Recording")
                    .font(.srHeadline)
                    .foregroundStyle(Color.srText)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.srFootnote)
                    .foregroundStyle(Color.srTextSecondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let duration = video?.duration ?? link?.durationS { parts.append(Format.clock(duration)) }
        if let link, state == .ready { parts.append(ProText.views(link.views)) }
        if let quality { parts.append(quality) }
        return parts.joined(separator: " · ")
    }

    /// The web copy's size: the recording's own when it is smaller than the plan's, and on Free what Pro would send.
    private var quality: String? {
        guard let video else { return AuthService.shared.isPro ? "1080p" : "720p" }
        guard !video.isAudioOnly else { return nil }
        func lines(longest: Int) -> Int {
            let long = max(video.pixelWidth, video.pixelHeight), short = min(video.pixelWidth, video.pixelHeight)
            guard long > longest else { return short }
            return Int((Double(short) * Double(longest) / Double(long)).rounded())
        }
        let free = lines(longest: 1_280), pro = lines(longest: 1_920)
        if AuthService.shared.isPro { return "\(pro)p" }
        return pro > free ? "\(free)p (\(pro)p with Pro)" : "\(free)p"
    }

    private func linkField(_ link: CloudLink) -> some View {
        HStack(spacing: Space.s) {
            Image(systemName: "link")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.srRed)
            Text(verbatim: link.url.replacingOccurrences(of: "https://", with: ""))
                .font(.srSubheadline.weight(.medium))
                .foregroundStyle(Color.srText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .truncationMode(.middle)
            Spacer(minLength: Space.xs)
            Button {
                ShareLinks.shared.copyToPasteboard(link, video: video)
                Haptics.success()
                withAnimation(Motion.quick) { copiedAgain = true }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_600_000_000)
                    withAnimation(Motion.quick) { copiedAgain = false }
                }
            } label: {
                Label(copiedAgain ? "Copied" : "Copy", systemImage: copiedAgain ? "checkmark" : "doc.on.doc")
                    .font(.srSubheadlineStrong)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, Space.s)
                    .frame(height: 34)
                    .background(Capsule().fill(Color.srRed))
            }
            .buttonStyle(PressScaleStyle())
        }
        .padding(.leading, Space.m)
        .padding(.trailing, Space.xs)
        .frame(height: 52)
        .background(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).fill(Color.srSurface))
        .overlay(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).strokeBorder(Color.srLine, lineWidth: 1))
    }

    @ViewBuilder private var statusCard: some View {
        switch state {
        case .notShared:
            statusRow(systemImage: "link", tint: .srRed, title: "Not shared yet",
                      message: "Copy link uploads this recording to snapreel.video and puts its link on your clipboard.")
            Button("Copy link") { ShareLinks.shared.copyLink(videoID) }
                .buttonStyle(.srPrimary)
        case .creating:
            HStack(spacing: Space.s) {
                ProgressView()
                Text("Asking snapreel.video for a link…")
                    .font(.srSubheadline)
                    .foregroundStyle(Color.srTextSecondary)
            }
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .srCard()
        case .preparing:
            let progress = uploader.progress(for: videoID)
            progressCard(title: UploadText.preparing(progress), fraction: progress?.prepared,
                         detail: UploadText.preparingDetail(progress), retry: progress?.retry,
                         message: "Making a web copy. Keep Snapreel open until this part is done. Paste the link now: it plays once the upload is done.")
        case .uploading(let fraction):
            let progress = uploader.progress(for: videoID)
            progressCard(title: "Uploading \(Int((fraction * 100).rounded()))%", fraction: fraction,
                         detail: UploadText.uploadingDetail(progress), retry: progress?.retry,
                         message: "You can leave Snapreel or lock your iPhone: the upload carries on. The link plays once it's done.")
        case .waitingForNetwork(let fraction):
            VStack(alignment: .leading, spacing: Space.s) {
                statusRow(systemImage: "wifi.slash", tint: .srTextSecondary, title: "Waiting for a connection",
                          message: "What is sent is kept. The upload carries on by itself when you're back online.")
                LinkProgressBar(fraction: fraction)
                if let detail = UploadText.waitingDetail(uploader.progress(for: videoID)) {
                    Text(verbatim: detail)
                        .font(.srFootnote.monospacedDigit())
                        .foregroundStyle(Color.srTextSecondary)
                }
            }
            .padding(Space.m)
            .srCard()
        case .finishing:
            progressCard(title: "Almost there", fraction: 1, message: "Checking the files on snapreel.video.")
        case .ready:
            statusRow(systemImage: "checkmark.circle.fill", tint: .srRed, title: "Ready to watch",
                      message: "Anyone with the link can watch in a browser. No app or account needed.")
                .padding(Space.m)
                .srCard()
        case .failed(let message):
            VStack(alignment: .leading, spacing: Space.s) {
                statusRow(systemImage: "exclamationmark.triangle.fill", tint: .srRedText,
                          title: link == nil ? "Couldn't make the link" : "The upload stopped", message: message)
                Text(UploadText.failureHelp)
                    .font(.srFootnote)
                    .foregroundStyle(Color.srTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                // Nothing to retry while links aren't switched on in this build.
                if link != nil || CloudConfig.isConfigured {
                    Button {
                        Haptics.tap()
                        ShareLinks.shared.retry(videoID)
                    } label: {
                        Label("Try again", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.srPrimaryCompact)
                }
            }
            .padding(Space.m)
            .srCard()
        }
    }

    private func progressCard(title: String, fraction: Double?, detail: String? = nil, retry: UploadRetry? = nil,
                              message: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if let retry {
                // Said first: the numbers below aren't moving while Snapreel waits.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    statusRow(systemImage: retry.reason == .unreachable ? "wifi.exclamationmark" : "exclamationmark.icloud.fill",
                              tint: .srRedText, title: UploadText.retryTitle(retry),
                              message: UploadText.retryDetail(retry, now: context.date))
                }
            }
            HStack(spacing: Space.xs) {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundStyle(Color.srRed)
                Text(title)
                    .font(.srHeadline.monospacedDigit())
                    .foregroundStyle(Color.srText)
                Spacer()
                if fraction == nil { ProgressView() }
            }
            if let fraction { LinkProgressBar(fraction: fraction) }
            if let detail {
                Text(verbatim: detail)
                    .font(.srFootnote.weight(.medium).monospacedDigit())
                    .foregroundStyle(Color.srText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if retry == nil {
                Text(message)
                    .font(.srFootnote)
                    .foregroundStyle(Color.srTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.m)
        .srCard()
    }

    private func statusRow(systemImage: String, tint: Color, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.srHeadline)
                    .foregroundStyle(Color.srText)
                Text(message)
                    .font(.srFootnote)
                    .foregroundStyle(Color.srTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        HStack(spacing: Space.s) {
            ShareLinkAction(title: "Open", systemImage: "safari") {
                if let link { ShareLinks.shared.open(link) }
            }
            ShareLinkAction(title: "Share link", systemImage: "square.and.arrow.up") {
                if let link { ShareLinks.shared.shareURL(link) }
            }
            ShareLinkAction(title: "Settings", systemImage: "slider.horizontal.3") {
                ProPresenter.linkSettings(videoID)
            }
        }
    }
}

private struct ShareLinkAction: View {
    let title: String
    let systemImage: String
    let action: @MainActor () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.srRed)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.srRedSoft))
                Text(title)
                    .font(.srCaption)
                    .foregroundStyle(Color.srText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.s)
            .background(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(Color.srSurface))
            .overlay(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).strokeBorder(Color.srLine, lineWidth: 0.5))
        }
        .buttonStyle(PressScaleStyle(scale: 0.96))
    }
}
