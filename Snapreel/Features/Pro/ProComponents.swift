import SwiftUI

// Small pieces shared by the Snapreel Pro screens: the PRO badge, the "Shared · 12 views"
// badge, the upsell card and the link-state line.

/// "PRO" in a small red capsule.
struct ProBadge: View {
    var compact = false

    var body: some View {
        Text("PRO")
            .font(.system(size: compact ? 9 : 11, weight: .heavy, design: .rounded))
            .kerning(0.6)
            .foregroundStyle(Color.white)
            .padding(.horizontal, compact ? 5 : 7)
            .padding(.vertical, compact ? 2 : 3)
            .background(Capsule().fill(LinearGradient(colors: [Color.srRedGlow, Color.srRedDeep],
                                                      startPoint: .topLeading, endPoint: .bottomTrailing)))
            .accessibilityLabel("Snapreel Pro")
    }
}

/// The red app mark on a soft tile, for sheet headers.
struct ProMark: View {
    var size: CGFloat = 56

    var body: some View {
        Image("BrandMark")
            .resizable()
            .scaledToFit()
            .frame(width: size * 0.62, height: size * 0.62)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(Color.srInk))
            .overlay(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            .shadow(color: Color.srRed.opacity(0.28), radius: 14, y: 6)
            .accessibilityHidden(true)
    }
}

/// "Shared · 12 views" on cards and in the player, or the upload's progress while it runs.
struct SharedBadge: View {
    let link: CloudLink
    let state: LinkState
    /// On the recorder and player (stage colours).
    var onStage = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(verbatim: label)
                .lineLimit(1)
        }
        .font(.srCaption)
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(background))
        .accessibilityElement(children: .combine)
    }

    private var label: String {
        switch state {
        case .creating, .preparing: return "Preparing link"
        case .uploading(let value), .waitingForNetwork(let value): return "Uploading \(Int((value * 100).rounded()))%"
        case .finishing: return "Finishing upload"
        case .failed: return "Upload stopped"
        case .ready, .notShared: return link.sharedLabel
        }
    }

    private var icon: String {
        switch state {
        case .failed: return "exclamationmark.triangle.fill"
        case .uploading, .waitingForNetwork, .creating, .preparing, .finishing: return "arrow.up.circle.fill"
        case .ready, .notShared: return "link"
        }
    }

    private var tint: Color {
        if case .failed = state { return onStage ? .srStageRed : .srRedText }
        return onStage ? .srStageRed : .srRedText
    }

    private var background: Color {
        onStage ? Color.srRed.opacity(0.14) : Color.srRedSoft
    }
}

/// A soft card that explains a Pro feature, with "See Snapreel Pro".
struct ProUpsellCard: View {
    let title: String
    let message: String
    var onStage = false
    let action: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.xs) {
                ProBadge()
                Text(title)
                    .font(.srHeadline)
                    .foregroundStyle(onStage ? Color.srStageText : Color.srText)
            }
            Text(message)
                .font(.srSubheadline)
                .foregroundStyle(onStage ? Color.srStageTextSecondary : Color.srTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Haptics.tap()
                action()
            } label: {
                Text("See Snapreel Pro")
            }
            .buttonStyle(.srPrimaryCompact)
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
                .fill(LinearGradient(colors: [Color.srRed.opacity(0.14), Color.srRed.opacity(0.04)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
            .strokeBorder(Color.srRed.opacity(0.22), lineWidth: 1))
    }
}

/// A progress bar in brand red.
struct LinkProgressBar: View {
    let fraction: Double
    var onStage = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(onStage ? Color.srStageText.opacity(0.12) : Color.srFill)
                Capsule().fill(Color.srRed)
                    .frame(width: max(8, proxy.size.width * CGFloat(min(1, max(0, fraction)))))
            }
        }
        .frame(height: 6)
        .animation(Motion.standard, value: fraction)
        .accessibilityElement()
        .accessibilityLabel("Upload progress")
        .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
    }
}

/// Text helpers for the Pro screens.
enum ProText {
    /// "12 views", "1 view".
    static func views(_ count: Int) -> String { count == 1 ? "1 view" : "\(count) views" }
    static func viewers(_ count: Int) -> String { count == 1 ? "1 viewer" : "\(count) viewers" }
    static func comments(_ count: Int) -> String { count == 1 ? "1 comment" : "\(count) comments" }

    /// 🇬🇧 from "GB".
    static func flag(_ code: String?) -> String {
        guard let code, code.count == 2 else { return "🌐" }
        let base: UInt32 = 127_397
        return code.uppercased().unicodeScalars.compactMap { UnicodeScalar(base + $0.value) }
            .map(String.init).joined()
    }

    /// "United Kingdom" from "GB".
    static func country(_ code: String?) -> String {
        guard let code else { return "Somewhere" }
        return Locale.current.localizedString(forRegionCode: code) ?? code
    }

    /// "Mar 2027" style date for renewals: "20 November 2027".
    static func longDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.setLocalizedDateFormatFromTemplate("d MMMM yyyy")
        return formatter.string(from: date)
    }
}
