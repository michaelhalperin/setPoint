import Foundation

/// One day on the Week rail — settled past days plus today's live projection.
struct WeekStation: Identifiable, Hashable {
    let date: String
    let kind: String
    let kcalConsumed: Int
    let kcalTarget: Int
    let summaryLine: String?
    let isToday: Bool

    var id: String { date }

    /// Consumed vs target, clamped to 0...1 so the fill never overflows.
    var fill: Double {
        guard kcalTarget > 0 else { return 0 }
        return min(1, max(0, Double(kcalConsumed) / Double(kcalTarget)))
    }

    var kindLabel: String {
        switch kind {
        case "ON_TRACK": return "On track"
        case "UNDER": return "Under"
        case "OVER": return "Over"
        default: return "Missed"
        }
    }

    /// Short weekday for the rail, or "Today".
    var title: String {
        if isToday { return "Today" }
        guard let parsed = Self.parse(date) else { return date }
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM"
        return f.string(from: parsed)
    }

    var accessibilityTitle: String {
        if isToday { return "Today" }
        guard let parsed = Self.parse(date) else { return date }
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .none
        return f.string(from: parsed)
    }

    static func parse(_ iso: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: iso)
    }
}

extension SettlementResponse {
    /// Chronological stations, today last. A feed (newest first) is a report;
    /// a week unfolding is a flow.
    var weekStations: [WeekStation] {
        let past = days.map {
            WeekStation(
                date: $0.date,
                kind: $0.kind,
                kcalConsumed: $0.kcalConsumed,
                kcalTarget: $0.kcalTarget,
                summaryLine: $0.summaryLine,
                isToday: false
            )
        }
        guard !past.contains(where: { $0.date == today.date }) else { return past }
        return past + [
            WeekStation(
                date: today.date,
                kind: today.kind,
                kcalConsumed: today.kcalConsumed,
                kcalTarget: today.kcalTarget,
                summaryLine: nil,
                isToday: true
            ),
        ]
    }

    var settledOnTrackCount: Int {
        days.filter { $0.kind == "ON_TRACK" }.count
    }
}
