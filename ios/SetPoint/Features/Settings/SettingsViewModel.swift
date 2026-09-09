import Foundation
import Observation

@MainActor
@Observable
final class SettingsViewModel {
    enum Phase {
        case loading
        case loaded
        case failed(String)
    }

    var phase: Phase = .loading
    var saving = false
    var deleting = false
    var error: String?

    // Editable draft
    var goal: Goal = .bulk
    var kcalTarget = 2500
    var proteinTarget: Int?
    var mealTimes = MealTimesPayload(breakfastMin: 480, lunchMin: 780, dinnerMin: 1140)
    var quietHours = QuietHoursPayload(startMin: 1380, endMin: 420)
    var checkInsPaused = false
    var restrictions: [String] = []

    // Read-only
    private(set) var mode = "BASIC"
    private(set) var enforcementEnabled = true
    private(set) var enforcementDisabledReason: String?

    private var original: SettingsResponse?
    private let api: APIClient
    private let onUnauthorized: @MainActor () -> Void
    private let onDeleted: @MainActor () -> Void

    init(
        api: APIClient,
        onUnauthorized: @escaping @MainActor () -> Void,
        onDeleted: @escaping @MainActor () -> Void
    ) {
        self.api = api
        self.onUnauthorized = onUnauthorized
        self.onDeleted = onDeleted
    }

    var dirty: Bool {
        guard let o = original else { return false }
        return goal.rawValue != o.goal
            || kcalTarget != o.dailyKcalTarget
            || proteinTarget != o.dailyProteinTargetG
            || mealTimes != o.mealTimes
            || quietHours != o.quietHours
            || checkInsPaused != o.checkInsPaused
            || Set(restrictions) != Set(o.restrictions.map(\.label))
    }

    func load() async {
        do {
            let s: SettingsResponse = try await api.get("/api/settings")
            apply(s)
            phase = .loaded
        } catch APIError.unauthorized {
            onUnauthorized()
        } catch {
            phase = .failed(message(error))
        }
    }

    func save() async {
        guard dirty, !saving else { return }
        saving = true
        error = nil
        defer { saving = false }

        let patch = SettingsPatch(
            goal: goal.rawValue,
            dailyKcalTarget: kcalTarget,
            dailyProteinTargetG: proteinTarget,
            mealTimes: mealTimes,
            quietHours: quietHours,
            checkInsPaused: checkInsPaused,
            restrictions: restrictions.map { .init(label: $0, source: nil) }
        )
        do {
            let updated: SettingsResponse = try await api.patch("/api/settings", patch)
            apply(updated)
        } catch APIError.unauthorized {
            onUnauthorized()
        } catch {
            self.error = message(error)
        }
    }

    func deleteAccount() async {
        guard !deleting else { return }
        deleting = true
        error = nil
        defer { deleting = false }
        do {
            let _: DeleteAccountResponse = try await api.delete("/api/account", DeleteAccountRequest())
            onDeleted()
        } catch APIError.unauthorized {
            onUnauthorized()
        } catch {
            self.error = message(error)
        }
    }

    private func apply(_ s: SettingsResponse) {
        original = s
        goal = Goal(rawValue: s.goal) ?? .bulk
        kcalTarget = s.dailyKcalTarget
        proteinTarget = s.dailyProteinTargetG
        mealTimes = s.mealTimes
        quietHours = s.quietHours
        checkInsPaused = s.checkInsPaused
        restrictions = s.restrictions.map(\.label)
        mode = s.mode
        enforcementEnabled = s.enforcementEnabled
        enforcementDisabledReason = s.enforcementDisabledReason
    }

    private func message(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
    }

    #if DEBUG
    static func previewed() -> SettingsViewModel {
        let vm = SettingsViewModel(api: AppEnvironment.preview().api, onUnauthorized: {}, onDeleted: {})
        vm.apply(SettingsResponse(
            goal: "BULK", mode: "SMART", timezone: "America/New_York",
            dailyKcalTarget: 3100, dailyProteinTargetG: 165,
            mealTimes: .init(breakfastMin: 480, lunchMin: 780, dinnerMin: 1140),
            quietHours: .init(startMin: 1380, endMin: 420),
            checkInsPaused: false,
            restrictions: [.init(label: "Dairy", token: "dairy", source: "INTOLERANCE")],
            enforcementEnabled: true, enforcementDisabledReason: nil
        ))
        vm.phase = .loaded
        return vm
    }
    #endif
}
