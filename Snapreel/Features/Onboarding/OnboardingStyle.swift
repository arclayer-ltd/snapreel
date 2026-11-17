import SwiftUI

/// Shared look of the getting-started screens. The page colour is the one baked into the dark
/// character clips, so the clips sit on the page with no visible edge.
enum OnboardingStyle {
    static let background: Color = CharacterClip.welcome.background
    /// Cards and rows on the onboarding page.
    static let raised: Color = Color.srInkRaised
}

/// A character clip drawn at `width` (it may be wider than the screen), with its flat edges
/// faded out so only the people show against the page. Wrap it in a smaller frame to let it
/// spill past its box without pushing the layout around.
struct OnboardingCharacter: View {
    let clip: CharacterClip
    let width: CGFloat

    var body: some View {
        CharacterView(clip: clip, cornerRadius: 0)
            .frame(width: width, height: width / clip.aspectRatio)
            .mask { EdgeFadeMask() }
    }
}

/// Opaque in the middle, fading to clear over the outer tenth on every side.
struct EdgeFadeMask: View {
    var body: some View {
        LinearGradient(stops: Self.stops, startPoint: .leading, endPoint: .trailing)
            .mask { LinearGradient(stops: Self.stops, startPoint: .top, endPoint: .bottom) }
    }

    private static let stops: [Gradient.Stop] = [
        Gradient.Stop(color: .clear, location: 0),
        Gradient.Stop(color: .black, location: 0.1),
        Gradient.Stop(color: .black, location: 0.9),
        Gradient.Stop(color: .clear, location: 1),
    ]
}

/// Page indicator: the current page is a longer red capsule.
struct OnboardingPageDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { item in
                Capsule()
                    .fill(item == index ? Color.srRed : Color.white.opacity(0.26))
                    .frame(width: item == index ? 22 : 7, height: 7)
            }
        }
        .animation(Motion.quick, value: index)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(index + 1) of \(count)")
    }
}

/// Small brand lockup: the mark and the name.
struct BrandLockup: View {
    var markSize: CGFloat = 24
    var font: Font = .srHeadline

    var body: some View {
        HStack(spacing: Space.xs) {
            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: markSize, height: markSize)
            Text("Snapreel")
                .font(font)
                .foregroundStyle(Color.srOnDark)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Snapreel")
    }
}
