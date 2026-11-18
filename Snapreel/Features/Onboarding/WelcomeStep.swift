import SwiftUI

/// First screen on a new install: the five characters walking together, the name, the promise
/// and one way forward. There is nothing to sign in to.
struct WelcomeStep: View {
    let onStart: @MainActor () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var appeared = false

    init(onStart: @escaping @MainActor () -> Void) {
        self.onStart = onStart
    }

    var body: some View {
        GeometryReader { proxy in
            // The characters and the promise read as one block; the button stays at the bottom.
            VStack(spacing: 0) {
                Spacer(minLength: Space.s)
                character(in: proxy.size)
                copy
                    .padding(.top, Space.m)
                Spacer(minLength: Space.l)
                actions
            }
            .padding(.bottom, Space.s)
        }
        .onAppear { appeared = true }
    }

    // MARK: Parts

    /// The clip is drawn wider than the screen (its people fill the middle 70%), so they read
    /// large; the frame keeps the layout at screen width.
    private func character(in size: CGSize) -> some View {
        // Larger text sizes get the room; the characters shrink to make it.
        let share: CGFloat = typeSize.isAccessibilitySize ? 0.28 : 0.46
        let height = min(size.width * 1.22 * 0.75, size.height * share)
        let width = height / 0.75
        return OnboardingCharacter(clip: .welcome, width: width)
            .frame(width: size.width, height: height)
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared || reduceMotion ? 1 : 0.96)
            .animation(reduceMotion ? Animation.easeOut(duration: 0.25) : Motion.gentle, value: appeared)
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            BrandLockup(markSize: 28, font: .srTitle3)
                .padding(.bottom, Space.xxs)
            Text("Say it with a quick video.")
                .font(.srLargeTitle)
                .foregroundStyle(Color.srOnDark)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("Record your screen, your camera or just your voice, then send it to anyone in seconds.")
                .font(.srCallout)
                .foregroundStyle(Color.srOnDarkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.gutter)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared || reduceMotion ? 0 : 18)
        .animation(entrance(delay: 0.12), value: appeared)
    }

    private var actions: some View {
        VStack(spacing: Space.m) {
            Button("Get started") {
                Haptics.firm()
                onStart()
            }
            .buttonStyle(.srPrimary)
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text("No account. Everything stays on this iPhone.")
                    .font(.srFootnote)
            }
            .foregroundStyle(Color.srOnDarkTertiary)
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, Space.gutter)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared || reduceMotion ? 0 : 18)
        .animation(entrance(delay: 0.22), value: appeared)
    }

    private func entrance(delay: Double) -> Animation {
        reduceMotion ? Animation.easeOut(duration: 0.25) : Motion.standard.delay(delay)
    }
}
