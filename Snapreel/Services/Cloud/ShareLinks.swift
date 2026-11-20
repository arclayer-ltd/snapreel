import SafariServices
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Where a recording's share link is, as the share-link sheet and cards show it.
enum LinkState: Equatable {
    case notShared
    /// Asking snapreel.video for the link (a quarter of a second, usually).
    case creating
    /// The link exists and is copied; the web copy is being made.
    case preparing
    case uploading(Double)
    case waitingForNetwork(Double)
    /// All files are up; the server is checking them.
    case finishing
    case ready
    case failed(String)

    var isWorking: Bool {
        switch self {
        case .creating, .preparing, .uploading, .waitingForNetwork, .finishing: return true
        case .notShared, .ready, .failed: return false
        }
    }
}

/// Copy link, the Loom way: the link is created at once (`POST /api/videos`) and goes on the
/// clipboard straight away, with an HTML version carrying a preview picture for Mail; the
/// upload follows in the background and the watch page says "Uploading" until it can play.
///
/// Also keeps this iPhone's copy of your links (`CloudLink` in the library) in step with the
/// server, and handles the limits: a recording over 5 minutes or a 26th link on Free opens
/// the paywall.
@MainActor
final class ShareLinks: ObservableObject {
    static let shared = ShareLinks()

    /// Links being created right now.
    @Published private(set) var creating: Set<UUID> = []
    /// Why creating a link failed, until the next try.
    @Published private(set) var createErrors: [UUID: String] = [:]

    #if DEBUG
    /// Fixture screens: states to show instead of the real ones.
    @Published var debugStates: [UUID: LinkState] = [:]
    #endif

    private var lastRefresh: Date?
    private var library: Library { AppEnvironment.shared.library }

    private init() {}

    // MARK: - State

    func state(for videoID: UUID) -> LinkState {
        #if DEBUG
        if let state = debugStates[videoID] { return state }
        #endif
        if creating.contains(videoID) { return .creating }
        if let message = createErrors[videoID] { return .failed(message) }
        guard let link = library.link(for: videoID) else { return .notShared }
        if let phase = Uploader.shared.phase(for: videoID) {
            switch phase {
            case .preparing: return .preparing
            case .uploading(let value): return .uploading(value)
            case .waitingForNetwork(let value): return .waitingForNetwork(value)
            case .finishing: return .finishing
            case .failed(let message): return .failed(message)
            case .done: return .ready
            }
        }
        switch link.status {
        case .ready: return .ready
        case .failed: return .failed("The upload didn't finish.")
        case .uploading:
            // No job on this iPhone: the upload was interrupted for good (or happened elsewhere).
            return library.video(videoID) == nil ? .finishing : .failed("The upload didn't finish.")
        }
    }

    // MARK: - Copy link

    /// The Copy link button: signs in first if needed, checks the plan's limits, creates the
    /// link, copies it, shows the share-link sheet and starts the upload.
    func copyLink(_ videoID: UUID) {
        guard let video = library.video(videoID) else { return }
        guard video.state.isReady else {
            AppEnvironment.shared.router.showToast("Still saving. Try again in a moment.", systemImage: "hourglass")
            return
        }
        if let link = library.link(for: videoID) {
            copyToPasteboard(link, video: video)
            Haptics.success()
            ProPresenter.shareLink(videoID)
            if case .failed = state(for: videoID), Uploader.shared.jobs[videoID] == nil {
                reupload(videoID)
            }
            return
        }
        guard CloudConfig.isConfigured else {
            createErrors[videoID] = CloudError.notConfigured.message
            ProPresenter.shareLink(videoID)
            return
        }
        guard AuthService.shared.isSignedIn else {
            ProPresenter.signIn(reason: .link) { signedIn in
                if signedIn { ShareLinks.shared.copyLink(videoID) }
            }
            return
        }
        let auth = AuthService.shared
        if !auth.isPro {
            let maxDuration = auth.me?.usage.maxDurationS ?? CloudConfig.freeMaxDuration
            if video.duration > maxDuration + 0.5 {
                ProPresenter.paywall(.duration(video.duration))
                return
            }
            if let usage = auth.me?.usage, let limit = usage.linkLimit, usage.activeLinks >= limit {
                ProPresenter.paywall(.links)
                return
            }
        }
        create(video)
    }

