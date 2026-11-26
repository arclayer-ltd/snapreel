import SwiftUI

// Session D. Everything a list can do with one recording: the actions sheet and its follow-ups
// (rename, move, tags, share, save to Photos, delete, retry a failed save). Each screen owns one
// `LibraryActionsModel` and attaches `.libraryVideoActions(model)` once.

/// The sheets a list can show for one recording.
enum LibraryVideoSheet: Identifiable, Equatable {
    case actions(UUID)
    case rename(UUID)
    case move(UUID)
    case tags(UUID)

    var id: String {
        switch self {
        case .actions(let id): return "actions-\(id.uuidString)"
        case .rename(let id): return "rename-\(id.uuidString)"
        case .move(let id): return "move-\(id.uuidString)"
        case .tags(let id): return "tags-\(id.uuidString)"
        }
    }

    var videoID: UUID {
        switch self {
        case .actions(let id), .rename(let id), .move(let id), .tags(let id): return id
        }
    }
}

/// What the actions sheet asks the host to do.
enum LibraryVideoAction {
    case share
    case copyLink
    case saveToPhotos
    case watchLater
    case rename
    case move
    case tags
    case retry
    case delete
    case edit
    case deleteWithEdits
}

@MainActor
final class LibraryActionsModel: ObservableObject {
    @Published var sheet: LibraryVideoSheet?
    @Published var deleteCandidate: UUID?
    @Published var shareTarget: Video?
    @Published var photosTarget: Video?
    @Published var showsStorage = false

    /// Something to start once the sheet on screen has finished going away, so the next sheet
    /// (or the system share sheet) has a clear stage.
    private enum FollowUp {
        case sheet(LibraryVideoSheet)
        case share(Video)
        case copyLink(UUID)
        case photos(Video)
        case delete(UUID, withEdits: Bool)
        case storage
        case edit(UUID)
    }

    private var followUp: FollowUp?

    func showActions(_ id: UUID) {
        open(.actions(id))
    }

    /// Opens `next`, after the sheet already on screen (if any) has gone.
    func open(_ next: LibraryVideoSheet) {
        if sheet == nil {
            sheet = next
        } else {
            followUp = .sheet(next)
            sheet = nil
        }
    }

    func close() {
        sheet = nil
    }

    func share(_ video: Video) {
        if sheet == nil {
            shareTarget = video
        } else {
            followUp = .share(video)
            sheet = nil
        }
    }

    /// Copy link (Snapreel Pro's share links), once the actions sheet has gone.
    func copyLink(_ id: UUID) {
        if sheet == nil {
            ShareLinks.shared.copyLink(id)
        } else {
            followUp = .copyLink(id)
            sheet = nil
        }
    }

    func saveToPhotos(_ video: Video) {
        if sheet == nil {
            photosTarget = video
        } else {
            followUp = .photos(video)
            sheet = nil
        }
    }

    func showStorage() {
        if sheet == nil {
            showsStorage = true
        } else {
            followUp = .storage
            sheet = nil
        }
    }

    /// Asks before deleting (alert on the host).
    func requestDelete(_ id: UUID) {
        deleteCandidate = id
    }

    /// Deletes once the actions sheet (where the person already confirmed) has gone.
    func deleteAfterClosing(_ id: UUID, withEdits: Bool = false, library: Library, router: AppRouter) {
        if sheet == nil {
            performDelete(id, withEdits: withEdits, library: library, router: router)
        } else {
            followUp = .delete(id, withEdits: withEdits)
            sheet = nil
        }
    }

    /// Opens the editor once the actions sheet has gone.
    func edit(_ id: UUID, router: AppRouter) {
        if sheet == nil {
            router.edit(id)
        } else {
            followUp = .edit(id)
            sheet = nil
        }
    }

    func performDelete(_ id: UUID, withEdits: Bool = false, library: Library, router: AppRouter) {
        guard library.video(id) != nil else { return }
        let edits = withEdits ? library.edits(of: id) : []
        for edit in edits { library.delete(edit.id) }
        library.delete(id)
        Haptics.success()
        router.showToast(edits.isEmpty ? "Recording deleted" : "Recording and its edits deleted", systemImage: "trash.fill")
    }

    /// Called by the host when a sheet has been dismissed.
    func sheetDidDismiss(library: Library, router: AppRouter) {
        guard let next = followUp else { return }
        followUp = nil
        switch next {
        case .sheet(let nextSheet): sheet = nextSheet
        case .share(let video): shareTarget = video
        case .copyLink(let id): ShareLinks.shared.copyLink(id)
        case .photos(let video): photosTarget = video
        case .delete(let id, let withEdits): performDelete(id, withEdits: withEdits, library: library, router: router)
        case .storage: showsStorage = true
        case .edit(let id): router.edit(id)
        }
    }

