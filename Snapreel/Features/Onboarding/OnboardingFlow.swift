import SwiftUI

/// Where the getting-started flow opens (debug entries open any step directly).
enum OnboardingStep: Hashable {
    case welcome
    case intro1
    case intro2
    case intro3
    case useCase
}

/// Welcome, three intro slides and the "what will you use it for" question. Follows Light and
/// Dark like the rest of the app (`OnboardingStyle`).
/// Saves the answer to `settings.useCase`, then calls `onFinish`; the guided tour runs over the
/// tab shell afterwards.
struct OnboardingFlow: View {
    let onFinish: @MainActor () -> Void

    @EnvironmentObject private var settings: AppSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var stage: Stage
    @State private var introPage: Int
    @State private var useCase: UseCase?
    @State private var movingForward = true

    private enum Stage: Hashable {
        case welcome
        case intro
        case useCase
    }

    init(initialStep: OnboardingStep = .welcome, preselectedUseCase: UseCase? = nil,
         onFinish: @escaping @MainActor () -> Void) {
        self.onFinish = onFinish
        let stage: Stage
        let page: Int
        switch initialStep {
        case .welcome:
            stage = .welcome
            page = 0
        case .intro1:
            stage = .intro
            page = 0
        case .intro2:
            stage = .intro
            page = 1
        case .intro3:
            stage = .intro
            page = 2
        case .useCase:
            stage = .useCase
            page = IntroSlide.all.count - 1
        }
        _stage = State(initialValue: stage)
        _introPage = State(initialValue: page)
        _useCase = State(initialValue: preselectedUseCase)
    }

    var body: some View {
        ZStack {
            OnboardingStyle.background.ignoresSafeArea()
            content
        }
    }

    @ViewBuilder private var content: some View {
        switch stage {
        case .welcome:
            WelcomeStep(onStart: { go(to: .intro, forward: true) },
                        onSignIn: {
                            // A returning person: sign in, then straight into the app.
                            ProPresenter.signIn(reason: .account) { signedIn in
                                if signedIn {
                                    Haptics.success()
                                    onFinish()
                                }
                            }
                        })
                .transition(stageTransition)
        case .intro:
            IntroSlides(page: $introPage,
                        onSkip: { go(to: .useCase, forward: true) },
                        onContinue: { go(to: .useCase, forward: true) })
                .transition(stageTransition)
        case .useCase:
            UseCaseQuestion(selection: $useCase,
                            onBack: { go(to: .intro, forward: false) },
                            onContinue: { finish() })
                .transition(stageTransition)
        }
    }

    private var stageTransition: AnyTransition {
        if reduceMotion { return .opacity }
        let insertion: Edge = movingForward ? .trailing : .leading
        let removal: Edge = movingForward ? .leading : .trailing
        return .asymmetric(insertion: AnyTransition.move(edge: insertion).combined(with: .opacity),
                           removal: AnyTransition.move(edge: removal).combined(with: .opacity))
    }

    /// Sets the direction first, then changes the step on the next turn so the outgoing step
    /// leaves in the right direction.
    private func go(to next: Stage, forward: Bool) {
        movingForward = forward
        Task { @MainActor in
            withAnimation(reduceMotion ? Animation.easeOut(duration: 0.25) : Motion.standard) {
                stage = next
            }
        }
    }

    private func finish() {
        guard let useCase else { return }
        settings.useCase = useCase
        Haptics.success()
        onFinish()
    }
}
