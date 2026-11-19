import SwiftUI

/// Session E owns this file. Settings › Notifications: one switch per `NotificationKind`,
/// grouped by what it's about, with a banner when iOS isn't letting Snapreel show alerts.
/// The switches decide which alerts appear on the Lock Screen; the Notifications tab always
/// lists everything.
@MainActor
struct NotificationSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.scenePhase) private var scenePhase

    /// The system permission, nil until checked.
    @State private var permission: PermissionState?
    @State private var isRequesting = false
    /// Debug screens pin the permission banner to a state instead of asking iOS.
    private let pinnedPermission: PermissionState?

    init() {
        pinnedPermission = nil
    }

    /// For debug screens: shows the banner for `permission` without asking iOS.
    init(permission: PermissionState) {
        pinnedPermission = permission
        _permission = State(initialValue: permission)
    }

    var body: some View {
        List {
            if let permission, permission != .granted {
                Section {
                    AlertsPermissionBanner(state: permission, isRequesting: isRequesting, action: { bannerAction() })
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            ForEach(NotificationSettingsGroup.allCases) { group in
                Section {
                    ForEach(group.kinds) { kind in
                        toggleRow(kind)
                    }
                } header: {
                    Text(group.title)
                        .font(.srSubheadlineStrong)
                        .foregroundStyle(Color.srTextSecondary)
                        .textCase(nil)
                } footer: {
                    if let footer = group.footer {
                        Text(footer)
                            .font(.srFootnote)
                            .foregroundStyle(Color.srTextTertiary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.srCanvas.ignoresSafeArea())
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .animation(Motion.standard, value: permission)
        .task { await refreshPermission() }
        .onChange(of: scenePhase) { phase in
            // Coming back from the Settings app.
            if phase == .active { Task { @MainActor in await refreshPermission() } }
        }
    }

    private func toggleRow(_ kind: NotificationKind) -> some View {
        Toggle(isOn: binding(for: kind)) {
            HStack(alignment: .top, spacing: Space.s) {
                IconTile(systemName: kind.systemImage, size: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(kind.settingsTitle)
                        .font(.srBody)
                        .foregroundStyle(Color.srText)
                    Text(kind.settingsDetail)
                        .font(.srFootnote)
                        .foregroundStyle(Color.srTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, Space.xxs)
        }
        .tint(Color.srRed)
    }

    private func binding(for kind: NotificationKind) -> Binding<Bool> {
        Binding(get: { settings.isNotificationEnabled(kind) },
                set: { enabled in
                    Haptics.selection()
                    settings.setNotification(kind, enabled: enabled)
                })
    }

    private func bannerAction() {
        switch permission {
        case .notDetermined?:
            isRequesting = true
            Task { @MainActor in
                let result = await Permissions.request(.notifications)
                isRequesting = false
                if result == .granted { Haptics.success() }
                permission = pinnedPermission ?? result
            }
        default:
            Permissions.openSettings()
        }
    }

    private func refreshPermission() async {
        if let pinnedPermission {
            permission = pinnedPermission
            return
        }
        permission = await Permissions.state(.notifications)
    }
}

/// How the switches are grouped on screen.
enum NotificationSettingsGroup: String, CaseIterable, Identifiable {
    case recording
    case library
    case links
    case device

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recording: return "Recording"
        case .library: return "Library"
        case .links: return "Share links"
        case .device: return "This iPhone"
        }
    }

    var kinds: [NotificationKind] {
        switch self {
        case .recording: return [.recordingSaved, .needsTitle, .importFinished]
        case .library: return [.transcriptReady]
        case .links: return [.newViewer, .newComment, .uploadFinished, .uploadFailed]
        case .device: return [.storageLow]
        }
    }

    var footer: String? {
        switch self {
        case .recording: return nil
        case .library: return "Transcripts are made on this iPhone, so they can take a few minutes for long recordings."
        case .links: return "Viewer and comment alerts come from snapreel.video while you're signed in. Switch both off to stop them reaching this iPhone."
        case .device: return "Snapreel checks free space when you open it, and warns you at most once a day. Everything here still shows up in the Notifications tab when an alert is off."
        }
    }
}

/// Shown above the switches when iOS isn't letting Snapreel show alerts.
@MainActor
private struct AlertsPermissionBanner: View {
    let state: PermissionState
    let isRequesting: Bool
    let action: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .top, spacing: Space.s) {
                IconTile(systemName: "bell.slash.fill", tint: .white, background: .srRed, size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.srHeadline)
                        .foregroundStyle(Color.srText)
                    Text(message)
                        .font(.srSubheadline)
                        .foregroundStyle(Color.srTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            Button {
                action()
            } label: {
                HStack(spacing: Space.xs) {
                    if isRequesting {
                        ProgressView().tint(Color.white)
                    }
                    Text(buttonTitle)
                }
            }
            .buttonStyle(.srPrimaryCompact)
            .disabled(isRequesting)
            .padding(.leading, 36 + Space.s)
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srCard()
    }

    private var title: String {
        state == .denied ? "Alerts are off for Snapreel" : "Get an alert when it's ready"
    }

    private var message: String {
        state == .denied
            ? "You'll still find everything in the Notifications tab. To see alerts on your Lock Screen, turn on notifications for Snapreel in Settings."
            : "Snapreel can tell you when a screen recording is saved or a transcript is ready, even when you're in another app."
    }

    private var buttonTitle: String {
        state == .denied ? "Turn on in Settings" : "Allow notifications"
    }
}
