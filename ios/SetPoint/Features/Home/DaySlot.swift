import Foundation

/// Breakfast / lunch / dinner stations on Today. A meal lands in a slot by
/// the user's usual times: breakfast until lunch, lunch until dinner, dinner
/// after that. Logs before breakfast still sit in breakfast.
enum DaySlot: String, CaseIterable, Identifiable {
    case breakfast
    case lunch
    case dinner

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakfast: return "Breakfast"
        case .lunch: return "Lunch"
        case .dinner: return "Dinner"
        }
    }

    func clock(in times: MealTimesPayload) -> String {
        switch self {
        case .breakfast: return formatMinutes(times.breakfastMin)
        case .lunch: return formatMinutes(times.lunchMin)
        case .dinner: return formatMinutes(times.dinnerMin)
        }
    }

    /// Breakfast: before lunch time. Lunch: from lunch until dinner. Dinner: from dinner on.
    static func assigning(minutesFromMidnight mins: Int, times: MealTimesPayload) -> DaySlot {
        if mins < times.lunchMin { return .breakfast }
        if mins < times.dinnerMin { return .lunch }
        return .dinner
    }

    static func assigning(_ date: Date, times: MealTimesPayload, calendar: Calendar = .current) -> DaySlot {
        let minutes = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        return assigning(minutesFromMidnight: minutes, times: times)
    }

    static func assigning(iso: String, times: MealTimesPayload) -> DaySlot {
        guard let date = MealFormat.parse(iso) else { return .lunch }
        return assigning(date, times: times)
    }

    /// First unfilled station walking breakfast → lunch → dinner. Nil when the day is full.
    static func firstEmpty(filled: Set<DaySlot>) -> DaySlot? {
        allCases.first { !filled.contains($0) }
    }
}
