import Foundation
import Observation

struct ScoffAnswers {
    var makeSelfSick: Bool?
    var lostControl: Bool?
    var lostOneStone: Bool?
    var believesFat: Bool?
    var foodDominates: Bool?

    var isComplete: Bool {
        makeSelfSick != nil && lostControl != nil && lostOneStone != nil
            && believesFat != nil && foodDominates != nil
    }
}

struct OnboardingDraft {
    var goal: Goal?
    var sex: Sex = .unspecified
    var birthDate = Calendar.current.date(byAdding: .year, value: -28, to: .now) ?? .now
    var heightCm: Double?
    var weightKg: Double?
    var activityLevel: ActivityLevel = .moderate
    var hasWearable = false

    // Weight goal (M16) — nil / ignored for Maintain.
    var targetWeightKg: Double?
    var pace: GoalPace = .gentle

    var breakfastMin = 480    // 08:00
    var lunchMin = 780        // 13:00
    var dinnerMin = 1140      // 19:00
    var quietStartMin = 1380  // 23:00
    var quietEndMin = 420     // 07:00

    var restrictions: [String] = []
    var restrictionsFreeText = ""
    var medicalSupervisionRequired = false
    var scoff = ScoffAnswers()

    func toRequest() -> OnboardingRequest {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        df.dateFormat = "yyyy-MM-dd"

        let resolvedGoal = goal ?? .bulk

        return OnboardingRequest(
            goal: resolvedGoal.rawValue,
            mode: hasWearable ? "SMART" : "BASIC",
            timezone: TimeZone.current.identifier,
            sex: sex.rawValue,
            birthDate: df.string(from: birthDate),
            heightCm: heightCm,
            weightKg: weightKg,
            activityLevel: activityLevel.rawValue,
            targetWeightKg: resolvedGoal.hasWeightTarget ? targetWeightKg : nil,
            paceKgPerWeek: resolvedGoal.hasWeightTarget ? pace.kgPerWeek(for: resolvedGoal) : nil,
            mealTimes: .init(breakfastMin: breakfastMin, lunchMin: lunchMin, dinnerMin: dinnerMin),
            quietHours: .init(startMin: quietStartMin, endMin: quietEndMin),
            safety: .init(
                medicalSupervisionRequired: medicalSupervisionRequired,
                scoff: .init(
                    makeSelfSick: scoff.makeSelfSick ?? false,
                    lostControl: scoff.lostControl ?? false,
                    lostOneStone: scoff.lostOneStone ?? false,
                    believesFat: scoff.believesFat ?? false,
                    foodDominates: scoff.foodDominates ?? false
                ),
                restrictions: restrictions.map { .init(label: $0, source: nil) },
                restrictionsFreeText: restrictionsFreeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil
                    : restrictionsFreeText.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        )
    }
}

@MainActor
@Observable
final class OnboardingViewModel {
    /// The intake, as beats rather than a form split into pages. `welcome` sets
    /// the tone before any data; `you → goal → checkins → safety` are the input
    /// beats shown on the progress thread; `review` confirms; `outcome` delivers.
    enum Step: Int, CaseIterable {
        case welcome, you, goal, checkins, safety, review, outcome
    }

    var step: Step = .welcome
    var draft = OnboardingDraft()
    var submitting = false
    var result: OnboardingResponse?
    var error: String?

    private let api: APIClient
    let onComplete: @MainActor () -> Void

    init(api: APIClient, onComplete: @escaping @MainActor () -> Void) {
        self.api = api
        self.onComplete = onComplete
    }

    /// Beats that carry the progress thread (welcome + outcome don't).
    static let threadedSteps: [Step] = [.you, .goal, .checkins, .safety, .review]

    /// 0-based position of `step` within the thread, or nil if it isn't threaded.
    var threadIndex: Int? {
        Self.threadedSteps.firstIndex(of: step)
    }

    var canGoBack: Bool {
        ![.welcome, .you, .outcome].contains(step) && !submitting
    }

    var canAdvance: Bool {
        switch step {
        case .welcome: return true
        case .you: return draft.heightCm != nil && draft.weightKg != nil
        case .goal:
            guard let goal = draft.goal else { return false }
            return !goal.hasWeightTarget || draft.targetWeightKg != nil
        case .checkins: return true
        case .safety: return draft.scoff.isComplete
        case .review: return !submitting
        case .outcome: return true
        }
    }

    var primaryTitle: String {
        switch step {
        case .welcome: return "Set this up"
        case .review: return submitting ? "Setting up…" : "Start"
        case .outcome: return "Go to today"
        default: return "Continue"
        }
    }

    func advance() {
        switch step {
        case .review:
            Task { await submit() }
        case .outcome:
            onComplete()
        default:
            if let next = Step(rawValue: step.rawValue + 1) { step = next }
        }
    }

    func goBack() {
        if let prev = Step(rawValue: step.rawValue - 1) { step = prev }
    }

    private func submit() async {
        submitting = true
        error = nil
        defer { submitting = false }
        do {
            let response: OnboardingResponse = try await api.post("/api/onboarding", draft.toRequest())
            result = response
            step = .outcome
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "Couldn't save your setup."
        }
    }

    #if DEBUG
    static func previewed(at step: Step) -> OnboardingViewModel {
        let vm = OnboardingViewModel(api: AppEnvironment.preview().api, onComplete: {})
        vm.draft.goal = .bulk
        vm.draft.heightCm = 182
        vm.draft.weightKg = 79
        vm.draft.targetWeightKg = 85
        vm.draft.pace = .steady
        vm.draft.restrictions = ["Dairy", "Peanuts"]
        vm.draft.scoff = ScoffAnswers(
            makeSelfSick: false, lostControl: false, lostOneStone: false,
            believesFat: false, foodDominates: false
        )
        if step == .outcome {
            vm.result = OnboardingResponse(
                dailyKcalTarget: 3120, dailyProteinTargetG: 142,
                targetWeightKg: 85, paceKgPerWeek: 0.25,
                enforcementEnabled: true, enforcementDisabledReason: nil
            )
        }
        vm.step = step
        return vm
    }
    #endif
}
