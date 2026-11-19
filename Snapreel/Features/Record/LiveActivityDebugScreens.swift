#if DEBUG
import SwiftUI

extension DebugCatalog {
    /// The recording Live Activity (the Live Activity build, after build 25). The simulator
    /// can't screenshot the real Lock Screen, so these draw the same views the widget
    /// extension uses (`RecordingActivity/`) on a stand-in Lock Screen and Dynamic Island.
    static var liveActivityScreens: [DebugScreen] {
        [
            DebugScreen("rec.live", "Live Activity on the Lock Screen [screen recording]") {
                LiveActivityLockScreenMock(cards: [
                    (.screen, .recording(clockStart: Date().addingTimeInterval(-83))),
                ])
            },
            DebugScreen("rec.live.states", "Live Activity on the Lock Screen [starting, voice, paused]") {
                LiveActivityLockScreenMock(cards: [
                    (.screen, .starting()),
                    (.audio, .recording(clockStart: Date().addingTimeInterval(-42))),
                    (.audio, .paused(elapsed: 125)),
                ])
            },
            DebugScreen("rec.live.stopped", "Live Activity after the phone locked [stopped, stale]") {
                // Locking the phone ends a screen broadcast: the card freezes as stopped. The
                // second card is the backstop when Snapreel couldn't hear the end (stale date
                // passed): no clock, "open Snapreel to check".
                LiveActivityLockScreenMock(cards: [
                    (.screen, .stopped(elapsed: 14)),
                    (.screen, .recording(clockStart: Date().addingTimeInterval(-1_000))),
                ], staleCards: [1])
            },
            DebugScreen("rec.live.island", "Live Activity in the Dynamic Island") {
                LiveActivityIslandMock(kind: .screen,
                                       status: .recording(clockStart: Date().addingTimeInterval(-83)))
            },
        ]
    }
}

/// A stand-in wallpaper: the Live Activity is drawn by iOS over whatever the person chose.
/// Like Apple's own wallpapers it has a light and a dark version, so the screenshots show
/// which appearance the card is in.
private struct LiveActivityWallpaper: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(colors: colorScheme == .dark
                        ? [Color(hex: 0x3B2F63), Color(hex: 0x1B2A44), Color(hex: 0x0E1420)]
                        : [Color(hex: 0xC9C3E8), Color(hex: 0xDCE3F2), Color(hex: 0xEEF1F7)],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

/// The Lock Screen's clock and date: white on the dark wallpaper, ink on the light one.
private func lockScreenText(_ scheme: ColorScheme) -> Color {
    scheme == .dark ? .white : RecordingActivityStyle.ink
}

private struct LiveActivityLockScreenMock: View {
    let cards: [(RecordingActivityKind, RecordingActivityStatus)]
    /// Indexes of cards drawn as iOS draws them once their stale date has passed.
    var staleCards: Set<Int> = []
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LiveActivityWallpaper()
            VStack(spacing: 0) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .padding(.top, 18)
                Text("Thursday 19 November")
                    .font(.system(size: 20, weight: .semibold))
                    .padding(.top, 10)
                Text("9:41")
                    .font(.system(size: 88, weight: .bold, design: .rounded))
                Spacer()
                VStack(spacing: 10) {
                    ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                        RecordingActivityLockScreenView(kind: card.0, status: card.1,
                                                        isStale: staleCards.contains(index))
                            .background(RecordingActivityStyle.background(colorScheme))
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                }
                .padding(.horizontal, 12)
                Spacer().frame(height: 120)
            }
            .foregroundColor(lockScreenText(colorScheme))
        }
    }
}

/// The Dynamic Island is black in both appearances (iOS draws it), so only the wallpaper and
/// the captions around it change.
private struct LiveActivityIslandMock: View {
    let kind: RecordingActivityKind
    let status: RecordingActivityStatus
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .top) {
            LiveActivityWallpaper()
            VStack(spacing: 28) {
                // Compact: either side of the camera.
                HStack {
                    RecordingActivityCompactLeading(phase: status.phase)
                    Spacer()
                    RecordingActivityCompactTrailing(status: status)
                }
                .padding(.horizontal, 14)
                .frame(width: 250, height: 37)
                .background(Capsule().fill(Color.black))
                .padding(.top, 11)

                caption("Touch and hold")

                // Expanded.
                VStack(spacing: 10) {
                    HStack(alignment: .center) {
                        RecordingActivityMark(phase: status.phase, size: 44)
                            .padding(.leading, 4)
                        Spacer()
                        RecordingActivityExpandedClock(status: status)
                            .padding(.trailing, 4)
                    }
                    RecordingActivityExpandedText(kind: kind, status: status)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
                .frame(width: 355)
                .background(RoundedRectangle(cornerRadius: 44, style: .continuous).fill(Color.black))

                caption("With another Live Activity")

                // Minimal: beside another app's Live Activity.
                HStack(spacing: 8) {
                    Capsule().fill(Color.black).frame(width: 160, height: 37)
                    RecordingActivityCompactLeading(phase: status.phase)
                        .frame(width: 37, height: 37)
                        .background(Circle().fill(Color.black))
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundColor(lockScreenText(colorScheme).opacity(0.7))
    }
}
#endif