    func toggleWatchLater(_ id: UUID, library: Library, router: AppRouter) {
        library.toggleWatchLater(id)
        let added = library.video(id)?.isInWatchLater == true
        Haptics.success()
        router.showToast(added ? "Added to Watch later" : "Removed from Watch later",
                         systemImage: added ? "bookmark.fill" : "bookmark.slash.fill")
    }

    /// Tries a failed save again with the recorder's saver; the card shows progress and ends
    /// as ready or failed again with the reason.
    func retry(_ id: UUID, library: Library, router: AppRouter) {
        guard let video = library.video(id), case .failed = video.state else { return }
        Haptics.tap()
        RecordingSaver.shared.retry(video.id, library: library)
        router.showToast("Trying again", systemImage: "arrow.clockwise")
    }
}

// MARK: - Host

extension View {
    /// Presents the actions sheet and its follow-ups for cards that use `model`.
    func libraryVideoActions(_ model: LibraryActionsModel) -> some View {
        modifier(LibraryVideoActionsHost(model: model))
    }
}

struct LibraryVideoActionsHost: ViewModifier {
    @ObservedObject var model: LibraryActionsModel
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var settings: AppSettings

    func body(content: Content) -> some View {
        content
            .sheet(item: $model.sheet, onDismiss: {
                model.sheetDidDismiss(library: library, router: router)
            }, content: { sheet in
                sheetView(sheet)
                    .environmentObject(library)
                    .environmentObject(router)
                    .environmentObject(settings)
            })
            .sheet(isPresented: $model.showsStorage) {
                storageSheet
            }
            .shareVideo($model.shareTarget)
            .saveToPhotos($model.photosTarget)
            .alert("Delete this recording?", isPresented: deleteAlertShown, presenting: deleteCandidate) { video in
                Button("Delete", role: .destructive) {
                    model.performDelete(video.id, library: library, router: router)
                }
                if !library.edits(of: video.id).isEmpty {
                    Button("Delete with its edits", role: .destructive) {
                        model.performDelete(video.id, withEdits: true, library: library, router: router)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { video in
                Text(LibraryActionsSheet.deleteMessage(video, edits: library.edits(of: video.id).count))
            }
    }

    private var deleteCandidate: Video? {
        model.deleteCandidate.flatMap { library.video($0) }
    }

    private var deleteAlertShown: Binding<Bool> {
        Binding(get: { model.deleteCandidate != nil },
                set: { shown in if !shown { model.deleteCandidate = nil } })
    }

    @ViewBuilder
    private func sheetView(_ sheet: LibraryVideoSheet) -> some View {
        switch sheet {
        case .actions(let id):
            LibraryActionsSheet(videoID: id, onAction: { action in
                handle(action, videoID: id)
            })
            .presentationDetents([.fraction(0.74), .large])
            .presentationDragIndicator(.visible)
        case .rename(let id):
            TitleEditorSheet(initialTitle: library.video(id)?.title ?? "",
                             heading: "Rename recording",
                             onSave: { title in
                                 library.rename(id, to: title)
                                 router.showToast("Renamed", systemImage: "pencil")
                                 model.close()
                             },
                             onCancel: { model.close() })
            .presentationDetents([.height(220)])
        case .move(let id):
            MoveToFolderSheet(videoID: id, onDone: { model.close() })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        case .tags(let id):
            TagEditorSheet(videoID: id,
                           initialTags: library.video(id)?.tags ?? [],
                           onDone: { model.close() })
            .presentationDetents([.large])
        }
    }

    private var storageSheet: some View {
        NavigationStack {
            StorageView()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { model.showsStorage = false }
                            .font(.srHeadline)
                            .foregroundStyle(Color.srRed)
                    }
                }
        }
        .environmentObject(library)
        .environmentObject(router)
        .environmentObject(settings)
    }

    private func handle(_ action: LibraryVideoAction, videoID: UUID) {
        guard let video = library.video(videoID) else {
            model.close()
            return
        }
        switch action {
        case .share:
            model.share(video)
        case .copyLink:
            model.copyLink(video.id)
        case .saveToPhotos:
            model.saveToPhotos(video)
        case .watchLater:
            model.toggleWatchLater(videoID, library: library, router: router)
            model.close()
        case .rename:
            model.open(.rename(videoID))
        case .move:
            model.open(.move(videoID))
        case .tags:
            model.open(.tags(videoID))
        case .retry:
            model.close()
            model.retry(videoID, library: library, router: router)
        case .delete:
            model.deleteAfterClosing(videoID, library: library, router: router)
        case .deleteWithEdits:
            model.deleteAfterClosing(videoID, withEdits: true, library: library, router: router)
        case .edit:
            model.edit(videoID, router: router)
        }
    }
}

// MARK: - Actions sheet

/// The "…" sheet for one recording: a header, three quick actions, organising rows and delete.
struct LibraryActionsSheet: View {
    let videoID: UUID
    let onAction: @MainActor (LibraryVideoAction) -> Void

