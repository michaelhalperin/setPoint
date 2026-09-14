import Foundation
import Observation

@MainActor
@Observable
final class SettlementViewModel {
    enum Phase {
        case loading
        case loaded(SettlementResponse)
        case failed(String)
    }

    var phase: Phase = .loading
    var loggingWeight = false
    var weighInError: String?
    var applyingTargetReview = false
    /// Recent weigh-ins, oldest first — the trend line.
    private(set) var weights: [WeightHistoryResponse.Entry] = []
    private(set) var applyingPattern = false
    /// Set after a weigh-in that reached the goal — the view shows a note.
    var reachedGoalTarget: Double?

    private let api: APIClient
    private let onUnauthorized: @MainActor () -> Void

    init(api: APIClient, onUnauthorized: @escaping @MainActor () -> Void) {
        self.api = api
        self.onUnauthorized = onUnauthorized
    }

    func load() async {
        do {
            async let history: WeightHistoryResponse? = try? api.get("/api/weight", query: ["limit": "30"])
            let s: SettlementResponse = try await api.get("/api/settlement")
            weights = (await history)?.entries.reversed() ?? []
            phase = .loaded(s)
        } catch APIError.unauthorized {
            onUnauthorized()
        } catch {
            phase = .failed(UserFacingError.message(for: error, fallback: "Couldn't load. Try again."))
        }
    }

    func meals(on date: String) async -> [MealSummary] {
        do {
            let res: MealsListResponse = try await api.get("/api/meals", query: ["date": date])
            return res.meals
        } catch APIError.unauthorized {
            onUnauthorized()
            return []
        } catch {
            return []
        }
    }

    func removeMeal(id: String) async throws {
        do {
            try await api.delete("/api/meals/\(id)")
            await load()
        } catch APIError.unauthorized {
            onUnauthorized()
            throw APIError.unauthorized
        }
    }

    /// "Expect it at 13:30" — move that meal time, keep the others.
    func applyPattern(_ pattern: SettlementResponse.Record.Pattern) async -> Bool {
        applyingPattern = true
        defer { applyingPattern = false }
        do {
            let settings: SettingsResponse = try await api.get("/api/settings")
            var times = settings.mealTimes
            switch pattern.slot {
            case "breakfast": times.breakfastMin = pattern.suggestedMin
            case "lunch": times.lunchMin = pattern.suggestedMin
            default: times.dinnerMin = pattern.suggestedMin
            }
            let _: SettingsResponse = try await api.patch("/api/settings", SettingsPatch(mealTimes: times))
            PatternMemory.dismiss(pattern)
            await load()
            return true
        } catch APIError.unauthorized {
            onUnauthorized()
            return false
        } catch {
            return false
        }
    }

    func logWeight(kg: Double) async -> Bool {
        loggingWeight = true
        weighInError = nil
        defer { loggingWeight = false }
        do {
            let res: WeightLogResponse = try await api.post("/api/weight", WeightLogRequest(weightKg: kg))
            if res.goalReached { reachedGoalTarget = res.entry.weightKg }
            await load()
            return true
        } catch APIError.unauthorized {
            onUnauthorized()
            return false
        } catch {
            weighInError = UserFacingError.message(for: error, fallback: "Couldn't save. Try again.")
            return false
        }
    }

    /// The server recomputes the suggestion; we only send the target the user saw.
    func acceptTargetReview(_ review: SettlementResponse.TargetReview) async {
        await decideTargetReview(TargetReviewDecision(action: "accept", proposedKcal: review.proposedKcal))
    }

    /// "Not now" — the server records it, and the card stays away for a week.
    func dismissTargetReview() async {
        await decideTargetReview(TargetReviewDecision(action: "dismiss", proposedKcal: nil))
    }

    private func decideTargetReview(_ decision: TargetReviewDecision) async {
        guard !applyingTargetReview else { return }
        applyingTargetReview = true
        weighInError = nil
        defer { applyingTargetReview = false }
        do {
            try await api.post("/api/settings/target-review", decision)
            await load()
        } catch APIError.unauthorized {
            onUnauthorized()
        } catch let APIError.http(status, _) where status == 409 {
            // The suggestion moved or no longer applies — show what's true now.
            await load()
        } catch {
            weighInError = UserFacingError.message(for: error, fallback: "Couldn't update the target.")
        }
    }

    #if DEBUG
    static func previewed(_ response: SettlementResponse) -> SettlementViewModel {
        let vm = SettlementViewModel(api: AppEnvironment.preview().api, onUnauthorized: {})
        vm.phase = .loaded(response)
        return vm
    }
    #endif
}

