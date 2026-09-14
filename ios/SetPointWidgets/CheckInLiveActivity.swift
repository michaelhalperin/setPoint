import ActivityKit
import SwiftUI
import WidgetKit

// The widget extension can't see the app's Palette, so the few colours it needs
// are mirrored here.
private let terracotta = Color(red: 0.835, green: 0.38, blue: 0.227)
private let cream = Color(red: 0.984, green: 0.965, blue: 0.941)
private let ink = Color(red: 0.169, green: 0.149, blue: 0.133)

/// The check-in on the lock screen and in the Dynamic Island: a terracotta bell,
/// the manager's line, and the suggested meal.
struct CheckInLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CheckInActivityAttributes.self) { context in
            LockScreenView(state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Bell(size: 34)
                        .padding(.leading, 2)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.title)
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .lineLimit(2)
                        if !context.state.detail.isEmpty {
                            Text(context.state.detail)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Bell(size: 22)
            } compactTrailing: {
                Text("Eat")
                    .font(.system(.caption, design: .rounded).weight(.heavy))
                    .foregroundStyle(terracotta)
            } minimal: {
                Bell(size: 22)
            }
            .widgetURL(URL(string: context.state.deepLink))
            .keylineTint(terracotta)
        }
    }
}

private struct Bell: View {
    let size: CGFloat

    var body: some View {
        Image(systemName: "bell.fill")
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(terracotta, in: Circle())
    }
}

private struct LockScreenView: View {
    let state: CheckInActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Bell(size: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(state.title)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(cream)
                    .lineLimit(2)
                if !state.detail.isEmpty {
                    Text(state.detail)
                        .font(.system(.caption, design: .rounded).weight(.medium))
                        .foregroundStyle(cream.opacity(0.7))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(cream.opacity(0.5))
        }
        .padding(16)
        .activityBackgroundTint(ink.opacity(0.82))
        .activitySystemActionForegroundColor(cream)
    }
}
