import SwiftUI
import UIKit

// MARK: - Colour
//
// Sampled from the app icon (art/icon-1024.png): a record-red ring and dot on near-black.
// Red is the only accent: primary actions, recording state, selection and the unread dot.
//
// Two kinds of colour:
// - Fixed ink colours (`srInk…`, `srOnDark…`) for the recorder, the player and the splash,
//   which stay dark in both appearances, like the Camera app and a video player.
// - Adaptive colours (`srCanvas`, `srSurface`, `srText`…) for everything else. They're light
//   in Light mode and switch to the ink family in Dark mode, following the iPhone's setting
//   or Settings > Appearance (`AppearanceMode`).

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }

    /// A colour that follows the current appearance: `light` in Light mode, `dark` in Dark mode.
    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

extension ShapeStyle where Self == Color {
    // Accent (icon ring and dot)
    /// #F04850, the ring. Primary buttons, record button, selection, unread dot.
    static var srRed: Color { Color(hex: 0xF04850) }
    /// #D32434, the ring's shaded edge. Pressed state, text on light red.
    static var srRedDeep: Color { Color(hex: 0xD32434) }
    /// #FE6262, the dot's highlight. Glows and live indicators on dark.
    static var srRedGlow: Color { Color(hex: 0xFE6262) }
    /// Tinted red behind red icons and destructive labels. Light: #FDECED. Dark: #3B1D24.
    static var srRedSoft: Color { Color(light: 0xFDECED, dark: 0x3B1D24) }
    /// Red text and destructive labels on adaptive surfaces. Light: #D32434. Dark: #FF6E72.
    static var srRedText: Color { Color(light: 0xD32434, dark: 0xFF6E72) }

    // Dark surfaces (icon background)
    /// #13141B, the icon background. Recorder, player, splash.
    static var srInk: Color { Color(hex: 0x13141B) }
    /// #07080C, the icon's darkest corner. Behind video.
    static var srInkDeep: Color { Color(hex: 0x07080C) }
    /// #1C1E27, raised cards and sheets on dark.
    static var srInkRaised: Color { Color(hex: 0x1C1E27) }
    /// #2A2C37, controls and fields on dark.
    static var srInkControl: Color { Color(hex: 0x2A2C37) }
    /// Hairlines on dark.
    static var srInkLine: Color { Color.white.opacity(0.09) }

    // Text on dark
    static var srOnDark: Color { Color.white }
    static var srOnDarkSecondary: Color { Color.white.opacity(0.72) }
    static var srOnDarkTertiary: Color { Color.white.opacity(0.42) }

    // Adaptive surfaces (tabs, lists, settings, sheets, onboarding)
    /// Grouped background behind lists and settings. Light: #F4F4F6. Dark: #0E0F14.
    static var srCanvas: Color { Color(light: 0xF4F4F6, dark: 0x0E0F14) }
    /// Cards, rows and the tab bar. Light: white. Dark: #1C1E27 (ink raised).
    static var srSurface: Color { Color(light: 0xFFFFFF, dark: 0x1C1E27) }
    /// Search fields, chips, placeholders. Light: #ECECF0. Dark: #2A2C37 (ink control).
    static var srFill: Color { Color(light: 0xECECF0, dark: 0x2A2C37) }
    /// Hairlines. Light: #E3E3E8. Dark: #30323D.
    static var srLine: Color { Color(light: 0xE3E3E8, dark: 0x30323D) }

    // Adaptive text
    /// Primary text. Light: ink #13141B. Dark: #F4F4F6.
    static var srText: Color { Color(light: 0x13141B, dark: 0xF4F4F6) }
    /// Light: #5B5E6B. Dark: #A6A9B5.
    static var srTextSecondary: Color { Color(light: 0x5B5E6B, dark: 0xA6A9B5) }
    /// Light: #8F929D. Dark: #737685.
    static var srTextTertiary: Color { Color(light: 0x8F929D, dark: 0x737685) }

    // Adaptive inverse, for selected chips and pills that stand out from the page
    /// Light: ink. Dark: near-white.
    static var srInverse: Color { Color(light: 0x13141B, dark: 0xF4F4F6) }
    /// Text on `srInverse`. Light: white. Dark: ink.
    static var srOnInverse: Color { Color(light: 0xFFFFFF, dark: 0x13141B) }
    /// Floating toasts: ink in Light mode, a raised grey in Dark mode so they lift off the page.
    static var srToast: Color { Color(light: 0x13141B, dark: 0x30323D) }
}

extension UIColor {
    static let srRed = UIColor(red: 0xF0 / 255, green: 0x48 / 255, blue: 0x50 / 255, alpha: 1)
    static let srInk = UIColor(red: 0x13 / 255, green: 0x14 / 255, blue: 0x1B / 255, alpha: 1)
}

// MARK: - Type
//
// System font on text styles so everything follows Dynamic Type. Rounded design is reserved
// for numbers (timers, durations, stats), which also use monospaced digits.

extension Font {
    /// 34 bold. Tab titles ("Home", "Library").
    static let srLargeTitle = Font.system(.largeTitle, design: .default, weight: .bold)
    /// 28 bold. Onboarding and empty-state headlines.
    static let srDisplay = Font.system(.title, design: .default, weight: .bold)
    /// 22 bold. Section and sheet titles.
    static let srTitle = Font.system(.title2, design: .default, weight: .bold)
    /// 20 semibold. Card titles on detail screens.
    static let srTitle3 = Font.system(.title3, design: .default, weight: .semibold)
    /// 17 semibold. Row titles, buttons.
    static let srHeadline = Font.system(.headline, design: .default, weight: .semibold)
    /// 17 regular.
    static let srBody = Font.system(.body)
    /// 16 regular.
    static let srCallout = Font.system(.callout)
    /// 15 regular. Secondary lines.
    static let srSubheadline = Font.system(.subheadline)
    /// 15 semibold.
    static let srSubheadlineStrong = Font.system(.subheadline, design: .default, weight: .semibold)
    /// 13 regular. Metadata ("2h ago").
    static let srFootnote = Font.system(.footnote)
    /// 12 medium. Badges, captions.
    static let srCaption = Font.system(.caption, design: .default, weight: .medium)
    /// Timers and durations: rounded, monospaced digits.
    static let srTimer = Font.system(.body, design: .rounded, weight: .semibold).monospacedDigit()
    static let srTimerSmall = Font.system(.caption, design: .rounded, weight: .semibold).monospacedDigit()
    /// Big numbers on stats.
    static let srStat = Font.system(.largeTitle, design: .rounded, weight: .bold).monospacedDigit()
}

// MARK: - Layout

enum Space {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48
    /// Side margin of every screen.
    static let gutter: CGFloat = 20
}

enum Radius {
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
}

enum Motion {
    static let quick = Animation.spring(response: 0.28, dampingFraction: 0.9)
    static let standard = Animation.spring(response: 0.42, dampingFraction: 0.86)
    static let gentle = Animation.easeInOut(duration: 0.5)
}

extension View {
    /// Soft shadow for cards that float over light surfaces.
    func srCardShadow() -> some View {
        shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
    }

    /// Light surface card: white, rounded, hairline.
    func srCard(radius: CGFloat = Radius.l) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color.srSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.srLine, lineWidth: 0.5)
        )
    }
}
