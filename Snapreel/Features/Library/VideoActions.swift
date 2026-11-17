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
    case saveToPhotos
    case watchLater
    case rename
    case move
    case tags
    case retry
    case delete
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
        case photos(Video)
        case delete(UUID)
        case storage
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
    func deleteAfterClosing(_ id: UUID, library: Library, router: AppRouter) {
        if sheet == nil {
            performDelete(id, library: library, router: router)
        } else {
            followUp = .delete(id)
            sheet = nil
        }
    }

    func performDelete(_ id: UUID, library: Library, router: AppRouter) {
        guard library.video(id) != nil else { return }
        library.delete(id)
        Haptics.success()
        router.showToast("Recording deleted", systemImage: "trash.fill")
    }

    /// Called by the host when a sheet has been dismissed.
    func sheetDidDismiss(library: Library, router: AppRouter) {
        guard let next = followUp else { return }
        followUp = nil
        switch next {
        case .sheet(let nextSheet): sheet = nextSheet
        case .share(let video): shareTarget = video
        case .photos(let video): photosTarget = video
        case .delete(let id): performDelete(id, library: library, router: router)
        case .storage: showsStorage = true
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
                Button("Cancel", role: .cancel) {}
            } message: { video in
                Text("“\(video.title)” and its notes, reactions and transcript will be removed from this iPhone. You can't undo this.")
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
            .presentationDetents([.fraction(0.68), .large])
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
        }
    }
}

// MARK: - Actions sheet

/// The "…" sheet for one recording: a header, three quick actions, organising rows and delete.
struct LibraryActionsSheet: View {
    let videoID: UUID
    let onAction: @MainActor (LibraryVideoAction) -> Void

    @EnvironmentObject private var library: Library
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
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("“\(video.title)” and its notes, reactions and transcript will be removed from this iPhone. You can't undo this.")
        }
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
                Text(verbatim: "\(Format.dateTime(video.createdAt)) · \(Format.bytes(video.fileSize))")
                    .font(.srFootnote)
                    .foregroundStyle(Color.srTextTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func quickActions(_ video: Video) -> some View {
        let ready = video.state.isReady
        return HStack(spacing: Space.s) {
            ActionTile(title: "Share", systemImage: "square.and.arrow.up", enabled: ready) {
                onAction(.share)
            }
            ActionTile(title: "Save to Photos", systemImage: "square.and.arrow.down", enabled: ready) {
                onAction(.saveToPhotos)
            }
            ActionTile(title: video.isInWatchLater ? "In Watch later" : "Watch later",
                       systemImage: video.isInWatchLater ? "bookmark.fill" : "bookmark",
                       isOn: video.isInWatchLater, enabled: ready) {
                onAction(.watchLater)
            }
        }
    }

    private func organiseCard(_ video: Video) -> some View {
        VStack(spacing: 0) {
            if case .failed = video.state {
                row("Try saving again", systemImage: "arrow.clockwise", value: nil) { onAction(.retry) }
                Divider().padding(.leading, 44)
            }
            row("Rename", systemImage: "pencil", value: nil) { onAction(.rename) }
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
                Text(title)
                    .font(.srCaption)
                    .foregroundStyle(Color.srText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.s)
            .padding(.horizontal, Space.xxs)
            .background(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(Color.srSurface))
            .overlay(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).strokeBorder(Color.srLine, lineWidth: 0.5))
        }
        .buttonStyle(PressScaleStyle(scale: 0.96))
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
                actions.toggleWatchLater(video.id, library: library, router: router)
            } label: {
                Label(video.isInWatchLater ? "Remove from Watch later" : "Watch later",
                      systemImage: video.isInWatchLater ? "bookmark.slash" : "bookmark")
            }
        }
        Button {
            actions.open(.rename(video.id))
        } label: {
            Label("Rename", systemImage: "pencil")
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
