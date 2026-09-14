import AppIntents
import SwiftUI

/// Colours the widget extension can use without the app's Palette.
enum WidgetChrome {
    static let terracotta = Color(red: 0.835, green: 0.38, blue: 0.227)
    static let cream = Color(red: 0.984, green: 0.965, blue: 0.941)
    static let ink = Color(red: 0.169, green: 0.149, blue: 0.133)
    static let inkSoft = Color(red: 0.169, green: 0.149, blue: 0.133).opacity(0.62)
    static let paper = Color(red: 0.984, green: 0.965, blue: 0.941)
    static let ringTrack = Color(red: 0.169, green: 0.149, blue: 0.133).opacity(0.12)
}

struct TodayWidgetSmallView: View {
    let snapshot: TodaySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetRing(progress: snapshot.progress, size: 44)
            Spacer(minLength: 0)
            Text("\(max(0, snapshot.remainingKcal))")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(WidgetChrome.ink)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text("kcal left")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(WidgetChrome.inkSoft)
            if let line = snapshot.nextLine {
                Text(line)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(WidgetChrome.terracotta)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(14)
        .background(WidgetChrome.paper)
    }
}

struct TodayWidgetMediumView: View {
    let snapshot: TodaySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                WidgetRing(progress: snapshot.progress, size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(max(0, snapshot.remainingKcal)) kcal left")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(WidgetChrome.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if let line = snapshot.nextLine {
                        Text(line)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(WidgetChrome.terracotta)
                            .lineLimit(1)
                    } else {
                        Text("Nothing due")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(WidgetChrome.inkSoft)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                ForEach(snapshot.savedMeals.prefix(2)) { meal in
                    Button(intent: LogSavedMealIntent(mealId: meal.id, mealName: meal.name, kcal: meal.kcal)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(meal.name)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .lineLimit(1)
                            Text("\(meal.kcal)")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .opacity(0.7)
                        }
                        .foregroundStyle(WidgetChrome.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(WidgetChrome.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                Link(destination: URL(string: "setpoint://log/photo")!) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(WidgetChrome.cream)
                        .frame(width: 40, height: 40)
                        .background(WidgetChrome.terracotta, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(14)
        .background(WidgetChrome.paper)
    }
}

struct TodayLockCircularView: View {
    let snapshot: TodaySnapshot

    var body: some View {
        ZStack {
            WidgetRing(progress: snapshot.progress, size: 54, line: 5)
            VStack(spacing: 0) {
                Text("\(max(0, snapshot.remainingKcal))")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("left")
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .opacity(0.7)
            }
            .foregroundStyle(WidgetChrome.cream)
        }
    }
}

struct TodayLockRectangularView: View {
    let snapshot: TodaySnapshot

    var body: some View {
        HStack(spacing: 10) {
            WidgetRing(progress: snapshot.progress, size: 34, line: 4)
            VStack(alignment: .leading, spacing: 2) {
                if let slot = snapshot.nextSlotTitle, let time = snapshot.nextCheckIn {
                    Text("\(slot) check-in \(time)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    Text("only if nothing's logged")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .opacity(0.72)
                        .lineLimit(1)
                } else {
                    Text("\(max(0, snapshot.remainingKcal)) kcal left")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    Text("Nothing due")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .opacity(0.72)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(WidgetChrome.cream)
    }
}

struct WidgetRing: View {
    var progress: Double
    var size: CGFloat
    var line: CGFloat = 5

    var body: some View {
        ZStack {
            Circle().stroke(WidgetChrome.ringTrack, lineWidth: line)
            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(WidgetChrome.terracotta, style: StrokeStyle(lineWidth: line, lineCap: .round))
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
        return nextSlot.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var nextLine: String? {
        guard let nextSlotTitle else { return nil }
        if let nextCheckIn {
            return "\(nextSlotTitle) · \(nextCheckIn)"
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
