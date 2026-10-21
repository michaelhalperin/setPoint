import Foundation

/// One training session as the Train screen holds it on the phone: planned by
/// the person or recorded by Apple Health.
struct TrainSession: Identifiable, Equatable {
    /// The server's id, or the phone's own until the server has it. Either works for edits.
    var id: String
    var clientId: String?
    /// Shared by the sessions of one weekly repeat.
    var seriesId: String?
    var kind: String
    var source: String
    var start: Date
    var durationMin: Int
    var activeKcal: Int?

    var end: Date { start.addingTimeInterval(Double(durationMin) * 60) }
    var isPlanned: Bool { source == "PLANNED" }
    var repeats: Bool { seriesId != nil }

    /// Only sessions the person added, and only before they start.
    func canEdit(now: Date) -> Bool { isPlanned && start > now }
}

/// What the plan sheet produces.
struct SessionDraft: Equatable {
    var kind = "STRENGTH"
    var start: Date
    var durationMin = 60
    /// Weekdays to repeat on every week (Calendar weekday, 1 = Sunday); empty = just once.
    var repeatDays: Set<Int> = []
}

/// Which sessions an edit or delete covers.
enum SessionScope: String {
    case one, following
}

/// The training rules, the same as the server's (engine/training.ts and
/// training/status.ts), so the screen can answer instantly from what's on the phone.
enum TrainMath {
    static let refuelWindowMin = 45
    static let refuelMinKcal = 250
    static let snackMinKcal = 150
    static let preWorkoutLookbackMin = 180
    static let dinnerLookbackMin = 90
    static let plannedMatchMin = 90
    static let bumpCap = 800
    static let bumpRound = 50
    static let minDailyKcal = 1200

    struct Meal: Equatable {
        let at: Date
        let kcal: Int
    }

    struct Steps: Equatable {
        var before = false
        var workout = false
        var refuel = false
        var dinner = false
    }

    /// After a session: done · missed · due (window open now) · planned (hasn't happened).
    enum Refuel: String {
        case done, missed, due, planned
    }

