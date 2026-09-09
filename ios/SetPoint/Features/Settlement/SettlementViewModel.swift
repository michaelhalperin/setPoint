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
            let s: SettlementResponse = try await api.get("/api/settlement")
            phase = .loaded(s)
        } catch APIError.unauthorized {
            onUnauthorized()
        } catch {
            phase = .failed((error as? LocalizedError)?.errorDescription ?? "Something went wrong.")
        }
    }

    func logWeight(kg: Double) async -> Bool {
        loggingWeight = true
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
            phase = .failed((error as? LocalizedError)?.errorDescription ?? "Couldn't save that weigh-in.")
            return false
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
        weekSummary: "4 of 6 days on target. Some ground to make up, nothing dramatic.",
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
        )
    )
}
#endif
