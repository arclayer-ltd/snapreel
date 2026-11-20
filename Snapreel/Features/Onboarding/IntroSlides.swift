import SwiftUI

/// One intro slide: a character clip and what Snapreel does for you.
struct IntroSlide: Identifiable {
    let index: Int
    let clip: CharacterClip
    let kicker: String
    let symbol: String
    let title: String
    /// The end of the title, drawn in the accent colour.
    let accent: String
    let message: String

    var id: Int { index }

    static let all: [IntroSlide] = [
        IntroSlide(index: 0, clip: .introRecord, kicker: "Record", symbol: "record.circle",
                   title: "Record ", accent: "what you mean",
                   message: "Capture your screen, your camera or just your voice. One tap to start, one tap to stop."),
        IntroSlide(index: 1, clip: .introLibrary, kicker: "Organise", symbol: "folder",
                   title: "Keep it ", accent: "organised",
                   message: "Sort recordings into folders, add tags and pin notes to the exact moment. Search even finds the words you said."),
        IntroSlide(index: 2, clip: .introSend, kicker: "Send", symbol: "paperplane",
                   title: "Send it ", accent: "your way",
                   message: "Copy a link that plays in any browser and see who watched, or AirDrop, message or mail the video file itself."),
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
            .foregroundStyle(Color.srTextSecondary)
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
        HStack(spacing: Space.s) {
            if page > 0 {
                Button {
                    withAnimation(Motion.standard) { page -= 1 }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.srText)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color.srFill))
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel("Back")
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
            // Welcome is the first page of four; the slides are the other three.
            OnboardingPageDots(count: slides.count + 1, index: page + 1)
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
    @Environment(\.colorScheme) private var colorScheme

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
            .onboardingStage(clip: slide.clip, pageWidth: size.width, height: side * 0.8, colorScheme: colorScheme)
            .scaleEffect(isActive || reduceMotion ? 1 : 0.92)
            .opacity(isActive ? 1 : 0.55)
            .overlay(alignment: IntroCallout.alignment(for: slide.index)) {
                // A bit of the real app beside the character, so the slide shows what it means.
                IntroCallout(index: slide.index)
                    // In Light mode the art is a card inset by the margin; keep the callout inside it.
                    .padding(.horizontal, colorScheme == .light ? Space.gutter + Space.m : Space.gutter)
                    .padding(.vertical, colorScheme == .light ? Space.m : Space.l)
                    .opacity(isActive ? 1 : 0)
                    .offset(y: isActive || reduceMotion ? 0 : 12)
                    .accessibilityHidden(true)
            }
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
            (Text(slide.title).foregroundColor(Color.srText)
                + Text(slide.accent).foregroundColor(OnboardingStyle.accent))
                .font(.srDisplay)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(slide.message)
                .font(.srBody)
                .foregroundStyle(Color.srTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.gutter)
    }
}

/// Small pieces of Snapreel's own interface floating beside each intro character: the
/// recording pill, a folder with a tag, and the places a file can go. They follow the
/// appearance, like the screens they come from.
struct IntroCallout: View {
    let index: Int

    static func alignment(for index: Int) -> Alignment {
        switch index {
        case 0: return .topTrailing
        case 1: return .bottomLeading
        default: return .bottomTrailing
        }
    }

    var body: some View {
        switch index {
        case 0: recording
        case 1: folder
        default: destinations
        }
    }

    private var recording: some View {
        VStack(alignment: .trailing, spacing: Space.xs) {
            HStack(spacing: 6) {
                Circle().fill(Color.white).frame(width: 7, height: 7)
                Text("REC 0:42")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Capsule().fill(Color.srRed))
            .shadow(color: Color.srRed.opacity(0.45), radius: 12, y: 4)
            HStack(spacing: 6) {
                ForEach(["rectangle.on.rectangle", "video.fill", "waveform"], id: \.self) { symbol in
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.srText)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.srFill))
                }
            }
        }
    }

    private var folder: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Space.xs) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.srRed)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Product")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.srText)
                    Text("3 recordings")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.srTextSecondary)
                }
            }
            HStack(spacing: 4) {
                Text("# checkout")
                Text("Note at 0:14")
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.srRedText)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.srSurface))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.srLine))
        .shadow(color: Color.black.opacity(0.18), radius: 14, y: 6)
    }

    private var destinations: some View {
        HStack(spacing: 6) {
            ForEach(["dot.radiowaves.left.and.right", "message.fill", "envelope.fill", "photo.on.rectangle"], id: \.self) { symbol in
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(symbol == "photo.on.rectangle" ? Color.white : Color.srText)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(symbol == "photo.on.rectangle" ? Color.srRed : Color.srFill))
            }
        }
        .padding(6)
        .background(Capsule().fill(Color.srSurface))
        .overlay(Capsule().strokeBorder(Color.srLine))
        .shadow(color: Color.black.opacity(0.18), radius: 14, y: 6)
    }
}
