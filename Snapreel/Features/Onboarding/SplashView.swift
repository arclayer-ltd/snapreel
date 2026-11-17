import SwiftUI

/// Session A owns this file. Brand splash shown on every cold launch, then `onFinish`.
struct SplashView: View {
    let onFinish: () -> Void

    var body: some View {
        ZStack {
            Color.srInk.ignoresSafeArea()
            Image("BrandMark").resizable().scaledToFit().frame(width: 96)
        }
        .task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            onFinish()
        }
    }
}
