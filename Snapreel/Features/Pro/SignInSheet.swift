import AuthenticationServices
import SwiftUI

/// Sign in to Snapreel: Sign in with Apple, or a 6-digit code sent to your email. It opens
/// the first time you tap Copy link (never at launch), before subscribing, and from
/// "I already have an account" on Welcome. Follows Light and Dark; a swipe down closes it.
/// Where US app-store age laws apply, it first reads the age range declared to Apple (`AgeGate`);
/// under-13s can't make an account, and 13 to 17s wait for a parent's approval.
struct SignInSheet: View {
    enum Step: Equatable {
        case start
        case code
    }

    let reason: SignInReason
    let onDone: @MainActor (Bool) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var step: Step
    @State private var email: String
    @State private var code: String
    @State private var isWorking: Bool
    @State private var error: String?
    @State private var rawNonce = ""
    @State private var resendAfter: Date?
    /// The age check's answer; nil while Apple is being asked.
    @State private var age: AgeGate.Outcome?
    @State private var legal: LegalDocument?
    @FocusState private var focus: Field?

    /// A code that was sent, kept for as long as it works, so closing the sheet on the code step and opening it
    /// again doesn't mean typing the email again.
    private struct Draft {
        var email: String
        var sentAt: Date
        var resendAfter: Date?

        var isCurrent: Bool { Date().timeIntervalSince(sentAt) < 10 * 60 }
    }

    private static var draft: Draft?

    /// The longest email address there can be.
    static let maxEmailLength = 254

    private enum Field: Hashable {
        case email
        case code
    }

