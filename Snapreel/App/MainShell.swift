import SwiftUI

/// The tab shell: four tab stacks kept alive, the custom tab bar with the red record button,
/// the mini player above the bar, and the app-wide presentations (recorder, player, settings).
struct MainShell: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                tabStack(.home, path: $router.homePath) { HomeView() }
                tabStack(.library, path: $router.libraryPath) { LibraryView() }
                tabStack(.notifications, path: $router.notificationsPath) { NotificationsView() }
                tabStack(.search, path: $router.searchPath) { SearchView() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                VStack(spacing: Space.xs) {
                    if let recording = router.minimizedRecorder {
                        MinimizedRecordingBar(model: recording)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    if let player = router.player, player.isMinimized {
                        MiniPlayerBar(videoID: player.videoID)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, Space.s)
                .padding(.bottom, Space.xs)
            }
            SnapreelTabBar(selection: router.tab,
                           unreadCount: library.unreadNotificationCount,
                           onSelect: { router.select($0) })
        }
        .background(Color.srCanvas.ignoresSafeArea())
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .toast($router.toast, bottomInset: 110)
        .overlayPreferenceValue(TourAnchorKey.self) { anchors in
            Group {
                if !settings.hasCompletedTour {
                    GeometryReader { proxy in
                        GuidedTourOverlay(targets: anchors.mapValues { proxy[$0] }, onFinish: {
                            withAnimation(Motion.standard) { settings.hasCompletedTour = true }
                        })
                    }
                    .ignoresSafeArea()
                }
            }
        }
        .fullScreenCover(item: $router.recorder) { launch in
            RecorderView(launch: launch)
                .environmentObject(library)
                .environmentObject(settings)
                .environmentObject(router)
                .clearCoverBackground()
        }
        .fullScreenCover(isPresented: playerExpanded) {
            if let player = router.player {
                PlayerScreen(presentation: player)
                    .environmentObject(library)
                    .environmentObject(settings)
                    .environmentObject(router)
                    .clearCoverBackground()
            }
        }
        .fullScreenCover(item: $router.editor) { launch in
            EditorScreen(videoID: launch.videoID, library: library)
                .environmentObject(library)
                .environmentObject(settings)
                .environmentObject(router)
                .clearCoverBackground()
        }
        .sheet(isPresented: $router.isSettingsPresented) {
            SettingsView(initialPath: router.settingsPath)
                .environmentObject(library)
                .environmentObject(settings)
                .environmentObject(router)
        }
    }

    private var playerExpanded: Binding<Bool> {
        Binding(get: { router.player.map { !$0.isMinimized } ?? false },
                set: { expanded in
                    if !expanded, router.player?.isMinimized == false { router.closePlayer() }
                })
    }

    private func tabStack<Content: View>(_ tab: AppTab, path: Binding<NavigationPath>,
                                         @ViewBuilder content: () -> Content) -> some View {
        let selected = router.tab == tab
        return NavigationStack(path: path) {
            content()
                .navigationDestination(for: Route.self) { RouteDestination(route: $0) }
        }
        .opacity(selected ? 1 : 0)
        .accessibilityHidden(!selected)
        // The shown tab on top, where it takes every touch. Not `allowsHitTesting(false)` on the hidden ones: after a
        // sheet closed (Settings), iOS 16 applied it to the shown tab's toolbar too, and the Home gear stopped
        // working until the tab was switched (tester t26, 4 of 4; seen on the rig as the gear losing its button trait).
        .zIndex(selected ? 1 : 0)
    }
}

/// Maps pushed routes to the feature views that own them.
struct RouteDestination: View {
    let route: Route

    var body: some View {
        switch route {
        case .folder(let id): FolderDetailView(folderID: id)
        case .watchLater: WatchLaterView()
        case .history: WatchHistoryView()
        case .allVideos: LibraryView()
        }
    }
}

// MARK: - Tab bar

struct SnapreelTabBar: View {
    let selection: AppTab
    let unreadCount: Int
    let onSelect: (AppTab) -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                if tab == .record {
                    recordButton
                } else {
                    item(tab)
                }
            }
        }
        .padding(.horizontal, Space.xs)
        .padding(.top, 6)
        .background(
            Color.srSurface
                .overlay(alignment: .top) { Rectangle().fill(Color.srLine).frame(height: 0.5) }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func item(_ tab: AppTab) -> some View {
        let selected = tab == selection
        return Button {
            Haptics.selection()
            onSelect(tab)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: selected ? tab.selectedSystemImage : tab.systemImage)
                    .font(.system(size: 20, weight: selected ? .semibold : .regular))
                    .frame(height: 26)
                    .overlay(alignment: .topTrailing) {
                        if tab == .notifications && unreadCount > 0 {
                            UnreadDot(size: 10).offset(x: 4, y: -1)
                        }
                    }
                Text(tab.title)
                    .font(.system(size: 10, weight: selected ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? Color.srText : Color.srTextTertiary)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tourAnchor(tab)
        .accessibilityLabel(tab == .notifications && unreadCount > 0 ? "\(tab.title), \(unreadCount) unread" : tab.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var recordButton: some View {
        Button {
            Haptics.firm()
            onSelect(.record)
        } label: {
            ZStack {
                Circle().fill(Color.srRed)
                    .shadow(color: Color.srRed.opacity(0.35), radius: 10, y: 4)
                Circle().strokeBorder(Color.white, lineWidth: 3).padding(11)
                Circle().fill(Color.white).padding(20)
            }
            .frame(width: 56, height: 56)
            .offset(y: -10)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressScaleStyle(scale: 0.92))
        .tourAnchor(.record)
        .accessibilityLabel("Record")
        .accessibilityHint("Opens the recorder")
    }
}

// MARK: - Tour anchors

/// Tab bar item bounds, published for the guided tour (session A) to spotlight.
struct TourAnchorKey: PreferenceKey {
    static let defaultValue: [AppTab: Anchor<CGRect>] = [:]
    static func reduce(value: inout [AppTab: Anchor<CGRect>], nextValue: () -> [AppTab: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

extension View {
    func tourAnchor(_ tab: AppTab) -> some View {
        anchorPreference(key: TourAnchorKey.self, value: .bounds) { [tab: $0] }
    }

    /// The gear button every tab root shows top-right; opens Settings.
    func settingsToolbar() -> some View {
        modifier(SettingsToolbarModifier())
    }
}

private struct SettingsToolbarModifier: ViewModifier {
    @EnvironmentObject private var router: AppRouter

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Haptics.tap()
                    router.openSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.srText)
                }
                .accessibilityLabel("Settings")
            }
        }
    }
}
