import LinkPresentation
import SwiftUI
import UIKit

// MARK: - .shareVideo

/// `.shareVideo($video)`: presents the system share sheet with the recording's file.
struct ShareVideoModifier: ViewModifier {
    @Binding var video: Video?

    @EnvironmentObject private var library: Library
    /// The video whose share sheet is up, so a repeated request for it is ignored.
    @State private var activeID: UUID?
    @State private var toast: ToastMessage?

    func body(content: Content) -> some View {
        content
            .toast($toast, bottomInset: Space.xl)
            .onAppear { startIfRequested() }
            .onChange(of: video?.id) { _ in startIfRequested() }
    }

    private func startIfRequested() {
        guard let requested = video, activeID != requested.id else { return }
        activeID = requested.id
        let current = library.video(requested.id) ?? requested
        let source = library.fileURL(for: current)
        guard FileManager.default.fileExists(atPath: source.path) else {
            Haptics.error()
            toast = ToastMessage(text: "This recording's file is missing", systemImage: "exclamationmark.circle.fill")
            finish()
            return
        }
        Haptics.tap()
        let shared = ShareFile.prepare(source, title: current.title, root: library.media.root)
        let item = ShareItemSource(fileURL: shared,
                                   title: current.title,
                                   thumbnailURL: library.thumbnailURL(for: current),
                                   isAudio: current.isAudioOnly)
        let videoID = current.id
        let store = library
        ShareSheetPresenter.present(item: item, onComplete: { activity in
            // "Save Video" in the share sheet puts it in Photos; count it there, not as a share.
            if activity == .saveToCameraRoll {
                store.recordSavedToPhotos(videoID)
            } else {
                store.recordShare(videoID)
            }
            Haptics.success()
        }, onDismiss: {
            finish()
        })
    }

    private func finish() {
        activeID = nil
        video = nil
    }
}

// MARK: - Presenting UIActivityViewController

/// Presents the share sheet from the topmost view controller of the key window, so it works
/// from tab roots, sheets, the player and the recorder (both full-screen covers).
@MainActor
enum ShareSheetPresenter {
    /// - Parameters:
    ///   - onComplete: called for each activity that finished (AirDrop can finish several times
    ///     while the sheet stays open).
    ///   - onDismiss: called once, when the sheet has gone (or could not be shown).
    static func present(item: ShareItemSource,
                        onComplete: @escaping @MainActor (UIActivity.ActivityType?) -> Void,
                        onDismiss: @escaping @MainActor () -> Void) {
        let controller = UIActivityViewController(activityItems: [item], applicationActivities: nil)
        controller.excludedActivityTypes = [.assignToContact, .addToReadingList, .print, .openInIBooks, .markupAsPDF]
        let session = ShareSession(onComplete: onComplete, onDismiss: onDismiss)
        controller.completionWithItemsHandler = { [weak controller] activity, completed, _, _ in
            Task { @MainActor in
                session.handle(activity: activity, completed: completed, controller: controller)
            }
        }
        Task { @MainActor in
            // Let a sheet or menu that the caller closed in the same action start closing first,
            // so the share sheet isn't presented on top of something that is going away.
            try? await Task.sleep(nanoseconds: 120_000_000)
            await presentWhenReady(controller, session: session)
        }
    }

    private static func presentWhenReady(_ controller: UIViewController, session: ShareSession) async {
        for _ in 0..<25 {
            if let top = topViewController(), !top.isBeingPresented, !top.isBeingDismissed,
               top.transitionCoordinator == nil, top.viewIfLoaded?.window != nil {
                if let popover = controller.popoverPresentationController {
                    popover.sourceView = top.view
                    popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.maxY, width: 0, height: 0)
                    popover.permittedArrowDirections = []
                }
                top.present(controller, animated: true)
                return
            }
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
        // Nothing could present it (no window yet, or a transition that never ended).
        session.finish()
    }

    static func topViewController() -> UIViewController? {
        guard let window = keyWindow else { return nil }
        var top = window.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }

    static var keyWindow: UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let active = scenes.filter { $0.activationState == .foregroundActive }
        for scene in active + scenes {
            if let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first {
                return window
            }
        }
        return nil
    }
}

