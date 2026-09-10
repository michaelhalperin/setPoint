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
    case parsing(title: String)
    case logged(title: String, kcal: Int)
}

/// What the single "Next" card on Today is about.
enum TodayNext: Equatable {
    /// A tier 1–2 check-in waiting for an answer.
    case checkIn
    /// A check-in the user snoozed.
    case snoozed
    /// Tier 3 — the "let's talk" conversation.
    case conversation
    /// Under target with a meal time still open.
    case meal(MealSlot, atMin: Int, suggestedKcal: Int)
    /// Under target but every meal time has passed.
    case toGo(kcal: Int)
    /// Target met or passed — nothing to push.
    case covered
    /// Quiet mode: the manager doesn't prompt at all.
    case quiet

    /// Stable within a case, distinct between cases — drives the card's
    /// crossfade when the situation changes, without re-triggering on a plain
    /// re-render.
    var caseKey: String {
        switch self {
        case .checkIn: return "checkIn"
        case .snoozed: return "snoozed"
        case .conversation: return "conversation"
        case let .meal(slot, _, _): return "meal-\(slot.rawValue)"
        case .toGo: return "toGo"
        case .covered: return "covered"
        case .quiet: return "quiet"
        }
    }

    static func resolve(_ home: HomeResponse) -> TodayNext {
        if let checkIn = home.activeCheckIn {
            if checkIn.tier >= 3 { return .conversation }
            return checkIn.status == "DEFERRED" ? .snoozed : .checkIn
        }
        guard home.enforcementEnabled else { return .quiet }
        guard home.framing.state == "under" else { return .covered }
        if let next = home.day?.pace?.next {
            return .meal(MealSlot(rawValue: next.slot) ?? .lunch, atMin: next.atMin, suggestedKcal: next.suggestedKcal)
        }
        return .toGo(kcal: max(0, home.ledger.remainingKcal))
    }
}

enum TodayCopy {
    /// Caption beside the big number.
    static func heroCaption(_ framing: HomeResponse.Framing) -> String {
        framing.heroKcal >= 0 ? "kcal left" : "kcal past target"
    }

    /// One line about pace under the day track — only while there's still food
    /// to eat, never in quiet mode, and never about going over.
    static func paceLine(_ home: HomeResponse) -> String? {
        guard home.enforcementEnabled, home.framing.state == "under", let pace = home.day?.pace else { return nil }
        switch pace.status {
        case "behind": return "About \(pace.behindKcal.formatted()) kcal behind your usual pace"
        case "ahead": return "Ahead of your usual pace"
        default: return "On pace with your usual meals"
        }
    }
}

/// Positions along the day track as fractions (0...1) of a window that spans
/// the user's meal times with some air either side, always including now.
struct DayTrackLayout: Equatable {
    let startMin: Int
    let endMin: Int

    init(mealTimes: MealTimesPayload, nowMin: Int) {
        let start = max(0, min(mealTimes.breakfastMin - 90, nowMin - 30))
        let end = min(1440, max(mealTimes.dinnerMin + 150, nowMin + 30))
        startMin = start
        endMin = max(end, start + 60)
    }

    func fraction(_ minute: Int) -> Double {
        min(1, max(0, Double(minute - startMin) / Double(endMin - startMin)))
    }
}

enum TodayLayout {
    /// A slot's meals, in the order the backend listed them.
    static func meals(in slot: HomeResponse.Day.Slot, from meals: [MealSummary]) -> [MealSummary] {
        let byID = Dictionary(meals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return slot.mealIds.compactMap { byID[$0] }
    }

    /// Minutes from local midnight for a logged-at timestamp.
    static func minuteOfDay(_ iso: String, calendar: Calendar = .current) -> Int? {
        guard let date = MealFormat.parse(iso) else { return nil }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// Today at a minute of day — the time a missed meal gets backdated to.
    static func today(atMin minute: Int, now: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: now) ?? now
    }
}