    // MARK: Days

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// The first day of the week holding `date`, as the phone's region starts weeks.
    static func weekStart(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// `date`'s day at hour:minute.
    static func at(_ hour: Int, _ minute: Int, on date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
    }

    /// Minutes after midnight.
    static func minute(_ date: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    // MARK: Sessions

    /// Drops a planned session Apple Health also recorded, so one workout counts once.
    static func effective(_ sessions: [TrainSession]) -> [TrainSession] {
        let recorded = sessions.filter { !$0.isPlanned }
        guard !recorded.isEmpty else { return sessions }
        let slack = Double(plannedMatchMin) * 60
        return sessions.filter { s in
            guard s.isPlanned else { return true }
            return !recorded.contains { r in
                r.start.timeIntervalSince1970 < s.end.timeIntervalSince1970 + slack
                    && s.start.timeIntervalSince1970 < r.end.timeIntervalSince1970 + slack
            }
        }
    }

    /// Each day's sessions, counted once and in time order, keyed by local day.
    static func byDay(_ sessions: [TrainSession], calendar: Calendar = .current) -> [String: [TrainSession]] {
        let grouped = Dictionary(grouping: sessions) { dayKey($0.start, calendar: calendar) }
        return grouped.mapValues { effective($0).sorted { $0.start < $1.start } }
    }

    /// Net training kcal for one session. Apple Health's active energy wins when present.
    static func sessionKcal(_ s: TrainSession, weightKg: Double) -> Double {
        if let active = s.activeKcal, active > 0 { return Double(active) }
        let met: Double = s.kind == "CARDIO" ? 8 : s.kind == "MIXED" ? 7 : 6
        return max(0, (met - 1) * weightKg * Double(max(0, s.durationMin)) / 60)
    }

    /// What a day's training adds to the target, rounded to 50 and capped at 800.
    static func bump(_ sessions: [TrainSession], weightKg: Double) -> Int {
        let raw = effective(sessions).reduce(0) { $0 + sessionKcal($1, weightKg: weightKg) }
        let rounded = Int((raw / Double(bumpRound)).rounded()) * bumpRound
        return min(bumpCap, max(0, rounded))
    }

    static func target(base: Int, bump: Int, addCalories: Bool) -> Int {
        guard addCalories, bump > 0 else { return base }
        return max(minDailyKcal, base + bump)
    }

    // MARK: Eating around it

    private static func refuelled(_ s: TrainSession, _ meals: [Meal]) -> Bool {
        let until = s.end.addingTimeInterval(Double(refuelWindowMin) * 60)
        return meals.contains { $0.kcal >= refuelMinKcal && $0.at >= s.end && $0.at <= until }
    }

    /// The day's status from its sessions in time order; nil on a rest day.
    static func refuel(_ day: [TrainSession], meals: [Meal], now: Date) -> Refuel? {
        guard !day.isEmpty else { return nil }
        let finished = day.filter { $0.end <= now }
        guard let last = finished.last else { return .planned }
        if finished.contains(where: { refuelled($0, meals) }) { return .done }
        return last.end.addingTimeInterval(Double(refuelWindowMin) * 60) > now ? .due : .missed
    }

    /// Which of the day's steps are done: a snack before, the session, the refuel, dinner.
    static func steps(first: TrainSession?, dinnerAt: Date, meals: [Meal], now: Date) -> Steps {
        func ate(from: Date, to: Date, atLeast kcal: Int) -> Bool {
            meals.contains { $0.kcal >= kcal && $0.at >= from && $0.at < to }
        }
        let dinnerFrom = dinnerAt.addingTimeInterval(-Double(dinnerLookbackMin) * 60)
        guard let s = first else {
            return Steps(dinner: ate(from: dinnerFrom, to: .distantFuture, atLeast: refuelMinKcal))
        }
        let refuelBy = s.end.addingTimeInterval(Double(refuelWindowMin) * 60)
        return Steps(
            before: ate(from: s.start.addingTimeInterval(-Double(preWorkoutLookbackMin) * 60), to: s.start, atLeast: snackMinKcal),
            workout: s.end <= now,
            refuel: refuelled(s, meals),
            dinner: ate(from: max(refuelBy, dinnerFrom), to: .distantFuture, atLeast: refuelMinKcal)
        )
    }

    // MARK: Planning ahead

    /// A weekly repeat: `start`, then the same weekday and clock time each week up to `until`.
    static func weeklyStarts(from start: Date, until: Date, calendar: Calendar = .current) -> [Date] {
        var out: [Date] = []
        var week = 0
        while let next = calendar.date(byAdding: .weekOfYear, value: week, to: start), next < until, out.count < 10 {
            out.append(next)
            week += 1
        }
        return out
    }

    /// Every session a plan makes: once at `start`, or on each repeat weekday from
    /// `start`'s day on, at the same clock time, up to `until`.
    static func plannedStarts(from start: Date, weekdays: Set<Int>, until: Date, calendar: Calendar = .current) -> [Date] {
        guard !weekdays.isEmpty else { return [start] }
        let day = calendar.startOfDay(for: start)
        let c = calendar.dateComponents([.hour, .minute], from: start)
        var out: [Date] = []
        for offset in 0..<7 {
            guard let first = calendar.date(byAdding: .day, value: offset, to: day),
                  weekdays.contains(calendar.component(.weekday, from: first)) else { continue }
            let firstStart = at(c.hour ?? 0, c.minute ?? 0, on: first, calendar: calendar)
            out += weeklyStarts(from: firstStart, until: until, calendar: calendar)
        }
        return out.sorted()
    }

    /// Logged snacks first, then a usual plate, then a light staple. Saved meals
    /// are only one signal — what they actually ate wins. A name from the server
    /// is ignored so a deployed API cannot hide a better logged snack.
    static func snackBefore(
        server: TrainingWeekResponse.SnackBefore?,
        saved: [SavedMeal],
        meals: [MealSummary],
        disliked: [String] = [],
        pantry: [String] = []
    ) -> TrainingWeekResponse.SnackBefore {
        let blocked = disliked.map { $0.lowercased() }.filter { $0.count >= 2 }
        let pantryHits = pantry.map { $0.lowercased().replacingOccurrences(of: "_", with: " ") }.filter { $0.count >= 2 }

        var scored: [(snack: TrainingWeekResponse.SnackBefore, score: Double)] = []
        var repeats: [String: Int] = [:]
        for meal in meals {
            let name = snackName(items: meal.items?.map { ($0.name, $0.quantity, $0.kcal, $0.proteinG) }, fallback: meal.title)
            repeats[name.lowercased(), default: 0] += 1
        }

        for meal in meals {
            guard (snackMinKcal...400).contains(meal.kcal) else { continue }
            let items = (meal.items ?? []).map {
                TrainingWeekResponse.SnackBefore.Item(name: $0.name, quantity: $0.quantity, kcal: $0.kcal, proteinG: $0.proteinG)
            }
            let name = snackName(items: items.map { ($0.name, $0.quantity, $0.kcal, $0.proteinG) }, fallback: meal.title)
            guard allowed(name, blocked: blocked), name != L10n("Logged meal") else { continue }
            let hour = MealFormat.parse(meal.loggedAt).map { Calendar.current.component(.hour, from: $0) } ?? 12
            var score = 10.0 + min(8, Double(repeats[name.lowercased(), default: 1]) * 4)
            if !items.isEmpty { score += 8 }
            if (meal.proteinG) >= 12 { score += 6 }
            if (14...18).contains(hour) { score += 14 }
            if pantryHits.contains(where: { name.lowercased().contains($0) }) { score += 5 }
            scored.append((.init(name: name, kcal: meal.kcal, source: "history", proteinG: meal.proteinG, items: items.isEmpty ? nil : items), score))
        }

        for meal in saved {
            guard (snackMinKcal...400).contains(meal.kcal), allowed(meal.name, blocked: blocked) else { continue }
            let items = meal.items.map {
                TrainingWeekResponse.SnackBefore.Item(name: $0.name, quantity: $0.quantity, kcal: $0.kcal, proteinG: $0.proteinG)
            }
            var score = 6.0 + min(6, Double(meal.useCount))
            if meal.useInCheckIns { score += 3 }
            if pantryHits.contains(where: { meal.name.lowercased().contains($0) }) { score += 5 }
            scored.append((.init(name: meal.name, kcal: meal.kcal, source: "usual", proteinG: meal.proteinG, items: items.isEmpty ? nil : items), score))
        }

        scored.sort { $0.score > $1.score || ($0.score == $1.score && $0.snack.name < $1.snack.name) }
        if let best = scored.first?.snack { return best }
        if let server, let items = server.items, !items.isEmpty { return server }
        return .init(
            name: "Greek yogurt",
            kcal: 220,
            source: "suggested",
            proteinG: 20,
            items: [.init(name: "Greek yogurt", quantity: "1 cup", kcal: 220, proteinG: 20)]
        )
    }

    /// Today's log includes this plate — so Train still shows it logged after a relaunch.
    static func ateToday(
        _ snack: TrainingWeekResponse.SnackBefore,
        meals: [MealSummary],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        meals.contains { meal in
            guard let at = MealFormat.parse(meal.loggedAt), calendar.isDate(at, inSameDayAs: now) else { return false }
            guard abs(meal.kcal - snack.kcal) <= 40 else { return false }
            let want = snack.name.lowercased()
            if meal.title.lowercased() == want { return true }
            let fromItems = snackName(
                items: meal.items?.map { ($0.name, $0.quantity, $0.kcal, $0.proteinG) },
                fallback: meal.title
            )
            return fromItems.lowercased() == want
        }
    }

    private static func allowed(_ name: String, blocked: [String]) -> Bool {
        let n = name.lowercased()
        return !blocked.contains { n.contains($0) }
    }

    private static func snackName(items: [(String, String?, Int, Double?)]?, fallback: String) -> String {
        guard let items, !items.isEmpty else { return fallback }
        if items.count == 1 { return items[0].0 }
        return items.prefix(2).map(\.0).joined(separator: " + ")
    }

    /// "This and all after": the edited session moved from `old` to `new`; another
    /// one moves by the same number of days and takes the new clock time.
    static func moved(_ other: Date, from old: Date, to new: Date, calendar: Calendar = .current) -> Date {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: old), to: calendar.startOfDay(for: new)).day ?? 0
        let day = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: other)) ?? other
        let c = calendar.dateComponents([.hour, .minute], from: new)
        return at(c.hour ?? 0, c.minute ?? 0, on: day, calendar: calendar)
    }
}
