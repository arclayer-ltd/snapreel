import SwiftUI

// Session D. New / rename folder, move a recording to a folder, add recordings to a folder.

// MARK: - Name rules

@MainActor
enum FolderNameRules {
    static let limit = 40

    static func clean(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// What's wrong with `name` in plain words, or nil when it can be saved. An empty name is
    /// not reported (Save just stays disabled).
    static func problem(with name: String, in library: Library, excluding id: UUID? = nil) -> String? {
        let cleaned = clean(name)
        guard !cleaned.isEmpty else { return nil }
        let taken = library.folders.contains { folder in
            folder.id != id && folder.name.compare(cleaned, options: BrowseMatch.options) == .orderedSame
        }
        return taken ? "You already have a folder called “\(cleaned)”." : nil
    }

    static func canSave(_ name: String, in library: Library, excluding id: UUID? = nil) -> Bool {
        !clean(name).isEmpty && problem(with: name, in: library, excluding: id) == nil
    }
}

// MARK: - Folder editor

enum FolderEditorMode: Identifiable, Equatable {
    case create(initialName: String)
    case rename(UUID)

    var id: String {
        switch self {
        case .create: return "create"
        case .rename(let id): return "rename-\(id.uuidString)"
        }
    }

    var isCreate: Bool {
        if case .create = self { return true }
        return false
    }

    var folderID: UUID? {
        if case .rename(let id) = self { return id }
        return nil
    }
}

/// Name a new folder or rename one. Validates as you type (not empty, not a duplicate).
struct FolderEditorSheet: View {
    let mode: FolderEditorMode
    /// The created or renamed folder, or nil when cancelled.
    let onFinish: @MainActor (Folder?) -> Void

    @EnvironmentObject private var library: Library
    @State private var name: String
    @FocusState private var focused: Bool

    init(mode: FolderEditorMode, initialName: String, onFinish: @escaping @MainActor (Folder?) -> Void) {
        self.mode = mode
        self.onFinish = onFinish
        _name = State(initialValue: initialName)
    }

    private var problem: String? {
        FolderNameRules.problem(with: name, in: library, excluding: mode.folderID)
    }

    private var canSave: Bool {
        FolderNameRules.canSave(name, in: library, excluding: mode.folderID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: mode.isCreate ? "New folder" : "Rename folder",
                        leadingTitle: "Cancel", leadingAction: { onFinish(nil) },
                        trailingTitle: mode.isCreate ? "Create" : "Save", trailingEnabled: canSave,
                        trailingAction: { save() })
            field
                .padding(.horizontal, Space.gutter)
            Text(verbatim: problem ?? "Up to \(FolderNameRules.limit) characters. A recording sits in one folder at a time.")
                .font(.srFootnote)
                .foregroundStyle(problem == nil ? Color.srTextSecondary : Color.srRedText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Space.gutter)
                .padding(.top, Space.xs)
                .animation(Motion.quick, value: problem)
            Spacer(minLength: 0)
        }
        .background(Color.srSurface.ignoresSafeArea())
        .onAppear { focused = true }
        .onChange(of: name) { value in
            if value.count > FolderNameRules.limit {
                name = String(value.prefix(FolderNameRules.limit))
            }
        }
    }

    private var field: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: "folder.fill")
                .foregroundStyle(Color.srRed)
            TextField("Folder name", text: $name)
                .font(.srBody)
                .foregroundStyle(Color.srText)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit { save() }
            if !name.isEmpty {
                Button {
                    name = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.srTextTertiary)
                }
                .accessibilityLabel("Clear name")
            }
        }
        .padding(.horizontal, Space.m)
        .frame(height: 52)
        .background(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).fill(Color.srFill))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                .strokeBorder(problem == nil ? Color.clear : Color.srRed, lineWidth: 1.5)
        )
    }

    private func save() {
        guard canSave else {
            if problem != nil { Haptics.error() }
            return
        }
        let cleaned = FolderNameRules.clean(name)
        switch mode {
        case .create:
            let folder = library.createFolder(named: cleaned)
            Haptics.success()
            onFinish(folder)
        case .rename(let id):
            library.renameFolder(id, to: cleaned)
            Haptics.success()
            onFinish(library.folder(id))
        }
    }
}

// MARK: - Move to folder

/// Pick the folder a recording lives in: "No folder", every folder (current one checked), or a
/// new folder made right here.
struct MoveToFolderSheet: View {
    let videoID: UUID
    let onDone: @MainActor () -> Void

    @EnvironmentObject private var library: Library
    @EnvironmentObject private var router: AppRouter
    @State private var isCreating = false
    @State private var newName = ""
    @FocusState private var nameFocused: Bool