    private func create(_ video: Video) {
        let id = video.id
        createErrors[id] = nil
        creating.insert(id)
        ProPresenter.shareLink(id)
        let request = CreateVideoRequest(localId: id.uuidString.lowercased(), title: video.title,
                                         kind: CloudVideoKind(video.kind), durationS: video.duration,
                                         width: video.pixelWidth, height: video.pixelHeight,
                                         sizeBytes: video.fileSize,
                                         transcript: library.transcript(for: id).map(CloudTranscript.init))
        Task { @MainActor in
            do {
                let created = try await APIClient.shared.createVideo(request)
                let link = CloudLink(videoID: id, created: created, title: video.title, durationS: video.duration)
                self.library.saveLink(link)
                self.creating.remove(id)
                self.copyToPasteboard(link, video: video)
                Haptics.success()
                if created.status != .ready {
                    Uploader.shared.start(video: video, source: self.library.fileURL(for: video), link: created)
                }
                await AuthService.shared.refreshMe()
            } catch CloudError.limit(let reason) {
                self.creating.remove(id)
                ProPresenter.dismissShareLink()
                switch reason {
                case .links: ProPresenter.paywall(.links)
                case .duration: ProPresenter.paywall(.duration(video.duration))
                case .proFeature: ProPresenter.paywall(.settings)
                }
            } catch CloudError.signedOut {
                self.creating.remove(id)
                ProPresenter.dismissShareLink()
                ProPresenter.signIn(reason: .link) { signedIn in
                    if signedIn { ShareLinks.shared.copyLink(id) }
                }
            } catch {
                self.creating.remove(id)
                self.createErrors[id] = (error as? CloudError)?.message ?? CloudError.offline.message
                Haptics.error()
            }
        }
    }

    /// Try again after a failure: create the link again if there's none, otherwise restart
    /// the upload.
    func retry(_ videoID: UUID) {
        createErrors[videoID] = nil
        if library.link(for: videoID) == nil {
            copyLink(videoID)
        } else if Uploader.shared.jobs[videoID] != nil {
            Uploader.shared.retry(videoID, library: library)
        } else {
            reupload(videoID)
        }
    }

    /// The link exists but this iPhone has no upload for it: `POST /api/videos` again returns
    /// the same link with fresh upload paths, then the upload starts over.
    func reupload(_ videoID: UUID) {
        guard let video = library.video(videoID), !creating.contains(videoID) else { return }
        creating.insert(videoID)
        let request = CreateVideoRequest(localId: videoID.uuidString.lowercased(), title: video.title,
                                         kind: CloudVideoKind(video.kind), durationS: video.duration,
                                         width: video.pixelWidth, height: video.pixelHeight,
                                         sizeBytes: video.fileSize, transcript: nil)
        Task { @MainActor in
            defer { self.creating.remove(videoID) }
            do {
                let created = try await APIClient.shared.createVideo(request)
                self.library.updateLink(videoID) { $0.status = created.status }
                Uploader.shared.start(video: video, source: self.library.fileURL(for: video), link: created)
            } catch {
                self.createErrors[videoID] = (error as? CloudError)?.message ?? CloudError.offline.message
            }
        }
    }

    // MARK: - Clipboard

    /// The plain link, plus an HTML version with the preview picture, so a paste into Mail
    /// shows the picture and a paste anywhere else shows the link.
    func copyToPasteboard(_ link: CloudLink, video: Video?) {
        guard let url = link.linkURL else { return }
        var item: [String: Any] = [
            UTType.url.identifier: url,
            UTType.plainText.identifier: url.absoluteString,
        ]
        if let html = Self.html(for: link, video: video) {
            item[UTType.html.identifier] = html
        }
        UIPasteboard.general.setItems([item])
    }

    /// `<a href=link><img preview> Title · 2:05</a>`. The picture is the recording's own
    /// thumbnail with a play button, embedded in the HTML, so it needs nothing from the server.
    static func html(for link: CloudLink, video: Video?) -> String? {
        let title = escape(video?.title ?? link.title)
        let duration = video.map { Format.clock($0.duration) } ?? link.durationS.map(Format.clock) ?? ""
        var picture = ""
        if let video, let data = previewImageData(for: video) {
            picture = "<img src=\"data:image/jpeg;base64,\(data.base64EncodedString())\" alt=\"\(title)\" width=\"480\" style=\"display:block;max-width:100%;border-radius:12px\"><br>"
        }
        return """
        <a href="\(link.url)" style="text-decoration:none;color:inherit">\(picture)<b>\(title)</b>\(duration.isEmpty ? "" : " · \(duration)")</a><br><a href="\(link.url)">\(link.url)</a>
        """
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// The thumbnail at 480 px wide with a round play button over it (a drawn card for voice
    /// recordings).
    private static func previewImageData(for video: Video) -> Data? {
        let library = AppEnvironment.shared.library
        let base: UIImage
        if let url = library.thumbnailURL(for: video), let image = UIImage(contentsOfFile: url.path) {
            base = image
        } else {
            base = WebExport.audioCard(title: video.title, duration: video.duration, size: CGSize(width: 960, height: 540))
        }
        let width: CGFloat = 480
        let height = min(640, width * base.size.height / max(1, base.size.width))
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let scale = max(size.width / base.size.width, size.height / base.size.height)
            let drawn = CGSize(width: base.size.width * scale, height: base.size.height * scale)
            base.draw(in: CGRect(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2,
                                 width: drawn.width, height: drawn.height))
            let cg = context.cgContext
            let diameter: CGFloat = 72
            let circle = CGRect(x: (size.width - diameter) / 2, y: (size.height - diameter) / 2,
                                width: diameter, height: diameter)
            cg.setFillColor(UIColor(hex: 0xF04850).cgColor)
            cg.fillEllipse(in: circle)
            let triangle = UIBezierPath()
            triangle.move(to: CGPoint(x: circle.midX - 10, y: circle.midY - 15))
            triangle.addLine(to: CGPoint(x: circle.midX + 16, y: circle.midY))
            triangle.addLine(to: CGPoint(x: circle.midX - 10, y: circle.midY + 15))
            triangle.close()
            cg.setFillColor(UIColor.white.cgColor)
            cg.addPath(triangle.cgPath)
            cg.fillPath()
        }
        return image.jpegData(compressionQuality: 0.72)
    }

