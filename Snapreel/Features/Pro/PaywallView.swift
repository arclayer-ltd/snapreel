import SwiftUI

/// Snapreel Pro: what it adds, the two plans with their prices, trial and renewal, Restore,
/// and the Terms of Use (EULA) and Privacy Policy, as App Review guideline 3.1.2 asks. It
/// opens from Settings and from the limits: a recording over 5 minutes, the 26th link, or a
/// Pro-only setting. Recording, the library and sending files stay free.
struct PaywallView: View {
    typealias Outcome = PurchaseEnding

    /// What the paywall is about right now. Every way a purchase can end has one.
    enum Stage: Equatable {
        /// The plans, with a note about the last try when there was one.
        case plans
        /// Just bought or restored.
        case welcome
        /// Already on Pro.
        case active
        /// Paid for; the server hasn't got it yet.
        case confirming
        /// This Apple Account's subscription is on another Snapreel account.
        case otherAccount(hint: String?, canMove: Bool)
        /// Paid for, and nobody signed in to have it.
        case signInNeeded
        /// The server doesn't accept the transaction.
        case refused
    }

    let reason: PaywallReason
    /// Something carries on after this (copying the link that met the limit).
    let continues: Bool
    let onClose: @MainActor () -> Void
    /// On Pro now: close, into what the person was doing.
    let onUnlocked: @MainActor () -> Void

    @ObservedObject private var store = PurchaseService.shared
    @ObservedObject private var auth = AuthService.shared
    @State private var selected: String
    /// Fixture screens: an ending to show without a purchase.
    @State private var fixedOutcome: Outcome
    @State private var isRestoring = false
    @State private var isSigningIn = false
    @State private var asksAboutMoving = false
    @State private var asksAboutSwitching = false

    init(reason: PaywallReason, selected: String = CloudConfig.yearlyProductID, outcome: Outcome = .none,
         continues: Bool = false, onClose: @escaping @MainActor () -> Void,
         onUnlocked: (@MainActor () -> Void)? = nil) {
        self.reason = reason
        self.continues = continues
        self.onClose = onClose
        self.onUnlocked = onUnlocked ?? onClose
        _selected = State(initialValue: selected)
        _fixedOutcome = State(initialValue: outcome)
    }

    private var plans: [ProPlan] { store.plans }
    private var selectedPlan: ProPlan? { plans.first { $0.id == selected } ?? plans.first }
    private var ending: PurchaseEnding { fixedOutcome == .none ? store.ending : fixedOutcome }
    private var isBusy: Bool { store.activity != nil || isRestoring || isSigningIn || store.isMoving }

    private var stage: Stage {
        Self.stage(standing: store.standing, ending: ending, isPro: auth.isPro,
                   serverIsPro: auth.me?.isPro == true, isSignedIn: auth.isSignedIn)
    }

    static func stage(standing: PurchaseService.Standing, ending: PurchaseEnding, isPro: Bool,
                      serverIsPro: Bool, isSignedIn: Bool) -> Stage {
        let justGotIt = ending == .purchased || ending == .restored
        // The server has this account on Pro, whichever Apple Account pays for it.
        if isSignedIn, serverIsPro { return justGotIt ? .welcome : .active }
        switch standing {
        case .confirming: return .confirming
        case .signInNeeded: return .signInNeeded
        case .refused: return .refused
        case .otherAccount(let hint, let canMove): return .otherAccount(hint: hint, canMove: canMove)
        case .none, .paymentProblem, .subscribed: break
        }
        if isPro { return justGotIt ? .welcome : .active }
        return .plans
    }