/// Remembers a pattern the user already answered, so Week doesn't ask again.
enum PatternMemory {
    private static func key(_ pattern: SettlementResponse.Record.Pattern) -> String {
        "com.setpoint.app.pattern.\(pattern.slot).\(pattern.suggestedMin)"
    }

    static func isDismissed(_ pattern: SettlementResponse.Record.Pattern) -> Bool {
        UserDefaults.standard.bool(forKey: key(pattern))
    }

    static func dismiss(_ pattern: SettlementResponse.Record.Pattern) {
        UserDefaults.standard.set(true, forKey: key(pattern))
    }
}

#if DEBUG
extension SettlementResponse {
    static let sample = SettlementResponse(
        days: [
            .init(date: "2026-09-02", kind: "ON_TRACK", kcalConsumed: 2980, kcalTarget: 3000, summaryLine: "Landed on target. That's the pattern to keep."),
            .init(date: "2026-09-03", kind: "UNDER", kcalConsumed: 2260, kcalTarget: 3000, summaryLine: "Came in 740 kcal short. Let's close that gap tomorrow."),
            .init(date: "2026-09-04", kind: "ON_TRACK", kcalConsumed: 3040, kcalTarget: 3000, summaryLine: "Right on target."),
            .init(date: "2026-09-05", kind: "MISSED", kcalConsumed: 0, kcalTarget: 3000, summaryLine: "Nothing logged. Tomorrow's a clean start."),
            .init(date: "2026-09-06", kind: "OVER", kcalConsumed: 3560, kcalTarget: 3000, summaryLine: "Over target, but not by much. Steady as you go."),
            .init(date: "2026-09-07", kind: "ON_TRACK", kcalConsumed: 2950, kcalTarget: 3000, summaryLine: "Solid day — that's how the week is won."),
        ],
        today: .init(date: "2026-09-08", kind: "UNDER", kcalConsumed: 1180, kcalTarget: 3000),
        weekSummary: "3 of 6 days on target. Some ground to make up, nothing dramatic.",
        weightGoal: .init(
            goal: "BULK",
            startWeightKg: 74,
            targetWeightKg: 80,
            currentWeightKg: 76.4,
            changedKg: 2.4,
            remainingKg: 3.6,
            totalKg: 6,
            fractionComplete: 0.4,
            status: "on_pace",
            etaWeeks: 15,
            lastWeighInAt: "2026-09-05T08:00:00.000Z",
            needsWeighIn: false
        ),
        record: .init(
            days: [
                .init(date: "2026-09-02", slots: ["on_time", "after_check_in", "on_time"]),
                .init(date: "2026-09-03", slots: ["on_time", "after_check_in", "on_time"]),
                .init(date: "2026-09-04", slots: ["on_time", "on_time", "on_time"]),
                .init(date: "2026-09-05", slots: ["on_time", "after_check_in", "missed"]),
                .init(date: "2026-09-06", slots: ["after_check_in", "after_check_in", "on_time"]),
                .init(date: "2026-09-07", slots: ["on_time", "on_time", "on_time"]),
                .init(date: "2026-09-08", slots: ["on_time", "open", "open"]),
            ],
            onTime: 13,
            afterCheckIn: 5,
            missed: 1,
            checkIns: 6,
            pattern: .init(slot: "lunch", lateDays: 4, ofDays: 5, currentMin: 780, suggestedMin: 810)
        )
    )

    static let sampleNeedsWeighIn = SettlementResponse(
        days: sample.days,
        today: sample.today,
        weekSummary: sample.weekSummary,
        weightGoal: .init(
            goal: "DIET",
            startWeightKg: 82,
            targetWeightKg: 76,
            currentWeightKg: 80.2,
            changedKg: 1.8,
            remainingKg: 4.2,
            totalKg: 6,
            fractionComplete: 0.3,
            status: "behind",
            etaWeeks: 18,
            lastWeighInAt: nil,
            needsWeighIn: true
        )
    )

    static let sampleEmpty = SettlementResponse(
        days: [],
        today: .init(date: "2026-09-08", kind: "UNDER", kcalConsumed: 0, kcalTarget: 3000),
        weekSummary: "First week underway — the pattern starts now.",
        weightGoal: sample.weightGoal
    )

    static let sampleMaintain = SettlementResponse(
        days: sample.days,
        today: sample.today,
        weekSummary: sample.weekSummary,
        weightGoal: nil
    )
}
#endif
