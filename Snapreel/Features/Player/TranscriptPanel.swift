import SwiftUI

/// The Transcript tab: lines with their times, the line being spoken highlighted while it plays,
/// tap a line to play from there. Otherwise shows why there is no transcript yet and what to do.
struct TranscriptPanel: View {
    let video: Video
    let transcript: Transcript?
    let clock: PlaybackClock
    @ObservedObject var service: TranscriptService
    /// Pins the tab to one state (debug screens).
    let phaseOverride: TranscriptPhase?
    let onSeek: @MainActor (Double) -> Void
    let onRequest: @MainActor () -> Void
    let onCopy: @MainActor () -> Void

    @State private var currentIndex: Int?

    private var phase: TranscriptPhase {
        if let phaseOverride { return phaseOverride }
        if service.isQueuedOrRunning(video.id) { return .working }
        switch video.transcriptStatus {
        case .ready: return transcript == nil ? .notStarted : .ready
        case .inProgress: return .working
        case .notStarted: return .notStarted
        case .unavailable: return .unavailable(service.unavailableReason(for: video.id))
        }
    }

    var body: some View {
        content
            .onReceive(clock.$time) { time in
                let index = Self.index(at: time, in: transcript?.segments ?? [])
                if index != currentIndex { currentIndex = index }
            }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .ready:
            if let transcript { lines(transcript) }
        case .working:
            working
        case .notStarted:
            message(systemImage: "text.quote",
                    title: "No transcript yet",
                    text: "Snapreel can write down everything that's said, right here on this iPhone. Nothing is sent anywhere.",
                    actionTitle: "Make a transcript", action: { onRequest() })
        case .unavailable(let reason):
            unavailable(reason)
        }
    }

    // MARK: - Ready

    private func lines(_ transcript: Transcript) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(transcript.segments.enumerated()), id: \.element.id) { index, segment in
                TranscriptLineRow(segment: segment, isCurrent: index == currentIndex,
                                  onTap: { onSeek(segment.start) })
            }
            footer(transcript)
                .padding(.top, Space.s)
        }
    }

    private func footer(_ transcript: Transcript) -> some View {
        HStack(alignment: .center, spacing: Space.s) {
            Label {
                Text("Made on this iPhone · \(Self.languageName(transcript.localeIdentifier))")
            } icon: {
                Image(systemName: "lock.fill")
            }
            .font(.srCaption)
            .foregroundStyle(Color.srOnDarkTertiary)
            Spacer(minLength: Space.xs)
            Button {
                onCopy()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
                    .font(.srSubheadlineStrong)
                    .foregroundStyle(Color.srRedGlow)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy transcript")
        }
    }

    // MARK: - Working

    private var working: some View {
        VStack(spacing: Space.s) {
            ProgressView()
                .tint(Color.srOnDark)
                .scaleEffect(1.2)
                .frame(height: 44)
            Text("Transcribing on this iPhone")
                .font(.srTitle3)
                .foregroundStyle(Color.srOnDark)
            Text("Keep watching if you like. It takes a minute or two, and we'll let you know when it's ready.")
                .font(.srSubheadline)
                .foregroundStyle(Color.srOnDarkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if service.activeVideoID == video.id && service.progress > 0 {
                ProgressView(value: service.progress)
                    .tint(Color.srRed)
                    .frame(maxWidth: 200)
                    .padding(.top, Space.xxs)
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.xl)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Unavailable

    @ViewBuilder
    private func unavailable(_ reason: TranscriptUnavailableReason) -> some View {
        switch reason {
        case .noSpeech:
            message(systemImage: "speaker.slash",
                    title: "No speech found",
                    text: "Snapreel listened all the way through and didn't hear anyone talking.",
                    actionTitle: "Try again", action: { onRequest() })
        case .languageUnsupported:
            message(systemImage: "globe",
                    title: "This language can't be transcribed here",
                    text: "This iPhone can't recognise speech in your language without sending audio away, and Snapreel keeps everything on the device. Adding the language under Settings › General › Keyboard › Dictation may help.",
                    actionTitle: "Try again", action: { onRequest() })
        case .permissionDenied:
            message(systemImage: "mic.slash",
                    title: "Speech recognition is off",
                    text: "Allow speech recognition for Snapreel in Settings to make transcripts. It all happens on this iPhone.",
                    actionTitle: "Open Settings", action: { Permissions.openSettings() })
        case .failed:
            message(systemImage: "exclamationmark.triangle",
                    title: "The transcript didn't finish",
                    text: "Something interrupted it. Give it another go.",
                    actionTitle: "Try again", action: { onRequest() })
        }
    }

    private func message(systemImage: String, title: String, text: String,
                         actionTitle: String, action: @escaping @MainActor () -> Void) -> some View {
        EmptyStateView(systemImage: systemImage, title: title, message: text,
                       actionTitle: actionTitle, action: { action() }, onDark: true)
            .padding(.vertical, Space.l)
    }

    // MARK: - Helpers

    /// The line being spoken at `time`: the last line that starts at or before it.
    static func index(at time: Double, in segments: [TranscriptSegment]) -> Int? {
        guard let first = segments.first, time >= first.start - 0.05 else { return nil }
        var low = 0
        var high = segments.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if segments[mid].start <= time + 0.05 {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low
    }

    static func languageName(_ identifier: String) -> String {
        Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }
}

private struct TranscriptLineRow: View {
    let segment: TranscriptSegment
    let isCurrent: Bool
    let onTap: @MainActor () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            onTap()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text(Format.stamp(segment.start))
                    .font(.srTimerSmall)
                    .foregroundStyle(isCurrent ? Color.srRedGlow : Color.srOnDarkTertiary)
                    .frame(width: 44, alignment: .leading)
                Text(segment.text)
                    .font(.srBody)
                    .foregroundStyle(isCurrent ? Color.srOnDark : Color.srOnDarkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, Space.xs)
            .padding(.horizontal, Space.s)
            .background(
                RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
                    .fill(isCurrent ? Color.white.opacity(0.08) : Color.clear)
            )
            .overlay(alignment: .leading) {
                if isCurrent {
                    Capsule().fill(Color.srRed).frame(width: 3).padding(.vertical, 6)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Motion.quick, value: isCurrent)
        .accessibilityLabel("\(Format.stamp(segment.start)), \(segment.text)")
        .accessibilityHint("Plays from here")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}
