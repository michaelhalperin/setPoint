import AppIntents
import SwiftUI
import WidgetKit

/// Design v2 colours the widget extension can use without the app's Palette.
enum WidgetChrome {
    static let ground = Color(red: 0.035, green: 0.035, blue: 0.043)       // #09090B
    static let bone = Color(red: 0.961, green: 0.961, blue: 0.957)         // #F5F5F4
    static let soft = Color(red: 0.631, green: 0.631, blue: 0.667)         // #A1A1AA
    static let ember = Color(red: 1.0, green: 0.478, blue: 0.239)          // #FF7A3D
    static let amber = Color(red: 1.0, green: 0.722, blue: 0.420)          // #FFB86B
    static let onEmber = Color(red: 0.102, green: 0.039, blue: 0.016)      // #1A0A04
    static let glass = Color.white.opacity(0.06)
    static let hairline = Color.white.opacity(0.09)
    static let ringTrack = Color.white.opacity(0.10)

    /// The widget background: the dark ground with an ember glow in one corner.
    static var background: some View {
        ZStack {
            ground
            RadialGradient(colors: [ember.opacity(0.35), .clear], center: UnitPoint(x: 0.15, y: 0.1), startRadius: 0, endRadius: 140)
        }
    }

    static func orbGradient(_ size: CGFloat) -> RadialGradient {
        RadialGradient(
        stops: [
            .init(color: Color(red: 1.0, green: 0.914, blue: 0.8), location: 0),
            .init(color: amber, location: 0.18),
            .init(color: Color(red: 0.941, green: 0.416, blue: 0.180), location: 0.46),
            .init(color: Color(red: 0.431, green: 0.133, blue: 0.055), location: 0.76),
            .init(color: Color(red: 0.118, green: 0.039, blue: 0.020), location: 1),
        ],
        center: UnitPoint(x: 0.34, y: 0.28),
        startRadius: 0,
        endRadius: size * 0.78
        )
    }
}

/// The fuel orb in a ring, sized for a widget.
struct WidgetOrb: View {
    var progress: Double
    var size: CGFloat

    var body: some View {
        ZStack {
            WidgetRing(progress: progress, size: size, line: max(3, size * 0.06))
            Circle()
                .fill(WidgetChrome.orbGradient(size * 0.72))
                .frame(width: size * 0.72, height: size * 0.72)
                .shadow(color: WidgetChrome.ember.opacity(0.45), radius: size * 0.15)
        }
        .frame(width: size, height: size)
    }
}

