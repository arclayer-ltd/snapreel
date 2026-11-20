import SwiftUI

/// A share link's settings: who can watch (anyone with the link, or a password), when it
/// expires, whether viewers can download, comment and react, a call-to-action button, and
/// Stop sharing. Password, expiry, downloads and the button are Pro; on Free they show the PRO
/// badge and open the paywall.
struct LinkSettingsView: View {
    let videoID: UUID
    /// Set when the settings have their own sheet (from the share-link sheet); pushed from
    /// Settings they go back instead.
    var onClose: (@MainActor () -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: Library
    @ObservedObject private var auth = AuthService.shared
    @State private var draft: LinkDraft?
    @State private var original: LinkDraft?
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var error: String?
    @State private var confirmsStop = false
    @State private var isStopping = false

    private var link: CloudLink? { library.link(for: videoID) }
    private var isPro: Bool { auth.isPro }

    var body: some View {
        Group {
            if let link, draft != nil {
                form(link)
            } else if isLoading {
                ProgressView("Loading settings…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyStateView(systemImage: "link.badge.plus",
                               title: link == nil ? "Not shared" : "Settings didn't load",
                               message: error ?? "This recording doesn't have a share link.",
                               actionTitle: link == nil ? nil : "Try again",
                               action: link == nil ? nil : { retryLoad() })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.srCanvas.ignoresSafeArea())
        .navigationTitle("Link settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if let onClose {
                    Button("Close") { onClose() }
                        .foregroundStyle(Color.srTextSecondary)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save") { save() }
                        .font(.srHeadline)
                        .foregroundStyle(Color.srRed)
                        .disabled(draft == original || draft == nil)
                        .opacity(draft == original || draft == nil ? 0.4 : 1)
                }
            }
        }
        .confirmationDialog("Stop sharing this link?", isPresented: $confirmsStop, titleVisibility: .visible) {
            Button("Stop sharing", role: .destructive) { stopSharing() }
            Button("Keep sharing", role: .cancel) {}
        } message: {
            Text("The link stops working, and its video, views and comments are deleted from snapreel.video. The recording stays on this iPhone.")
        }
        .task { await load() }
    }

    // MARK: Form

