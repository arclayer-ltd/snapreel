import SwiftUI

/// Snapreel's button styles. Use `.buttonStyle(.srPrimary)` etc.
struct SRButtonStyle: ButtonStyle {
    enum Kind {
        /// Red capsule, white label. One per screen.
        case primary
        /// Light: ink outline on white. Dark: white outline on ink.
        case secondary
        /// Plain red text.
        case tertiary
        /// Red text on a soft red fill, for destructive confirmations inside sheets.
        case destructive
        /// White capsule with ink label, for primary actions on dark video surfaces.
        case inverted
    }

    var kind: Kind
    var fullWidth: Bool = true
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        SRButtonBody(configuration: configuration, kind: kind, fullWidth: fullWidth, compact: compact)
    }
}

private struct SRButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: SRButtonStyle.Kind
    let fullWidth: Bool
    let compact: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        configuration.label
            .font(compact ? .srSubheadlineStrong : .srHeadline)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .foregroundStyle(foreground)
            .padding(.horizontal, compact ? Space.m : Space.xl)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: kind == .tertiary ? nil : (compact ? 40 : 54))
            .background(background)
            .overlay(border)
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: return .white
        case .secondary: return colorScheme == .dark ? .white : .srText
        case .tertiary: return configuration.isPressed ? .srRedDeep : .srRed
        case .destructive: return .srRedText
        case .inverted: return .srInk
        }
    }

    @ViewBuilder private var background: some View {
        switch kind {
        case .primary:
            Capsule().fill(configuration.isPressed ? Color.srRedDeep : Color.srRed)
        case .secondary:
            Capsule().fill(colorScheme == .dark ? Color.white.opacity(configuration.isPressed ? 0.12 : 0.06)
                                                : Color.srSurface.opacity(configuration.isPressed ? 0.7 : 1))
        case .tertiary:
            Color.clear
        case .destructive:
            Capsule().fill(Color.srRedSoft)
        case .inverted:
            Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.85 : 1))
        }
    }

    @ViewBuilder private var border: some View {
        if kind == .secondary {
            Capsule().strokeBorder(colorScheme == .dark ? Color.white.opacity(0.22) : Color.srLine, lineWidth: 1)
        }
    }
}

extension ButtonStyle where Self == SRButtonStyle {
    static var srPrimary: SRButtonStyle { SRButtonStyle(kind: .primary) }
    static var srSecondary: SRButtonStyle { SRButtonStyle(kind: .secondary) }
    static var srTertiary: SRButtonStyle { SRButtonStyle(kind: .tertiary, fullWidth: false) }
    static var srDestructive: SRButtonStyle { SRButtonStyle(kind: .destructive) }
    static var srInverted: SRButtonStyle { SRButtonStyle(kind: .inverted) }
    static var srPrimaryCompact: SRButtonStyle { SRButtonStyle(kind: .primary, fullWidth: false, compact: true) }
    static var srSecondaryCompact: SRButtonStyle { SRButtonStyle(kind: .secondary, fullWidth: false, compact: true) }
}

/// Round icon button. `.light` sits on white/canvas, `.dark` on ink or over video.
struct CircleIconButton: View {
    enum Tone { case light, dark, glass, red }

    let systemName: String
    let label: String
    var tone: Tone = .light
    var size: CGFloat = 36
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.tap()
            action()
        }) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .background(Circle().fill(fill))
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(label)
    }

    private var foreground: Color {
        switch tone {
        case .light: return .srText
        case .dark, .glass, .red: return .white
        }
    }

    private var fill: Color {
        switch tone {
        case .light: return .srFill
        case .dark: return .srInkControl
        case .glass: return Color.black.opacity(0.38)
        case .red: return .srRed
        }
    }
}

/// Subtle press feedback for custom tappable views.
struct PressScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.94
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}

/// The big round record control used by the recorder and the tab bar's centre button.
struct RecordButtonShape: View {
    var isRecording: Bool
    var diameter: CGFloat = 76

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.white.opacity(0.9), lineWidth: diameter * 0.06)
            RoundedRectangle(cornerRadius: isRecording ? diameter * 0.1 : diameter * 0.4, style: .continuous)
                .fill(Color.srRed)
                .frame(width: isRecording ? diameter * 0.38 : diameter * 0.8,
                       height: isRecording ? diameter * 0.38 : diameter * 0.8)
        }
        .frame(width: diameter, height: diameter)
        .animation(Motion.standard, value: isRecording)
    }
}