    init(reason: SignInReason, step: Step = .start, email: String = "", code: String = "",
         isWorking: Bool = false, error: String? = nil, age: AgeGate.Outcome? = nil,
         onDone: @escaping @MainActor (Bool) -> Void) {
        self.reason = reason
        self.onDone = onDone
        var step = step
        var email = email
        var resendAfter: Date?
        if step == .start, email.isEmpty, let draft = Self.draft, draft.isCurrent {
            step = .code
            email = draft.email
            resendAfter = draft.resendAfter
        }
        _step = State(initialValue: step)
        _email = State(initialValue: email)
        _resendAfter = State(initialValue: resendAfter)
        _code = State(initialValue: code)
        _isWorking = State(initialValue: isWorking)
        _error = State(initialValue: error)
        _age = State(initialValue: age)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.srCanvas.ignoresSafeArea()
            ScrollView {
                VStack(spacing: Space.xl) {
                    header
                    if let age, age != .allowed {
                        ageContent(age)
                            .transition(.opacity)
                    } else {
                        switch step {
                        case .start:
                            startContent
                                .transition(.opacity.combined(with: .move(edge: .leading)))
                        case .code:
                            codeContent
                                .transition(.opacity.combined(with: .move(edge: .trailing)))
                        }
                    }
                    if let error {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .font(.srSubheadline)
                            .foregroundStyle(Color.srRedText)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.opacity)
                    }
                    footer
                }
                .padding(.horizontal, Space.gutter)
                .padding(.top, Space.xxxl)
                .padding(.bottom, Space.xxl)
                .animation(Motion.standard, value: step)
                .animation(Motion.quick, value: error)
                .animation(Motion.standard, value: age)
            }
            .scrollDismissesKeyboard(.interactively)
            CircleIconButton(systemName: "xmark", label: "Close", tone: .light, size: 32) { onDone(false) }
                .padding(Space.m)
        }
        .task {
            if age == nil { await checkAge() }
        }
        .sheet(item: $legal) { document in
            NavigationStack {
                LegalDocumentView(document: document)
                    .navigationTitle(document.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .background(Color.srCanvas.ignoresSafeArea())
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { legal = nil }
                                .font(.srHeadline)
                        }
                    }
            }
            .tint(Color.srRed)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: Space.s) {
            ProMark(size: 64)
                .padding(.bottom, Space.xxs)
            Text(step == .code ? "Check your email" : headline)
                .font(.srDisplay)
                .foregroundStyle(Color.srText)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(step == .code ? "We sent a 6-digit code to \(email.isEmpty ? "your email" : email). It works for 10 minutes." : subtitle)
                .font(.srSubheadline)
                .foregroundStyle(Color.srTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var headline: String {
        switch reason {
        case .link: return "Sign in to share links"
        case .subscribe: return "Sign in to get Pro"
        case .account: return "Sign in or create an account"
        }
    }

    private var subtitle: String {
        switch reason {
        case .link: return "A link plays in any browser, no app needed. Your account keeps track of who watched and what they said."
        case .subscribe: return "Snapreel Pro belongs to your account, so it works on snapreel.video and after a reinstall too."
        case .account: return "Your account keeps your share links, their views and comments. New to Snapreel? The same steps make one."
        }
    }

    // MARK: Start

    private var startContent: some View {
        VStack(spacing: Space.l) {
            SignInWithAppleButton(.continue, onRequest: { request in
                let nonce = AuthService.makeNonce()
                rawNonce = nonce
                request.requestedScopes = [.fullName, .email]
                request.nonce = AuthService.sha256(nonce)
            }, onCompletion: { result in
                handleApple(result)
            })
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 54)
            .clipShape(Capsule())
            .disabled(isWorking || age == nil)
            .accessibilityLabel("Continue with Apple")

            HStack(spacing: Space.s) {
                Rectangle().fill(Color.srLine).frame(height: 1)
                Text("or use your email")
                    .font(.srFootnote)
                    .foregroundStyle(Color.srTextTertiary)
                    .fixedSize()
                Rectangle().fill(Color.srLine).frame(height: 1)
            }

            VStack(spacing: Space.s) {
                HStack(spacing: Space.s) {
                    Image(systemName: "envelope.fill")
                        .foregroundStyle(Color.srTextTertiary)
                    // Verbatim and grey: as a localized key, "you@example.com" was read as an email link and drawn blue, like typed text.
                    TextField("Email address", text: $email,
                              prompt: Text(verbatim: "you@example.com").foregroundColor(Color.srTextTertiary))
                        .font(.srBody)
                        .foregroundStyle(Color.srText)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.send)
                        .focused($focus, equals: .email)
                        .onSubmit { sendCode() }
                        .onChange(of: email) { value in
                            if value.count > Self.maxEmailLength { email = String(value.prefix(Self.maxEmailLength)) }
                            if error != nil, step == .start { error = nil }
                        }
                        .accessibilityLabel("Email address")
                }
                .padding(.horizontal, Space.m)
                .padding(.vertical, Space.xs)
                .frame(minHeight: 54)
                .background(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).fill(Color.srSurface))
                .overlay(RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                    .strokeBorder(focus == .email ? Color.srRed : Color.srLine, lineWidth: focus == .email ? 1.5 : 1))

                Button {
                    sendCode()
                } label: {
                    HStack(spacing: Space.xs) {
                        if isWorking { ProgressView().tint(.white) }
                        Text(isWorking ? "Sending…" : "Email me a code")
                    }
                }
                .buttonStyle(.srPrimary)
                // A wrong address gets words when tapped, rather than a button that does nothing.
                .disabled(trimmedEmail.isEmpty || isWorking || age == nil)
            }
        }
    }

    // MARK: Age

    /// Instead of the sign-in options, when the age check says not yet (or not at all).
    private func ageContent(_ outcome: AgeGate.Outcome) -> some View {
        VStack(spacing: Space.l) {
            VStack(alignment: .leading, spacing: Space.s) {
                Label(outcome == .tooYoung ? "Snapreel accounts are for 13 and over" : "A parent or guardian needs to agree",
                      systemImage: outcome == .tooYoung ? "person.crop.circle.badge.xmark" : "person.2.fill")
                    .font(.srSubheadlineStrong)
                    .foregroundStyle(Color.srText)
                Text(AgeGate.message(for: outcome, moment: .accountCreation) ?? "")
                    .font(.srSubheadline)
                    .foregroundStyle(Color.srTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(Color.srSurface))
            if outcome != .tooYoung {
                Button("Try again") {
                    Task { @MainActor in await checkAge() }
                }
                .buttonStyle(.srPrimary)
            }
        }
    }

    private func checkAge() async {
        withAnimation(Motion.standard) { age = nil }
        let outcome = await AgeGate.check(.accountCreation)
        withAnimation(Motion.standard) { age = outcome }
    }

    // MARK: Code

    private var codeContent: some View {
        VStack(spacing: Space.l) {
            OneTimeCodeField(code: $code, isFocused: $focus, focusValue: .code, onComplete: { verify() })
            Button {
                verify()
            } label: {
                HStack(spacing: Space.xs) {
                    if isWorking { ProgressView().tint(.white) }
                    Text(isWorking ? "Checking…" : "Sign in")
                }
            }
            .buttonStyle(.srPrimary)
            .disabled(code.count != 6 || isWorking)
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                                                      : AnyLayout(HStackLayout())
            layout {
                Button("Use a different email") {
                    Self.draft = nil
                    withAnimation(Motion.standard) {
                        step = .start
                        code = ""
                        error = nil
                    }
                    focus = .email
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                if !typeSize.isAccessibilitySize { Spacer() }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let wait = Int((resendAfter ?? .distantPast).timeIntervalSince(context.date).rounded(.up))
                    Button(wait > 0 ? "Send again in \(wait)s" : "Send a new code") { sendCode() }
                        .disabled(wait > 0 || isWorking)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
            }
            .font(.srSubheadlineStrong)
            .foregroundStyle(Color.srRed)
        }
        .onAppear { focus = .code }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: Space.s) {
            Label("Your recordings stay on this iPhone. Only the ones you share as links are uploaded.",
                  systemImage: "lock.fill")
                .font(.srFootnote)
                .foregroundStyle(Color.srTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("By continuing you agree to Snapreel's Terms of Use and Privacy Policy.")
                .font(.srFootnote)
                .foregroundStyle(Color.srTextTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            // Opened here in Snapreel, as on the Pro page.
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 0))
                                                      : AnyLayout(HStackLayout(spacing: Space.l))
            layout {
                Button("Terms of Use") { legal = .terms }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                Button("Privacy Policy") { legal = .privacy }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .font(.srFootnote.weight(.semibold))
            .foregroundStyle(Color.srRedText)
        }
        .padding(.top, Space.xs)
    }

    // MARK: Actions

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var emailLooksValid: Bool { Self.looksLikeEmail(trimmedEmail) }

    /// name@domain.tld, at most 254 characters, 64 before the @, no spaces.
    static func looksLikeEmail(_ address: String) -> Bool {
        guard address.count <= maxEmailLength, !address.contains(where: \.isWhitespace) else { return false }
        let parts = address.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[0].count <= 64 else { return false }
        let domain = parts[1]
        return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".") && !domain.contains("..")
    }

    private func sendCode() {
        guard !isWorking else { return }
        guard emailLooksValid else {
            Haptics.error()
            error = trimmedEmail.isEmpty
                ? "Type your email address."
                : "That doesn't look like a full email address. Check it, for example name@example.com."
            focus = .email
            return
        }
        let address = trimmedEmail
        run(failing: "The code wasn't sent.") {
            try await AuthService.shared.sendCode(to: address)
            email = address
            code = ""
            let wait = Date().addingTimeInterval(30)
            resendAfter = wait
            Self.draft = Draft(email: address, sentAt: Date(), resendAfter: wait)
            withAnimation(Motion.standard) { step = .code }
        }
    }

    private func verify() {
        guard code.count == 6, !isWorking else { return }
        let address = trimmedEmail
        let token = code
        run(failing: "You're not signed in yet.") {
            try await AuthService.shared.verify(email: address, code: token)
            Self.draft = nil
            onDone(true)
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let data = credential.identityToken, let token = String(data: data, encoding: .utf8) else {
                error = "Sign in with Apple didn't finish. Try again, or use your email."
                return
            }
            let nonce = rawNonce
            let name = credential.fullName
            run(failing: "You're not signed in yet.") {
                try await AuthService.shared.signInWithApple(identityToken: token, rawNonce: nonce, fullName: name)
                Self.draft = nil
                onDone(true)
            }
        case .failure(let failure):
            if (failure as? ASAuthorizationError)?.code == .canceled { return }
            error = "Sign in with Apple didn't finish. Try again, or use your email."
        }
    }

    /// `failing` goes before a server fault's words, so they say what didn't happen.
    private func run(failing: String, _ work: @escaping @MainActor () async throws -> Void) {
        error = nil
        isWorking = true
        Task { @MainActor in
            do {
                try await work()
            } catch {
                Haptics.error()
                let cloud = error as? CloudError
                let message = cloud?.message ?? CloudError.offline.message
                if case .server = cloud {
                    self.error = "\(failing) \(message)"
                } else {
                    self.error = message
                }
            }
            isWorking = false
        }
    }
}

