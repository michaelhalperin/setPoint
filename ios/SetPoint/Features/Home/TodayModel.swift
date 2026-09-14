import Foundation

// The logic behind Today, kept out of the views so it can be tested. The
// backend decides the day's shape (`day` on /api/home — slots, states, pace);
// this only interprets it for display.

enum MealSlot: String, CaseIterable, Identifiable {
    case breakfast, lunch, dinner

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakfast: return "Breakfast"
        case .lunch: return "Lunch"
        case .dinner: return "Dinner"
        }
    }

    var symbol: String {
        switch self {
        case .breakfast: return "sun.horizon.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "sunset.fill"
        }
    }
}

enum SlotState: String {
    case logged, now, missed, upcoming
}

extension HomeResponse.Day.Slot {
    var meal: MealSlot { MealSlot(rawValue: slot) ?? .lunch }
    var slotState: SlotState { SlotState(rawValue: state) ?? .upcoming }
}

/// The meal being logged from the dock, shown in the log before Home reloads.
enum TodayPending: Equatable {
    case parsing(title: String, slot: MealSlot)
    case logged(title: String, kcal: Int, slot: MealSlot)

    var slot: MealSlot {
        switch self {
        case let .parsing(_, slot), let .logged(_, _, slot): return slot
        }
    }
}

/// What Today is about right now — decides the hero (the dial, or the
/// terracotta check-in takeover) and its words.
enum TodayMoment: Equatable {
    /// A tier 1–2 check-in waiting for an answer — the manager is talking.
    case checkIn(MealSlot?)
    /// Tier 3 — the "let's talk" conversation.
    case conversation
    /// A check-in the user snoozed, until this time.
    case snoozed(until: Date?)
    /// Watching a meal: the next check-in comes at `dueMin` if nothing's logged.
    case watching(MealSlot, dueMin: Int, overdue: Bool)
    /// Under target with nothing scheduled (paused, or the meal times have passed).
    case toGo(kcal: Int)
    /// Target met or passed — nothing to push.
    case covered
    /// Quiet mode: no check-ins, no "left", no accent.
    case quiet

    static func resolve(_ home: HomeResponse) -> TodayMoment {
        if let checkIn = home.activeCheckIn {
            if checkIn.tier >= 3 { return .conversation }
            if checkIn.status == "DEFERRED" {
                return .snoozed(until: checkIn.deferUntil.flatMap(MealFormat.parse))
            }
            return .checkIn(checkIn.slot.flatMap(MealSlot.init(rawValue:)))
        }
        guard home.enforcementEnabled else { return .quiet }
        guard home.framing.state == "under" else { return .covered }
        if let next = home.nextCheckIn {
            return .watching(MealSlot(rawValue: next.slot) ?? .lunch, dueMin: next.dueMin, overdue: next.overdue)
        }
        return .toGo(kcal: max(0, home.ledger.remainingKcal))
    }

    /// The takeover replaces the dial while the manager is asking something.
    var takesOver: Bool {
        switch self {
        case .checkIn, .conversation: return true
        default: return false
        }
    }
}

enum TodayCopy {
    static func headline(_ moment: TodayMoment) -> String {
        switch moment {
        case let .checkIn(slot): return slot.map { "\($0.title) slipped." } ?? "Time to eat."
        case .conversation: return "Rough few days."
        case .snoozed: return "Snoozed."
        case let .watching(slot, _, overdue): return overdue ? "\(slot.title) slipped." : "\(slot.title) is next."
        case let .toGo(kcal): return "\(kcal.formatted()) kcal to go."
        case .covered: return "Day covered."
        case .quiet: return "Here’s today."
        }
    }

    static func detail(_ moment: TodayMoment, home: HomeResponse, now: Date = .now) -> String? {
        switch moment {
        case .checkIn:
            return sinceLastMeal(home, now: now)
        case .conversation:
            return "Let’s change something."
        case let .snoozed(until):
            return until.map { "I’ll check again at \($0.formatted(date: .omitted, time: .shortened))." }
        case let .watching(_, _, overdue):
            return overdue ? "Checking in now." : nil
        case .toGo:
            return "A snack or a late meal covers it."
        case .covered:
            return "Nothing else needed today."
        case .quiet:
            return "Log when you like. No check-ins."
        }
    }

