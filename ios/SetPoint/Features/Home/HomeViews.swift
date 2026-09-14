import SwiftUI

/// The check-in answers, shared by the Today takeover and the full check-in.
enum CheckInActions {
    struct SnoozeChoice: Identifiable, Equatable {
        let title: String
        let minutes: Int
        var id: String { title }
    }

    /// Snooze lengths to offer. "After <next meal time>" only when that's far
    /// enough away to mean something; the backend caps a snooze at 6 hours.
    static func snoozeChoices(nextMealMinutes: Int?, now: Date = .now) -> [SnoozeChoice] {
        var choices = [SnoozeChoice(title: "1 hour", minutes: 60), SnoozeChoice(title: "2 hours", minutes: 120)]
        if let minutes = nextMealMinutes, minutes >= 45 {
            let capped = min(minutes, 360)
            let at = now.addingTimeInterval(TimeInterval(capped * 60))
            choices.append(SnoozeChoice(title: "After \(at.formatted(date: .omitted, time: .shortened))", minutes: capped))
        }
        return choices
    }

    /// "I ate this" — logs the prescription's totals and answers the check-in.
    static func eat(prescriptionID: String, api: APIClient) async throws {
        let _: LogMealResponse = try await api.post(
            "/api/meals",
            LogMealRequest(text: nil, macros: nil, prescriptionId: prescriptionID)
        )
    }

    /// "I already ate" — closes the check-in without logging; not a miss.
    static func alreadyAte(checkInID: String, api: APIClient) async throws {
        try await api.post("/api/checkins/\(checkInID)/dismiss")
    }

    static func cover(checkInID: String, api: APIClient) async throws {
        try await api.post("/api/checkins/\(checkInID)/cover")
    }

    static func snooze(checkInID: String, minutes: Int?, api: APIClient) async throws {
        if let minutes {
            try await api.post("/api/checkins/\(checkInID)/defer", SnoozeBody(minutes: min(max(minutes, 15), 360)))
        } else {
            try await api.post("/api/checkins/\(checkInID)/defer")
        }
    }

    private struct SnoozeBody: Encodable {
        let minutes: Int
    }
}