/// Six boxes over one hidden text field, so iOS can fill the code from Mail
/// (`.oneTimeCode`) and a paste works.
struct OneTimeCodeField<FocusValue: Hashable>: View {
    @Binding var code: String
    var isFocused: FocusState<FocusValue?>.Binding
    let focusValue: FocusValue
    let onComplete: @MainActor () -> Void

    var body: some View {
        ZStack {
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused(isFocused, equals: focusValue)
                .foregroundStyle(Color.clear)
                .tint(Color.clear)
                .frame(height: 60)
                .onChange(of: code) { value in
                    let digits = String(value.filter(\.isNumber).prefix(6))
                    if digits != value { code = digits }
                    if digits.count == 6 { onComplete() }
                }
                .accessibilityLabel("Six-digit code")
            HStack(spacing: Space.xs) {
                ForEach(0..<6, id: \.self) { index in
                    box(index)
                }
            }
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture { isFocused.wrappedValue = focusValue }
    }

    private func box(_ index: Int) -> some View {
        let characters = Array(code)
        let digit = index < characters.count ? String(characters[index]) : ""
        let isCurrent = index == min(characters.count, 5) && isFocused.wrappedValue == focusValue
        return Text(digit)
            .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(Color.srText)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).fill(Color.srSurface))
            .overlay(RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                .strokeBorder(isCurrent ? Color.srRed : Color.srLine, lineWidth: isCurrent ? 2 : 1))
    }
}
