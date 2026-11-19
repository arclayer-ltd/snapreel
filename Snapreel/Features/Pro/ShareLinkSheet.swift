import SwiftUI

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
                        actions
                    }
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.xl)
                .animation(Motion.standard, value: state)
            }
        }
        .background(Color.srCanvas.ignoresSafeArea())
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

    private var title: String {
        switch state {
        case .creating: return "Making your link"
        case .failed: return link == nil ? "No link yet" : "Link copied"
        case .notShared: return "Share a link"
        default: return "Link copied"
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
        parts.append(AuthService.shared.isPro ? "1080p" : "720p")
        return parts.joined(separator: " · ")
    }

    private func linkField(_ link: CloudLink) -> some View {
        HStack(spacing: Space.s) {
            Image(systemName: "link")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.srRed)
            Text(verbatim: link.url.replacingOccurrences(of: "https://", with: ""))
                .font(.srBody.monospaced())
                .foregroundStyle(Color.srText)
                .lineLimit(1)
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
            progressCard(title: "Preparing the video", fraction: nil,
                         message: "Making a web copy. You can paste the link now: it plays as soon as the upload finishes.")
        case .uploading(let fraction):
            progressCard(title: "Uploading \(Int((fraction * 100).rounded()))%", fraction: fraction,
                         message: "You can paste the link now. It plays as soon as the upload finishes, and carries on if you leave Snapreel.")
        case .waitingForNetwork(let fraction):
            VStack(alignment: .leading, spacing: Space.s) {
                statusRow(systemImage: "wifi.slash", tint: .srTextSecondary, title: "Waiting for a connection",
                          message: "The upload carries on by itself when you're back online.")
                LinkProgressBar(fraction: fraction)
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
                if CloudConfig.isConfigured {
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

    private func progressCard(title: String, fraction: Double?, message: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
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
            Text(message)
                .font(.srFootnote)
                .foregroundStyle(Color.srTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
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
