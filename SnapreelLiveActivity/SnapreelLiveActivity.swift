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
            RecordingActivityLockScreenView(kind: context.attributes.kind, status: context.state)
                .activityBackgroundTint(RecordingActivityStyle.ink)
                .activitySystemActionForegroundColor(.white)
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
}
