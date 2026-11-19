import SwiftUI

// The pieces of the recording Live Activity. The widget extension puts them on the Lock Screen
// and in the Dynamic Island; the app's `rec.live` debug screens draw them too, so CI has
// screenshots of what the Lock Screen shows.

/// Colours and link for the Live Activity. The widget extension can't see the app's design
/// tokens (`Kit/Tokens.swift`), so it repeats the two it needs: the record red (#F04850) and the
/// recorder's ink (#13141B). Like the recorder, it stays dark in both appearances.
enum RecordingActivityStyle {
    static let red = Color(red: 0xF0 / 255, green: 0x48 / 255, blue: 0x50 / 255)
    static let ink = Color(red: 0x13 / 255, green: 0x14 / 255, blue: 0x1B / 255)
    static let secondary = Color.white.opacity(0.72)
    /// Opens Snapreel on the recording, where Stop is (see `AppLinks`).
    static let url = URL(string: "snapreel://recording")!

    /// "1:23", or "1:02:03" past an hour.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let rest = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }

    static func title(_ kind: RecordingActivityKind, _ phase: RecordingActivityStatus.Phase) -> String {
        switch (kind, phase) {
        case (_, .starting): return "Starting screen recording"
        case (.screen, .recording): return "Recording your screen"
        case (.screen, .paused): return "Screen recording paused"
        case (.audio, .recording): return "Recording your voice"
        case (.audio, .paused): return "Voice recording paused"
        }
    }

    static func subtitle(_ phase: RecordingActivityStatus.Phase) -> String {
        switch phase {
        case .starting: return "Tap Start Broadcast to begin"
        case .recording: return "Tap to open Snapreel and stop"
        case .paused: return "Tap to open Snapreel"
        }
    }
}

/// The recording time. While recording it counts by itself (iOS redraws a timer text without
/// Snapreel running).
struct RecordingActivityClock: View {
    let status: RecordingActivityStatus

    var body: some View {
        switch status.phase {
        case .recording:
            Text(status.clockStart, style: .timer)
        case .paused:
            Text(RecordingActivityStyle.clock(status.elapsed))
        case .starting:
            Text(RecordingActivityStyle.clock(0))
        }
    }
}

/// The red record mark: a dot while recording, pause bars while paused.
struct RecordingActivityMark: View {
    let phase: RecordingActivityStatus.Phase
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle().fill(RecordingActivityStyle.red.opacity(0.22))
            Image(systemName: RecordingActivityMark.symbol(phase))
                .font(.system(size: size * 0.46, weight: .bold))
                .foregroundColor(RecordingActivityStyle.red)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    static func symbol(_ phase: RecordingActivityStatus.Phase) -> String {
        switch phase {
        case .starting: return "record.circle"
        case .recording: return "record.circle.fill"
        case .paused: return "pause.fill"
        }
    }
}

/// The Lock Screen (and, on iPhones without the Dynamic Island, the banner at the top).
struct RecordingActivityLockScreenView: View {
    let kind: RecordingActivityKind
    let status: RecordingActivityStatus

    var body: some View {
        HStack(spacing: 12) {
            RecordingActivityMark(phase: status.phase, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(RecordingActivityStyle.title(kind, status.phase))
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(RecordingActivityStyle.subtitle(status.phase))
                    .font(.subheadline)
                    .foregroundColor(RecordingActivityStyle.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            RecordingActivityClock(status: status)
                .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundColor(status.phase == .recording ? .white : RecordingActivityStyle.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: 96, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }
}

/// Dynamic Island, compact: the mark on the left of the camera…
struct RecordingActivityCompactLeading: View {
    let phase: RecordingActivityStatus.Phase

    var body: some View {
        Image(systemName: RecordingActivityMark.symbol(phase))
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(RecordingActivityStyle.red)
            .accessibilityHidden(true)
    }
}

/// …and the time on its right. A timer text takes all the width it's offered, so it gets a
/// fixed width.
struct RecordingActivityCompactTrailing: View {
    let status: RecordingActivityStatus

    var body: some View {
        RecordingActivityClock(status: status)
            .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundColor(RecordingActivityStyle.red)
            .multilineTextAlignment(.trailing)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: 48, alignment: .trailing)
    }
}

/// Dynamic Island, expanded (touch and hold): the time large on the right.
struct RecordingActivityExpandedClock: View {
    let status: RecordingActivityStatus

    var body: some View {
        RecordingActivityClock(status: status)
            .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundColor(.white)
            .multilineTextAlignment(.trailing)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: 104, alignment: .trailing)
    }
}

/// Dynamic Island, expanded: what is recording and how to stop, under the camera.
struct RecordingActivityExpandedText: View {
    let kind: RecordingActivityKind
    let status: RecordingActivityStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(RecordingActivityStyle.title(kind, status.phase))
                .font(.headline)
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(RecordingActivityStyle.subtitle(status.phase))
                .font(.subheadline)
                .foregroundColor(RecordingActivityStyle.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