    private var currentFolderID: UUID? { library.video(videoID)?.folderID }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Move to folder", leadingTitle: "Cancel", leadingAction: { onDone() })
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    if let video = library.video(videoID) {
                        Text(verbatim: video.title)
                            .font(.srFootnote)
                            .foregroundStyle(Color.srTextSecondary)
                            .lineLimit(1)
                            .padding(.horizontal, Space.xxs)
                    }
                    optionsCard
                    newFolderCard
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.xl)
            }
        }
        .background(Color.srCanvas.ignoresSafeArea())
    }

    private var optionsCard: some View {
        VStack(spacing: 0) {
            option(title: "No folder", subtitle: "Only in My videos", systemImage: "tray",
                   selected: currentFolderID == nil) {
                move(to: nil)
            }
            ForEach(library.sortedFolders) { folder in
                Divider().padding(.leading, 44)
                option(title: folder.name,
                       subtitle: BrowseText.recordings(library.videos(inFolder: folder.id).count),
                       systemImage: "folder.fill",
                       selected: currentFolderID == folder.id) {
                    move(to: folder.id)
                }
            }
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.xxs)
        .srCard()
    }

    private func option(title: String, subtitle: String, systemImage: String, selected: Bool,
                        action: @escaping @MainActor () -> Void) -> some View {
        Button {
            action()
        } label: {
            HStack(spacing: Space.s) {
                IconTile(systemName: systemImage)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title)
                        .font(.srBody)
                        .foregroundStyle(Color.srText)
                        .lineLimit(1)
                    Text(verbatim: subtitle)
                        .font(.srFootnote)
                        .foregroundStyle(Color.srTextSecondary)
                }
                Spacer(minLength: Space.xs)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.srRed)
                }
            }
            .padding(.vertical, Space.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var newFolderCard: some View {
        if isCreating {
            VStack(alignment: .leading, spacing: Space.s) {
                HStack(spacing: Space.xs) {
                    Image(systemName: "folder.badge.plus")
                        .foregroundStyle(Color.srRed)
                    TextField("New folder name", text: $newName)
                        .font(.srBody)
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .onSubmit { createAndMove() }
                }
                .padding(.horizontal, Space.m)
                .frame(height: 48)
                .background(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).fill(Color.srFill))
                if let problem = FolderNameRules.problem(with: newName, in: library) {
                    Text(verbatim: problem)
                        .font(.srFootnote)
                        .foregroundStyle(Color.srRedText)
                }
                Button("Create and move") { createAndMove() }
                    .buttonStyle(.srPrimaryCompact)
                    .disabled(!FolderNameRules.canSave(newName, in: library))
            }
            .padding(Space.m)
            .srCard()
            .onChange(of: newName) { value in
                if value.count > FolderNameRules.limit {
                    newName = String(value.prefix(FolderNameRules.limit))
                }
            }
        } else {
            Button {
                Haptics.tap()
                withAnimation(Motion.quick) { isCreating = true }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    nameFocused = true
                }
            } label: {
                HStack(spacing: Space.s) {
                    IconTile(systemName: "plus")
                    Text("New folder")
                        .font(.srBody)
                        .foregroundStyle(Color.srRed)
                    Spacer()
                }
                .padding(.horizontal, Space.m)
                .padding(.vertical, Space.s)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .srCard()
        }
    }

    private func move(to folderID: UUID?) {
        guard library.video(videoID) != nil else {
            onDone()
            return
        }
        if currentFolderID != folderID {
            library.move(videoID, toFolder: folderID)
            Haptics.success()
            if let folderID, let folder = library.folder(folderID) {
                router.showToast("Moved to \(folder.name)", systemImage: "folder.fill")
            } else {
                router.showToast("Taken out of its folder", systemImage: "tray.fill")
            }
        }
        onDone()
    }

    private func createAndMove() {
        guard FolderNameRules.canSave(newName, in: library) else { return }
        let folder = library.createFolder(named: FolderNameRules.clean(newName))
        move(to: folder.id)
    }
}

// MARK: - Add recordings to a folder

/// Choose recordings from the library to put in a folder.
struct AddRecordingsSheet: View {
    let folderID: UUID
    let onDone: @MainActor () -> Void

    @EnvironmentObject private var library: Library
    @EnvironmentObject private var router: AppRouter
    @State private var selection: Set<UUID> = []

    private var candidates: [Video] {
        library.allVideos.filter { $0.folderID != folderID }
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Add recordings",
                        leadingTitle: "Cancel", leadingAction: { onDone() },
                        trailingTitle: selection.isEmpty ? "Add" : "Add \(selection.count)",
                        trailingEnabled: !selection.isEmpty,
                        trailingAction: { add() })
            if candidates.isEmpty {
                Spacer()
                EmptyStateView(systemImage: "checkmark.circle",
                               title: "Nothing else to add",
                               message: "Every recording is already in this folder.")
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(candidates) { video in
                            row(video)
                            if video.id != candidates.last?.id {
                                Divider().padding(.leading, 116)
                            }
                        }
                    }
                    .padding(.horizontal, Space.m)
                    .srCard()
                    .padding(.horizontal, Space.gutter)
                    .padding(.bottom, Space.xl)
                }
            }
        }
        .background(Color.srCanvas.ignoresSafeArea())
    }

    private func row(_ video: Video) -> some View {
        let selected = selection.contains(video.id)
        return Button {
            Haptics.selection()
            if selected { selection.remove(video.id) } else { selection.insert(video.id) }
        } label: {
            HStack(spacing: Space.s) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(selected ? Color.srRed : Color.srTextTertiary)
                VideoThumbnail(video: video, cornerRadius: 6, showsDuration: false)
                    .frame(width: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: video.title)
                        .font(.srSubheadlineStrong)
                        .foregroundStyle(Color.srText)
                        .lineLimit(2)
                    Text(verbatim: whereItIs(video))
                        .font(.srFootnote)
                        .foregroundStyle(Color.srTextSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, Space.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func whereItIs(_ video: Video) -> String {
        if let id = video.folderID, let folder = library.folder(id) {
            return "Now in \(folder.name)"
        }
        return "\(Format.duration(video.duration)) · not in a folder"
    }

    private func add() {
        guard !selection.isEmpty else { return }
        let count = selection.count
        for id in selection {
            library.move(id, toFolder: folderID)
        }
        Haptics.success()
        router.showToast("Added \(BrowseText.recordings(count))", systemImage: "folder.fill")
        onDone()
    }
}
