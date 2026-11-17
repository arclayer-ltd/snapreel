import SwiftUI

/// Session A owns this file. Welcome, three intro slides and the "what will you use it for"
/// question. Calls `onFinish` when done; the guided tour then runs over the tab shell.
struct OnboardingFlow: View {
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: Space.l) {
            Spacer()
            Text("Snapreel").font(.srDisplay).foregroundStyle(Color.srOnDark)
            Spacer()
            Button("Get started", action: onFinish).buttonStyle(.srPrimary)
        }
        .padding(Space.gutter)
        .background(Color.srInk.ignoresSafeArea())
    }
}
