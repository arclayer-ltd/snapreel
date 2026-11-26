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
    /// Nothing is said to be missing before loading has been tried and has failed.
    @State private var loading = Loading.waiting
    @State private var isSaving = false
    @State private var error: String?
    @State private var confirmsStop = false
    @State private var isStopping = false
    @State private var confirmsDiscard = false
    /// A field that can't be saved as it is, with why: shown under that field.
    @State private var problem: Problem?
    @State private var toast: ToastMessage?
    @FocusState private var focus: Field?

    /// The fields that take typing, also the places the form scrolls to.
    enum Field: Hashable {
        case password
        case buttonText
        case address
    }

    private struct Problem: Equatable {
        var field: Field
        var message: String
    }

    /// The top of the form, where an error from snapreel.video shows.
    private static let topID = "top"

    private enum Loading: Equatable {
        case waiting
        case running
        case loaded
        case failed(String)
        /// The server doesn't know the link any more.
        case gone
    }

    private var link: CloudLink? { library.link(for: videoID) }
    private var isPro: Bool { auth.isPro }
    private var hasChanges: Bool { draft != nil && draft != original }

    var body: some View {
        // A ZStack, not a Group: a Group hands `.task` and `.onAppear` to whichever branch is showing. In this sheet, on
        // iOS 16, its loading never ran, and the "no link" message showed for a live link (seen in build 37).
        ZStack {
            if let link, draft != nil {
                form(link)
            } else {
                switch loading {
                case .waiting, .running, .loaded:
                    ProgressView("Loading settings…")
                        .onAppear {
                            if loading == .waiting { load() }
                        }
                case .failed(let message):
                    EmptyStateView(systemImage: "wifi.exclamationmark", title: "Settings didn't load", message: message,
                                   actionTitle: "Try again", action: { load() })
                case .gone:
                    EmptyStateView(systemImage: "link.badge.plus", title: "Not shared",
                                   message: "This recording doesn't have a share link any more. Copy link makes a new one.")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.srCanvas.ignoresSafeArea())
        .navigationTitle("Link settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if let onClose {
                    Button("Close") {
                        if hasChanges { confirmsDiscard = true } else { onClose() }
                    }
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
                        .disabled(!hasChanges)
                        .opacity(hasChanges ? 1 : 0.4)
                        .accessibilityHint(hasChanges ? "" : "Nothing changed yet")
                }
            }
        }
        .confirmationDialog("Discard your changes?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button("Discard changes", role: .destructive) { onClose?() }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("The link keeps the settings it had.")
        }
        // A swipe down doesn't throw changes away either: Close asks first.
        .interactiveDismissDisabled(hasChanges)
        .toast($toast, bottomInset: Space.xl)
        .confirmationDialog("Stop sharing this link?", isPresented: $confirmsStop, titleVisibility: .visible) {
            Button("Stop sharing", role: .destructive) { stopSharing() }
            Button("Keep sharing", role: .cancel) {}
        } message: {
            Text("The link stops working, and its video, views and comments are deleted from snapreel.video. The recording stays on this iPhone.")
        }
        .onAppear {
            if loading == .waiting { load() }
        }
    }

    // MARK: Form

    private func form(_ link: CloudLink) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    linkHeader(link)
                        .id(Self.topID)
                    if let error {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .font(.srFootnote)
                            .foregroundStyle(Color.srRedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    accessGroup
                    expiryGroup
                    viewersGroup
                    callToActionGroup
                    stopButton
                }
                .padding(.horizontal, Space.gutter)
                .padding(.top, Space.s)
                .padding(.bottom, Space.xxl)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: focus) { field in
                guard let field else { return }
                // After the keyboard is up, so the field ends above it.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    withAnimation(Motion.standard) { proxy.scrollTo(field, anchor: .center) }
                }
            }
            .onChange(of: problem) { problem in
                guard let problem else { return }
                withAnimation(Motion.standard) { proxy.scrollTo(problem.field, anchor: .center) }
            }
            .onChange(of: error) { error in
                guard error != nil else { return }
                withAnimation(Motion.standard) { proxy.scrollTo(Self.topID, anchor: .top) }
            }
        }
    }

    /// Why a field can't be saved, under it.
    @ViewBuilder private func problemText(_ field: Field) -> some View {
        if let problem, problem.field == field {
            Label(problem.message, systemImage: "exclamationmark.circle.fill")
                .font(.srFootnote)
                .foregroundStyle(Color.srRedText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Space.m)
                .padding(.bottom, Space.s)
        }
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
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: Space.s) {
                        IconTile(systemName: "key.fill")
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            SecureField(draft?.hasPassword == true ? "Password set. Type to change it" : "Choose a password",
                                        text: binding(\.password))
                                .font(.srBody)
                                .textContentType(.newPassword)
                                .focused($focus, equals: .password)
                                .submitLabel(.done)
                                .accessibilityLabel("Password")
                                .accessibilityHint("At least 4 characters")
                            Text("At least 4 characters")
                                .font(.srCaption)
                                .foregroundStyle(Color.srTextSecondary)
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(.horizontal, Space.m)
                    .padding(.vertical, Space.s)
                    problemText(.password)
                }
                .id(Field.password)
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
            return "The link stops working on \(Format.dateTime(date)). The video is deleted from snapreel.video 30 days later."
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
                field(.buttonText, label: "Button text", placeholder: "Book a call", text: binding(\.ctaLabel),
                      systemImage: "textformat")
                SettingsDivider()
                field(.address, label: "Web address", placeholder: "https://example.com", text: binding(\.ctaURL),
                      systemImage: "globe", isURL: true)
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
                .accessibilityHidden(true)
            // The switch carries the name; the text beside it isn't read a second time.
            Text(title)
                .font(.srBody)
                .foregroundStyle(Color.srText)
                .accessibilityHidden(true)
            if pro != nil && !isPro { ProBadge(compact: true).accessibilityHidden(true) }
            Spacer(minLength: Space.xs)
            Toggle(pro != nil && !isPro ? "\(title), Snapreel Pro" : title, isOn: Binding(get: { draft?[keyPath: value] ?? false },
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

    /// A text field with its name above it, so the name stays when typing starts, and its problem under it.
    private func field(_ field: Field, label: String, placeholder: String, text: Binding<String>, systemImage: String,
                       isURL: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.s) {
                IconTile(systemName: systemImage)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.srCaption)
                        .foregroundStyle(Color.srTextSecondary)
                        .accessibilityHidden(true)
                    TextField(placeholder, text: text)
                        .font(.srBody)
                        .keyboardType(isURL ? .URL : .default)
                        .textContentType(isURL ? .URL : nil)
                        .textInputAutocapitalization(isURL ? .never : .sentences)
                        .autocorrectionDisabled(isURL)
                        .focused($focus, equals: field)
                        .submitLabel(field == .buttonText ? .next : .done)
                        .onSubmit { if field == .buttonText { focus = .address } }
                        .accessibilityLabel(label)
                }
            }
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.s)
            problemText(field)
        }
        .id(field)
    }

    private func binding(_ keyPath: WritableKeyPath<LinkDraft, String>) -> Binding<String> {
        Binding(get: { draft?[keyPath: keyPath] ?? "" },
                set: { draft?[keyPath: keyPath] = $0 })
    }

    // MARK: Loading and saving

    /// Shows the settings kept on this iPhone at once, then the server's. Its own task, so a change of what is on
    /// screen never cancels it.
    private func load() {
        guard loading != .running else { return }
        guard let link else {
            loading = .gone
            return
        }
        if let detail = link.detail, draft == nil {
            let initial = LinkDraft(detail)
            draft = initial
            original = initial
        }
        loading = .running
        Task { @MainActor in
            do {
                let detail = try await ShareLinks.shared.loadDetail(videoID)
                // Keep what was already typed; only fill an untouched form.
                if draft == original {
                    let fresh = LinkDraft(detail)
                    draft = fresh
                    original = fresh
                }
                loading = .loaded
            } catch CloudError.notFound {
                draft = nil
                loading = .gone
            } catch {
                loading = .failed((error as? CloudError)?.message ?? CloudError.offline.message)
            }
        }
    }

    private func save() {
        guard var draft, let original else { return }
        error = nil
        problem = nil
        if draft.access == .password && ((!draft.hasPassword && draft.password.count < 4)
                                         || (!draft.password.isEmpty && draft.password.count < 4)) {
            return refuse(.password, "Choose a password of at least 4 characters.")
        }
        if draft.ctaOn {
            if draft.ctaLabel.trimmingCharacters(in: .whitespaces).isEmpty {
                return refuse(.buttonText, "Give the button some text, for example \u{201C}Book a call\u{201D}.")
            }
            guard let address = LinkDraft.webAddress(draft.ctaURL) else {
                return refuse(.address, "Type a web address, for example example.com/book.")
            }
            draft.ctaURL = address
            self.draft = draft
        }
        focus = nil
        isSaving = true
        let change = draft.changes(from: original)
        let sent = draft
        Task { @MainActor in
            do {
                try await ShareLinks.shared.update(videoID, change)
                Haptics.success()
                var saved = sent
                if !saved.password.isEmpty { saved.hasPassword = true }
                saved.password = ""
                self.draft = saved
                self.original = saved
                // Here, not on the screen underneath (the sheet would cover it).
                toast = ToastMessage(text: "Link settings saved", systemImage: "checkmark.circle.fill")
            } catch CloudError.limit {
                ProPresenter.paywall(.feature(.password))
            } catch {
                self.error = (error as? CloudError)?.message ?? CloudError.offline.message
            }
            isSaving = false
        }
    }

    private func refuse(_ field: Field, _ message: String) {
        Haptics.error()
        problem = Problem(field: field, message: message)
        focus = field
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

    /// "example.com/book" as "https://example.com/book"; nil when it can't be a web address.
    static func webAddress(_ typed: String) -> String? {
        var text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return nil }
        if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") { text = "https://" + text }
        guard let url = URL(string: text), let host = url.host, host.contains("."), !host.hasSuffix("."),
              !host.hasPrefix(".") else { return nil }
        return text
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
