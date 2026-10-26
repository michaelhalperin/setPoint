import ActivityKit
import SwiftUI
import WidgetKit

// The widget extension can't see the app's Palette; it uses WidgetChrome.
private let ember = WidgetChrome.ember
private let amber = WidgetChrome.amber
private let bone = WidgetChrome.bone
private let soft = WidgetChrome.soft
private let faint = Color(red: 0.545, green: 0.545, blue: 0.58)      // #8B8B94
private let haze = Color(red: 0.506, green: 0.549, blue: 0.973)      // #818CF8
private let hazeSoft = Color(red: 0.780, green: 0.824, blue: 0.996)  // #C7D2FE
private let onHaze = Color(red: 0.082, green: 0.082, blue: 0.165)    // #15152A

/// The check-in on the lock screen and in the Dynamic Island: a calm dark card
/// with a small mono label, the plate's kcal in light type, one action and a thin
/// line for how the day is going. A meal is ember and amber; a refuel after
/// training is haze, like the Train screen.
struct CheckInLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CheckInActivityAttributes.self) { context in
            LockScreenView(state: context.state).sharedLanguage()
        } dynamicIsland: { context in
            let state = context.state
            let tint = Tint(state)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { EmptyView() }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Dot(tint: tint, size: 10)
                            MonoLabel(text: state.label ?? "")
                        }
                        HStack(alignment: .lastTextBaseline) {
                            Amount(state: state, size: 44)
                            Spacer(minLength: 8)
                            ActionPill(state: state, tint: tint)
                        }
                        Line(state: state)
                    }
                    .padding(.horizontal, 6)
                    .sharedLanguage()
                }
            } compactLeading: {
                Dot(tint: tint, size: 15)
            } compactTrailing: {
                Text(state.kcal.map { "\($0)" } ?? "Eat")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(tint.pill)
                    .sharedLanguage()
            } minimal: {
                Dot(tint: tint, size: 15)
            }
            .widgetURL(URL(string: state.deepLink))
            .keylineTint(tint.dot)
        }
    }
}

/// Meal: ember orb and amber pill. Refuel: haze.
private struct Tint {
    let dot: Color
    let pill: Color
    let onPill: Color
    let isRefuel: Bool

    init(_ state: CheckInActivityAttributes.ContentState) {
        isRefuel = state.isRefuel ?? false
        dot = isRefuel ? haze : ember
        pill = isRefuel ? hazeSoft : amber
        onPill = isRefuel ? onHaze : WidgetChrome.onEmber
    }
}

private struct Dot: View {
    let tint: Tint
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(tint.isRefuel
                ? AnyShapeStyle(haze)
                : AnyShapeStyle(RadialGradient(colors: [Color(red: 1, green: 0.878, blue: 0.722), ember], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.7)))
            .frame(width: size, height: size)
    }
}

private struct MonoLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .tracking(0.9)
            .foregroundStyle(faint)
            .lineLimit(1)
    }
}

/// "700 kcal" in light type; without a plate, the manager's line instead.
private struct Amount: View {
    let state: CheckInActivityAttributes.ContentState
    let size: CGFloat

    var body: some View {
        if let kcal = state.kcal, kcal > 0 {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(kcal)")
                    .font(.system(size: size, weight: .light))
                    .tracking(-size * 0.04)
                    .monospacedDigit()
                    .foregroundStyle(bone)
                Text("kcal")
                    .font(.system(size: size * 0.3, weight: .regular))
                    .foregroundStyle(soft)
            }
        } else {
            Text(state.title)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(bone)
                .lineLimit(2)
        }
    }
}

/// The tap target: the whole card opens the check-in; the pill says what it's for.
private struct ActionPill: View {
    let state: CheckInActivityAttributes.ContentState
    let tint: Tint

    var body: some View {
        Link(destination: URL(string: state.deepLink) ?? URL(string: "setpoint://")!) {
            Text("Log it")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint.onPill)
                .padding(.horizontal, 18)
                .frame(height: 40)
                .background(tint.pill, in: Capsule())
        }
    }
}

/// What to eat, then how the day is going: a hairline track and "0 / 2,910".
private struct Line: View {
    let state: CheckInActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !state.detail.isEmpty {
                Text(state.detail)
                    .font(.system(size: 15))
                    .foregroundStyle(bone)
                    .lineLimit(1)
            } else if state.kcal != nil {
                Text(state.title)
                    .font(.system(size: 15))
                    .foregroundStyle(soft)
                    .lineLimit(1)
            }
            if let day = state.dayKcal, let target = state.dayTarget, target > 0 {
                HStack(spacing: 10) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.10))
                            Capsule().fill(bone).frame(width: geo.size.width * min(1, CGFloat(day) / CGFloat(target)))
                        }
                    }
                    .frame(height: 3)
                    Text("\(day.formatted()) / \(target.formatted())")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(faint)
                        .fixedSize()
                }
            }
        }
    }
}

private struct LockScreenView: View {
    let state: CheckInActivityAttributes.ContentState

    var body: some View {
        let tint = Tint(state)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Dot(tint: tint, size: 10)
                MonoLabel(text: state.label ?? "")
            }
            HStack(alignment: .lastTextBaseline) {
                Amount(state: state, size: 56)
                Spacer(minLength: 8)
                ActionPill(state: state, tint: tint)
            }
            Line(state: state)
        }
        .padding(16)
        .activityBackgroundTint(Color(red: 0.078, green: 0.078, blue: 0.09).opacity(0.92))
        .activitySystemActionForegroundColor(bone)
        .widgetURL(URL(string: state.deepLink))
    }
}
