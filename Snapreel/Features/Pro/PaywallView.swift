import SwiftUI

/// Snapreel Pro: what it adds, the two plans with their prices, trial and renewal, Restore,
/// and the Terms of Use (EULA) and Privacy Policy, as App Review guideline 3.1.2 asks. It
/// opens from Settings and from the limits: a recording over 5 minutes, the 26th link, or a
/// Pro-only setting. Recording, the library and sending files stay free.
struct PaywallView: View {
    enum Outcome: Equatable {
        case none
        case purchased
        case pending
        case restoredNothing
    }

    let reason: PaywallReason
    let onClose: @MainActor () -> Void

    @ObservedObject private var store = PurchaseService.shared
    @ObservedObject private var auth = AuthService.shared
    @State private var selected: String
    @State private var outcome: Outcome
    @State private var error: String?
    @State private var isRestoring = false

    init(reason: PaywallReason, selected: String = CloudConfig.yearlyProductID, outcome: Outcome = .none,
         onClose: @escaping @MainActor () -> Void) {
        self.reason = reason
        self.onClose = onClose
        _selected = State(initialValue: selected)
        _outcome = State(initialValue: outcome)
    }

    private var plans: [ProPlan] { store.plans }
    private var selectedPlan: ProPlan? { plans.first { $0.id == selected } ?? plans.first }