    /// "Nothing since 8:05." — when the last meal was today.
    static func sinceLastMeal(_ home: HomeResponse, now: Date = .now, calendar: Calendar = .current) -> String {
        guard let iso = home.ledger.lastMealAt, let last = MealFormat.parse(iso),
              calendar.isDate(last, inSameDayAs: now) else {
            return "Nothing logged yet today."
        }
        return "Nothing since \(last.formatted(date: .omitted, time: .shortened))."
    }

    /// "Usually 13:00 · nothing since 8:05" — why the check-in came now.
    static func whyNow(_ home: HomeResponse, now: Date = .now) -> String? {
        guard let slot = home.activeCheckIn?.slot.flatMap(MealSlot.init(rawValue:)) else { return nil }
        let times = home.resolvedMealTimes
        let at = slot == .breakfast ? times.breakfastMin : slot == .lunch ? times.lunchMin : times.dinnerMin
        let since = sinceLastMeal(home, now: now).dropLast().lowercased()
        return "Usually \(formatMinutes(at)) · \(since)"
    }

    /// Each meal's state, for the dial's knobs.
    /// Quiet mode never marks a meal as missed.
    static func dialStates(_ home: HomeResponse) -> [MealSlot: SlotState] {
        var states: [MealSlot: SlotState] = [:]
        for slot in home.day?.slots ?? [] {
            let state = slot.slotState
            states[slot.meal] = state == .missed && !home.enforcementEnabled ? .upcoming : state
        }
        return states
    }
}

enum TodayLayout {
    /// A slot's meals, in the order the backend listed them.
    static func meals(in slot: HomeResponse.Day.Slot, from meals: [MealSummary]) -> [MealSummary] {
        let byID = Dictionary(meals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return slot.mealIds.compactMap { byID[$0] }
    }

    /// The meal time a logged minute belongs to — same rule as the backend:
    /// closest usual time, with boundaries halfway between meals.
    static func slot(forMinute minute: Int, times: MealTimesPayload) -> MealSlot {
        let breakfastEnd = (times.breakfastMin + times.lunchMin) / 2
        let lunchEnd = (times.lunchMin + times.dinnerMin) / 2
        if minute < breakfastEnd { return .breakfast }
        if minute < lunchEnd { return .lunch }
        return .dinner
    }

    /// Minutes from local midnight.
    static func minuteOfDay(from date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// Minutes from local midnight for a logged-at timestamp.
    static func minuteOfDay(_ iso: String, calendar: Calendar = .current) -> Int? {
        guard let date = MealFormat.parse(iso) else { return nil }
        return minuteOfDay(from: date, calendar: calendar)
    }

    /// Today at a minute of day — the time a missed meal gets backdated to.
    static func today(atMin minute: Int, now: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: now) ?? now
    }
}

extension HomeResponse {
    /// Drop a just-logged meal into the local home so Today doesn't wait on a
    /// round-trip — and so it lands under the slot it was logged for.
    func inserting(_ meal: MealSummary, into slot: MealSlot) -> HomeResponse {
        guard !meals.contains(where: { $0.id == meal.id }) else { return self }
        let remainingProtein = ledger.remainingProteinG.map { $0 - meal.proteinG }
        return HomeResponse(
            goal: goal,
            mode: mode,
            enforcementEnabled: enforcementEnabled,
            ledger: .init(
                consumedKcal: ledger.consumedKcal + meal.kcal,
                targetKcal: ledger.targetKcal,
                remainingKcal: ledger.remainingKcal - meal.kcal,
                consumedProteinG: ledger.consumedProteinG + meal.proteinG,
                targetProteinG: ledger.targetProteinG,
                remainingProteinG: remainingProtein,
                mealsToday: ledger.mealsToday + 1,
                lastMealAt: meal.loggedAt
            ),
            framing: framing,
            managerNote: managerNote,
            meals: meals + [meal],
            mealTimes: mealTimes,
            activeCheckIn: activeCheckIn,
            day: day?.inserting(meal, into: slot),
            nextCheckIn: nextCheckIn,
            needsWeighIn: needsWeighIn,
            quietHours: quietHours
        )
    }
}

extension HomeResponse.Day {
    func inserting(_ meal: MealSummary, into slot: MealSlot) -> HomeResponse.Day {
        HomeResponse.Day(
            nowMin: nowMin,
            slots: slots.map { s in
                guard s.meal == slot else { return s }
                return .init(
                    slot: s.slot,
                    atMin: s.atMin,
                    state: "logged",
                    mealIds: s.mealIds + [meal.id],
                    kcal: s.kcal + meal.kcal
                )
            },
            pace: pace
        )
    }
}
