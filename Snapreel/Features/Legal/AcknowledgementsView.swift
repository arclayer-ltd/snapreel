import SwiftUI

/// What Snapreel is built with: Apple frameworks, SQLite, SF Symbols and its own character art.
/// Snapreel includes no third-party code.
struct AcknowledgementsView: View {
    private struct Credit: Identifiable {
        let name: String
        let detail: String
        var id: String { name }
    }

    private let frameworks: [Credit] = [
        Credit(name: "SwiftUI and UIKit", detail: "Every screen you see"),
        Credit(name: "AVFoundation and AVKit", detail: "Camera and microphone recording, playback and picture in picture"),
        Credit(name: "ReplayKit", detail: "Recording your screen"),
        Credit(name: "Speech", detail: "Transcripts made on this iPhone"),
        Credit(name: "Photos and PhotosUI", detail: "Importing videos and saving to Photos"),
        Credit(name: "User Notifications", detail: "Letting you know when recordings and transcripts are ready"),
        Credit(name: "MessageUI", detail: "Writing to support from the app"),
        Credit(name: "Foundation Models", detail: "Short summaries on iPhones with Apple Intelligence"),
    ]

    init() {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                intro
                SettingsGroup(title: "Apple frameworks") {
                    ForEach(Array(frameworks.enumerated()), id: \.element.id) { offset, credit in
                        if offset > 0 { SettingsDivider(inset: Space.m) }
                        creditRow(credit)
                    }
                }
                SettingsGroup(title: "Database") {
                    creditRow(Credit(name: "SQLite",
                                     detail: "Keeps your library in order. SQLite is in the public domain, and we're grateful to its authors."))
                }
                SettingsGroup(title: "Symbols") {
                    creditRow(Credit(name: "SF Symbols",
                                     detail: "Icons by Apple, used under Apple's licence for apps on its platforms."))
                }
                SettingsGroup(title: "Illustration") {
                    creditRow(Credit(name: "Maya, Jun, Theo, Priya and Leo",
                                     detail: "Original characters drawn and animated for Snapreel."))
                }
                Text("Snapreel uses no third-party libraries, analytics or advertising code.")
                    .font(.srFootnote)
                    .foregroundStyle(Color.srTextSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.s)
            .padding(.bottom, Space.xxl)
        }
        .background(Color.srCanvas.ignoresSafeArea())
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("Built with care, and with help")
                .font(.srTitle)
                .foregroundStyle(Color.srText)
                .accessibilityAddTraits(.isHeader)
            Text("Snapreel stands on the shoulders of these tools. Thank you to everyone who made them.")
                .font(.srCallout)
                .foregroundStyle(Color.srTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func creditRow(_ credit: Credit) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(credit.name)
                .font(.srBody)
                .foregroundStyle(Color.srText)
            Text(credit.detail)
                .font(.srFootnote)
                .foregroundStyle(Color.srTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
        .accessibilityElement(children: .combine)
    }
}
