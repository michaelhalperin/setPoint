import ActivityKit
import SwiftUI
import WidgetKit

// The widget extension can't see the app's Palette; it uses WidgetChrome.
private let ember = WidgetChrome.ember
private let bone = WidgetChrome.bone

/// The check-in on the lock screen and in the Dynamic Island: a lit ember ball,
/// the manager's line, and the suggested meal.
struct CheckInLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CheckInActivityAttributes.self) { context in
            LockScreenView(state: context.state).sharedLanguage()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Bell(size: 34)
                        .padding(.leading, 2)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.title)
                            .font(.system(.subheadline).weight(.medium))
                            .lineLimit(2)
                        if !context.state.detail.isEmpty {
                            Text(context.state.detail)
                                .font(.system(.caption))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .sharedLanguage()
                }
            } compactLeading: {
                Bell(size: 22)
            } compactTrailing: {
                Text("Eat")
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .foregroundStyle(WidgetChrome.amber)
                    .sharedLanguage()
            } minimal: {
                Bell(size: 22)
            }
            .widgetURL(URL(string: context.state.deepLink))
            .keylineTint(ember)
        }
    }
}

private struct Bell: View {
    let size: CGFloat

    var body: some View {
        Image(systemName: "fork.knife")
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(WidgetChrome.onEmber)
            .frame(width: size, height: size)
            .background(
                RadialGradient(colors: [Color(red: 1, green: 0.878, blue: 0.722), ember], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.6),
                in: Circle()
            )
            .shadow(color: ember.opacity(0.5), radius: size * 0.25)
    }
}

/// A breathing ember orb, the manager's line and the plate, with an "Eat" pill.
private struct LockScreenView: View {
    let state: CheckInActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(RadialGradient(colors: [Color(red: 1, green: 0.878, blue: 0.722), ember], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 26))
                .frame(width: 42, height: 42)
                .shadow(color: ember.opacity(0.6), radius: 10)
            VStack(alignment: .leading, spacing: 3) {
                Text(state.title)
                    .font(.system(.subheadline).weight(.medium))
                    .foregroundStyle(bone)
                    .lineLimit(2)
                if !state.detail.isEmpty {
                    Text(state.detail)
                        .font(.system(.caption))
                        .foregroundStyle(bone.opacity(0.7))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Text("Eat")
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .foregroundStyle(WidgetChrome.onEmber)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(WidgetChrome.amber, in: Capsule())
        }
        .padding(16)
        .activityBackgroundTint(WidgetChrome.ground.opacity(0.85))
        .activitySystemActionForegroundColor(bone)
    }
}
