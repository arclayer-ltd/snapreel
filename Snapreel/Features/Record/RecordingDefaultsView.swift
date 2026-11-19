import SwiftUI

/// Session B owns this file. Settings > Recording: quality, microphone default, countdown,
/// camera, mirroring. Pushed inside the Settings NavigationStack.
struct RecordingDefaultsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        List {
            qualitySection
            recordingSection
            cameraSection
        }
        .listStyle(.insetGrouped)
        .tint(Color.srRed)
        .navigationTitle("Recording")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var qualitySection: some View {
        Section {
            ForEach(RecordingQuality.allCases) { quality in
                Button {
                    Haptics.selection()
                    settings.recordingQuality = quality
                } label: {
                    HStack(spacing: Space.s) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(quality.label).font(.srBody).foregroundStyle(Color.srText)
                            Text(quality.detail).font(.srFootnote).foregroundStyle(Color.srTextSecondary)
                        }
                        Spacer()
                        if settings.recordingQuality == quality {
                            Image(systemName: "checkmark")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.srRed)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(settings.recordingQuality == quality ? .isSelected : [])
            }
        } header: {
            Text("Quality")
        } footer: {
            Text("Applies to camera and screen recordings. 4K needs the back camera; the front camera records at up to 1080p on some iPhones.")
        }
    }

    private var recordingSection: some View {
        Section {
            Toggle(isOn: $settings.microphoneOnByDefault) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Microphone on").font(.srBody)
                    Text("Camera recordings include your voice. Screen recordings ask in the system sheet.")
                        .font(.srFootnote)
                        .foregroundStyle(Color.srTextSecondary)
                }
            }
            Picker("Countdown", selection: $settings.countdown) {
                ForEach(CountdownLength.allCases) { length in
                    Text(length.label).tag(length)
                }
            }
            if ScreenRecordingFloater.isSupported {
                Toggle(isOn: $settings.showsRecordingFloater) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Floating button").font(.srBody)
                        Text("While you record your screen, a small Snapreel button floats over other apps so you can stop from anywhere. It shows in the recording.")
                            .font(.srFootnote)
                            .foregroundStyle(Color.srTextSecondary)
                    }
                }
            }
        } header: {
            Text("Recording")
        }
    }

    private var cameraSection: some View {
        Section {
            HStack {
                Text("Start with")
                Spacer()
                Picker("Start with", selection: $settings.defaultCamera) {
                    ForEach(CameraSide.allCases) { side in
                        Text(side.label).tag(side)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)
            }
            Toggle("Mirror front camera", isOn: $settings.mirrorFrontCamera)
        } header: {
            Text("Camera")
        } footer: {
            Text("Mirrored videos look the way you see yourself in the preview. Recordings stay on this iPhone.")
        }
    }
}