/// Tracks one share sheet from presentation to dismissal.
@MainActor
final class ShareSession {
    private let onComplete: @MainActor (UIActivity.ActivityType?) -> Void
    private let onDismiss: @MainActor () -> Void
    private var isFinished = false

    init(onComplete: @escaping @MainActor (UIActivity.ActivityType?) -> Void,
         onDismiss: @escaping @MainActor () -> Void) {
        self.onComplete = onComplete
        self.onDismiss = onDismiss
    }

    func handle(activity: UIActivity.ActivityType?, completed: Bool, controller: UIViewController?) {
        if completed { onComplete(activity) }
        // No activity: the person closed the sheet.
        if activity == nil {
            finish()
            return
        }
        // After an activity the sheet either closes by itself or stays open (AirDrop).
        Task { @MainActor [weak controller] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            if controller?.presentingViewController == nil { self.finish() }
        }
    }

    func finish() {
        guard !isFinished else { return }
        isFinished = true
        onDismiss()
    }
}

/// The file plus the title and thumbnail the share sheet shows in its header.
final class ShareItemSource: NSObject, UIActivityItemSource {
    private let fileURL: URL
    private let title: String
    private let thumbnailURL: URL?
    private let isAudio: Bool

    init(fileURL: URL, title: String, thumbnailURL: URL?, isAudio: Bool) {
        self.fileURL = fileURL
        self.title = title
        self.thumbnailURL = thumbnailURL
        self.isAudio = isAudio
        super.init()
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        fileURL
    }

    func activityViewController(_ activityViewController: UIActivityViewController,
                                itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        fileURL
    }

    func activityViewController(_ activityViewController: UIActivityViewController,
                                subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        title
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = title
        if let thumbnailURL, FileManager.default.fileExists(atPath: thumbnailURL.path),
           let provider = NSItemProvider(contentsOf: thumbnailURL) {
            metadata.iconProvider = provider
        } else if let symbol = UIImage(systemName: isAudio ? "waveform" : "video.fill") {
            metadata.iconProvider = NSItemProvider(object: symbol)
        }
        return metadata
    }
}

// MARK: - Shared file names

/// Recordings are stored as "<id>.mp4". Before sharing, Snapreel makes a hard link named after
/// the title ("Checkout flow walkthrough.mp4"), so whoever receives it sees a real name. A hard
/// link takes no extra space and leaves the original untouched.
enum ShareFile {
    static func directory(root: URL) -> URL {
        root.appendingPathComponent("Sharing", isDirectory: true)
    }

    /// A link to `source` named after `title`, or `source` itself if a link can't be made.
    static func prepare(_ source: URL, title: String, root: URL) -> URL {
        let fm = FileManager.default
        let folder = directory(root: root).appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let target = folder.appendingPathComponent(fileName(for: title, pathExtension: source.pathExtension))
            try fm.linkItem(at: source, to: target)
            return target
        } catch {
            try? fm.removeItem(at: folder)
            return source
        }
    }

    /// "Bug: map pins jump on zoom" → "Bug map pins jump on zoom.mp4".
    static func fileName(for title: String, pathExtension: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
            .union(.newlines)
            .union(.controlCharacters)
        var name = title.components(separatedBy: invalid).joined(separator: " ")
        while name.contains("  ") { name = name.replacingOccurrences(of: "  ", with: " ") }
        name = name.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".")))
        if name.count > 80 { name = String(name.prefix(80)).trimmingCharacters(in: .whitespaces) }
        if name.isEmpty { name = "Snapreel recording" }
        return pathExtension.isEmpty ? name : "\(name).\(pathExtension)"
    }

    /// Removes links left from shares that finished more than `age` seconds ago. A leftover
    /// link would keep a deleted recording's space in use, so this runs on every foreground.
    static func cleanUp(olderThan age: TimeInterval, root: URL) {
        let fm = FileManager.default
        let folder = directory(root: root)
        guard let items = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey]) else { return }
        let cutoff = Date().addingTimeInterval(-age)
        for item in items {
            let created = (try? item.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            if created < cutoff { try? fm.removeItem(at: item) }
        }
    }

    static func removeAll(root: URL) {
        try? FileManager.default.removeItem(at: directory(root: root))
    }
}