    @EnvironmentObject private var library: Library
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var confirmsDelete = false

    var body: some View {
        Group {
            if let video = library.video(videoID) {
                content(video)
            } else {
                Color.clear
            }
        }
        .background(Color.srCanvas.ignoresSafeArea())
    }

    private func content(_ video: Video) -> some View {
        ScrollView {
            VStack(spacing: Space.l) {
                header(video)
                quickActions(video)
                organiseCard(video)
                deleteButton
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.xl)
            .padding(.bottom, Space.l)
        }
        .alert("Delete this recording?", isPresented: $confirmsDelete) {
            Button("Delete", role: .destructive) {
                // Let the alert finish closing before the sheet goes.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    onAction(.delete)
                }
            }
            if !library.edits(of: video.id).isEmpty {
                Button("Delete with its edits", role: .destructive) {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        onAction(.deleteWithEdits)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(Self.deleteMessage(video, edits: library.edits(of: video.id).count))
        }
    }

    /// The delete warning; an original with edits says they stay unless deleted too.
    static func deleteMessage(_ video: Video, edits: Int) -> String {
        let base = "“\(video.title)” and its notes, reactions and transcript will be removed from this iPhone. You can't undo this."
        guard edits > 0 else { return base }
        return base + (edits == 1 ? " Its edited copy stays unless you delete it too." : " Its \(edits) edited copies stay unless you delete them too.")
    }

    private func header(_ video: Video) -> some View {
        HStack(alignment: .top, spacing: Space.s) {
            VideoThumbnail(video: video, cornerRadius: Radius.s)
                .frame(width: 112)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(verbatim: video.title)
                    .font(.srHeadline)
                    .foregroundStyle(Color.srText)
                    .lineLimit(2)
                Text(verbatim: "\(video.kind.label) · \(Format.duration(video.duration))")
                    .font(.srFootnote)
                    .foregroundStyle(Color.srTextSecondary)
                Text(verbatim: Self.dateLine(video))
                    .font(.srFootnote)
                    .foregroundStyle(Color.srTextTertiary)
                    // At the largest sizes "Saving 12%" was cut off the end.
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// When it was made and its size; while it is still being written, how far that is instead.
    static func dateLine(_ video: Video) -> String {
        let date = Format.dateTime(video.createdAt)
        switch video.state {
        case .saving(let progress):
            return "\(date) · Saving \(Int((min(1, max(0, progress)) * 100).rounded(.down)))%"
        case .failed:
            return "\(date) · Not saved"
        case .ready:
            return video.fileSize > 0 ? "\(date) · \(Format.bytes(video.fileSize))" : date
        }
    }

    /// Why the quick actions are greyed out, when they are.
    static func waitNote(_ video: Video) -> String? {
        switch video.state {
        case .ready: return nil
        case .saving:
            return "Share, Copy link and Save to Photos work as soon as this recording is saved."
        case .failed:
            return "This recording isn't saved, so it can't be shared yet."
        }
    }

    private func quickActions(_ video: Video) -> some View {
        let ready = video.state.isReady
        let share = ActionTile(title: "Share", systemImage: "square.and.arrow.up", enabled: ready) {
            onAction(.share)
        }
        let link = ActionTile(title: "Copy link",
                              systemImage: "link", isOn: library.link(for: video.id) != nil, enabled: ready) {
            onAction(.copyLink)
        }
        let photos = ActionTile(title: "Save to Photos", systemImage: "square.and.arrow.down", enabled: ready) {
            onAction(.saveToPhotos)
        }
        let later = ActionTile(title: video.isInWatchLater ? "In Watch later" : "Watch later",
                               systemImage: video.isInWatchLater ? "bookmark.fill" : "bookmark",
                               isOn: video.isInWatchLater, enabled: ready) {
            onAction(.watchLater)
        }
        return VStack(alignment: .leading, spacing: Space.s) {
            if typeSize.isAccessibilitySize {
                // Two to a row, so the largest text keeps whole words.
                Grid(horizontalSpacing: Space.s, verticalSpacing: Space.s) {
                    GridRow { share; link }
                    GridRow { photos; later }
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                // All four as tall as the tallest, so a two-line title doesn't make one stand out.
                HStack(alignment: .top, spacing: Space.s) { share; link; photos; later }
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let note = Self.waitNote(video) {
                Label {
                    Text(note)
                } icon: {
                    Image(systemName: "clock")
                }
                .font(.srFootnote)
                .foregroundStyle(Color.srTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func organiseCard(_ video: Video) -> some View {
        VStack(spacing: 0) {
            if case .failed = video.state {
                row("Try saving again", systemImage: "arrow.clockwise", value: nil) { onAction(.retry) }
                Divider().padding(.leading, 44)
            }
            if video.state.isReady {
                row(video.isAudioOnly ? "Edit recording" : "Edit video", systemImage: "scissors", value: nil) { onAction(.edit) }
                Divider().padding(.leading, 44)
            }
            row("Edit title", systemImage: "pencil", value: nil) { onAction(.rename) }
            Divider().padding(.leading, 44)
            row("Move to folder", systemImage: "folder", value: folderName(video)) { onAction(.move) }
            Divider().padding(.leading, 44)
            row("Tags", systemImage: "number", value: tagSummary(video)) { onAction(.tags) }
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.xxs)
        .srCard()
    }

    private var deleteButton: some View {
        Button {
            Haptics.warning()
            confirmsDelete = true
        } label: {
            Label("Delete recording", systemImage: "trash")
        }
        .buttonStyle(.srDestructive)
    }

    private func row(_ title: String, systemImage: String, value: String?,
                     action: @escaping @MainActor () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            ListRow(systemImage: systemImage, title: title, value: value)
        }
        .buttonStyle(.plain)
    }

    private func folderName(_ video: Video) -> String {
        video.folderID.flatMap { library.folder($0)?.name } ?? "None"
    }

    private func tagSummary(_ video: Video) -> String {
        switch video.tags.count {
        case 0: return "None"
        case 1, 2: return video.tags.joined(separator: ", ")
        default: return "\(video.tags.count) tags"
        }
    }
}

/// A square-ish quick action in the actions sheet.
private struct ActionTile: View {
    let title: String
    let systemImage: String
    var isOn = false
    var enabled = true
    let action: @MainActor () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(spacing: Space.xs) {
                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(isOn ? Color.white : Color.srRed)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(isOn ? Color.srRed : Color.srRedSoft))
                // The same size in every tile: a longer title takes a second line instead of shrinking.
                Text(title)
                    .font(.srCaption)
                    .foregroundStyle(Color.srText)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.vertical, Space.s)
            .padding(.horizontal, Space.xxs)
            .background(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(Color.srSurface))
            .overlay(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).strokeBorder(Color.srLine, lineWidth: 0.5))
        }
        .buttonStyle(PressScaleStyle(scale: 0.96))
        .frame(maxHeight: .infinity)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - Shared card controls

/// The round "…" button on cards.
struct LibraryMoreButton: View {
    let video: Video
    let actions: LibraryActionsModel

    var body: some View {
        Button {
            Haptics.tap()
            actions.showActions(video.id)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.srTextSecondary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.srFill))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel("More for \(video.title)")
    }
}

/// Long-press menu items for a card. Library and router are passed in so the actions never
/// depend on the menu's environment.
struct LibraryVideoMenu: View {
    let video: Video
    let actions: LibraryActionsModel
    let library: Library
    let router: AppRouter

    var body: some View {
        if video.state.isReady {
            Button {
                actions.share(video)
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            Button {
                actions.copyLink(video.id)
            } label: {
                Label("Copy link", systemImage: "link")
            }
            Button {
                actions.toggleWatchLater(video.id, library: library, router: router)
            } label: {
                Label(video.isInWatchLater ? "Remove from Watch later" : "Watch later",
                      systemImage: video.isInWatchLater ? "bookmark.slash" : "bookmark")
            }
        }
        if video.state.isReady {
            Button {
                router.edit(video.id, afterClosing: true)
            } label: {
                Label(video.isAudioOnly ? "Edit recording" : "Edit video", systemImage: "scissors")
            }
        }
        Button {
            actions.open(.rename(video.id))
        } label: {
            Label("Edit title", systemImage: "pencil")
        }
        Button {
            actions.open(.move(video.id))
        } label: {
            Label("Move to folder", systemImage: "folder")
        }
        Button {
            actions.open(.tags(video.id))
        } label: {
            Label("Tags", systemImage: "number")
        }
        Button(role: .destructive) {
            actions.requestDelete(video.id)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}
