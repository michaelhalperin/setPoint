import Foundation
import Observation

struct ScoffAnswers: Codable {
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

/// The healthy-weight floor for a diet target — BMI 18.5, mirroring the backend's
/// `minHealthyWeightKg`. SetPoint never helps anyone diet below it (§3).
enum HealthyWeight {
    static let bmiFloor = 18.5

    /// Lowest healthy target weight for a height, rounded up to 0.1 kg.
    static func minKg(heightCm: Double) -> Double {
        let meters = heightCm / 100
        return (bmiFloor * meters * meters * 10).rounded(.up) / 10
    }

    static func floorMessage(_ floor: Double) -> String {
        let unit = MassUnit.current
        return L10n( "The lowest target I'll set for your height is \(unit.number(floor)) \(unit.abbreviation).")
    }
}

/// The appetite question, and what each answer sets in the appetite settings.
enum AppetiteChoice: String, Codable, CaseIterable, Identifiable {
    case forgets, fullFast, chore, varies

    var id: String { rawValue }

    var title: String {
        switch self {
        case .forgets: return L10n("I eat fine, I just forget")
        case .fullFast: return L10n("I get full fast")
        case .chore: return L10n("Food feels like a chore")
        case .varies: return L10n("It changes day to day")
        }
    }

    var mode: String {
        switch self {
        case .fullFast, .chore: return "SMALL_FREQUENT"
        case .forgets, .varies: return "NORMAL"
        }
    }
    var drinkableOk: Bool { self == .chore || self == .fullFast }
    var askDaily: Bool { self == .varies }
    /// Small plates, five a day.
    var smallPlates: Bool { mode == "SMALL_FREQUENT" }
}

/// A rough plan, worked out on the phone for the reveal. The server's own
/// number replaces it once the account exists; it uses the same formula.
struct PlanEstimate {
    let dailyKcal: Int
    let proteinG: Int
}

struct OnboardingDraft: Codable {
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
    var preferredDurationWeeks: Int?

    var mealRhythmPreset: MealRhythmPreset = .standard
    var breakfastMin = 480    // 08:00
    var lunchMin = 780        // 13:00
    var dinnerMin = 1140      // 19:00
    var quietStartMin = 1380  // 23:00
    var quietEndMin = 420     // 07:00

    /// How appetite behaves — sets plate size, drinks and the morning ask once the account exists.
    var appetite: AppetiteChoice?

    var restrictions: [String] = []
    var restrictionsFreeText = ""
    /// nil until the first safety card is answered.
    var medicalSupervisionRequired: Bool?
    var scoff = ScoffAnswers()

    var age: Int {
        Calendar.current.dateComponents([.year], from: birthDate, to: .now).year ?? 0
    }

    /// Fill in whatever Apple Health knows, leaving the rest as the user set it.
    mutating func apply(_ profile: HealthProfile) {
        if let height = profile.heightCm { heightCm = height }
        if let weight = profile.weightKg { weightKg = weight }
        if let birthDate = profile.birthDate { self.birthDate = birthDate }
        if let sex = profile.sex { self.sex = sex }
    }

    var isOldEnough: Bool { age >= OnboardingDraft.minimumAge }

    /// SCOFF "yes" answers so far.
    var scoffYesCount: Int {
        [scoff.makeSelfSick, scoff.lostControl, scoff.lostOneStone, scoff.believesFat, scoff.foodDominates]
            .filter { $0 == true }.count
    }

    /// Mirrors the server's safety rule: a medical condition, or two or more SCOFF yeses, turns check-ins off.
    var checkInsLikelyOff: Bool {
        medicalSupervisionRequired == true || scoffYesCount >= 2
    }

