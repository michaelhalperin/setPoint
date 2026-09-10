import XCTest
@testable import SetPoint

/// The healthy-weight floor on diet targets (BMI 18.5), mirrored from the backend.
@MainActor
final class HealthyWeightTests: XCTestCase {
    func testFloorMatchesTheBackendRounding() {
        XCTAssertEqual(HealthyWeight.minKg(heightCm: 175), 56.7)   // 18.5 × 1.75² = 56.66
        XCTAssertEqual(HealthyWeight.minKg(heightCm: 160), 47.4)   // 18.5 × 1.60² = 47.36
    }

    private func dietDraft(height: Double, weight: Double, target: Double) -> OnboardingViewModel {
        let vm = OnboardingViewModel(api: AppEnvironment.preview().api, onComplete: {})
        vm.draft.goal = .diet
        vm.draft.heightCm = height
        vm.draft.weightKg = weight
        vm.draft.targetWeightKg = target
        return vm
    }

    func testOnboardingBlocksADietTargetBelowTheFloor() {
        let vm = dietDraft(height: 175, weight: 70, target: 52)
        XCTAssertFalse(vm.targetWeightIsValid)
        XCTAssertEqual(vm.targetWeightMessage, "The lowest target I'll set for your height is 56.7 kg.")

        vm.draft.targetWeightKg = 60
        XCTAssertTrue(vm.targetWeightIsValid)
        XCTAssertNil(vm.targetWeightMessage)
    }

    func testOnboardingSteersAnAlreadyLeanDieterToMaintain() {
        let vm = dietDraft(height: 175, weight: 55, target: 50)
        XCTAssertFalse(vm.targetWeightIsValid)
        XCTAssertEqual(vm.targetWeightMessage, "At your height, I won't set a lower target. Maintain is the better fit.")
    }

    func testOnboardingKeepsTheExistingDirectionChecks() {
        let vm = dietDraft(height: 175, weight: 70, target: 72)
        XCTAssertEqual(vm.targetWeightMessage, "Below current weight.")
        vm.draft.goal = .bulk
        vm.draft.targetWeightKg = 65
        XCTAssertEqual(vm.targetWeightMessage, "Above current weight.")
    }

    func testSettingsBlocksSavingATargetBelowTheFloor() {
        let vm = SettingsViewModel.previewed()          // 182 cm → floor 61.3 kg
        XCTAssertFalse(vm.blocksSave)
        vm.goal = .diet
        vm.targetWeightKg = 55
        XCTAssertEqual(vm.targetWeightMessage, "The lowest target I'll set for your height is 61.3 kg.")
        XCTAssertTrue(vm.blocksSave)

        vm.targetWeightKg = 70
        XCTAssertNil(vm.targetWeightMessage)
        XCTAssertFalse(vm.blocksSave)
    }

    func testSettingsResponseDecodesTheFloor() throws {
        let json = """
        {
          "goal": "DIET", "mode": "BASIC", "timezone": "UTC",
          "dailyKcalTarget": 2000, "dailyProteinTargetG": 120,
          "targetWeightKg": 65, "paceKgPerWeek": 0.3, "startWeightKg": 72, "currentWeightKg": 70,
          "heightCm": 170, "minHealthyWeightKg": 53.5,
          "mealTimes": { "breakfastMin": 480, "lunchMin": 780, "dinnerMin": 1140 },
          "quietHours": { "startMin": 1380, "endMin": 420 },
          "checkInsPaused": false, "restrictions": [],
          "enforcementEnabled": true, "enforcementDisabledReason": null
        }
        """.data(using: .utf8)!
        let s = try JSONDecoder().decode(SettingsResponse.self, from: json)
        XCTAssertEqual(s.heightCm, 170)
        XCTAssertEqual(s.minHealthyWeightKg, 53.5)
    }

    func testCrashReportingStaysOffWithoutADSN() {
        XCTAssertNil(CrashReporting.dsn(in: .main))
    }
}
