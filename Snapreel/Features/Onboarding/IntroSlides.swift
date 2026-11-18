import SwiftUI

/// One intro slide: a character clip and what Snapreel does for you.
struct IntroSlide: Identifiable {
    let index: Int
    let clip: CharacterClip
    let kicker: String
    let symbol: String
    let title: String
    let message: String

    var id: Int { index }

    static let all: [IntroSlide] = [
        IntroSlide(index: 0, clip: .introRecord, kicker: "Record", symbol: "record.circle",
                   title: "Record what you mean",
                   message: "Capture your screen, your camera or just your voice. One tap to start, one tap to stop."),
        IntroSlide(index: 1, clip: .introLibrary, kicker: "Organise", symbol: "folder",
                   title: "Keep it organised",
                   message: "Sort recordings into folders, add tags and pin notes to the exact moment. Search even finds the words you said."),
        IntroSlide(index: 2, clip: .introSend, kicker: "Send", symbol: "paperplane",
                   title: "Send it your way",
                   message: "AirDrop it, message it, mail it or save it to Photos. It's a real video file, so it plays anywhere."),
    ]
}

/// The three swipeable intro slides with Skip, a page indicator and Next.
struct IntroSlides: View {
    @Binding var page: Int
    let onSkip: @MainActor () -> Void
    let onContinue: @MainActor () -> Void

    private let slides = IntroSlide.all

    init(page: Binding<Int>, onSkip: @escaping @MainActor () -> Void, onContinue: @escaping @MainActor () -> Void) {
        _page = page
        self.onSkip = onSkip
        self.onContinue = onContinue
    }

    private var isLast: Bool { page >= slides.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            TabView(selection: $page) {
                ForEach(slides) { slide in
                    IntroSlidePage(slide: slide, isActive: slide.index == page)
                        .tag(slide.index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            bottomBar
        }
        .onChange(of: page) { _ in Haptics.selection() }
    }

    private var topBar: some View {
        HStack {
            BrandLockup(markSize: 22, font: .srHeadline)
            Spacer()
            Button("Skip") {
                Haptics.tap()
                onSkip()
            }
            .font(.srSubheadlineStrong)
            .foregroundStyle(Color.srOnDarkSecondary)
            .padding(.vertical, Space.xs)
            .padding(.leading, Space.m)
            .contentShape(Rectangle())
            .opacity(isLast ? 0 : 1)
            .disabled(isLast)
            .accessibilityHint("Goes straight to the last question")
        }
        .padding(.horizontal, Space.gutter)
        .frame(height: 44)
        .animation(Motion.quick, value: isLast)
    }

    private var bottomBar: some View {
        HStack {
            OnboardingPageDots(count: slides.count, index: page)
            Spacer()
            Button {
                if isLast {
                    Haptics.tap()
                    onContinue()
                } else {
                    withAnimation(Motion.standard) { page += 1 }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(isLast ? "Continue" : "Next")
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .bold))
                }
            }
            .buttonStyle(.srPrimaryCompact)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.s)
        .padding(.bottom, Space.m)
    }
}

/// A single slide. The character eases up to full size when its slide settles.
struct IntroSlidePage: View {
    let slide: IntroSlide
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    init(slide: IntroSlide, isActive: Bool) {
        self.slide = slide
        self.isActive = isActive
    }

    var body: some View {
        GeometryReader { proxy in
            // Art and words sit together as one block in the middle of the page.
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                character(in: proxy.size)
                text
                    .padding(.top, Space.s)
                Spacer(minLength: Space.m)
            }
        }
    }

    /// Square clips keep their people in the middle 72%, so the box is shorter than the clip
    /// and the faded edges spill over the page.
    private func character(in size: CGSize) -> some View {
        let share: CGFloat = typeSize.isAccessibilitySize ? 0.4 : 0.7
        let side = min(size.width * 1.06, size.height * share)
        return OnboardingCharacter(clip: slide.clip, width: side)
            .frame(width: size.width, height: side * 0.8)
            .scaleEffect(isActive || reduceMotion ? 1 : 0.92)
            .opacity(isActive ? 1 : 0.55)
            .animation(reduceMotion ? nil : Motion.standard, value: isActive)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: 6) {
                Image(systemName: slide.symbol)
                    .font(.system(size: 12, weight: .bold))
                Text(slide.kicker.uppercased())
                    .font(.srCaption)
                    .kerning(1.2)
            }
            .foregroundStyle(Color.srRed)
            .accessibilityHidden(true)
            Text(slide.title)
                .font(.srDisplay)
                .foregroundStyle(Color.srOnDark)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(slide.message)
                .font(.srCallout)
                .foregroundStyle(Color.srOnDarkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.gutter)
    }
}
