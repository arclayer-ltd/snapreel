import SwiftUI

/// Session E owns this file. Settings > Notifications: one toggle per `NotificationKind`.
struct NotificationSettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        List {
            ForEach(NotificationKind.allCases) { kind in
                Toggle(kind.settingsTitle, isOn: settings.notificationBinding(kind))
            }
        }
        .navigationTitle("Notifications")
    }
}