    // MARK: - Open and share

    /// Opens the watch page in Safari inside Snapreel (a plain open would come straight back
    /// to Snapreel through the universal link).
    func open(_ link: CloudLink) {
        guard let url = link.linkURL else { return }
        Self.openInSafari(url)
    }

    static func openInSafari(_ url: URL) {
        let safari = SFSafariViewController(url: url)
        safari.preferredControlTintColor = UIColor.srRed
        Task { @MainActor in
            for _ in 0..<20 {
                if let top = ShareSheetPresenter.topViewController(), !top.isBeingPresented, !top.isBeingDismissed {
                    top.present(safari, animated: true)
                    return
                }
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
        }
    }

    /// The system share sheet with the link (not the file).
    func shareURL(_ link: CloudLink) {
        guard let url = link.linkURL else { return }
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        Task { @MainActor in
            if let top = ShareSheetPresenter.topViewController() {
                if let popover = controller.popoverPresentationController {
                    popover.sourceView = top.view
                    popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.maxY, width: 0, height: 0)
                }
                top.present(controller, animated: true)
            }
        }
    }

    // MARK: - Stop sharing

    /// Deletes the link and its files on snapreel.video. The recording stays on this iPhone.
    func stopSharing(_ videoID: UUID) async throws {
        guard let link = library.link(for: videoID) else { return }
        Uploader.shared.cancel(videoID)
        do {
            try await APIClient.shared.deleteVideo(link.serverID)
        } catch CloudError.notFound {
            // Already gone.
        }
        library.removeLink(videoID)
        await AuthService.shared.refreshMe()
    }

    // MARK: - Keeping in step with the server

    /// Reloads your links (`GET /api/videos`) at most once a minute unless `force`.
    func refresh(force: Bool = false) async {
        guard CloudConfig.isConfigured, AuthService.shared.isSignedIn else { return }
        if !force, let lastRefresh, Date().timeIntervalSince(lastRefresh) < 60 { return }
        lastRefresh = Date()
        guard let summaries = try? await APIClient.shared.videos() else { return }
        var seen = Set<UUID>()
        for summary in summaries {
            guard let id = UUID(uuidString: summary.localId) else { continue }
            seen.insert(id)
            if var link = library.link(for: id) {
                link.apply(summary)
                library.saveLink(link)
            } else {
                library.saveLink(CloudLink(videoID: id, summary: summary))
            }
        }
        // Links deleted on the web (or expired and removed) go here too.
        for link in library.sortedLinks where !seen.contains(link.videoID) {
            if creating.contains(link.videoID) || Uploader.shared.jobs[link.videoID] != nil { continue }
            library.removeLink(link.videoID)
        }
    }

    /// Reloads one link with its settings.
    @discardableResult
    func refreshDetail(_ videoID: UUID) async -> VideoDetail? {
        guard let link = library.link(for: videoID) else { return nil }
        do {
            let detail = try await APIClient.shared.video(link.serverID)
            library.updateLink(videoID) { $0.apply(detail) }
            return detail
        } catch CloudError.notFound {
            library.removeLink(videoID)
            return nil
        } catch {
            return nil
        }
    }

    /// Saves link settings and keeps the new values here.
    func update(_ videoID: UUID, _ change: UpdateVideoRequest) async throws {
        guard let link = library.link(for: videoID), !change.isEmpty else { return }
        let detail = try await APIClient.shared.updateVideo(link.serverID, change)
        library.updateLink(videoID) { $0.apply(detail) }
    }

    // MARK: - Upload results (from the uploader)

    func uploadFinished(_ videoID: UUID, detail: VideoDetail) {
        library.updateLink(videoID) { $0.apply(detail) }
        let title = library.video(videoID)?.title ?? detail.title
        Notifier.shared.post(.uploadFinished, title: "Your link is ready",
                             body: "\u{201C}\(title)\u{201D} can be watched now.", videoID: videoID)
    }

    func uploadFailed(_ videoID: UUID, message: String) {
        let title = library.video(videoID)?.title ?? library.link(for: videoID)?.title ?? "Your recording"
        Notifier.shared.post(.uploadFailed, title: "Upload stopped",
                             body: "\u{201C}\(title)\u{201D}: \(message)", videoID: videoID)
    }
}
