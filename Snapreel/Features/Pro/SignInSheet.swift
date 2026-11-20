import AuthenticationServices
import SwiftUI

/// Sign in to Snapreel: Sign in with Apple, or a 6-digit code sent to your email. It opens
/// the first time you tap Copy link (never at launch), before subscribing, and from
/// "I already have an account" on Welcome. Follows Light and Dark; a swipe down closes it.
struct SignInSheet: View {
    enum Step: Equatable {
        case start
        case code
    }

    let reason: SignInReason
    let onDone: @MainActor (Bool) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var step: Step
    @State private var email: String
    @State private var code: String
    @State private var isWorking: Bool
    @State private var error: String?
    @State private var rawNonce = ""
    @State private var resendAfter: Date?
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case email
        case code
    }

    init(reason: SignInReason, step: Step = .start, email: String = "", code: String = "",
         isWorking: Bool = false, error: String? = nil, onDone: @escaping @MainActor (Bool) -> Void) {
        self.reason = reason
        self.onDone = onDone
        _step = State(initialValue: step)
        _email = State(initialValue: email)
        _code = State(initialValue: code)
        _isWorking = State(initialValue: isWorking)
        _error = State(initialValue: error)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.srCanvas.ignoresSafeArea()
            ScrollView {
                VStack(spacing: Space.xl) {
                    header
                    switch step {
                    case .start:
                        startContent
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                    case .code:
                        codeContent
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
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
            }
            .scrollDismissesKeyboard(.interactively)
            CircleIconButton(systemName: "xmark", label: "Close", tone: .light, size: 32) { onDone(false) }
                .padding(Space.m)
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
        case .account: return "Welcome back"
        }
    }

    private var subtitle: String {
        switch reason {
        case .link: return "A link plays in any browser, no app needed. Your account keeps track of who watched and what they said."
        case .subscribe: return "Snapreel Pro belongs to your account, so it works on snapreel.video and after a reinstall too."
        case .account: return "Sign in to see your share links, their views and comments on this iPhone."
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
            .disabled(isWorking)
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
                    TextField("you@example.com", text: $email)
                        .font(.srBody)
                        .foregroundStyle(Color.srText)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.send)
                        .focused($focus, equals: .email)
                        .onSubmit { sendCode() }
                }
                .padding(.horizontal, Space.m)
                .frame(height: 54)
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
                .disabled(!emailLooksValid || isWorking)
            }
        }
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
            HStack {
                Button("Use a different email") {
                    withAnimation(Motion.standard) {
                        step = .start
                        code = ""
                        error = nil
                    }
                    focus = .email
                }
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let wait = Int((resendAfter ?? .distantPast).timeIntervalSince(context.date).rounded(.up))
                    Button(wait > 0 ? "Send again in \(wait)s" : "Send a new code") { sendCode() }
                        .disabled(wait > 0 || isWorking)
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
            Text(.init("By continuing you agree to Snapreel's [Terms of Use](https://snapreel.video/terms) and [Privacy Policy](https://snapreel.video/privacy)."))
                .font(.srFootnote)
                .foregroundStyle(Color.srTextTertiary)
                .tint(Color.srRedText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Space.xs)
    }

    // MARK: Actions

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var emailLooksValid: Bool {
        let parts = trimmedEmail.split(separator: "@")
        return parts.count == 2 && parts[1].contains(".") && !parts[0].isEmpty
    }

    private func sendCode() {
        guard emailLooksValid, !isWorking else { return }
        let address = trimmedEmail
        run {
            try await AuthService.shared.sendCode(to: address)
            email = address
            resendAfter = Date().addingTimeInterval(30)
            withAnimation(Motion.standard) { step = .code }
        }
    }

    private func verify() {
        guard code.count == 6, !isWorking else { return }
        let address = trimmedEmail
        let token = code
        run {
            try await AuthService.shared.verify(email: address, code: token)
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
            run {
                try await AuthService.shared.signInWithApple(identityToken: token, rawNonce: nonce, fullName: name)
                onDone(true)
            }
        case .failure(let failure):
            if (failure as? ASAuthorizationError)?.code == .canceled { return }
            error = "Sign in with Apple didn't finish. Try again, or use your email."
        }
    }

    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        error = nil
        isWorking = true
        Task { @MainActor in
            do {
                try await work()
            } catch {
                Haptics.error()
                self.error = (error as? CloudError)?.message ?? CloudError.offline.message
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
