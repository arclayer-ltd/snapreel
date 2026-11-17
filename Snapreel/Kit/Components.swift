import SwiftUI
import UIKit

// MARK: - Empty state

/// Centered empty state. Pass `character` only where the brief allows a character (library,
/// watch history/later); everywhere else use `systemImage`.
struct EmptyStateView: View {
    var character: CharacterClip? = nil
    var systemImage: String? = nil
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var onDark = false

    var body: some View {
        VStack(spacing: Space.m) {
            if let character {
                CharacterView(clip: character)
                    .frame(maxWidth: 220)
                    .padding(.bottom, Space.xs)
            } else if let systemImage {
                ZStack {
                    Circle().fill(onDark ? Color.srInkControl : Color.srRedSoft)
                    Image(systemName: systemImage)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Color.srRed)
                }
                .frame(width: 64, height: 64)
                .padding(.bottom, Space.xxs)
            }
            VStack(spacing: Space.xs) {
                Text(title)
                    .font(.srTitle3)
                    .foregroundStyle(onDark ? Color.srOnDark : Color.srText)
                Text(message)
                    .font(.srSubheadline)
                    .foregroundStyle(onDark ? Color.srOnDarkSecondary : Color.srTextSecondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.srPrimaryCompact)
                    .padding(.top, Space.xs)
            }
        }
        .padding(.horizontal, Space.xxl)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Section header

/// "From my library            See all"
struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.srTitle3).foregroundStyle(Color.srText)
                if let subtitle {
                    Text(subtitle).font(.srFootnote).foregroundStyle(Color.srTextSecondary)
                }
            }
            Spacer(minLength: Space.s)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.srSubheadlineStrong)
                    .foregroundStyle(Color.srRed)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Rows

/// Icon tile used at the start of list rows (settings, home shortcuts).
struct IconTile: View {
    let systemName: String
    var tint: Color = .srRed
    var background: Color = .srRedSoft
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(background))
    }
}

/// A list row: icon tile, title, optional subtitle/value, chevron.
struct ListRow: View {
    var systemImage: String? = nil
    let title: String
    var subtitle: String? = nil
    var value: String? = nil
    var showsChevron = true
    var titleColor: Color = .srText

    var body: some View {
        HStack(spacing: Space.s) {
            if let systemImage { IconTile(systemName: systemImage) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.srBody).foregroundStyle(titleColor)
                if let subtitle {
                    Text(subtitle).font(.srFootnote).foregroundStyle(Color.srTextSecondary)
                }
            }
            Spacer(minLength: Space.xs)
            if let value {
                Text(value).font(.srSubheadline).foregroundStyle(Color.srTextTertiary)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.srTextTertiary)
            }
        }
        .padding(.vertical, Space.xs)
        .contentShape(Rectangle())
    }
}

// MARK: - Underline tabs

/// "My videos | Folders" style tabs with a red underline.
struct UnderlineTabs<Tab: Hashable>: View {
    let tabs: [Tab]
    @Binding var selection: Tab
    let title: (Tab) -> String
    @Namespace private var underline

    var body: some View {
        HStack(spacing: Space.xl) {
            ForEach(tabs, id: \.self) { tab in
                let selected = tab == selection
                Button {
                    Haptics.selection()
                    withAnimation(Motion.quick) { selection = tab }
                } label: {
                    VStack(spacing: 6) {
                        Text(title(tab))
                            .font(.srSubheadlineStrong)
                            .foregroundStyle(selected ? Color.srText : Color.srTextTertiary)
                        ZStack {
                            Capsule().fill(Color.clear).frame(height: 3)
                            if selected {
                                Capsule().fill(Color.srRed).frame(height: 3)
                                    .matchedGeometryEffect(id: "underline", in: underline)
                            }
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer()
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.srLine).frame(height: 0.5)
        }
    }
}

/// Capsule switch for two to three options on dark surfaces ("Notes | Transcript",
/// "Camera | Screen | Audio").
struct PillSwitch<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String
    var onDark = true
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    Haptics.selection()
                    withAnimation(Motion.quick) { selection = option }
                } label: {
                    Text(title(option))
                        .font(.srSubheadlineStrong)
                        .foregroundStyle(selected ? (onDark ? Color.srInk : Color.white)
                                                  : (onDark ? Color.srOnDarkSecondary : Color.srTextSecondary))
                        .padding(.horizontal, Space.m)
                        .frame(height: 34)
                        .background {
                            if selected {
                                Capsule().fill(onDark ? Color.white : Color.srInk)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(onDark ? Color.srInkControl : Color.srFill))
    }
}

// MARK: - Toast

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var systemImage: String = "checkmark.circle.fill"
}

/// Floating confirmation that disappears by itself ("Saved to Photos").
struct ToastView: View {
    let message: ToastMessage

    var body: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: message.systemImage)
                .foregroundStyle(Color.srRed)
            Text(message.text)
                .font(.srSubheadlineStrong)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
        .background(Capsule().fill(Color.srInk.opacity(0.94)))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Shows `message` for 2.4 seconds at the bottom, then clears it.
    func toast(_ message: Binding<ToastMessage?>, bottomInset: CGFloat = 96) -> some View {
        overlay(alignment: .bottom) {
            if let current = message.wrappedValue {
                ToastView(message: current)
                    .padding(.bottom, bottomInset)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: current.id) {
                        UIAccessibility.post(notification: .announcement, argument: current.text)
                        try? await Task.sleep(nanoseconds: 2_400_000_000)
                        withAnimation(Motion.standard) {
                            if message.wrappedValue?.id == current.id { message.wrappedValue = nil }
                        }
                    }
            }
        }
        .animation(Motion.standard, value: message.wrappedValue)
    }
}

// MARK: - Sheet header

/// Title bar for custom sheets: optional leading button, centred title, trailing button.
struct SheetHeader: View {
    let title: String
    var leadingTitle: String? = nil
    var leadingAction: (() -> Void)? = nil
    var trailingTitle: String? = nil
    var trailingEnabled = true
    var trailingAction: (() -> Void)? = nil
    var onDark = false

    var body: some View {
        ZStack {
            Text(title)
                .font(.srHeadline)
                .foregroundStyle(onDark ? Color.srOnDark : Color.srText)
                .lineLimit(1)
                .padding(.horizontal, 72)
            HStack {
                if let leadingTitle, let leadingAction {
                    Button(leadingTitle, action: leadingAction)
                        .font(.srBody)
                        .foregroundStyle(onDark ? Color.srOnDarkSecondary : Color.srTextSecondary)
                }
                Spacer()
                if let trailingTitle, let trailingAction {
                    Button(trailingTitle, action: trailingAction)
                        .font(.srHeadline)
                        .foregroundStyle(Color.srRed)
                        .disabled(!trailingEnabled)
                        .opacity(trailingEnabled ? 1 : 0.4)
                }
            }
        }
        .padding(.horizontal, Space.gutter)
        .frame(height: 52)
    }
}

// MARK: - Unread dot

struct UnreadDot: View {
    var size: CGFloat = 8
    var body: some View {
        Circle().fill(Color.srRed).frame(width: size, height: size)
            .overlay(Circle().strokeBorder(Color.white, lineWidth: size * 0.2))
    }
}