    /// Mifflin–St Jeor × activity, plus the goal's daily surplus or deficit (the server's formula).
    func estimatedPlan(paceKgPerWeek: Double) -> PlanEstimate? {
        guard let heightCm, let weightKg else { return nil }
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(age)
        let sexOffset: Double = sex == .male ? 5 : (sex == .female ? -161 : -78)
        let factor: Double
        switch activityLevel {
        case .sedentary: factor = 1.2
        case .light: factor = 1.375
        case .moderate: factor = 1.55
        case .active: factor = 1.725
        case .veryActive: factor = 1.9
        }
        let resolvedGoal = goal ?? .bulk
        let perDay = (abs(paceKgPerWeek) * 7700 / 7).rounded()
        let delta: Double = resolvedGoal == .maintain ? 0 : (resolvedGoal == .bulk ? perDay : -perDay)
        let kcal = max(1200, Int((((base + sexOffset) * factor + delta) / 10).rounded()) * 10)
        let protein: Double
        switch resolvedGoal {
        case .bulk: protein = 1.8
        case .diet: protein = 2.0
        case .maintain: protein = 1.6
        }
        return PlanEstimate(dailyKcal: kcal, proteinG: Int((weightKg * protein).rounded()))
    }

    static let minimumAge = 16

    mutating func applyPreset(_ preset: MealRhythmPreset) {
        mealRhythmPreset = preset
        guard let times = preset.times else { return }
        breakfastMin = times.breakfast
        lunchMin = times.lunch
        dinnerMin = times.dinner
        applyDerivedQuietHours()
    }

    mutating func applyDerivedQuietHours() {
        let quiet = derivedQuietHours(breakfastMin: breakfastMin, dinnerMin: dinnerMin)
        quietStartMin = quiet.start
        quietEndMin = quiet.end
    }