struct TodayWidgetSmallView: View {
    let snapshot: TodaySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetOrb(progress: snapshot.progress, size: 50)
            Spacer(minLength: 0)
            Text(snapshot.consumedKcal.formatted())
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(WidgetChrome.bone)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text("of \(snapshot.targetKcal.formatted()) kcal")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(WidgetChrome.soft)
                .lineLimit(1)
            if let line = snapshot.nextLine {
                Text(LocalizedStringKey(line))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WidgetChrome.amber)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct TodayWidgetMediumView: View {
    let snapshot: TodaySnapshot

    var body: some View {
        HStack(spacing: 14) {
            WidgetOrb(progress: snapshot.progress, size: 92)
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(max(0, snapshot.remainingKcal).formatted()) kcal left")
                        .font(.system(size: 19, weight: .light))
                        .foregroundStyle(WidgetChrome.bone)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(snapshot.nextLine.map { SharedLanguage.tr("Next · \($0)") } ?? SharedLanguage.tr("Nothing due"))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(snapshot.nextLine == nil ? WidgetChrome.soft : WidgetChrome.amber)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    ForEach(snapshot.savedMeals.prefix(2)) { meal in
                        Button(intent: LogSavedMealIntent(mealId: meal.id, mealName: meal.name, kcal: meal.kcal)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(meal.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(WidgetChrome.bone)
                                    .lineLimit(1)
                                Text("+\(meal.kcal)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(WidgetChrome.amber)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 7)
                            .background(WidgetChrome.glass, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(WidgetChrome.hairline))
                        }
                        .buttonStyle(.plain)
                    }
                    Link(destination: URL(string: "setpoint://log/photo")!) {
                        Image(systemName: "camera")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(WidgetChrome.onEmber)
                            .frame(width: 36, height: 36)
                            .background(
                                RadialGradient(colors: [Color(red: 1, green: 0.878, blue: 0.722), WidgetChrome.ember], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 22),
                                in: Circle()
                            )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct TodayLockCircularView: View {
    let snapshot: TodaySnapshot

    var body: some View {
        ZStack {
            WidgetRing(progress: snapshot.progress, size: 56, line: 5)
            VStack(spacing: 0) {
                Text(max(0, snapshot.remainingKcal).formatted())
                    .font(.system(size: 13, weight: .medium))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("LEFT")
                    .font(.system(size: 8, weight: .regular, design: .monospaced))
                    .opacity(0.7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(max(0, snapshot.remainingKcal)) calories left today")
    }
}

/// The next meal and, when you've tagged one, your usual for it; a thin bar of the day.
struct TodayLockRectangularView: View {
    let snapshot: TodaySnapshot

    private var usual: TodaySnapshot.Saved? {
        guard let slot = snapshot.nextSlot?.lowercased() else { return nil }
        return snapshot.savedMeals.first { $0.suggestSlot?.lowercased() == slot }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let slot = snapshot.nextSlotTitle, let time = snapshot.nextCheckIn {
                Text("\(slot) · check-in \(time)")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(usual.map { "\($0.name) · ~\($0.kcal)" } ?? SharedLanguage.tr("Only if nothing’s logged"))
                    .font(.system(size: 11, weight: .regular))
                    .opacity(0.75)
                    .lineLimit(1)
            } else {
                Text("\(max(0, snapshot.remainingKcal).formatted()) kcal left")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text("Nothing due")
                    .font(.system(size: 11, weight: .regular))
                    .opacity(0.75)
            }
            GeometryReader { geo in
                Capsule().fill(Color.primary.opacity(0.25))
                    .overlay(alignment: .leading) {
                        Capsule().fill(Color.primary)
                            .frame(width: max(4, geo.size.width * snapshot.progress))
                    }
            }
            .frame(height: 4)
            .padding(.top, 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// One line above the clock: "◔ 1,240 left · lunch 13:45".
struct TodayLockInlineView: View {
    let snapshot: TodaySnapshot

    var body: some View {
        let next = snapshot.nextSlotTitle.flatMap { slot in snapshot.nextCheckIn.map { " · \(slot.lowercased()) \($0)" } } ?? ""
        Label("\(max(0, snapshot.remainingKcal).formatted()) left\(next)", systemImage: "circle.lefthalf.filled")
    }
}

struct WidgetRing: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    var progress: Double
    var size: CGFloat
    var line: CGFloat = 5

    var body: some View {
        let tinted = renderingMode != .fullColor
        ZStack {
            Circle().stroke(tinted ? Color.primary.opacity(0.25) : WidgetChrome.ringTrack, lineWidth: line)
            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(tinted ? Color.primary : WidgetChrome.amber, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}

extension TodaySnapshot {
    var progress: Double {
        guard targetKcal > 0 else { return 0 }
        return min(1, Double(consumedKcal) / Double(targetKcal))
    }

    var nextSlotTitle: String? {
        guard let nextSlot, !nextSlot.isEmpty else { return nil }
        switch nextSlot.lowercased() {
        case "breakfast": return SharedLanguage.tr("Breakfast")
        case "lunch": return SharedLanguage.tr("Lunch")
        case "dinner": return SharedLanguage.tr("Dinner")
        case let slot where slot.hasPrefix("snack"): return SharedLanguage.tr("Snack")
        default: return nextSlot.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var nextLine: String? {
        guard let nextSlotTitle else { return nil }
        if let nextCheckIn {
            return SharedLanguage.tr("\(nextSlotTitle) · \(nextCheckIn)")
        }
        return nextSlotTitle
    }

    static let preview = TodaySnapshot(
        remainingKcal: 1240,
        targetKcal: 3120,
        consumedKcal: 1880,
        nextCheckIn: "13:45",
        nextSlot: "lunch",
        savedMeals: [
            Saved(id: "sm_lunch", name: "Usual lunch", kcal: 660),
            Saved(id: "sm_shake", name: "Shake", kcal: 380),
        ],
        day: dayKey(for: .now)
    )
}