    var body: some View {
        // The hero runs up under the top edge; the close button stays inside the safe area.
        ZStack(alignment: .topTrailing) {
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(spacing: 0) {
                        hero
                        VStack(spacing: Space.xl) {
                            VStack(spacing: Space.xl) { main }
                                .id(Self.mainID)
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
                // Restore is at the very bottom, and what came of it at the top.
                .onChange(of: ending) { ending in
                    guard ending != .none else { return }
                    withAnimation(Motion.standard) { scroller.scrollTo(Self.mainID, anchor: .bottom) }
                }
                .onChange(of: stage) { _ in
                    withAnimation(Motion.standard) { scroller.scrollTo(Self.mainID, anchor: .bottom) }
                }
            }
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
        .animation(Motion.standard, value: stage)
        .animation(Motion.quick, value: ending)
        .task { await store.keepLoadingProducts() }
        .task(id: stage) { await leaveWhenUnlocked() }
        .onAppear { store.paywallOpened() }
        .onDisappear { store.paywallClosed() }
        .onChange(of: store.ending) { ending in
            switch ending {
            case .purchased, .restored, .alreadyYours: Haptics.success()
            case .failed: Haptics.error()
            case .none, .pending, .cancelled, .restoredNothing, .restoreCancelled: break
            }
        }
        .confirmationDialog("Move Snapreel Pro to this account?", isPresented: $asksAboutMoving, titleVisibility: .visible) {
            Button("Move Pro here") { Task { @MainActor in await store.moveHere() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Pro switches off on the other account, and its links go back to the Free limits. Your Apple subscription stays the same, and you aren't charged.")
        }
        .confirmationDialog("Sign in to the other account?", isPresented: $asksAboutSwitching, titleVisibility: .visible) {
            Button("Sign out and switch") { ProPresenter.switchAccount() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll sign out of \(auth.email ?? "this account") first. Your recordings stay on this iPhone, and links already shared keep working. Uploads that haven't finished stop.")
        }
    }

    /// Met on the way to something (a long recording, the 26th link, a Pro setting): once Pro is on,
    /// a moment to see it and then straight back to that. Opened from Settings, it stays.
    private func leaveWhenUnlocked() async {
        guard stage == .welcome, reason != .settings, fixedOutcome == .none,
              !UIAccessibility.isVoiceOverRunning else { return }
        try? await Task.sleep(nanoseconds: 1_800_000_000)
        guard !Task.isCancelled else { return }
        onUnlocked()
    }

    private static let mainID = "main"

    /// The plans, or what became of them.
    @ViewBuilder
    private var main: some View {
        switch stage {
        case .plans:
            planPicker
            buyBlock
        case .welcome: welcomeCard
        case .active: activeCard
        case .confirming: confirmingCard
        case .otherAccount(let hint, let canMove): otherAccountCard(hint: hint, canMove: canMove)
        case .signInNeeded: signInCard
        case .refused: refusedCard
        }
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
    private var showsProHero: Bool { stage == .welcome || stage == .active }

    private var heroTitle: String {
        switch stage {
        case .welcome, .active: return "You're on Pro"
        case .confirming: return "Almost there"
        case .otherAccount, .refused, .signInNeeded: return "You've got Snapreel Pro"
        case .plans: break
        }
        switch reason {
        case .settings: return "Share without limits"
        case .duration(let seconds): return "This recording is \(Format.clock(seconds))"
        case .links: return "You've used your \(CloudConfig.freeLinkLimit) free links"
        case .feature(let feature): return "\(feature.title) come with Pro"
        }
    }

    private var heroMessage: String {
        switch stage {
        case .welcome, .active: return "Thanks for supporting Snapreel. Everything below is switched on for your links."
        case .confirming: return "Apple has your payment. Pro is being switched on for your account."
        case .otherAccount: return "This Apple Account pays for it, on a different Snapreel account from this one."
        case .signInNeeded: return "This Apple Account has a subscription. Sign in to use it."
        case .refused: return "Apple has your payment, but Snapreel's server couldn't confirm it."
        case .plans: break
        }
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
                         saving: plan.period == .year ? store.yearlySaving : nil,
                         hasPrice: plan.isPurchasable) {
                    Haptics.selection()
                    withAnimation(Motion.quick) { selected = plan.id }
                }
            }
        }
    }

    private var buyBlock: some View {
        VStack(spacing: Space.s) {
            // Above the button, where the eye is after a tap and no phone is too small to show it.
            purchaseNote
            Button {
                buy()
            } label: {
                HStack(spacing: Space.xs) {
                    if store.activity != nil { ProgressView().tint(.white) }
                    Text(buyTitle)
                }
            }
            .buttonStyle(.srPrimary)
            .disabled(isBusy || !canBuy)

            if let plan = selectedPlan, canBuy {
                Text(renewalLine(plan))
                    .font(.srFootnote)
                    .foregroundStyle(Color.srTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !auth.isSignedIn {
                Text("You'll sign in first, so Pro belongs to your Snapreel account.")
                    .font(.srFootnote)
                    .foregroundStyle(Color.srTextTertiary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var canBuy: Bool { selectedPlan?.isPurchasable == true }

    /// How the last try ended, or why there's nothing to try yet.
    @ViewBuilder
    private var purchaseNote: some View {
        if let activity = store.activity {
            if activity.isSlow {
                VStack(spacing: Space.s) {
                    note("The App Store is taking longer than usual. If Apple's sheet isn't on screen, you can stop waiting and try again. You won't be charged twice.",
                         systemImage: "clock.fill")
                    Button("Stop waiting") { store.stopWaiting() }
                        .buttonStyle(.srSecondaryCompact)
                }
            }
        } else if case .failed(let message) = ending {
            note(message, systemImage: "exclamationmark.circle.fill", isError: true)
        } else if ending == .pending {
            note("Waiting for approval. Pro switches on by itself as soon as the purchase is approved, also while Snapreel is closed.",
                 systemImage: "hourglass")
        } else if ending == .cancelled {
            note("Not subscribed, and you haven't been charged. If Apple asked for your password, finish that step on Apple's sheet. Tap the button to try again.",
                 systemImage: "info.circle.fill")
        } else if ending == .restoreCancelled {
            note("Restore was cancelled, so nothing changed. Tap Restore Purchases to try again.",
                 systemImage: "info.circle.fill")
        } else if ending == .restoredNothing {
            note("No Snapreel Pro subscription was found for this Apple Account. If you bought it with another Apple Account, sign in to Snapreel with the account you used then.",
                 systemImage: "info.circle.fill")
        } else if store.standing == .paymentProblem {
            VStack(spacing: Space.s) {
                note("Apple couldn't charge your last renewal, so Pro is off. Update your payment details with Apple and it comes back by itself.",
                     systemImage: "creditcard.trianglebadge.exclamationmark", isError: true)
                manageButton
            }
        } else if !canBuy, store.loadFailed {
            VStack(spacing: Space.s) {
                note("The App Store isn't answering, so there are no prices yet. Trying again by itself.",
                     systemImage: "wifi.exclamationmark", isError: true)
                Button(store.isLoading ? "Trying…" : "Try now") { Task { @MainActor in await store.loadProducts() } }
                    .buttonStyle(.srSecondaryCompact)
                    .disabled(store.isLoading)
            }
        }
    }

    private var manageButton: some View {
        Button {
            store.manageSubscriptions()
        } label: {
            HStack(spacing: Space.xs) {
                if store.isOpeningManage { ProgressView() }
                Text(store.isOpeningManage ? "Opening Apple's page…" : "Manage subscription")
            }
        }
        .buttonStyle(.srSecondaryCompact)
        .disabled(store.isOpeningManage)
    }

    private var buyTitle: String {
        guard let plan = selectedPlan else { return "Subscribe" }
        switch store.activity?.phase {
        case .starting: return "One moment…"
        case .appStore: return "Waiting for the App Store…"
        case .confirming: return "Switching Pro on…"
        case nil: break
        }
        if isSigningIn { return "Signing in…" }
        if !canBuy { return store.loadFailed && !store.isLoading ? "Subscribe" : "Loading prices…" }
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
            if ending == .alreadyYours {
                note("You already have this, so nothing was bought and you weren't charged.", systemImage: "info.circle.fill")
            } else if ending == .cancelled {
                note("Your plan stays as it is, and you haven't been charged.", systemImage: "info.circle.fill")
            } else if ending == .pending {
                note("Waiting for approval. The change happens by itself once it's approved.", systemImage: "hourglass")
            } else if case .failed(let message) = ending {
                note(message, systemImage: "exclamationmark.circle.fill", isError: true)
            }
            if reason != .settings {
                Button(continueTitle) { onUnlocked() }
                    .buttonStyle(.srPrimary)
            }
            if let yearly = yearlyUpgrade {
                Button {
                    buy(yearly.id)
                } label: {
                    HStack(spacing: Space.xs) {
                        if store.activity != nil { ProgressView() }
                        Text(store.activity == nil ? "Switch to yearly, \(yearly.displayPrice)" : "Waiting for the App Store…")
                    }
                }
                .buttonStyle(.srSecondary)
                .disabled(isBusy)
                Text("Apple takes off what's left of your month.")
                    .font(.srFootnote)
                    .foregroundStyle(Color.srTextTertiary)
            }
            manageButton
        }
        .padding(Space.m)
        .srCard()
    }

    /// The yearly plan, for someone paying monthly on this Apple Account.
    private var yearlyUpgrade: ProPlan? {
        guard store.activeProductID == CloudConfig.monthlyProductID, store.nextProductID != CloudConfig.yearlyProductID,
              let yearly = plans.first(where: { $0.period == .year }), yearly.isPurchasable else { return nil }
        return yearly
    }

    private var activeDetail: String {
        let product = store.activeProductID ?? auth.me?.plan.productId
        let name = product == CloudConfig.monthlyProductID ? "Monthly" : "Yearly"
        guard let expiry = store.activeExpiry ?? auth.me?.plan.expiresAt else {
            return "\(name) plan, managed by the App Store."
        }
        let date = ProText.longDate(expiry)
        if store.willRenew == false { return "\(name) plan. Ends on \(date)." }
        if let next = store.nextProductID, next != product {
            return "\(name) plan. Changes to \(next == CloudConfig.monthlyProductID ? "monthly" : "yearly") on \(date)."
        }
        return "\(name) plan. Renews on \(date)."
    }

    // MARK: Paid for, but not on here

    private var confirmingCard: some View {
        stateCard(systemImage: "checkmark.circle.fill", title: "Payment received",
                  text: "Snapreel's server hasn't confirmed it yet, usually because of the connection. Snapreel keeps trying by itself, also after you close this. Don't buy it again.") {
            Button {
                Task { @MainActor in await store.confirmNow() }
            } label: {
                HStack(spacing: Space.xs) {
                    ProgressView().tint(.white)
                    Text("Try now")
                }
            }
            .buttonStyle(.srPrimary)
        }
    }

    private func otherAccountCard(hint: String?, canMove: Bool) -> some View {
        stateCard(systemImage: "person.2.fill", title: "Pro is on another account",
                  text: otherAccountText(hint: hint)) {
            if case .failed(let message) = ending {
                note(message, systemImage: "exclamationmark.circle.fill", isError: true)
            }
            Button("Sign in to that account") { asksAboutSwitching = true }
                .buttonStyle(.srPrimary)
                .disabled(isBusy)
            if canMove {
                Button {
                    asksAboutMoving = true
                } label: {
                    HStack(spacing: Space.xs) {
                        if store.isMoving { ProgressView() }
                        Text(store.isMoving ? "Moving…" : "Use Pro on this account instead")
                    }
                }
                .buttonStyle(.srSecondary)
                .disabled(isBusy)
            }
        }
    }

    private func otherAccountText(hint: String?) -> String {
        let whose = hint.map { "It belongs to \($0)." } ?? "It belongs to a different Snapreel account."
        let here = auth.email.map { " You're signed in as \($0)." } ?? ""
        return "\(whose)\(here) You don't need to buy it again."
    }

    private var signInCard: some View {
        stateCard(systemImage: "person.crop.circle.badge.checkmark", title: "Sign in to use it",
                  text: "Snapreel Pro belongs to a Snapreel account. Sign in with the one you use, and Pro switches on. You won't be charged again.") {
            Button(isSigningIn ? "Signing in…" : "Sign in") { signIn() }
                .buttonStyle(.srPrimary)
                .disabled(isSigningIn)
        }
    }

    private var refusedCard: some View {
        stateCard(systemImage: "exclamationmark.triangle.fill", title: "Couldn't confirm it",
                  text: "Your subscription is safe with Apple, and you don't need to buy it again. Update Snapreel and try again; if it still doesn't switch on, write to support@snapreel.video.") {
            Button("Try again") { Task { @MainActor in await store.confirmNow() } }
                .buttonStyle(.srPrimary)
        }
    }

    private func stateCard<Actions: View>(systemImage: String, title: String, text: String,
                                          @ViewBuilder actions: () -> Actions) -> some View {
        VStack(spacing: Space.s) {
            ZStack {
                Circle().fill(Color.srRedSoft)
                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.srRed)
            }
            .frame(width: 64, height: 64)
            .accessibilityHidden(true)
            Text(title)
                .font(.srTitle)
                .foregroundStyle(Color.srText)
                .multilineTextAlignment(.center)
            Text(text)
                .font(.srSubheadline)
                .foregroundStyle(Color.srTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: Space.s) { actions() }
                .padding(.top, Space.xs)
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity)
        .srCard()
    }

    /// What closing a paywall someone met on the way leads to.
    private var continueTitle: String {
        switch reason {
        case .duration, .links: return continues ? "Copy the link" : "Continue"
        case .settings: return "Done"
        case .feature: return "Continue"
        }
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
            Text(ending == .restored ? "Pro is back" : "Welcome to Pro")
                .font(.srTitle)
                .foregroundStyle(Color.srText)
            Text("Your links can now be any length up to 2 hours, in 1080p, with passwords, expiry and full insights.")
                .font(.srSubheadline)
                .foregroundStyle(Color.srTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(continueTitle) { onUnlocked() }
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
                FeatureRow(systemImage: "clock.fill", title: "Videos up to 2 hours", detail: "Free links hold up to 5 minutes")
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
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
            .disabled(isBusy)
            divider
            NavigationLink(value: LegalDocument.terms) {
                Text("Terms of Use (EULA)")
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            divider
            NavigationLink(value: LegalDocument.privacy) {
                Text("Privacy Policy")
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
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

    /// Buys the chosen plan, signing in first when needed. `PurchaseService` takes the tap at once, so
    /// a second one can't start another purchase.
    private func buy(_ productID: String? = nil) {
        guard let id = productID ?? selectedPlan?.id, !isBusy else { return }
        store.clearEnding()
        guard auth.isSignedIn else {
            isSigningIn = true
            // Completes once the sign-in sheet has gone, so Apple's comes up on a still screen.
            ProPresenter.signIn(reason: .subscribe) { signedIn in
                isSigningIn = false
                if signedIn { store.buy(id) }
            }
            return
        }
        store.buy(id)
    }

    private func signIn() {
        isSigningIn = true
        ProPresenter.signIn(reason: .subscribe) { signedIn in
            isSigningIn = false
            if signedIn { Task { @MainActor in await store.confirmNow() } }
        }
    }

    private func restore() {
        isRestoring = true
        Task { @MainActor in
            await store.restoreForPaywall()
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
    /// The App Store's price has loaded.
    let hasPrice: Bool
    let action: @MainActor () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button {
            action()
        } label: {
            Group {
                if typeSize.isAccessibilitySize {
                    // One thing under another, so no word or price is broken in two.
                    VStack(alignment: .leading, spacing: Space.xs) {
                        HStack(spacing: Space.s) {
                            radio
                            Text(plan.title)
                                .font(.srHeadline)
                                .foregroundStyle(Color.srText)
                        }
                        savingBadge
                        Text(subtitle)
                            .font(.srFootnote)
                            .foregroundStyle(Color.srTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .redacted(reason: hasPrice ? [] : .placeholder)
                        (Text(plan.displayPrice).font(.srTitle3.monospacedDigit()).foregroundColor(.srText)
                            + Text(" " + plan.periodText).font(.srFootnote).foregroundColor(.srTextTertiary))
                            .fixedSize(horizontal: false, vertical: true)
                            .redacted(reason: hasPrice ? [] : .placeholder)
                            .accessibilityHidden(!hasPrice)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(alignment: .center, spacing: Space.s) {
                        radio
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: Space.xs) {
                                Text(plan.title)
                                    .font(.srHeadline)
                                    .foregroundStyle(Color.srText)
                                savingBadge
                            }
                            Text(subtitle)
                                .font(.srFootnote)
                                .foregroundStyle(Color.srTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .redacted(reason: hasPrice ? [] : .placeholder)
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
                        .redacted(reason: hasPrice ? [] : .placeholder)
                        .accessibilityHidden(!hasPrice)
                    }
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

    private var radio: some View {
        ZStack {
            Circle().strokeBorder(isSelected ? Color.srRed : Color.srLine, lineWidth: 2)
            if isSelected {
                Circle().fill(Color.srRed).padding(5)
            }
        }
        .frame(width: 24, height: 24)
    }

    @ViewBuilder private var savingBadge: some View {
        if let saving {
            Text("Save \(saving)%")
                .font(.srCaption)
                .foregroundStyle(Color.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.srRed))
                .fixedSize()
        }
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
            // Kept in the band above the text (it starts 84 pt down), clear of the close button, however large the
            // text makes the hero.
            sparkle(size: 24, x: 0.66, y: 40)
            sparkle(size: 11, x: 0.53, y: 22)
            sparkle(size: 14, x: 0.78, y: 68)
            sparkle(size: 9, x: 0.42, y: 52)
        }
        .clipped()
        .accessibilityHidden(true)
    }

    private func sparkle(size: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        GeometryReader { proxy in
            Image(systemName: "sparkle")
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.92))
                .position(x: proxy.size.width * x, y: y)
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
