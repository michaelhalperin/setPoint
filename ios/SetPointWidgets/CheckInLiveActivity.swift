import ActivityKit
import SwiftUI
import WidgetKit

private let terracotta = Color(red: 0.835, green: 0.38, blue: 0.227)
private let warmGround = Color(red: 0.984, green: 0.965, blue: 0.941)

struct CheckInLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CheckInActivityAttributes.self) { context in
            LockScreenView(state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "fork.knife")
                        .foregroundStyle(terracotta)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.title)
                            .font(.footnote.weight(.semibold))
                            .lineLimit(2)
                        if !context.state.detail.isEmpty {
                            Text(context.state.detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "fork.knife").foregroundStyle(terracotta)
            } compactTrailing: {
                Text("eat").font(.caption2.weight(.semibold)).foregroundStyle(terracotta)
            } minimal: {
                Image(systemName: "fork.knife").foregroundStyle(terracotta)
            }
            .widgetURL(URL(string: context.state.deepLink))
        }
    }
}

private struct LockScreenView: View {
    let state: CheckInActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "fork.knife")
                .font(.title3)
                .foregroundStyle(terracotta)
            VStack(alignment: .leading, spacing: 3) {
                Text(state.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                if !state.detail.isEmpty {
                    Text(state.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(16)
        .activityBackgroundTint(warmGround)
        .activitySystemActionForegroundColor(.primary)
    }
}
