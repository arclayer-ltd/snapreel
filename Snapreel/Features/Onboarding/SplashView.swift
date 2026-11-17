import SwiftUI

/// Brand splash shown on every cold launch, then `onFinish`.
/// The ring draws itself, the dot drops in and settles, the name fades up (about 0.9 s), then a
/// short hold. With Reduce Motion the finished mark shows straight away.
struct SplashView: View {
    let onFinish: @MainActor () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ringProgress: CGFloat = 0
    @State private var dotScale: CGFloat = 0.01
    @State private var glow: Double = 0
    @State private var nameShown: Double = 0

    init(onFinish: @escaping @MainActor () -> Void) {
        self.onFinish = onFinish
    }

    var body: some View {
        ZStack {
            Color.srInk.ignoresSafeArea()
            VStack(spacing: Space.l) {
                BrandMarkDrawing(ringProgress: ringProgress, dotScale: dotScale)
                    .frame(width: 96, height: 96)
                    .background(glowHalo)
                Text("Snapreel")
                    .font(.srTitle)
                    .foregroundStyle(Color.srOnDark)
                    .opacity(nameShown)
                    .offset(y: CGFloat(1 - nameShown) * 8)
            }
            .offset(y: -12)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Snapreel")
        .task { await play() }
    }

    private var glowHalo: some View {
        Circle()
            .fill(Color.srRed.opacity(0.32))
            .frame(width: 170, height: 170)
            .blur(radius: 44)
            .opacity(glow)
    }

    @MainActor
    private func play() async {
        if reduceMotion {
            ringProgress = 1
            dotScale = 1
            glow = 1
            nameShown = 1
            try? await Task.sleep(nanoseconds: 650_000_000)
            onFinish()
            return
        }
        withAnimation(.easeInOut(duration: 0.5)) { ringProgress = 1 }
        try? await Task.sleep(nanoseconds: 320_000_000)
        withAnimation(.spring(response: 0.36, dampingFraction: 0.58)) { dotScale = 1 }
        withAnimation(.easeOut(duration: 0.6)) { glow = 1 }
        try? await Task.sleep(nanoseconds: 160_000_000)
        withAnimation(.easeOut(duration: 0.4)) { nameShown = 1 }
        try? await Task.sleep(nanoseconds: 620_000_000)
        onFinish()
    }
}

/// The record mark (red ring around a red dot) drawn in SwiftUI so it can animate.
/// Proportions follow the app icon: ring 11.5% of the width, dot 45.5%.
struct BrandMarkDrawing: View {
    var ringProgress: CGFloat = 1
    var dotScale: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let line = side * 0.115
            ZStack {
                Circle()
                    .trim(from: 0, to: ringProgress)
                    .stroke(ringFill, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(line / 2)
                Circle()
                    .fill(RadialGradient(colors: [Color.srRedGlow, Color.srRed, Color.srRedDeep],
                                         center: UnitPoint(x: 0.38, y: 0.32),
                                         startRadius: 0,
                                         endRadius: side * 0.3))
                    .frame(width: side * 0.455, height: side * 0.455)
                    .scaleEffect(dotScale)
            }
            .frame(width: side, height: side)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }

    private var ringFill: LinearGradient {
        LinearGradient(colors: [Color.srRedGlow, Color.srRed, Color.srRedDeep],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
