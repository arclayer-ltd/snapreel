import SwiftUI

/// Settings › Account: who you're signed in as, your plan, your links, Manage subscription,
/// Sign out and Delete account. Signed out, it explains what an account is for.
struct AccountView: View {
    var initiallyDeleting: DeleteAccountSheet.Step? = nil

    @EnvironmentObject private var library: Library
    @ObservedObject private var auth = AuthService.shared
    @ObservedObject private var store = PurchaseService.shared
    @State private var confirmsSignOut = false
    @State private var deleteStep: DeleteAccountSheet.Step?
    @State private var restoreMessage: String?
    @State private var isRestoring = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                if auth.isSignedIn {
                    profileCard
                    planCard
                    linksGroup
                    subscriptionGroup
                    accountGroup
                } else {
                    signedOutCard
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.s)
            .padding(.bottom, Space.xxl)
        }
        .background(Color.srCanvas.ignoresSafeArea())
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Sign out of Snapreel?", isPresented: $confirmsSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) {
                Task { await auth.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your recordings stay on this iPhone and your links keep working. Sign in again to see their views and comments.")
        }
        .sheet(item: $deleteStep) { step in
            DeleteAccountSheet(initialStep: step, onClose: { deleteStep = nil })
                .environmentObject(library)
        }
        .onAppear {
            if let initiallyDeleting, deleteStep == nil { deleteStep = initiallyDeleting }
        }
        .task {
            await auth.refreshMe()
            await store.refreshEntitlements()
        }
    }

    // MARK: Signed out

    private var signedOutCard: some View {
        VStack(spacing: Space.m) {
            ProMark(size: 64)
            Text("Share recordings as links")
                .font(.srTitle)
                .foregroundStyle(Color.srText)
                .multilineTextAlignment(.center)
            Text("With a free account, Copy link uploads a recording to snapreel.video so anyone can watch it in a browser. You'll see who watched and what they said. Everything else in Snapreel works without an account.")
                .font(.srSubheadline)
                .foregroundStyle(Color.srTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Sign in or create an account") {
                ProPresenter.signIn(reason: .account)
            }
            .buttonStyle(.srPrimary)
            Button("See Snapreel Pro") { ProPresenter.paywall(.settings) }
                .buttonStyle(.srTertiary)
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity)
        .srCard()
    }

    // MARK: Signed in

    private var profileCard: some View {
        HStack(spacing: Space.m) {
            AccountAvatar(name: auth.displayName, size: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(auth.displayName)
                    .font(.srTitle3)
                    .foregroundStyle(Color.srText)
                    .lineLimit(1)
                if let email = auth.email {
                    Text(verbatim: email)
                        .font(.srSubheadline)
                        .foregroundStyle(Color.srTextSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Space.m)
        .srCard()
        .accessibilityElement(children: .combine)
    }

    private var planCard: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.xs) {
                Text(auth.isPro ? "Snapreel Pro" : "Free plan")
                    .font(.srHeadline)
                    .foregroundStyle(Color.srText)
                if auth.isPro { ProBadge() }
                Spacer()
            }
            if auth.isPro {
                Text(proDetail)
                    .font(.srSubheadline)
                    .foregroundStyle(Color.srTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Manage subscription") { store.manageSubscriptions() }
                    .buttonStyle(.srSecondaryCompact)
            } else {
                let used = auth.me?.usage.activeLinks ?? library.links.count
                let limit = auth.me?.usage.linkLimit ?? CloudConfig.freeLinkLimit
                Text("\(used) of \(limit) links · videos up to 5 minutes · 720p")
                    .font(.srSubheadline)
                    .foregroundStyle(Color.srTextSecondary)
                LinkProgressBar(fraction: Double(used) / Double(max(1, limit)))
                Button("Get Snapreel Pro") { ProPresenter.paywall(.settings) }
                    .buttonStyle(.srPrimaryCompact)
                    .padding(.top, Space.xxs)
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srCard()
    }

    private var proDetail: String {
        let product = store.activeProductID ?? auth.me?.plan.productId
        let name = product == CloudConfig.monthlyProductID ? "Monthly" : "Yearly"
        var line = "\(name) · unlimited links up to 2 hours · 1080p"
        if let expiry = store.activeExpiry ?? auth.me?.plan.expiresAt {
            line += "\n\(store.willRenew == false ? "Ends" : "Renews") on \(ProText.longDate(expiry))"
        }
        return line
    }

    private var linksGroup: some View {
        SettingsGroup(title: "Your links") {
            SettingsLinkRow(page: .sharedLinks, systemImage: "link", title: "Shared links",
                            value: library.links.isEmpty ? "None" : "\(library.links.count)")
            SettingsDivider()
            SettingsActionRow(systemImage: "safari.fill", title: "Open the web dashboard") {
                ShareLinks.openInSafari(CloudConfig.dashboardURL)
            }
        }
    }

    private var subscriptionGroup: some View {
        SettingsGroup(title: "Subscription", footnote: restoreMessage) {
            if !auth.isPro {
                SettingsActionRow(systemImage: "sparkles", title: "Snapreel Pro") {
                    ProPresenter.paywall(.settings)
                }
                SettingsDivider()
            }
            SettingsActionRow(systemImage: "creditcard.fill", title: "Manage subscription") {
                store.manageSubscriptions()
            }
            SettingsDivider()
            SettingsActionRow(systemImage: "arrow.clockwise", title: isRestoring ? "Restoring…" : "Restore purchases") {
                restore()
            }
        }
    }

    private var accountGroup: some View {
        SettingsGroup(footnote: "Deleting your account removes your links and everything on snapreel.video. Recordings on this iPhone stay.") {
            SettingsActionRow(systemImage: "rectangle.portrait.and.arrow.right", title: "Sign out") {
                confirmsSignOut = true
            }
            SettingsDivider()
            Button {
                Haptics.warning()
                deleteStep = .confirm
            } label: {
                ListRow(systemImage: "trash.fill", title: "Delete account", showsChevron: false, titleColor: .srRedText)
                    .padding(.horizontal, Space.m)
                    .padding(.vertical, 3)
            }
            .buttonStyle(SettingsRowStyle())
        }
    }

    private func restore() {
        guard !isRestoring else { return }
        isRestoring = true
        Task { @MainActor in
            do {
                let found = try await store.restore()
                restoreMessage = found ? "Snapreel Pro was restored." : "No subscription was found for this Apple Account."
            } catch {
                restoreMessage = "Restore didn't finish. Check your connection and try again."
            }
            isRestoring = false
        }
    }
}

/// Initials on brand red.
struct AccountAvatar: View {
    let name: String
    var size: CGFloat = 40

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
            .foregroundStyle(Color.white)
            .frame(width: size, height: size)
            .background(Circle().fill(LinearGradient(colors: [Color.srRedGlow, Color.srRedDeep],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing)))
            .accessibilityHidden(true)
    }

    private var initials: String {
        let words = name.split(separator: " ").prefix(2)
        let letters = words.compactMap(\.first).map { String($0).uppercased() }.joined()
        return letters.isEmpty ? "S" : letters
    }
}

// MARK: - Delete account

/// Says exactly what deleting the account removes and what stays, how to cancel the App Store
/// subscription (deleting the account doesn't), then deletes with a tick and a tap.
struct DeleteAccountSheet: View {
    enum Step: String, Identifiable {
        case confirm
        case deleting
        case done
        case failed

        var id: String { rawValue }
    }

    let onClose: @MainActor () -> Void

    @EnvironmentObject private var library: Library
    @ObservedObject private var auth = AuthService.shared
    @State private var step: Step
    @State private var understood: Bool
    @State private var failure: String?

    init(initialStep: Step = .confirm, onClose: @escaping @MainActor () -> Void) {
        self.onClose = onClose
        _step = State(initialValue: initialStep)
        _understood = State(initialValue: initialStep != .confirm)
    }

    var body: some View {
        ZStack {
            Color.srCanvas.ignoresSafeArea()
            switch step {
            case .confirm, .failed: confirm
            case .deleting: deleting
            case .done: done
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(step == .deleting ? .hidden : .visible)
        .interactiveDismissDisabled(step == .deleting)
    }

    private var linkCount: Int { library.links.count }

    private var confirm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                VStack(spacing: Space.s) {
                    ZStack {
                        Circle().fill(Color.srRedSoft)
                        Image(systemName: "person.crop.circle.badge.xmark")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(Color.srRed)
                    }
                    .frame(width: 72, height: 72)
                    Text("Delete your account?")
                        .font(.srDisplay)
                        .foregroundStyle(Color.srText)
                    Text("This can't be undone. Snapreel deletes everything below straight away.")
                        .font(.srSubheadline)
                        .foregroundStyle(Color.srTextSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 0) {
                    sectionTitle("Deleted from snapreel.video")
                    item("link", linkCount == 1
                         ? "Your share link stops working, and its video is deleted"
                         : "Your \(linkCount == 0 ? "" : "\(linkCount) ")share links stop working, and their videos are deleted")
                    item("text.bubble", "Every view, comment and reaction on them, and your block list")
                    item("person.text.rectangle", "Your profile, email address and sign-in. If you used Sign in with Apple, Snapreel's access to it is revoked")
                    item("bell.slash", "Alerts about viewers and comments on this iPhone", isLast: true)
                }
                .srCard()

                VStack(alignment: .leading, spacing: 0) {
                    sectionTitle("Stays on this iPhone")
                    item("iphone", "Your recordings, notes, reactions and transcripts. Delete them in Settings › Storage if you want.",
                         tint: .srTextSecondary, isLast: true)
                }
                .srCard()

                VStack(alignment: .leading, spacing: Space.s) {
                    Label("Your subscription isn't cancelled", systemImage: "creditcard.fill")
                        .font(.srHeadline)
                        .foregroundStyle(Color.srText)
                    Text("Apple bills Snapreel Pro, so deleting your account doesn't stop it. Cancel it in the Settings app › your name › Subscriptions › Snapreel, or with the button below, before you delete.")
                        .font(.srSubheadline)
                        .foregroundStyle(Color.srTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Manage subscription") { PurchaseService.shared.manageSubscriptions() }
                        .buttonStyle(.srSecondaryCompact)
                }
                .padding(Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(Color.srRedSoft))

                if let failure {
                    Label(failure, systemImage: "exclamationmark.circle.fill")
                        .font(.srSubheadline)
                        .foregroundStyle(Color.srRedText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Haptics.selection()
                    understood.toggle()
                } label: {
                    HStack(alignment: .top, spacing: Space.s) {
                        Image(systemName: understood ? "checkmark.square.fill" : "square")
                            .font(.system(size: 22))
                            .foregroundStyle(understood ? Color.srRed : Color.srTextTertiary)
                        Text("I understand my account and links are deleted for good")
                            .font(.srSubheadline)
                            .foregroundStyle(Color.srText)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(understood ? .isSelected : [])

                VStack(spacing: Space.s) {
                    Button("Delete account") { delete() }
                        .buttonStyle(.srPrimary)
                        .disabled(!understood)
                    Button("Keep my account") { onClose() }
                        .buttonStyle(.srSecondary)
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.xl)
            .padding(.bottom, Space.xxl)
        }
    }

    private var deleting: some View {
        VStack(spacing: Space.m) {
            ProgressView()
                .controlSize(.large)
            Text("Deleting your account…")
                .font(.srHeadline)
                .foregroundStyle(Color.srText)
            Text("Removing your links and everything on snapreel.video.")
                .font(.srSubheadline)
                .foregroundStyle(Color.srTextSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Space.xxl)
    }

    private var done: some View {
        VStack(spacing: Space.m) {
            ZStack {
                Circle().fill(Color.srRedSoft)
                Image(systemName: "checkmark")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Color.srRed)
            }
            .frame(width: 72, height: 72)
            Text("Account deleted")
                .font(.srDisplay)
                .foregroundStyle(Color.srText)
            Text("Your links and everything on snapreel.video are gone. Your recordings are still here, and you can keep using Snapreel without an account.")
                .font(.srSubheadline)
                .foregroundStyle(Color.srTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Done") { onClose() }
                .buttonStyle(.srPrimary)
                .padding(.top, Space.s)
        }
        .padding(.horizontal, Space.gutter)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.srCaption)
            .kerning(0.6)
            .foregroundStyle(Color.srTextTertiary)
            .padding(.horizontal, Space.m)
            .padding(.top, Space.m)
            .padding(.bottom, Space.xxs)
    }

    private func item(_ systemImage: String, _ text: String, tint: Color = .srRedText, isLast: Bool = false) -> some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24)
            Text(text)
                .font(.srSubheadline)
                .foregroundStyle(Color.srText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.xs)
        .padding(.bottom, isLast ? Space.s : 0)
    }

    private func delete() {
        failure = nil
        withAnimation(Motion.standard) { step = .deleting }
        Task { @MainActor in
            do {
                await PushService.shared.unregister()
                try await APIClient.shared.deleteAccount()
                auth.clearLocal()
                Haptics.success()
                withAnimation(Motion.standard) { step = .done }
            } catch {
                failure = (error as? CloudError)?.message ?? CloudError.offline.message
                withAnimation(Motion.standard) { step = .failed }
            }
        }
    }
}
