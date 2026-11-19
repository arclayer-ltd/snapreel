import SwiftUI

/// Settings > Appearance: match the iPhone's Light or Dark setting, or keep one of them.
/// The choice applies at once to the whole app except the recorder and the player.
struct AppearanceView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ScrollView {
            SettingsGroup(footnote: "Every screen follows this, the recorder and the player too. Only the video and the camera picture stay dark, like in the Camera and Photos apps.") {
                ForEach(Array(AppearanceMode.allCases.enumerated()), id: \.element) { index, mode in
                    if index > 0 { SettingsDivider() }
                    row(mode)
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.s)
            .padding(.bottom, Space.xxl)
        }
        .background(Color.srCanvas.ignoresSafeArea())
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ mode: AppearanceMode) -> some View {
        let selected = settings.appearance == mode
        return Button {
            Haptics.selection()
            settings.appearance = mode
        } label: {
            HStack(spacing: Space.s) {
                IconTile(systemName: mode.systemImage)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.label).font(.srBody).foregroundStyle(Color.srText)
                    Text(mode.detail).font(.srFootnote).foregroundStyle(Color.srTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.xs)
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.srRed)
                    .opacity(selected ? 1 : 0)
            }
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(SettingsRowStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(mode.detail)
    }
}
