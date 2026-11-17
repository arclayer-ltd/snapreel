import SwiftUI

/// Session E owns this file. Settings › Storage: how much of this iPhone Snapreel uses, what
/// kinds of recordings take the space, the largest recordings (delete with a confirmation),
/// and "Delete all my data".
@MainActor
struct StorageView: View {
    /// Where the delete-all sheet is.
    enum EraseStep: String {
        case confirm
        case erasing
        case done
    }

    @EnvironmentObject private var library: Library
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss

    @State private var disk = DiskUsageSnapshot()
    @State private var showsAllLargest = false
    @State private var videoToDelete: Video?
    @State private var showsErase: Bool
    @State private var eraseStep: EraseStep
    @State private var freedBytes: Int64 = 0
    @State private var toast: ToastMessage?

    /// How many of the largest recordings show before "Show all".
    private let largestLimit = 5

    init() {
        _showsErase = State(initialValue: false)
        _eraseStep = State(initialValue: .confirm)
    }

    /// For debug screens: opens with the delete-all sheet at `step`.
    init(initialErase step: EraseStep) {
        _showsErase = State(initialValue: true)
        _eraseStep = State(initialValue: step)
    }

    var body: some View {
        List {
            Section {
                StorageUsageCard(snapreelBytes: library.totalVideoBytes, disk: disk)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            Section {
                kindsGrid
            } header: {
                sectionHeader("By type")
            }
            largestSection
            deleteAllSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.srCanvas.ignoresSafeArea())
        .navigationTitle("Storage")
        .navigationBarTitleDisplayMode(.inline)
        .toast($toast, bottomInset: Space.xl)
        .onAppear { disk = .now() }
        .confirmationDialog("Delete this recording?", isPresented: deleteDialogPresented,
                            titleVisibility: .visible, presenting: videoToDelete) { video in
            Button("Delete recording", role: .destructive) { delete(video) }
            Button("Cancel", role: .cancel) {}
        } message: { video in
            Text("\u{201C}\(video.title)\u{201D} and its notes, reactions and transcript are removed from this iPhone, freeing \(Format.bytes(video.fileSize)). This can't be undone.")
        }
        .sheet(isPresented: $showsErase) {
            EraseAllSheet(step: eraseStep, summary: EraseSummary(library: library), freedBytes: freedBytes,
                          onErase: { erase() },
                          onCancel: { showsErase = false },
                          onDone: { finishErase() })
        }
    }

    // MARK: Sections

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.srSubheadlineStrong)
            .foregroundStyle(Color.srTextSecondary)
            .textCase(nil)
    }

    private var kindsGrid: some View {
        VStack(spacing: Space.s) {
            HStack(spacing: Space.s) {
                kindTile(.screen)
                kindTile(.camera)
            }
            HStack(spacing: Space.s) {
                kindTile(.audio)
                kindTile(.imported)
            }
        }
        .padding(.vertical, Space.xxs)
    }

    private func kindTile(_ kind: RecordingKind) -> some View {
        let videos = library.videos.filter { $0.kind == kind }
        let bytes = videos.reduce(Int64(0)) { $0 + $1.fileSize }
        return StorageKindTile(kind: kind, count: videos.count, bytes: bytes)
    }

    private var largest: [Video] {
        library.videos.sorted { $0.fileSize > $1.fileSize }
    }

    private var largestSection: some View {
        let all = largest
        let shown = showsAllLargest ? all : Array(all.prefix(largestLimit))
        return Section {
            if all.isEmpty {
                Text("No recordings yet. When you make one, it shows up here, biggest first.")
                    .font(.srSubheadline)
                    .foregroundStyle(Color.srTextSecondary)
                    .padding(.vertical, Space.xs)
            }
            ForEach(shown) { video in
                LargestVideoRow(video: video, onDelete: { requestDelete(video) })
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            requestDelete(video)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
            if all.count > largestLimit {
                Button {
                    Haptics.selection()
                    withAnimation(Motion.standard) { showsAllLargest.toggle() }
                } label: {
                    Text(showsAllLargest ? "Show fewer" : "Show all \(all.count)")
                        .font(.srSubheadlineStrong)
                        .foregroundStyle(Color.srRed)
                }
            }
        } header: {
            sectionHeader("Largest recordings")
        } footer: {
            if !all.isEmpty {
                Text("Deleting a recording also removes its notes, reactions and transcript.")
                    .font(.srFootnote)
                    .foregroundStyle(Color.srTextTertiary)
            }
        }
    }

    private var deleteAllSection: some View {
        Section {
            Button {
                Haptics.warning()
                eraseStep = .confirm
                showsErase = true
            } label: {
                HStack {
                    Text("Delete all my data")
                        .font(.srBody)
                        .foregroundStyle(Color.srRedDeep)
                    Spacer()
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.srRedDeep)
                }
                .contentShape(Rectangle())
            }
            .disabled(!hasAnyData)
        } footer: {
            Text(hasAnyData
                 ? "Removes every recording and everything you've added to them from this iPhone. Your settings stay."
                 : "There's nothing to delete. Snapreel has no recordings, folders or notifications on this iPhone.")
                .font(.srFootnote)
                .foregroundStyle(Color.srTextTertiary)
        }
    }

    private var hasAnyData: Bool {
        !library.videos.isEmpty || !library.folders.isEmpty || !library.notifications.isEmpty
            || !library.notes.isEmpty || !library.reactions.isEmpty || !library.transcripts.isEmpty
    }

    // MARK: Deleting one recording

    private var deleteDialogPresented: Binding<Bool> {
        Binding(get: { videoToDelete != nil },
                set: { presented in if !presented { videoToDelete = nil } })
    }

    private func requestDelete(_ video: Video) {
        Haptics.tap()
        videoToDelete = video
    }

    private func delete(_ video: Video) {
        let bytes = video.fileSize
        if router.player?.videoID == video.id { router.closePlayer() }
        withAnimation(Motion.standard) { library.delete(video.id) }
        Haptics.success()
        disk = .now()
        toast = ToastMessage(text: "Deleted. \(Format.bytes(bytes)) freed")
    }

    // MARK: Deleting everything

    private func erase() {
        freedBytes = library.totalVideoBytes
        withAnimation(Motion.standard) { eraseStep = .erasing }
        Task { @MainActor in
            // Let "Deleting…" show before the work blocks the main thread.
            try? await Task.sleep(nanoseconds: 450_000_000)
            router.closePlayer()
            library.eraseEverything()
            settings.resetAfterErase()
            ShareFileLink.removeAll(root: library.media.root)
            DeliveredAlerts.removeAll()
            disk = .now()
            Haptics.success()
            UIAccessibility.post(notification: .announcement, argument: "All data deleted")
            withAnimation(Motion.standard) { eraseStep = .done }
        }
    }

    /// "Back to library": close Storage and Settings and land on the (now empty) library.
    private func finishErase() {
        showsErase = false
        let dismissStorage = dismiss
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            router.homePath = NavigationPath()
            router.libraryPath = NavigationPath()
            router.notificationsPath = NavigationPath()
            router.searchPath = NavigationPath()
            router.isSettingsPresented = false
            router.tab = .library
            dismissStorage()
        }
    }
}

// MARK: - Disk numbers

struct DiskUsageSnapshot: Equatable {
    var total: Int64 = 0
    var free: Int64 = 0

    static func now() -> DiskUsageSnapshot {
        DiskUsageSnapshot(total: DiskSpace.total, free: DiskSpace.available)
    }
}
