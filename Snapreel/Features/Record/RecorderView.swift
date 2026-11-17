import SwiftUI

/// Session B owns this file. Full-screen recorder with Camera / Screen / Audio modes,
/// presented by the shell for `router.recorder`.
struct RecorderView: View {
    let launch: RecorderLaunch
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.srInk.ignoresSafeArea()
            CircleIconButton(systemName: "xmark", label: "Close", tone: .dark) { dismiss() }
                .padding(Space.gutter)
        }
        .preferredColorScheme(.dark)
    }
}
