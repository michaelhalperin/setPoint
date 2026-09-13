import XCTest
@testable import SetPoint

final class OnboardingTests: XCTestCase {
    private func encoded(_ req: OnboardingRequest) throws -> [String: Any] {
        let data = try JSONEncoder().encode(req)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testDraftEncodesToBackendShape() throws {
        var draft = OnboardingDraft()
        draft.goal = .bulk
        draft.hasWearable = true
        draft.heightCm = 182
        draft.weightKg = 79.5
        draft.birthDate = ISO8601DateFormatter().date(from: "1994-05-01T00:00:00Z")!
        draft.restrictions = ["Peanuts", "Dairy"]

        let json = try encoded(draft.toRequest())
        XCTAssertEqual(json["goal"] as? String, "BULK")
        XCTAssertEqual(json["mode"] as? String, "SMART")
        XCTAssertEqual(json["birthDate"] as? String, "1994-05-01")
        XCTAssertEqual(json["heightCm"] as? Double, 182)

        let safety = try XCTUnwrap(json["safety"] as? [String: Any])
        XCTAssertEqual(safety["medicalSupervisionRequired"] as? Bool, false)
        let restrictions = try XCTUnwrap(safety["restrictions"] as? [[String: Any]])
        XCTAssertEqual(restrictions.map { $0["label"] as? String }, ["Peanuts", "Dairy"])
        let scoff = try XCTUnwrap(safety["scoff"] as? [String: Any])
        XCTAssertEqual(scoff["makeSelfSick"] as? Bool, false)
    }

    func testFreeTextOmittedWhenBlank() throws {
        var draft = OnboardingDraft()
        draft.goal = .diet
        draft.restrictionsFreeText = "   "
        let safety = try XCTUnwrap(try encoded(draft.toRequest())["safety"] as? [String: Any])
        XCTAssertNil(safety["restrictionsFreeText"])
    }

    func testScoffCompleteness() {
        var s = ScoffAnswers()
        XCTAssertFalse(s.isComplete)
        s.makeSelfSick = false
        s.lostControl = false
        s.lostOneStone = false
        s.believesFat = false
        XCTAssertFalse(s.isComplete)
        s.foodDominates = true
        XCTAssertTrue(s.isComplete)
    }

    // MARK: Step gating — one decision per screen

    @MainActor
    func testTheSellGatesNothing() {
        let vm = OnboardingViewModel(api: AppEnvironment.preview().api, onComplete: {})
        XCTAssertEqual(vm.step, .hook)
        XCTAssertTrue(vm.canAdvance)
        vm.advance()
        XCTAssertEqual(vm.step, .demo)
        XCTAssertTrue(vm.canAdvance)
        vm.advance()
        XCTAssertEqual(vm.step, .goal)
    }

    @MainActor
    func testGoalGatesUntilChosen() {
        let vm = OnboardingViewModel(api: AppEnvironment.preview().api, onComplete: {})
        vm.step = .goal
        XCTAssertFalse(vm.canAdvance)
        vm.draft.goal = .bulk
        XCTAssertTrue(vm.canAdvance)
    }

    @MainActor
    func testVitalsRequiresHeightAndWeight() {
        let vm = OnboardingViewModel(api: AppEnvironment.preview().api, onComplete: {})
        vm.step = .vitals
        XCTAssertFalse(vm.canAdvance)
        vm.draft.heightCm = 175
        XCTAssertFalse(vm.canAdvance)
        vm.draft.weightKg = 70
        XCTAssertTrue(vm.canAdvance)
    }

    @MainActor
    func testTargetStepGatesOnAValidWeight() {
        let vm = OnboardingViewModel(api: AppEnvironment.preview().api, onComplete: {})
        vm.step = .target
        vm.draft.goal = .bulk
        vm.draft.weightKg = 70
        XCTAssertFalse(vm.canAdvance)             // no target yet
        vm.draft.targetWeightKg = 65
        XCTAssertFalse(vm.canAdvance)              // gain target must be above the baseline
        vm.draft.targetWeightKg = 76
        XCTAssertTrue(vm.canAdvance)
    }

    @MainActor
    func testMaintainSkipsTheTargetStepBothWays() {
        let vm = OnboardingViewModel(api: AppEnvironment.preview().api, onComplete: {})
        vm.draft.goal = .maintain
        vm.step = .vitals
        vm.draft.heightCm = 175
        vm.draft.weightKg = 70
        vm.advance()
        XCTAssertEqual(vm.step, .birthdate)       // .target skipped going forward
        vm.goBack()
        XCTAssertEqual(vm.step, .vitals)          // and skipped coming back
    }

    @MainActor
    func testGainKeepsTheTargetStepInBothDirections() {
        let vm = OnboardingViewModel(api: AppEnvironment.preview().api, onComplete: {})
        vm.draft.goal = .bulk
        vm.step = .vitals
        vm.draft.heightCm = 175
        vm.draft.weightKg = 70
        vm.advance()
        XCTAssertEqual(vm.step, .birthdate)
        vm.advance()
        XCTAssertEqual(vm.step, .sex)
        vm.advance()
        XCTAssertEqual(vm.step, .activity)
        vm.advance()
        XCTAssertEqual(vm.step, .target)
    }

    @MainActor
    func testRhythmGatesOnlyWhenCustomIsInvalid() {
        let vm = OnboardingViewModel(api: AppEnvironment.preview().api, onComplete: {})
        vm.step = .rhythm
        XCTAssertTrue(vm.canAdvance)               // default preset is always valid

        vm.draft.mealRhythmPreset = .custom
        vm.draft.lunchMin = vm.draft.breakfastMin
        XCTAssertFalse(vm.canAdvance)

        vm.draft.lunchMin = 780
        vm.draft.dinnerMin = 700
        XCTAssertFalse(vm.canAdvance)

        vm.draft.dinnerMin = 1140
        XCTAssertTrue(vm.canAdvance)
    }

    @MainActor
    func testSafetyGatesUntilAllFiveAreAnswered() {
        let vm = OnboardingViewModel(api: AppEnvironment.preview().api, onComplete: {})
        vm.step = .safety
        XCTAssertFalse(vm.canAdvance)
        vm.draft.scoff = ScoffAnswers(
            makeSelfSick: false, lostControl: false, lostOneStone: false,
            believesFat: false, foodDominates: false
        )
        XCTAssertTrue(vm.canAdvance)
    }

    @MainActor
    func testReviewGatesOnConsent() {
        let vm = OnboardingViewModel(api: AppEnvironment.preview().api, onComplete: {})
        vm.step = .review
        XCTAssertFalse(vm.canAdvance)
        vm.draft.agreedToTerms = true
        XCTAssertTrue(vm.canAdvance)
    }

    @MainActor
    func testAutoAdvanceOnlyFiresIfStillOnTheOriginatingStep() async {
        let vm = OnboardingViewModel(api: AppEnvironment.preview().api, onComplete: {})
        vm.draft.goal = .bulk
        vm.step = .goal
        vm.autoAdvance(from: .goal, after: 0.05)
        vm.step = .vitals // navigate away before the timer fires
        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(vm.step, .vitals) // unchanged — the stale auto-advance was ignored
    }

    @MainActor
    func testThreadIndexSkipsTheSellAndThePayoff() {
        let vm = OnboardingViewModel(api: AppEnvironment.preview().api, onComplete: {})
        XCTAssertNil(vm.threadIndex) // hook
        vm.step = .demo
        XCTAssertNil(vm.threadIndex)
        vm.step = .goal
        XCTAssertEqual(vm.threadIndex, 0)
        vm.step = .review
        XCTAssertEqual(vm.threadIndex, OnboardingViewModel.threadedSteps.count - 1)
        vm.step = .outcome
        XCTAssertNil(vm.threadIndex)
    }

    @MainActor
    func testGoalStepSendsTargetAndPace() throws {
        let vm = OnboardingViewModel(api: AppEnvironment.preview().api, onComplete: {})
        vm.draft.goal = .diet
        vm.draft.weightKg = 82
        vm.draft.targetWeightKg = 76
        vm.draft.pace = .steady
        let json = try encoded(vm.draft.toRequest())
        XCTAssertEqual(json["targetWeightKg"] as? Double, 76)
        XCTAssertEqual(json["paceKgPerWeek"] as? Double, GoalPace.steady.kgPerWeek(for: .diet))

        vm.draft.goal = .maintain
        XCTAssertNil(try encoded(vm.draft.toRequest())["targetWeightKg"])
    }

    // MARK: Meal rhythm presets

    func testPresetsCarryTheirOwnTimes() {
        XCTAssertEqual(MealRhythmPreset.standard.times.map { [$0.breakfast, $0.lunch, $0.dinner] }, [480, 780, 1140])
        XCTAssertNil(MealRhythmPreset.custom.times)
    }

    func testQuietHoursAreDerivedFromMealTimes() {
        let standard = derivedQuietHours(breakfastMin: 480, dinnerMin: 1140)
        XCTAssertEqual(standard.start, 1380) // 23:00 — matches the old fixed default
        XCTAssertEqual(standard.end, 420)    // 07:00

        let nightOwl = derivedQuietHours(breakfastMin: 600, dinnerMin: 1260)
        XCTAssertEqual(nightOwl.start, 60)   // wraps past midnight: 21:00 + 4h = 01:00
        XCTAssertEqual(nightOwl.end, 540)    // 09:00
    }

    func testClosestPresetMatchesExactTimesOnly() {
        XCTAssertEqual(MealRhythmPreset.closest(breakfast: 480, lunch: 780, dinner: 1140), .standard)
        XCTAssertEqual(MealRhythmPreset.closest(breakfast: 500, lunch: 780, dinner: 1140), .custom)
    }
}
