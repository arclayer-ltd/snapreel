import SwiftUI

/// The gear in the recorder. Same values as Settings › Recording.
struct RecordingSettingsSheet: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Recording settings", trailingTitle: "Done",
                        trailingAction: { dismiss() }, onStage: true)
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    qualitySection
                    countdownSection
                    togglesSection
                    Label("Recordings stay on this iPhone.", systemImage: "lock.fill")
                        .font(.srFootnote)
                        .foregroundStyle(Color.srStageTextTertiary)
                        .padding(.horizontal, Space.xxs)
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.xl)
            }
        }
        .background(Color.srStageRaised.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }

    private var qualitySection: some View {
        DarkSettingsSection(title: "Quality") {
            ForEach(RecordingQuality.allCases) { quality in
                Button {
                    Haptics.selection()
                    settings.recordingQuality = quality
                } label: {
                    HStack(spacing: Space.s) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(quality.label).font(.srBody).foregroundStyle(Color.srStageText)
                            Text(quality.detail).font(.srFootnote).foregroundStyle(Color.srStageTextSecondary)
                        }
                        Spacer()
                        if settings.recordingQuality == quality {
                            Image(systemName: "checkmark")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.srRed)
                        }
                    }
                    .padding(.vertical, Space.xs)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(settings.recordingQuality == quality ? .isSelected : [])
                if quality != RecordingQuality.allCases.last {
                    Divider().overlay(Color.srStageLine)
                }
            }
        }
    }

    private var countdownSection: some View {
        DarkSettingsSection(title: "Countdown before recording") {
            HStack(spacing: Space.xs) {
                ForEach(CountdownLength.allCases) { length in
                    let selected = settings.countdown == length
                    Button {
                        Haptics.selection()
                        settings.countdown = length
                    } label: {
                        Text(length == .off ? "Off" : "\(length.rawValue)s")
                            .font(.srSubheadlineStrong)
                            .foregroundStyle(selected ? Color.srStage : Color.srStageText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(Capsule().fill(selected ? Color.srStageText : Color.srStageControl))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(length.label)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.vertical, Space.xs)
        }
    }

    private var togglesSection: some View {
        DarkSettingsSection(title: "While recording") {
            DarkToggleRow(title: "Microphone on by default",
                          detail: "Camera recordings include your voice. For screen recordings, switch the microphone on in the system sheet.",
                          isOn: $settings.microphoneOnByDefault)
            Divider().overlay(Color.srStageLine)
            DarkToggleRow(title: "Mirror front camera",
                          detail: "Saves front camera videos the way you see yourself in the preview.",
                          isOn: $settings.mirrorFrontCamera)
            Divider().overlay(Color.srStageLine)
            DarkToggleRow(title: "Show speaker notes",
                          detail: "Your notes float over the camera while you record. They're never in the video.",
                          isOn: $settings.showsSpeakerNotes)
        }
    }
}

/// Rounded group with a small heading, in the stage colours.
private struct DarkSettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(title)
                .font(.srFootnote)
                .foregroundStyle(Color.srStageTextTertiary)
                .padding(.horizontal, Space.xxs)
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.xs)
            .background(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(Color.srStageGroup))
        }
    }
}

private struct DarkToggleRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.srBody).foregroundStyle(Color.srStageText)
                Text(detail).font(.srFootnote).foregroundStyle(Color.srStageTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(Color.srRed)
        .padding(.vertical, Space.xs)
    }
}

// MARK: - Speaker notes

/// The pencil-in-square: notes to read while you record.
struct SpeakerNotesSheet: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Speaker notes", trailingTitle: "Done",
                        trailingAction: { dismiss() }, onStage: true)
            VStack(alignment: .leading, spacing: Space.m) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $settings.speakerNotes)
                        .font(.srBody)
                        .foregroundStyle(Color.srStageText)
                        .scrollContentBackground(.hidden)
                        .focused($focused)
                        .padding(Space.xs)
                    if settings.speakerNotes.isEmpty {
                        Text("Jot down the points you want to cover. They scroll gently over the camera while you record.")
                            .font(.srBody)
                            .foregroundStyle(Color.srStageTextTertiary)
                            .padding(.horizontal, Space.s)
                            .padding(.vertical, Space.m)
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(Color.srStageControl))
                DarkToggleRow(title: "Show while recording",
                              detail: "Only you see them. They're never part of the video.",
                              isOn: $settings.showsSpeakerNotes)
                if !settings.speakerNotes.isEmpty {
                    Button("Clear notes", role: .destructive) {
                        Haptics.tap()
                        settings.speakerNotes = ""
                    }
                    .font(.srSubheadlineStrong)
                    .foregroundStyle(Color.srStageRed)
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.m)
        }
        .background(Color.srStageRaised.ignoresSafeArea())
        .presentationDetents([.large])
        .onChange(of: settings.speakerNotes) { text in
            // Writing notes is a strong hint they should show.
            if !text.isEmpty && !settings.showsSpeakerNotes && text.count == 1 {
                settings.showsSpeakerNotes = true
            }
        }
    }
}
