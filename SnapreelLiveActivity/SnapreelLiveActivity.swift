import ActivityKit
import SwiftUI
import WidgetKit

/// Snapreel's widget extension. It only draws the recording Live Activity: "Recording 1:23" on
/// the Lock Screen (iOS 16.1 and later) and in the Dynamic Island (iPhone 14 Pro and later).
/// Tapping it opens Snapreel on the recording, where Stop is. The app starts, updates and ends
/// it (`RecordingLiveActivity`); the views are shared with the app (`RecordingActivity/`).
@main
struct SnapreelLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        RecordingLiveActivityWidget()
    }
}

struct RecordingLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            RecordingActivityLockScreen(kind: context.attributes.kind, status: context.state,
                                        isStale: Self.isStale(context))
                .widgetURL(RecordingActivityStyle.url)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    RecordingActivityMark(phase: context.state.phase, size: 44)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RecordingActivityExpandedClock(status: context.state)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    RecordingActivityExpandedText(kind: context.attributes.kind, status: context.state)
                        .padding(.horizontal, 4)
                }
            } compactLeading: {
                RecordingActivityCompactLeading(phase: context.state.phase)
            } compactTrailing: {
                RecordingActivityCompactTrailing(status: context.state)
            } minimal: {
                RecordingActivityCompactLeading(phase: context.state.phase)
            }
            .widgetURL(RecordingActivityStyle.url)
            .keylineTint(RecordingActivityStyle.red)
        }
    }

    /// The content's `staleDate` passed (iOS 16.2 and later): Snapreel set it while a screen
    /// recording ran and couldn't renew it, so the recording may have ended.
    private static func isStale(_ context: ActivityViewContext<RecordingActivityAttributes>) -> Bool {
        if #available(iOS 16.2, *) { return context.isStale }
        return false
    }
}

/// The Lock Screen card with a background that matches the appearance (the Lock Screen and its
/// notifications are light in Light mode and dark in Dark mode).
private struct RecordingActivityLockScreen: View {
    let kind: RecordingActivityKind
    let status: RecordingActivityStatus
    let isStale: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RecordingActivityLockScreenView(kind: kind, status: status, isStale: isStale)
            .activityBackgroundTint(RecordingActivityStyle.background(colorScheme))
            .activitySystemActionForegroundColor(RecordingActivityStyle.primaryText(colorScheme))
    }
}