    private func form(_ link: CloudLink) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                linkHeader(link)
                accessGroup
                expiryGroup
                viewersGroup
                callToActionGroup
                if let error {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.srFootnote)
                        .foregroundStyle(Color.srRedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                stopButton
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.s)
            .padding(.bottom, Space.xxl)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func linkHeader(_ link: CloudLink) -> some View {
        HStack(spacing: Space.s) {
            if let video = library.video(videoID) {
                VideoThumbnail(video: video, cornerRadius: Radius.s, showsDuration: false)
                    .frame(width: 72)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(link.title)
                    .font(.srHeadline)
                    .foregroundStyle(Color.srText)
                    .lineLimit(2)
                Text(verbatim: link.url.replacingOccurrences(of: "https://", with: ""))
                    .font(.srFootnote.monospaced())
                    .foregroundStyle(Color.srTextSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private var accessGroup: some View {
        SettingsGroup(title: "Who can watch",
                      footnote: draft?.access == .password
                        ? "Viewers type the password once; it's kept for 12 hours in their browser."
                        : "Anyone you send the link to can watch. Links aren't listed or searchable.") {
            choiceRow("Anyone with the link", systemImage: "link", selected: draft?.access == .link) {
                draft?.access = .link
            }
            SettingsDivider()
            choiceRow("Only with a password", systemImage: "lock.fill", selected: draft?.access == .password,
                      pro: .password) {
                draft?.access = .password
            }
            if draft?.access == .password {
                SettingsDivider()
                HStack(spacing: Space.s) {
                    IconTile(systemName: "key.fill")
                    SecureField(draft?.hasPassword == true ? "Password set. Type to change it" : "Choose a password",
                                text: binding(\.password))
                        .font(.srBody)
                        .textContentType(.newPassword)
                }
                .padding(.horizontal, Space.m)
                .padding(.vertical, Space.s)
            }
        }
    }

    private var expiryGroup: some View {
        SettingsGroup(title: "Expiry", footnote: expiryFootnote) {
            ForEach(Array(ExpiryChoice.presets.enumerated()), id: \.offset) { index, choice in
                if index > 0 { SettingsDivider() }
                choiceRow(choice.title, systemImage: choice.systemImage,
                          selected: draft?.expiry.matches(choice) == true,
                          pro: choice == .never ? nil : .expiry) {
                    draft?.expiry = choice
                }
            }
        }
    }

    private var expiryFootnote: String {
        guard let draft else { return "" }
        if let date = draft.expiry.date(from: Date()) {
            return "The link stops working on \(Format.dateTime(date)). The video is then deleted from snapreel.video."
        }
        return "The link keeps working until you stop sharing it."
    }

    private var viewersGroup: some View {
        SettingsGroup(title: "Viewers can") {
            toggleRow("Download", systemImage: "arrow.down.circle.fill", value: \.allowDownload, pro: .downloads)
            SettingsDivider()
            toggleRow("Comment", systemImage: "text.bubble.fill", value: \.allowComments)
            SettingsDivider()
            toggleRow("React with emoji", systemImage: "face.smiling.inverse", value: \.allowReactions)
        }
    }

    private var callToActionGroup: some View {
        SettingsGroup(title: "Call to action",
                      footnote: "A button under the video, for example \u{201C}Book a call\u{201D} or \u{201C}Try it free\u{201D}.") {
            toggleRow("Show a button", systemImage: "hand.tap.fill", value: \.ctaOn, pro: .callToAction)
            if draft?.ctaOn == true {
                SettingsDivider()
                field("Button text", text: binding(\.ctaLabel), systemImage: "textformat")
                SettingsDivider()
                field("https://", text: binding(\.ctaURL), systemImage: "globe", isURL: true)
            }
        }
    }

    private var stopButton: some View {
        Button {
            Haptics.warning()
            confirmsStop = true
        } label: {
            HStack(spacing: Space.xs) {
                if isStopping { ProgressView() }
                Label("Stop sharing", systemImage: "link.badge.plus")
                    .labelStyle(.titleOnly)
            }
        }
        .buttonStyle(.srDestructive)
        .disabled(isStopping)
    }

    // MARK: Rows

    private func choiceRow(_ title: String, systemImage: String, selected: Bool, pro: ProFeature? = nil,
                           action: @escaping @MainActor () -> Void) -> some View {
        Button {
            if let pro, !isPro {
                ProPresenter.paywall(.feature(pro))
                return
            }
            Haptics.selection()
            withAnimation(Motion.quick) { action() }
        } label: {
            HStack(spacing: Space.s) {
                IconTile(systemName: systemImage)
                Text(title)
                    .font(.srBody)
                    .foregroundStyle(Color.srText)
                if pro != nil && !isPro { ProBadge(compact: true) }
                Spacer(minLength: Space.xs)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.srRed)
                }
            }
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(SettingsRowStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func toggleRow(_ title: String, systemImage: String, value: WritableKeyPath<LinkDraft, Bool>,
                           pro: ProFeature? = nil) -> some View {
        HStack(spacing: Space.s) {
            IconTile(systemName: systemImage)
            Text(title)
                .font(.srBody)
                .foregroundStyle(Color.srText)
            if pro != nil && !isPro { ProBadge(compact: true) }
            Spacer(minLength: Space.xs)
            Toggle(title, isOn: Binding(get: { draft?[keyPath: value] ?? false },
                                        set: { newValue in
                                            if let pro, !isPro, newValue {
                                                ProPresenter.paywall(.feature(pro))
                                                return
                                            }
                                            draft?[keyPath: value] = newValue
                                        }))
                .labelsHidden()
                .tint(Color.srRed)
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.xs)
    }

    private func field(_ placeholder: String, text: Binding<String>, systemImage: String, isURL: Bool = false) -> some View {
        HStack(spacing: Space.s) {
            IconTile(systemName: systemImage)
            TextField(placeholder, text: text)
                .font(.srBody)
                .keyboardType(isURL ? .URL : .default)
                .textInputAutocapitalization(isURL ? .never : .sentences)
                .autocorrectionDisabled(isURL)
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
    }

    private func binding(_ keyPath: WritableKeyPath<LinkDraft, String>) -> Binding<String> {
        Binding(get: { draft?[keyPath: keyPath] ?? "" },
                set: { draft?[keyPath: keyPath] = $0 })
    }

    // MARK: Loading and saving

    private func retryLoad() {
        Task { await load() }
    }

    private func load() async {
        guard let link else { return }
        if let detail = link.detail, draft == nil {
            let initial = LinkDraft(detail)
            draft = initial
            original = initial
        }
        isLoading = draft == nil
        let detail = await ShareLinks.shared.refreshDetail(videoID)
        isLoading = false
        if let detail {
            // Keep what was already typed; only fill an untouched form.
            if draft == original {
                let fresh = LinkDraft(detail)
                draft = fresh
                original = fresh
            }
        } else if draft == nil {
            error = "Check your connection and try again."
        }
    }

    private func save() {
        guard let draft, let original else { return }
        if draft.access == .password && !draft.hasPassword && draft.password.count < 4 {
            error = "Choose a password of at least 4 characters."
            return
        }
        if draft.ctaOn && (draft.ctaLabel.trimmingCharacters(in: .whitespaces).isEmpty || URL(string: draft.ctaURL)?.scheme == nil) {
            error = "Give the button some text and a full web address (starting https://)."
            return
        }
        error = nil
        isSaving = true
        let change = draft.changes(from: original)
        Task { @MainActor in
            do {
                try await ShareLinks.shared.update(videoID, change)
                Haptics.success()
                var saved = draft
                if !saved.password.isEmpty { saved.hasPassword = true }
                saved.password = ""
                self.draft = saved
                self.original = saved
                AppEnvironment.shared.router.showToast("Link settings saved", systemImage: "checkmark.circle.fill")
            } catch CloudError.limit {
                ProPresenter.paywall(.feature(.password))
            } catch {
                self.error = (error as? CloudError)?.message ?? CloudError.offline.message
            }
            isSaving = false
        }
    }

    private func stopSharing() {
        isStopping = true
        Task { @MainActor in
            do {
                try await ShareLinks.shared.stopSharing(videoID)
                Haptics.success()
                AppEnvironment.shared.router.showToast("Stopped sharing", systemImage: "link")
                ProPresenter.dismissShareLink()
                if let onClose { onClose() } else { dismiss() }
            } catch {
                self.error = (error as? CloudError)?.message ?? CloudError.offline.message
            }
            isStopping = false
        }
    }
}

// MARK: - Model

/// When a link stops working.
enum ExpiryChoice: Equatable {
    case never
    case days(Int)
    case on(Date)

    static let presets: [ExpiryChoice] = [.never, .days(1), .days(7), .days(30)]

    var title: String {
        switch self {
        case .never: return "Never"
        case .days(1): return "After 1 day"
        case .days(let count): return count == 7 ? "After 1 week" : "After \(count) days"
        case .on(let date): return "On \(Format.date(date))"
        }
    }

    var systemImage: String {
        switch self {
        case .never: return "infinity"
        case .days(1): return "sun.max.fill"
        case .days(7): return "calendar"
        default: return "calendar.badge.clock"
        }
    }

    func date(from now: Date) -> Date? {
        switch self {
        case .never: return nil
        case .days(let count): return now.addingTimeInterval(Double(count) * 86_400)
        case .on(let date): return date
        }
    }

    /// An existing date shows as "On …" but still ticks nothing in the presets.
    func matches(_ preset: ExpiryChoice) -> Bool { self == preset }
}

/// The form's values, compared with what was loaded to send only the changes.
struct LinkDraft: Equatable {
    var access: CloudAccess
    var hasPassword: Bool
    var password = ""
    var expiry: ExpiryChoice
    var allowDownload: Bool
    var allowComments: Bool
    var allowReactions: Bool
    var ctaOn: Bool
    var ctaLabel: String
    var ctaURL: String

    init(_ detail: VideoDetail) {
        access = detail.access
        hasPassword = detail.hasPassword
        expiry = detail.expiresAt.map { .on($0) } ?? .never
        allowDownload = detail.allowDownload
        allowComments = detail.allowComments
        allowReactions = detail.allowReactions
        ctaOn = detail.cta != nil
        ctaLabel = detail.cta?.label ?? ""
        ctaURL = detail.cta?.url ?? ""
    }

    func changes(from original: LinkDraft) -> UpdateVideoRequest {
        var change = UpdateVideoRequest()
        if access != original.access { change.access = access }
        if access == .password && !password.isEmpty { change.password = password }
        if expiry != original.expiry {
            if let date = expiry.date(from: Date()) { change.expiresAt = date } else { change.clearsExpiry = true }
        }
        if allowDownload != original.allowDownload { change.allowDownload = allowDownload }
        if allowComments != original.allowComments { change.allowComments = allowComments }
        if allowReactions != original.allowReactions { change.allowReactions = allowReactions }
        if ctaOn != original.ctaOn || ctaLabel != original.ctaLabel || ctaURL != original.ctaURL {
            if ctaOn {
                change.cta = CallToAction(label: ctaLabel.trimmingCharacters(in: .whitespaces),
                                          url: ctaURL.trimmingCharacters(in: .whitespaces))
            } else {
                change.clearsCallToAction = true
            }
        }
        return change
    }
}
