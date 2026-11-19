import SwiftUI

/// The bundled legal documents.
enum LegalDocument: String, CaseIterable, Identifiable, Hashable {
    case terms
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .terms: return "Terms of use"
        case .privacy: return "Privacy policy"
        }
    }

    var systemImage: String {
        switch self {
        case .terms: return "doc.plaintext.fill"
        case .privacy: return "hand.raised.fill"
        }
    }

    /// Markdown file in the app bundle (copied flat from Features/Legal).
    var resourceName: String {
        switch self {
        case .terms: return "legal-terms"
        case .privacy: return "legal-privacy"
        }
    }
}

/// Legal: privacy at a glance, then terms of use, privacy policy and acknowledgements.
struct LegalMenuView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                privacyAtAGlance
                SettingsGroup {
                    SettingsLinkRow(page: .legalDocument(.terms), systemImage: LegalDocument.terms.systemImage,
                                    title: LegalDocument.terms.title)
                    SettingsDivider()
                    SettingsLinkRow(page: .legalDocument(.privacy), systemImage: LegalDocument.privacy.systemImage,
                                    title: LegalDocument.privacy.title)
                    SettingsDivider()
                    SettingsLinkRow(page: .acknowledgements, systemImage: "heart.text.square.fill",
                                    title: "Acknowledgements")
                }
                Text(copyright)
                    .font(.srFootnote)
                    .foregroundStyle(Color.srTextTertiary)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.s)
            .padding(.bottom, Space.xxl)
        }
        .background(Color.srCanvas.ignoresSafeArea())
        .navigationTitle("Legal")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var copyright: String {
        let year = Calendar.current.component(.year, from: Date())
        return "© \(String(year)) \(AppInfo.publisher)"
    }

    private var privacyAtAGlance: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                IconTile(systemName: "lock.shield.fill", tint: .white, background: .srRed, size: 36)
                Text("Private by design")
                    .font(.srTitle3)
                    .foregroundStyle(Color.srText)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: Space.xs) {
                glanceLine("person.crop.circle", "No account needed, except to share links")
                glanceLine("chart.bar.xaxis", "No analytics, advertising or tracking")
                glanceLine("iphone", "Recordings stay on this iPhone until you send them or share a link")
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(Color.srRedSoft))
        .accessibilityElement(children: .combine)
    }

    private func glanceLine(_ systemImage: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.srRedText)
                .frame(width: 22)
            Text(text)
                .font(.srSubheadline)
                .foregroundStyle(Color.srText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
