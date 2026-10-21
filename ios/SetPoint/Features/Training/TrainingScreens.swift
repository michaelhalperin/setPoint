import SwiftUI

/// The Training tab without a subscription: what it does, and the way in.
struct TrainingLockedView: View {
    @State private var showingPaywall = false

    var body: some View {
        SettingsScreen(title: "Train", showsBack: false, glow: .haze, showsHeadline: false) {
            VStack(alignment: .leading, spacing: Space.md) {
                lockedRow("figure.strengthtraining.traditional", "Training days get more food", "Your target rises with the session, so the extra burn doesn’t widen the gap.")
                lockedRow("bolt.heart", "Refuel right after", "When Apple Health saves a workout, a refuel check-in follows within minutes.")
                lockedRow("fork.knife", "Eat before you train", "A nudge before a planned session if you haven’t eaten.")
            }
            .appearIn(2)
            ActionButton(title: "See Pro") { showingPaywall = true }
                .appearIn(3)
            Text("Meal check-ins, top-ups and the evening close stay free.")
                .font(Typography.data(13))
                .foregroundStyle(Palette.inkSoft)
                .appearIn(4)
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView().presentationDetents([.large])
        }
    }

    private func lockedRow(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: Space.sm) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Palette.hazeSoft)
                .frame(width: 38, height: 38)
                .background(Palette.haze.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Typography.data(15, weight: .medium))
                    .foregroundStyle(Palette.ink)
                Text(detail)
                    .font(Typography.data(14))
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct RefuelSheet: View {
    let checkIn: HomeResponse.ActiveCheckIn
    let dinnerMin: Int
    let remainingSeconds: Int
    let onHadThis: () -> Void
    let onCoveredByDinner: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(width: 40, height: 5)
                .padding(.top, 10)

            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Palette.haze.opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: 110))
                    .frame(width: 220, height: 220)
                OrbRing(progress: ringProgress, lineWidth: 5, tint: Palette.hazeSoft)
                    .frame(width: 168, height: 168)
                VStack(spacing: 2) {
                    Text(clock)
                        .font(Typography.data(36, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.ink)
                    Text("left to refuel")
                        .font(Typography.data(13, weight: .semibold))
                        .foregroundStyle(Palette.inkSoft)
                }
            }
            .frame(width: 200, height: 200)

            Headline("You trained.", tail: "Eat something now.", size: 30, alignment: .center)

            if let rx = checkIn.prescription {
                PrescriptionCard(prescription: rx)
            }

            ActionButton(title: "I had this", kind: .primary, action: onHadThis)
            ActionButton(title: L10n("Dinner at \(formatMinutes(dinnerMin)) covers it"), kind: .secondary, action: onCoveredByDinner)

            Button("Not now", action: onDismiss)
                .font(Typography.data(15, weight: .bold))
                .foregroundStyle(Palette.inkSoft)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.bottom, Space.lg)
        .frame(maxWidth: .infinity)
        .background(Palette.sheet.ignoresSafeArea())
    }

    private var ringProgress: CGFloat {
        CGFloat(min(1, max(0, Double(remainingSeconds) / (45 * 60))))
    }

    private var clock: String {
        let m = max(0, remainingSeconds) / 60
        let s = max(0, remainingSeconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}

#if DEBUG
extension TrainingWeekResponse {
    /// A week for previews: lifts and runs behind, a run today at 17:00, and
    /// weekly lifts planned ahead.
    static var sample: TrainingWeekResponse {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        func at(_ dayOffset: Int, _ minute: Int) -> Date {
            (calendar.date(byAdding: .day, value: dayOffset, to: today) ?? today).addingTimeInterval(Double(minute) * 60)
        }
        let iso = ISO8601DateFormatter()
        let past: [(Int, String, Int, Int, Int?)] = [(-6, "STRENGTH", 1050, 60, 340), (-4, "CARDIO", 1020, 50, 480), (-2, "STRENGTH", 1080, 55, 320)]
        var entries: [Entry] = past.enumerated().map { i, p in
            Entry(id: "hk\(i)", kind: p.1, source: "HEALTHKIT", start: iso.string(from: at(p.0, p.2)), durationMin: p.3, activeKcal: p.4)
        }
        entries.append(Entry(id: "today", kind: "CARDIO", source: "PLANNED", start: iso.string(from: at(0, 1020)), durationMin: 60))
        for week in 0..<6 {
            entries.append(Entry(id: "lift\(week)", seriesId: "lifts", kind: "STRENGTH", source: "PLANNED", start: iso.string(from: at(2 + week * 7, 1080)), durationMin: 60))
        }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let refuels: [Int: String] = [-6: "done", -4: "missed", -2: "done"]
        let refuelMeals: [Int: RefuelMeal] = [
            -6: RefuelMeal(at: iso.string(from: at(-6, 1135)), kcal: 410),
            -2: RefuelMeal(at: iso.string(from: at(-2, 1150)), kcal: 420),
        ]
        let days: [Day] = (-13...0).map { offset in
            Day(date: f.string(from: at(offset, 0)), bumpKcal: 0, rest: refuels[offset] == nil, workouts: [], refuel: refuels[offset], eatenKcal: 2900 + (offset % 3) * 120, refuelMeal: refuelMeals[offset])
        }
        return TrainingWeekResponse(
            addCalories: true,
            preWorkoutNudgeMin: 90,
            fueledWell: .init(good: 2, total: 3),
            days: days,
            sessions: entries,
            horizonDays: 56,
            weightKg: 75,
            today: .init(
                baseKcal: 3100,
                bumpKcal: 500,
                targetKcal: 3600,
                workouts: [],
                dinnerMin: 1170,
                timeline: [],
                steps: .init(before: false, workout: false, refuel: false, dinner: false),
                refuelWindowMin: 45
            )
        )
    }
}
#endif
