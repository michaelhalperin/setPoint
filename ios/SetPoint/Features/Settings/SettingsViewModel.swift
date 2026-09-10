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
    var targetWeightKg: Double?
    var pace: GoalPace = .gentle
    var kcalTarget = 2500
    var proteinTarget: Int?
    var mealTimes = MealTimesPayload(breakfastMin: 480, lunchMin: 780, dinnerMin: 1140)
    var quietHours = QuietHoursPayload(startMin: 1380, endMin: 420)
    var checkInsPaused = false
    var restrictions: [String] = []

    // Read-only
    private(set) var mode = "BASIC"
    private(set) var startWeightKg: Double?
    private(set) var currentWeightKg: Double?
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

    private var weightGoalDirty: Bool {
        guard let o = original else { return false }
        if goal.rawValue != o.goal { return true }
        guard goal.hasWeightTarget else { return false }
        return targetWeightKg != o.targetWeightKg
            || abs(pace.kgPerWeek(for: goal) - o.paceKgPerWeek) > 0.001
    }

    var dirty: Bool {
        guard let o = original else { return false }
        return weightGoalDirty
            || kcalTarget != o.dailyKcalTarget
            || proteinTarget != o.dailyProteinTargetG
            || mealTimes != o.mealTimes
            || quietHours != o.quietHours
            || checkInsPaused != o.checkInsPaused
            || Set(restrictions) != Set(o.restrictions.map(\.label))
    }

    func revertToOriginal() {
        guard let o = original else { return }
        apply(o)
        error = nil
    }

    func load() async {
        do {
            let s: SettingsResponse = try await api.get("/api/settings")
            apply(s)
            phase = .loaded
        } catch APIError.unauthorized {
            onUnauthorized()
        } catch {
            phase = .failed(UserFacingError.message(for: error, fallback: "Couldn't load profile."))
        }
    }

    func save() async {
        guard dirty, !saving else { return }
        saving = true
        error = nil
        defer { saving = false }

        let o = original
        // Let the backend recompute the daily target when the goal/weight-target
        // changed; only send an explicit kcal target when the user edited it.
        let kcalEdited = o.map { kcalTarget != $0.dailyKcalTarget } ?? true
        let proteinEdited = o.map { proteinTarget != $0.dailyProteinTargetG } ?? true

        var patch = SettingsPatch(
            goal: goal.rawValue,
            mealTimes: mealTimes,
            quietHours: quietHours,
            checkInsPaused: checkInsPaused,
            restrictions: restrictions.map { .init(label: $0, source: nil) }
        )
        if goal.hasWeightTarget {
            patch.targetWeightKg = targetWeightKg
            patch.paceKgPerWeek = pace.kgPerWeek(for: goal)
        }
        if kcalEdited { patch.dailyKcalTarget = kcalTarget }
        if proteinEdited { patch.dailyProteinTargetG = proteinTarget }
        do {
            let updated: SettingsResponse = try await api.patch("/api/settings", patch)
            apply(updated)
        } catch APIError.unauthorized {
            onUnauthorized()
        } catch {
            self.error = UserFacingError.message(for: error, fallback: "Couldn't save.")
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
            self.error = UserFacingError.message(for: error, fallback: "Couldn't delete account.")
        }
    }

    func setCheckInsPaused(_ paused: Bool) async {
        guard enforcementEnabled, checkInsPaused != paused, !saving else { return }
        let previous = checkInsPaused
        checkInsPaused = paused
        await save()
        if error != nil {
            checkInsPaused = previous
        }
    }

    private func apply(_ s: SettingsResponse) {
        original = s
        goal = Goal(rawValue: s.goal) ?? .bulk
        targetWeightKg = s.targetWeightKg
        pace = GoalPace.closest(toKgPerWeek: s.paceKgPerWeek, for: goal)
        startWeightKg = s.startWeightKg
        currentWeightKg = s.currentWeightKg
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

    #if DEBUG
    static func previewed() -> SettingsViewModel {
        let vm = SettingsViewModel(api: AppEnvironment.preview().api, onUnauthorized: {}, onDeleted: {})
        vm.apply(SettingsResponse(
            goal: "BULK", mode: "SMART", timezone: "America/New_York",
            dailyKcalTarget: 3100, dailyProteinTargetG: 165,
            targetWeightKg: 84, paceKgPerWeek: 0.25, startWeightKg: 78, currentWeightKg: 79.6,
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