    func toRequest() -> OnboardingRequest {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        df.dateFormat = "yyyy-MM-dd"

        let resolvedGoal = goal ?? .bulk
        let remaining: Double? = {
            guard resolvedGoal.hasWeightTarget, let current = weightKg, let target = targetWeightKg else { return nil }
            return WeightPace.remainingKg(goal: resolvedGoal, currentKg: current, targetKg: target)
        }()
        let resolved = WeightPace.resolve(
            goal: resolvedGoal,
            weightKg: weightKg,
            remainingKg: remaining,
            preferredWeeks: resolvedGoal.hasWeightTarget ? preferredDurationWeeks : nil,
            paceKgPerWeek: pace.kgPerWeek(for: resolvedGoal)
        )

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
            paceKgPerWeek: resolvedGoal.hasWeightTarget ? resolved.paceKgPerWeek : nil,
            preferredDurationWeeks: resolvedGoal.hasWeightTarget ? preferredDurationWeeks : nil,
            mealTimes: .init(breakfastMin: breakfastMin, lunchMin: lunchMin, dinnerMin: dinnerMin),
            quietHours: .init(startMin: quietStartMin, endMin: quietEndMin),
            safety: .init(
                medicalSupervisionRequired: medicalSupervisionRequired ?? false,
                medicalConditionAffectsEating: medicalSupervisionRequired,
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

/// The safety cards, in order: the medical question first, then SCOFF (§3).
enum SafetyQuestion: Int, CaseIterable {
    case medical, makeSelfSick, lostControl, lostOneStone, believesFat, foodDominates

    var text: String {
        switch self {
        case .medical: return L10n( "Do you have a medical condition that affects how you should eat — including eating under a doctor’s or dietitian’s care?")
        case .makeSelfSick: return L10n( "Do you make yourself sick because you feel uncomfortably full?")
        case .lostControl: return L10n( "Do you worry you have lost control over how much you eat?")
        case .lostOneStone:
            // SCOFF's "one stone": 6.35 kg / 14 lb.
            let amount = MassUnit.current == .lb ? L10n("14 lb") : L10n("6 kg")
            return L10n( "Have you recently lost more than \(amount) in a three-month period?")
        case .believesFat: return L10n( "Do you believe yourself to be fat when others say you are too thin?")
        case .foodDominates: return L10n( "Would you say that food dominates your life?")
        }
    }
}

@MainActor
@Observable
final class OnboardingViewModel {
    /// Setup after sign-in (the pitch lives in `WelcomeView`, before it). One
    /// decision per screen; `safety` submits, `reach` and `covered` come after.
    enum Step: Int, CaseIterable {
        /// Questions first, then the plan, then the account: nothing is asked of
        /// the person before they have seen what they get.
        case goal, health, about, target, appetite, training, rhythm, restrictions, safety
        case building, reveal, reach, save, covered
    }

    var step: Step = .goal
    /// Set while the questions run before the story is done with — Back from the
    /// first question returns to it.
    var backToStory: (() -> Void)?
    /// Whether the account exists. Set by the flow; the last step signs in, or
    /// (already signed in) goes straight to saving the plan.
    var signedIn = false
    var draft = OnboardingDraft()
    /// Which safety card is in front.
    var safetyIndex = 0
    var submitting = false
    var result: OnboardingResponse?
    var error: String?
    /// Set by the flow from the live notification status — nothing to ask when
    /// the user has already decided.
    var asksForNotifications = true

    private let api: APIClient
    let onComplete: @MainActor () -> Void

    /// Where in-progress answers are kept between launches. nil (tests,
    /// previews) keeps everything in memory.
    private let progressStore: UserDefaults?

    init(
        api: APIClient,
        progressStore: UserDefaults? = nil,
        onComplete: @escaping @MainActor () -> Void
    ) {
        self.api = api
        self.progressStore = progressStore
        self.onComplete = onComplete
        restoreProgress()
    }

    // MARK: Progress

    /// The steps counted in the setup header.
    var progressSteps: [Step] {
        let all: [Step] = [.goal, .health, .about, .target, .appetite, .training, .rhythm, .restrictions, .safety]
        return draft.goal == .maintain ? all.filter { $0 != .target } : all
    }

    /// The reveal and the notification ask only make sense when check-ins will run.
    var showsPlanAndReach: Bool { !draft.checkInsLikelyOff }

    /// The estimate behind the reveal.
    var estimate: PlanEstimate? {
        draft.estimatedPlan(paceKgPerWeek: resolvedPace.paceKgPerWeek)
    }

    /// 0...1 — how full the ring is once the current step is done.
    var progress: Double {
        let steps = progressSteps
        guard let index = steps.firstIndex(of: step) else { return 1 }
        return Double(index + 1) / Double(steps.count)
    }

    var enforcementEnabled: Bool {
        result?.enforcementDisabledReason == nil
    }

    // MARK: Validation

    var targetWeightIsValid: Bool {
        guard let goal = draft.goal else { return false }
        guard goal.hasWeightTarget else { return true }
        guard draft.weightKg != nil, draft.targetWeightKg != nil else { return false }
        return targetWeightMessage == nil
    }

    /// Why the entered target won't work, or nil when it's fine (or not entered yet).
    var targetWeightMessage: String? {
        guard let goal = draft.goal, goal.hasWeightTarget,
              let current = draft.weightKg, let target = draft.targetWeightKg else { return nil }
        switch goal {
        case .bulk:
            return target > current ? nil : L10n( "Above current weight.")
        case .diet:
            let floor = draft.heightCm.map { HealthyWeight.minKg(heightCm: $0) }
            if let floor, current <= floor {
                return L10n( "At your height, I won't set a lower target. Maintain is the better fit.")
            }
            if target >= current { return L10n( "Below current weight.") }
            if let floor, target < floor { return HealthyWeight.floorMessage(floor) }
            return nil
        case .maintain:
            return nil
        }
    }

    /// Whole weeks to the target at a safe pace, or nil without one.
    var etaWeeks: Int? {
        resolvedPace.preferredDurationWeeks
    }

    var timeframeFit: WeightPace.TimeframeFit {
        guard let goal = draft.goal else { return .ok }
        return WeightPace.timeframeFit(
            goal: goal,
            weightKg: draft.weightKg,
            remainingKg: remainingKg,
            preferredWeeks: draft.preferredDurationWeeks
        )
    }

    /// Why the entered timeframe won't be honored, or nil when it's inside the real cap.
    var durationMessage: String? {
        guard let goal = draft.goal, targetWeightMessage == nil else { return nil }
        return WeightPace.durationMessage(goal: goal, fit: timeframeFit)
    }

    private var remainingKg: Double? {
        guard let goal = draft.goal, goal.hasWeightTarget,
              let current = draft.weightKg, let target = draft.targetWeightKg else { return nil }
        return WeightPace.remainingKg(goal: goal, currentKg: current, targetKg: target)
    }

    private var resolvedPace: (paceKgPerWeek: Double, preferredDurationWeeks: Int?) {
        guard let goal = draft.goal else { return (0, nil) }
        return WeightPace.resolve(
            goal: goal,
            weightKg: draft.weightKg,
            remainingKg: remainingKg,
            preferredWeeks: draft.preferredDurationWeeks,
            paceKgPerWeek: draft.pace.kgPerWeek(for: goal)
        )
    }

    func applyPaceShortcut(_ pace: GoalPace) {
        draft.pace = pace
        guard let goal = draft.goal, let remaining = remainingKg else { return }
        let rate = WeightPace.clampKgPerWeek(goal: goal, weightKg: draft.weightKg, pace: pace.kgPerWeek(for: goal))
        draft.preferredDurationWeeks = WeightPace.etaWeeks(remainingKg: remaining, paceKgPerWeek: rate)
    }

    func setDurationWeeks(_ weeks: Int) {
        draft.preferredDurationWeeks = WeightPace.clampWeeks(weeks)
        guard let goal = draft.goal, let remaining = remainingKg, remaining > 0 else { return }
        draft.pace = GoalPace.closest(toKgPerWeek: remaining / Double(WeightPace.clampWeeks(weeks)), for: goal)
    }

    func proposeDurationIfNeeded() {
        guard draft.preferredDurationWeeks == nil, let remaining = remainingKg else { return }
        let rate = draft.pace.kgPerWeek(for: draft.goal ?? .bulk)
        draft.preferredDurationWeeks = WeightPace.etaWeeks(remainingKg: remaining, paceKgPerWeek: rate)
    }

    var mealAnchorsAreValid: Bool {
        draft.breakfastMin < draft.lunchMin && draft.lunchMin < draft.dinnerMin
    }

    var safetyComplete: Bool {
        draft.medicalSupervisionRequired != nil && draft.scoff.isComplete
    }

    func safetyAnswer(_ question: SafetyQuestion) -> Bool? {
        switch question {
        case .medical: return draft.medicalSupervisionRequired
        case .makeSelfSick: return draft.scoff.makeSelfSick
        case .lostControl: return draft.scoff.lostControl
        case .lostOneStone: return draft.scoff.lostOneStone
        case .believesFat: return draft.scoff.believesFat
        case .foodDominates: return draft.scoff.foodDominates
        }
    }

    // MARK: Navigation

    var canGoBack: Bool {
        guard !submitting else { return false }
        switch step {
        case .goal: return backToStory != nil
        case .building, .covered: return false
        default: return true
        }
    }

    var canAdvance: Bool {
        switch step {
        case .goal: return draft.goal != nil
        case .health: return true
        case .about: return draft.heightCm != nil && draft.weightKg != nil && draft.isOldEnough
        case .target: return targetWeightIsValid
        case .appetite: return draft.appetite != nil
        case .training: return true
        case .rhythm: return draft.mealRhythmPreset != .custom || mealAnchorsAreValid
        case .restrictions: return true
        case .safety: return safetyComplete && !submitting
        case .building, .reveal, .reach, .save, .covered: return true
        }
    }

    /// The step after this one, skipping what doesn't apply.
    private func nextStep(after current: Step) -> Step {
        switch current {
        case .goal: return .health
        case .health: return .about
        case .about: return draft.goal?.hasWeightTarget == true ? .target : .appetite
        case .target: return .appetite
        case .appetite: return .training
        case .training: return .rhythm
        case .rhythm: return .restrictions
        case .restrictions: return .safety
        case .safety: return .building
        case .building: return showsPlanAndReach ? .reveal : .save
        case .reveal: return asksForNotifications ? .reach : .save
        case .reach: return .save
        case .save, .covered: return .covered
        }
    }

    private func previousStep(before current: Step) -> Step? {
        switch current {
        case .goal: return nil
        case .health: return .goal
        case .about: return .health
        case .target: return .about
        case .appetite: return draft.goal?.hasWeightTarget == true ? .target : .about
        case .training: return .appetite
        case .rhythm: return .training
        case .restrictions: return .rhythm
        case .safety: return .restrictions
        case .building: return nil
        case .reveal: return .safety
        case .reach: return .reveal
        case .save: return showsPlanAndReach ? (asksForNotifications ? .reach : .reveal) : .safety
        case .covered: return nil
        }
    }

    func advance() {
        switch step {
        case .save:
            break // the account button moves on
        case .covered:
            onComplete()
        default:
            step = nextStep(after: step)
            saveProgress()
        }
    }

    func goBack() {
        if step == .safety, safetyIndex > 0 {
            safetyIndex -= 1
            saveProgress()
            return
        }
        if step == .goal {
            backToStory?()
            return
        }
        guard let previous = previousStep(before: step) else { return }
        if previous == .safety { safetyIndex = SafetyQuestion.allCases.count - 1 }
        step = previous
        saveProgress()
    }

    /// Answer the card in front; the last answer submits the plan.
    func answerSafety(_ value: Bool) {
        guard let question = SafetyQuestion(rawValue: safetyIndex) else { return }
        switch question {
        case .medical: draft.medicalSupervisionRequired = value
        case .makeSelfSick: draft.scoff.makeSelfSick = value
        case .lostControl: draft.scoff.lostControl = value
        case .lostOneStone: draft.scoff.lostOneStone = value
        case .believesFat: draft.scoff.believesFat = value
        case .foodDominates: draft.scoff.foodDominates = value
        }
        let answeredLast = safetyIndex == SafetyQuestion.allCases.count - 1
        if !answeredLast { safetyIndex += 1 }
        saveProgress()
        if answeredLast, safetyComplete {
            autoAdvance(from: .safety, after: 0.35)
        }
    }

    /// A single-choice screen advances itself shortly after the tap. Guards
    /// against firing if the user has already navigated away.
    func autoAdvance(from origin: Step, after seconds: Double = 0.32) {
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard self.step == origin else { return }
            advance()
        }
    }

    /// Where a saved plan goes after the server answers: the quiet screen when
    /// check-ins are off for this person, otherwise the app opens.
    func stepAfterSubmit(_ response: OnboardingResponse) -> Step {
        response.enforcementDisabledReason == nil ? .save : .covered
    }

    /// True once the plan is saved and the app can open.
    var planSaved = false

    /// Saves the plan to the new account. Safe to call again after a failure.
    func submit() async {
        // Every safety answer is required — never submit a missing one as "no".
        guard !submitting, safetyComplete else { return }
        submitting = true
        error = nil
        defer { submitting = false }
        #if DEBUG
        if previewOnly {
            let response = OnboardingResponse.preview
            result = response
            planSaved = response.enforcementDisabledReason == nil
            step = stepAfterSubmit(response)
            return
        }
        #endif
        do {
            let response: OnboardingResponse = try await api.post("/api/onboarding", draft.toRequest())
            result = response
            if let appetite = draft.appetite {
                // Best effort: the plan is saved either way, and Appetite in Settings can change it.
                _ = try? await api.patch(
                    "/api/settings",
                    SettingsPatch(appetite: .init(mode: appetite.mode, drinkableOk: appetite.drinkableOk, askDaily: appetite.askDaily))
                )
            }
            progressStore.map(Self.clearProgress)
            planSaved = response.enforcementDisabledReason == nil
            step = stepAfterSubmit(response)
        } catch {
            self.error = UserFacingError.message(for: error, fallback: L10n( "Couldn't save. Try again."))
            saveProgress()
        }
    }

    // MARK: Saved progress

    private struct Progress: Codable {
        static let version = 4
        var version = Progress.version
        var step: Int
        var safetyIndex: Int
        var draft: OnboardingDraft
    }

    static let progressKey = "com.setpoint.app.onboarding.progress"

    /// Everything answered so far — goal, body, target, meal times, quiet
    /// hours, restrictions and safety answers — so a relaunch resumes exactly.
    private func saveProgress() {
        guard let progressStore, step != .covered else { return }
        let progress = Progress(step: step.rawValue, safetyIndex: safetyIndex, draft: draft)
        guard let data = try? JSONEncoder().encode(progress) else { return }
        progressStore.set(data, forKey: Self.progressKey)
    }

    /// Whether a previous run left answers behind (the intro skips the story then).
    var hasSavedAnswers: Bool {
        draft.goal != nil || step != .goal
    }

    private func restoreProgress() {
        guard let progressStore,
              let data = progressStore.data(forKey: Self.progressKey),
              let saved = try? JSONDecoder().decode(Progress.self, from: data),
              saved.version == Progress.version
        else { return }
        draft = saved.draft
        var target = Step(rawValue: saved.step) ?? .goal
        // Past the questions, resume at the plan (or the account step, if that was reached).
        if target.rawValue > Step.safety.rawValue { target = saved.step == Step.save.rawValue ? .save : .reveal }
        // Resume at the saved step, but never past one whose answers are missing.
        step = .goal
        while step.rawValue < target.rawValue, step.rawValue < Step.safety.rawValue, canAdvance {
            step = nextStep(after: step)
        }
        if step == .safety {
            // Land on the first unanswered card.
            let firstOpen = SafetyQuestion.allCases.first { safetyAnswer($0) == nil }
            safetyIndex = firstOpen?.rawValue ?? min(saved.safetyIndex, SafetyQuestion.allCases.count - 1)
        }
        // Everything answered: carry on to where they were.
        if step == .safety, safetyComplete, target.rawValue > Step.safety.rawValue {
            step = target == .save ? .save : (showsPlanAndReach ? .reveal : .save)
        }
    }

    static func clearProgress(in store: UserDefaults = .standard) {
        store.removeObject(forKey: progressKey)
        store.removeObject(forKey: "com.setpoint.app.onboarding.snapshot") // v1 format
    }

    #if DEBUG
    /// When true, Safety → next skips the API so a preview can walk the whole flow.
    var previewOnly = false

    static func previewed(
        at step: Step,
        onComplete: @escaping @MainActor () -> Void = {}
    ) -> OnboardingViewModel {
        let vm = OnboardingViewModel(api: AppEnvironment.preview().api, onComplete: onComplete)
        vm.previewOnly = true
        if step != .goal {
            vm.draft.goal = .bulk
            vm.draft.heightCm = 178
            vm.draft.weightKg = 74
            vm.draft.targetWeightKg = 80
            vm.draft.pace = .steady
            vm.draft.appetite = .fullFast
        }
        if step == .safety { vm.safetyIndex = 2 }
        if step.rawValue > Step.safety.rawValue {
            vm.draft.medicalSupervisionRequired = false
            vm.draft.scoff = ScoffAnswers(
                makeSelfSick: false, lostControl: false, lostOneStone: false,
                believesFat: false, foodDominates: false
            )
        }
        if step == .covered { vm.result = .preview }
        vm.step = step
        return vm
    }
    #endif
}

#if DEBUG
extension OnboardingResponse {
    static let preview = OnboardingResponse(
        dailyKcalTarget: 3120, dailyProteinTargetG: 142,
        targetWeightKg: 80, paceKgPerWeek: 0.25,
        enforcementEnabled: true, enforcementDisabledReason: nil
    )
}
#endif

// Raw-value enums: Codable so an in-progress draft can be saved.
extension Goal: Codable {}
extension Sex: Codable {}
extension ActivityLevel: Codable {}
extension GoalPace: Codable {}
extension MealRhythmPreset: Codable {}
