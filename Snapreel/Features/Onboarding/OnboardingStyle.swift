import SwiftUI

/// Shared look of the getting-started screens, in both appearances.
/// Dark: the page is the colour baked into the character clips, so the clips sit on it with no
/// visible edge. Light: the page is the app's canvas and each clip sits in a rounded card of its
/// own colour (`onboardingStage`).
enum OnboardingStyle {
    static let background = Color(light: 0xF4F4F6, dark: 0x15151F)
    /// Answer rows on the onboarding page.
    static let raised = Color(light: 0xFFFFFF, dark: 0x1C1E27)
    /// A selected answer row.
    static let raisedSelected = Color(light: 0xFFFFFF, dark: 0x2A2C37)
    /// The red end of each headline: the dot's glow on dark, a deeper red that reads on light.
    static let accent = Color(light: 0xE03A44, dark: 0xFE6262)
    /// Page dots that aren't the current page, and unselected radio rings.
    static let quiet = Color(light: 0xC8C9D0, dark: 0x525259)
}

extension View {
    /// Frames a character clip `height` tall on a page `pageWidth` wide. Dark mode: full width,
    /// the clip's faded edges melting into the page. Light mode: inset by the screen margin in a
    /// rounded card the colour of the clip, so the dark art reads as a picture on the light page.
    func onboardingStage(clip: CharacterClip, pageWidth: CGFloat, height: CGFloat,
                         colorScheme: ColorScheme) -> some View {
        let isCard = colorScheme == .light
        let shape = RoundedRectangle(cornerRadius: isCard ? Radius.xl : 0, style: .continuous)
        return frame(width: isCard ? max(pageWidth - Space.gutter * 2, 0) : pageWidth, height: height)
            .background(isCard ? clip.background : Color.clear)
            .clipShape(shape)
            .frame(width: pageWidth)
    }
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
                    .fill(item == index ? Color.srRed : OnboardingStyle.quiet)
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
                .foregroundStyle(Color.srText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Snapreel")
    }
}