    var body: some View {
        // The hero runs up under the top edge; the close button stays inside the safe area.
        ZStack(alignment: .topTrailing) {
            ScrollView {
                VStack(spacing: 0) {
                    hero
                    VStack(spacing: Space.xl) {
                        if auth.isPro && outcome == .none {
                            activeCard
                        } else if outcome == .purchased {
                            welcomeCard
                        } else {
                            planPicker
                            buyBlock
                        }
                        features
                        finePrint
                        links
                    }
                    .padding(.horizontal, Space.gutter)
                    .padding(.top, Space.l)
                    .padding(.bottom, Space.xxxl)
                }
            }
            .ignoresSafeArea(edges: .top)
            CircleIconButton(systemName: "xmark", label: "Close", tone: .glass, size: 32) { onClose() }
                .padding(Space.m)
        }
        .background(Color.srCanvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: LegalDocument.self) { document in
            LegalDocumentView(document: document)
                .navigationTitle(document.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.visible, for: .navigationBar)
                .background(Color.srCanvas.ignoresSafeArea())
        }
        .task { await store.loadProducts() }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Space.s) {
                HStack(spacing: Space.xs) {
                    Image("BrandMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 26, height: 26)
                    Text("Snapreel")
                        .font(.srHeadline)
                        .foregroundStyle(Color.white)
                    ProBadge()
                }
                Text(heroTitle)
                    .font(.srDisplay)
                    .foregroundStyle(Color.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(heroMessage)
                    .font(.srSubheadline)
                    .foregroundStyle(Color.white.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.l)
            .padding(.top, 84)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ProHeroBackground())
    }

    /// Already Pro, or just subscribed.
    private var showsProHero: Bool { outcome == .purchased || (auth.isPro && outcome == .none) }

    private var heroTitle: String {
        if showsProHero { return "You're on Pro" }
        switch reason {
        case .settings: return "Share without limits"
        case .duration(let seconds): return "This recording is \(Format.clock(seconds))"
        case .links: return "You've used your \(CloudConfig.freeLinkLimit) free links"
        case .feature(let feature): return "\(feature.title) come with Pro"
        }
    }

    private var heroMessage: String {
        if showsProHero { return "Thanks for supporting Snapreel. Everything below is switched on for your links." }
        switch reason {
        case .settings:
            return "Unlimited share links, longer videos in sharper quality, and the full story of who watched."
        case .duration:
            return "Free links take recordings up to 5 minutes. With Pro, a link can hold up to 2 hours."
        case .links:
            return "Pro has no limit on links. Or stop sharing an old link to free up a space."
        case .feature(let feature):
            return feature == .insights
                ? "See who watched, how far they got and where they stopped."
                : "Control who can watch, for how long, and what they can do with your video."
        }
    }

    // MARK: Plans

    private var planPicker: some View {
        VStack(spacing: Space.s) {
            ForEach(plans) { plan in
                PlanCard(plan: plan, isSelected: plan.id == selectedPlan?.id,
                         saving: plan.period == .year ? store.yearlySaving : nil) {
                    Haptics.selection()
                    withAnimation(Motion.quick) { selected = plan.id }
                }
            }
        }
    }

    private var buyBlock: some View {
        VStack(spacing: Space.s) {
            Button {
                buy()
            } label: {
                HStack(spacing: Space.xs) {
                    if store.purchasing != nil { ProgressView().tint(.white) }
                    Text(buyTitle)
                }
            }
            .buttonStyle(.srPrimary)
            .disabled(store.purchasing != nil || isRestoring || !(selectedPlan?.isPurchasable ?? false) && !isDebugPlans)

            if let plan = selectedPlan {
                Text(renewalLine(plan))
                    .font(.srFootnote)
                    .foregroundStyle(Color.srTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if outcome == .pending {
                note("Waiting for approval. Pro switches on as soon as the purchase is approved.", systemImage: "hourglass")
            } else if outcome == .restoredNothing {
                note("No Snapreel Pro subscription was found for this Apple Account.", systemImage: "info.circle.fill")
            } else if let error {
                note(error, systemImage: "exclamationmark.circle.fill", isError: true)
            } else if store.loadFailed && !isDebugPlans {
                note("The App Store isn't answering, so prices may be out of date. Check your connection.",
                     systemImage: "wifi.exclamationmark", isError: true)
            }
            if !auth.isSignedIn {
                Text("You'll sign in first, so Pro belongs to your Snapreel account.")
                    .font(.srFootnote)
                    .foregroundStyle(Color.srTextTertiary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var isDebugPlans: Bool {
        #if DEBUG
        return store.debugPlans != nil
        #else
        return false
        #endif
    }

    private var buyTitle: String {
        guard let plan = selectedPlan else { return "Subscribe" }
        if store.purchasing != nil { return "Waiting for the App Store…" }
        if !plan.isPurchasable && !isDebugPlans { return store.isLoading ? "Loading prices…" : "Subscribe" }
        if let days = plan.trialDays { return "Try \(ProPlan.trialText(days)) free" }
        return "Subscribe for \(plan.displayPrice) \(plan.periodText)"
    }

    private func renewalLine(_ plan: ProPlan) -> String {
        if let days = plan.trialDays {
            return "\(ProPlan.trialText(days).capitalizedFirst) free, then \(plan.displayPrice) \(plan.periodText). Renews automatically. Cancel any time in Settings."
        }
        return "\(plan.displayPrice) \(plan.periodText). Renews automatically. Cancel any time in Settings."
    }

    private func note(_ text: String, systemImage: String, isError: Bool = false) -> some View {
        Label(text, systemImage: systemImage)
            .font(.srFootnote)
            .foregroundStyle(isError ? Color.srRedText : Color.srTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.s)
            .background(RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                .fill(isError ? Color.srRedSoft : Color.srFill))
    }

    // MARK: Pro already

    private var activeCard: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Label("Snapreel Pro", systemImage: "checkmark.seal.fill")
                    .font(.srHeadline)
                    .foregroundStyle(Color.srText)
                Spacer()
                ProBadge()
            }
            Text(activeDetail)
                .font(.srSubheadline)
                .foregroundStyle(Color.srTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Manage subscription") { store.manageSubscriptions() }
                .buttonStyle(.srSecondaryCompact)
        }
        .padding(Space.m)
        .srCard()
    }

    private var activeDetail: String {
        let product = store.activeProductID ?? auth.me?.plan.productId
        let name = product == CloudConfig.monthlyProductID ? "Monthly" : "Yearly"
        if let expiry = store.activeExpiry ?? auth.me?.plan.expiresAt {
            let renews = store.willRenew ?? true
            return "\(name) plan. \(renews ? "Renews" : "Ends") on \(ProText.longDate(expiry))."
        }
        return "\(name) plan, managed by the App Store."
    }

    private var welcomeCard: some View {
        VStack(spacing: Space.s) {
            ZStack {
                Circle().fill(Color.srRedSoft)
                Image(systemName: "checkmark")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Color.srRed)
            }
            .frame(width: 64, height: 64)
            Text("Welcome to Pro")
                .font(.srTitle)
                .foregroundStyle(Color.srText)
            Text("Your links can now be any length up to 2 hours, in 1080p, with passwords, expiry and full insights.")
                .font(.srSubheadline)
                .foregroundStyle(Color.srTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Done") { onClose() }
                .buttonStyle(.srPrimary)
                .padding(.top, Space.xs)
        }
        .padding(Space.l)
        .srCard()
    }

    // MARK: Features

    private var features: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("WHAT YOU GET")
                .font(.srCaption)
                .kerning(0.6)
                .foregroundStyle(Color.srTextTertiary)
                .padding(.horizontal, Space.xxs)
                .padding(.bottom, Space.xs)
            VStack(spacing: 0) {
                FeatureRow(systemImage: "link", title: "Unlimited share links", detail: "Free has \(CloudConfig.freeLinkLimit) at a time")
                FeatureRow(systemImage: "clock.fill", title: "Videos up to 2 hours", detail: "Free links take up to 5 minutes")
                FeatureRow(systemImage: "sparkles.tv.fill", title: "1080p on the web", detail: "Free plays at 720p")
                FeatureRow(systemImage: "chart.bar.xaxis", title: "Who watched and how far", detail: "Viewers, drop-off chart and countries")
                FeatureRow(systemImage: "lock.fill", title: "Passwords, expiry and downloads", detail: "Decide who watches, and for how long")
                FeatureRow(systemImage: "hand.tap.fill", title: "Your button, your colour", detail: "A call to action, and no Snapreel badge", isLast: true)
            }
            .srCard()
            Label("Recording, your library, transcripts and sending files stay free for everyone.",
                  systemImage: "heart.fill")
                .font(.srFootnote)
                .foregroundStyle(Color.srTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Space.xxs)
                .padding(.top, Space.s)
        }
    }

    // MARK: Fine print and links

    private var finePrint: some View {
        Text("Payment is charged to your Apple Account when you confirm the purchase; with a free trial, when the trial ends. The subscription renews automatically at the same price and for the same period unless you cancel at least 24 hours before the current period ends. Manage or cancel it any time in Settings › your name › Subscriptions. Any unused part of a free trial ends when you buy a subscription. Prices include tax where it applies.")
            .font(.srFootnote)
            .foregroundStyle(Color.srTextTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var links: some View {
        HStack(spacing: 0) {
            Button {
                restore()
            } label: {
                if isRestoring {
                    ProgressView()
                } else {
                    Text("Restore Purchases")
                }
            }
            .frame(maxWidth: .infinity)
            .disabled(isRestoring || store.purchasing != nil)
            divider
            NavigationLink(value: LegalDocument.terms) {
                Text("Terms of Use (EULA)")
            }
            .frame(maxWidth: .infinity)
            divider
            NavigationLink(value: LegalDocument.privacy) {
                Text("Privacy Policy")
            }
            .frame(maxWidth: .infinity)
        }
        .font(.srFootnote.weight(.semibold))
        .foregroundStyle(Color.srRedText)
        .lineLimit(2)
        .multilineTextAlignment(.center)
    }

    private var divider: some View {
        Rectangle().fill(Color.srLine).frame(width: 1, height: 28)
    }

    // MARK: Actions

    private func buy() {
        guard let plan = selectedPlan else { return }
        error = nil
        guard auth.isSignedIn else {
            ProPresenter.signIn(reason: .subscribe) { signedIn in
                if signedIn { buy() }
            }
            return
        }
        Task { @MainActor in
            do {
                switch try await store.purchase(plan.id) {
                case .purchased:
                    Haptics.success()
                    withAnimation(Motion.standard) { outcome = .purchased }
                case .pending:
                    withAnimation(Motion.standard) { outcome = .pending }
                case .cancelled:
                    break
                }
            } catch {
                Haptics.error()
                self.error = (error as? LocalizedError)?.errorDescription ?? (error as? CloudError)?.message
                    ?? "The purchase didn't go through. You haven't been charged."
            }
        }
    }

    private func restore() {
        isRestoring = true
        error = nil
        Task { @MainActor in
            do {
                let found = try await store.restore()
                Haptics.success()
                withAnimation(Motion.standard) { outcome = found ? .purchased : .restoredNothing }
            } catch {
                self.error = "Restore didn't finish. Check your connection and try again."
            }
            isRestoring = false
        }
    }
}

// MARK: - Pieces

/// One plan to pick: title, price and period, and the trial or per-month line.
private struct PlanCard: View {
    let plan: ProPlan
    let isSelected: Bool
    let saving: Int?
    let action: @MainActor () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack(alignment: .center, spacing: Space.s) {
                ZStack {
                    Circle().strokeBorder(isSelected ? Color.srRed : Color.srLine, lineWidth: 2)
                    if isSelected {
                        Circle().fill(Color.srRed).padding(5)
                    }
                }
                .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: Space.xs) {
                        Text(plan.title)
                            .font(.srHeadline)
                            .foregroundStyle(Color.srText)
                        if let saving {
                            Text("Save \(saving)%")
                                .font(.srCaption)
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.srRed))
                        }
                    }
                    Text(subtitle)
                        .font(.srFootnote)
                        .foregroundStyle(Color.srTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.xs)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(plan.displayPrice)
                        .font(.srTitle3.monospacedDigit())
                        .foregroundStyle(Color.srText)
                    Text(plan.periodText)
                        .font(.srFootnote)
                        .foregroundStyle(Color.srTextTertiary)
                }
            }
            .padding(Space.m)
            .background(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(Color.srSurface))
            .overlay(RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
                .strokeBorder(isSelected ? Color.srRed : Color.srLine, lineWidth: isSelected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var subtitle: String {
        if let days = plan.trialDays {
            return "\(ProPlan.trialText(days).capitalizedFirst) free, then \(plan.displayPrice) \(plan.periodText)"
        }
        if let perMonth = plan.perMonth { return "Just \(perMonth)" }
        return "Billed every month"
    }
}

private struct FeatureRow: View {
    let systemImage: String
    let title: String
    let detail: String
    var isLast = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.s) {
                IconTile(systemName: systemImage, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.srSubheadlineStrong)
                        .foregroundStyle(Color.srText)
                    Text(detail)
                        .font(.srFootnote)
                        .foregroundStyle(Color.srTextSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.srRed)
            }
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.s)
            if !isLast {
                SettingsDivider(inset: Space.m + 34 + Space.s)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The paywall's top: one saturated red field with soft light pools, a faint grid and white
/// four-point sparkles.
struct ProHeroBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x5E0B16), Color(hex: 0x8F1424), Color(hex: 0xF04850)],
                           startPoint: .bottomLeading, endPoint: .topTrailing)
            RadialGradient(colors: [Color(hex: 0xFE6262).opacity(0.75), .clear],
                           center: UnitPoint(x: 0.85, y: 0.15), startRadius: 0, endRadius: 260)
            RadialGradient(colors: [Color.white.opacity(0.16), .clear],
                           center: UnitPoint(x: 0.2, y: 0.35), startRadius: 0, endRadius: 200)
            GridPattern()
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
            // Kept in the band above the text, clear of the close button.
            sparkle(size: 24, x: 0.66, y: 0.15)
            sparkle(size: 11, x: 0.53, y: 0.08)
            sparkle(size: 14, x: 0.78, y: 0.27)
            sparkle(size: 9, x: 0.42, y: 0.2)
        }
        .clipped()
        .accessibilityHidden(true)
    }

    private func sparkle(size: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        GeometryReader { proxy in
            Image(systemName: "sparkle")
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.92))
                .position(x: proxy.size.width * x, y: proxy.size.height * y)
        }
    }
}

/// A faint square grid.
struct GridPattern: Shape {
    var spacing: CGFloat = 28

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x: CGFloat = 0
        while x <= rect.maxX {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += spacing
        }
        var y: CGFloat = 0
        while y <= rect.maxY {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += spacing
        }
        return path
    }
}

extension String {
    /// "1 week" → "1 week" ; "week" → "Week".
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
