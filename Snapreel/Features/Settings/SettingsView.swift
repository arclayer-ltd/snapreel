import SwiftUI

/// Session A owns this file. Settings root, presented as a sheet from the gear on every tab.
/// Links to NotificationSettingsView (E), RecordingDefaultsView (B), StorageView (E),
/// the help centre and legal (A). Footer shows the app version.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Notifications") { NotificationSettingsView() }
                NavigationLink("Recording") { RecordingDefaultsView() }
                NavigationLink("Storage") { StorageView() }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
