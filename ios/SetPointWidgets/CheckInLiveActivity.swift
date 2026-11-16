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

/// The check-in on the lock screen and in the Dynamic Island. What to eat leads (large),
/// the plate's kcal sits beside the meal's name, and the bottom row is the day so far with
/// the one action. A meal is ember and amber; a refuel after training is haze, like Train.
/// All copy is looked up in the app's language through `SharedLanguage.tr`, because a Live
/// Activity doesn't reliably follow the SwiftUI locale environment.
struct CheckInLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CheckInActivityAttributes.self) { context in
            LockScreenView(state: context.state).sharedLanguage()
        } dynamicIsland: { context in
            let state = context.state
            let tint = Tint(state)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 7) {
                        Dot(tint: tint, size: 12)
                        MonoLabel(text: state.label ?? "")
                    }
                    .sharedLanguage()
                }
                DynamicIslandExpandedRegion(.trailing) {
                    KcalTag(state: state, tint: tint).sharedLanguage()
                }
                DynamicIslandExpandedRegion(.center) {
                    Headline(state: state, size: 19).sharedLanguage()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    BottomRow(state: state, tint: tint).sharedLanguage()
                }
            } compactLeading: {
                Dot(tint: tint, size: 15)
            } compactTrailing: {
                Text(state.kcal.map { "\($0)" } ?? SharedLanguage.tr("Eat"))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(tint.pill)
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

/// The plate's size, "700 kcal", as a quiet tag. Nothing when there's no plate.
private struct KcalTag: View {
    let state: CheckInActivityAttributes.ContentState
    let tint: Tint

    var body: some View {
        if let kcal = state.kcal, kcal > 0 {
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text("\(kcal)")
                    .font(.system(size: 20, weight: .light))
                    .monospacedDigit()
                    .foregroundStyle(tint.pill)
                Text(SharedLanguage.tr("kcal"))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(faint)
            }
        }
    }
}

/// What to eat, large: the prescription when there is one, otherwise the manager's line.
/// With a prescription the manager's line sits under it, smaller.
private struct Headline: View {
    let state: CheckInActivityAttributes.ContentState
    let size: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(state.detail.isEmpty ? state.title : state.detail)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(bone)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if !state.detail.isEmpty {
                Text(state.title)
                    .font(.system(size: 13))
                    .foregroundStyle(soft)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The day so far on the left, the one action on the right.
private struct BottomRow: View {
    let state: CheckInActivityAttributes.ContentState
    let tint: Tint

    var body: some View {
        HStack(spacing: 14) {
            if let day = state.dayKcal, let target = state.dayTarget, target > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.10))
                            Capsule().fill(tint.pill).frame(width: max(4, geo.size.width * min(1, CGFloat(day) / CGFloat(target))))
                        }
                    }
                    .frame(height: 4)
                    Text("\(day.formatted()) / \(target.formatted())")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(faint)
                }
            } else {
                Spacer(minLength: 0)
            }
            Link(destination: URL(string: state.deepLink) ?? URL(string: "setpoint://")!) {
                HStack(spacing: 6) {
                    Text(SharedLanguage.tr("Log it"))
                        .font(.system(size: 15, weight: .semibold))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(tint.onPill)
                .padding(.horizontal, 16)
                .frame(height: 38)
                .background(tint.pill, in: Capsule())
            }
        }
    }
}

private struct LockScreenView: View {
    let state: CheckInActivityAttributes.ContentState

    var body: some View {
        let tint = Tint(state)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Dot(tint: tint, size: 11)
                MonoLabel(text: state.label ?? "")
                Spacer(minLength: 8)
                KcalTag(state: state, tint: tint)
            }
            Headline(state: state, size: 24)
            BottomRow(state: state, tint: tint)
        }
        .padding(18)
        .background(alignment: .topLeading) {
            // An ember (or haze) glow from the corner the orb sits in.
            RadialGradient(colors: [tint.dot.opacity(0.28), .clear], center: .topLeading, startRadius: 0, endRadius: 220)
        }
        .activityBackgroundTint(Color(red: 0.07, green: 0.07, blue: 0.08).opacity(0.94))
        .activitySystemActionForegroundColor(bone)
        .widgetURL(URL(string: state.deepLink))
    }
}
