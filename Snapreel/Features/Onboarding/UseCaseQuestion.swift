import SwiftUI

/// "What will you use Snapreel for?" One choice from `UseCase`; the chosen row opens up to show
/// its hint. Continue stays disabled until something is picked. The answer orders the
/// suggestions in the help centre.
struct UseCaseQuestion: View {
    @Binding var selection: UseCase?
    let onBack: @MainActor () -> Void
    let onContinue: @MainActor () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(selection: Binding<UseCase?>, onBack: @escaping @MainActor () -> Void,
         onContinue: @escaping @MainActor () -> Void) {
        _selection = selection
        self.onBack = onBack
        self.onContinue = onContinue
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    header
                    choices
                }
                .padding(.horizontal, Space.gutter)
                .padding(.top, Space.s)
                .padding(.bottom, Space.l)
            }
            footer
        }
    }

    private var topBar: some View {
        HStack {
            CircleIconButton(systemName: "chevron.left", label: "Back", tone: .dark, size: 36) {
                onBack()
            }
            Spacer()
        }
        .padding(.horizontal, Space.gutter)
        .frame(height: 44)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("ONE LAST THING")
                .font(.srCaption)
                .kerning(1.2)
                .foregroundStyle(Color.srRed)
                .accessibilityHidden(true)
            Text("What will you use Snapreel for?")
                .font(.srDisplay)
                .foregroundStyle(Color.srOnDark)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("Pick one and we'll put the most useful tips for you first in Help.")
                .font(.srCallout)
                .foregroundStyle(Color.srOnDarkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var choices: some View {
        VStack(spacing: Space.s) {
            ForEach(UseCase.allCases) { useCase in
                UseCaseRow(useCase: useCase, isSelected: selection == useCase) {
                    Haptics.selection()
                    withAnimation(reduceMotion ? Animation.easeOut(duration: 0.2) : Motion.standard) {
                        selection = useCase
                    }
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: Space.s) {
            Button("Continue") { onContinue() }
                .buttonStyle(.srPrimary)
                .disabled(selection == nil)
            Text(selection == nil ? "Choose one to continue" : "You're all set")
                .font(.srFootnote)
                .foregroundStyle(Color.srOnDarkTertiary)
                .animation(nil, value: selection)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.s)
        .padding(.bottom, Space.m)
    }
}

/// A selectable answer row. Selected: red outline, raised fill, hint revealed.
struct UseCaseRow: View {
    let useCase: UseCase
    let isSelected: Bool
    let action: @MainActor () -> Void

    init(useCase: UseCase, isSelected: Bool, action: @escaping @MainActor () -> Void) {
        self.useCase = useCase
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button {
            action()
        } label: {
            HStack(alignment: .top, spacing: Space.m) {
                IconTile(systemName: useCase.systemImage,
                         tint: isSelected ? .white : .srRed,
                         background: isSelected ? .srRed : Color.srRed.opacity(0.14),
                         size: 40)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(useCase.title)
                        .font(.srHeadline)
                        .foregroundStyle(Color.srOnDark)
                        .frame(minHeight: 40, alignment: .leading)
                    if isSelected {
                        Text(useCase.hint)
                            .font(.srSubheadline)
                            .foregroundStyle(Color.srOnDarkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                radio
                    .padding(.top, 9)
            }
            .padding(Space.m)
            .background(
                RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
                    .fill(isSelected ? Color.srInkControl : OnboardingStyle.raised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
                    .strokeBorder(isSelected ? Color.srRed : Color.srInkLine, lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(useCase.title)
        .accessibilityHint(isSelected ? useCase.hint : "")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }

    private var radio: some View {
        ZStack {
            Circle()
                .strokeBorder(isSelected ? Color.srRed : Color.white.opacity(0.3), lineWidth: 2)
            if isSelected {
                Circle()
                    .fill(Color.srRed)
                    .padding(5)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 22, height: 22)
    }
}
