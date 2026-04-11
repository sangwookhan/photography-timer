import ActivityKit
import SwiftUI
import WidgetKit

struct LockScreenTimerTargetWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerTargetLiveActivityAttributes.self) { context in
            LockScreenTimerTargetView(
                timerName: context.state.timerName,
                endDate: context.state.endDate
            )
            .activityBackgroundTint(Color(.systemBackground))
            .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    LockScreenTimerTargetIslandView(
                        timerName: context.state.timerName,
                        endDate: context.state.endDate
                    )
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .font(.caption)
            } compactTrailing: {
                Text(context.state.endDate, style: .time)
                    .font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: "timer")
                    .font(.caption2)
            }
        }
    }
}

private struct LockScreenTimerTargetView: View {
    let timerName: String
    let endDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Expected completion")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(endDate, style: .time)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)

            Text(timerName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct LockScreenTimerTargetIslandView: View {
    let timerName: String
    let endDate: Date

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "timer")
                .font(.caption)
            VStack(alignment: .leading, spacing: 2) {
                Text(timerName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(endDate, style: .time)
                    .font(.headline.monospacedDigit())
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}
