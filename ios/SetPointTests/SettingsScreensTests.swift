import XCTest
@testable import SetPoint

@MainActor
final class SettingsScreensTests: XCTestCase {
    func testDirtyFlagsAreIndependent() {
        let vm = SettingsViewModel.previewed()
        XCTAssertFalse(vm.goalDirty)
        XCTAssertFalse(vm.mealTimesDirty)
        XCTAssertFalse(vm.restrictionsDirty)

        vm.applyPaceShortcut(.gentle)
        XCTAssertTrue(vm.goalDirty)
        XCTAssertFalse(vm.mealTimesDirty)
        XCTAssertFalse(vm.restrictionsDirty)

        vm.revertToOriginal()
        vm.mealTimes.lunchMin = 810
        XCTAssertFalse(vm.goalDirty)
        XCTAssertTrue(vm.mealTimesDirty)
        XCTAssertFalse(vm.restrictionsDirty)

        vm.revertToOriginal()
        vm.restrictions.append("Peanuts")
        XCTAssertFalse(vm.goalDirty)
        XCTAssertFalse(vm.mealTimesDirty)
        XCTAssertTrue(vm.restrictionsDirty)
    }

    func testGoalSaveNoteForTargetPaceAndRecalc() {
        let vm = SettingsViewModel.previewed()
        vm.targetWeightKg = 80
        vm.applyPaceShortcut(.gentle)
        XCTAssertEqual(
            vm.goalSaveNote,
            "Target 84 → 80 kg · Timeframe 18 → 4 weeks · Your daily target will be recalculated."
        )
    }

    func testGoalSaveNoteForEditedKcal() {
        let vm = SettingsViewModel.previewed()
        vm.kcalTarget = 2980
        XCTAssertEqual(
            vm.goalSaveNote,
            "Daily target \(3100.formatted()) → \(2980.formatted()) kcal"
        )
    }

    func testMealTimesSaveNote() {
        let vm = SettingsViewModel.previewed()
        vm.mealTimes.lunchMin = 810
        XCTAssertEqual(
            vm.mealTimesSaveNote,
            "Lunch \(formatMinutes(780)) → \(formatMinutes(810))"
        )

        vm.quietHours.startMin = 1350
        vm.quietHours.endMin = 390
        XCTAssertEqual(
            vm.mealTimesSaveNote,
            "Lunch \(formatMinutes(780)) → \(formatMinutes(810)) · Quiet \(formatMinutes(1380))–\(formatMinutes(420)) → \(formatMinutes(1350))–\(formatMinutes(390))"
        )
    }

    func testFoodsSaveNote() {
        let vm = SettingsViewModel.previewed()
        XCTAssertEqual(vm.restrictionsSaveNote, "1 food · applies to your next check-in")
        vm.restrictions = []
        XCTAssertEqual(vm.restrictionsSaveNote, "Nothing avoided")
        vm.restrictions = ["Dairy", "Peanuts"]
        XCTAssertEqual(vm.restrictionsSaveNote, "2 foods · applies to your next check-in")
    }

    func testAddCustomRestrictionTrimsDedupesAndIgnoresEmpty() {
        let vm = SettingsViewModel.previewed()
        XCTAssertEqual(vm.restrictions, ["Dairy"])

        vm.addCustomRestriction("   ")
        XCTAssertEqual(vm.restrictions, ["Dairy"])

        vm.addCustomRestriction("dairy")
        XCTAssertEqual(vm.restrictions, ["Dairy"])

        vm.addCustomRestriction("  Quinoa  ")
        XCTAssertEqual(vm.restrictions, ["Dairy", "Quinoa"])

        vm.addCustomRestriction("quinoa")
        XCTAssertEqual(vm.restrictions, ["Dairy", "Quinoa"])
    }

    func testMealTimeSnapToFifteenMinutes() {
        XCTAssertEqual(MealTimeEditing.snap(480), 480)
        XCTAssertEqual(MealTimeEditing.snap(487), 480)
        XCTAssertEqual(MealTimeEditing.snap(488), 495)
        XCTAssertEqual(MealTimeEditing.snap(7), 0)
        XCTAssertEqual(MealTimeEditing.snap(8), 15)
    }

    func testMealTimeClampKeepsSixtyMinuteGaps() {
        let breakfast = 480, lunch = 780, dinner = 1140
        XCTAssertEqual(
            MealTimeEditing.clamp(800, slot: .breakfast, breakfast: breakfast, lunch: lunch, dinner: dinner),
            720
        )
        XCTAssertEqual(
            MealTimeEditing.clamp(400, slot: .lunch, breakfast: breakfast, lunch: lunch, dinner: dinner),
            540
        )
        XCTAssertEqual(
            MealTimeEditing.clamp(1300, slot: .lunch, breakfast: breakfast, lunch: lunch, dinner: dinner),
            1080
        )
        XCTAssertEqual(
            MealTimeEditing.clamp(700, slot: .dinner, breakfast: breakfast, lunch: lunch, dinner: dinner),
            840
        )
    }

    func testMealTimeClampHonoursBounds() {
        let breakfast = 480, lunch = 780, dinner = 1140
        XCTAssertEqual(
            MealTimeEditing.clamp(200, slot: .breakfast, breakfast: breakfast, lunch: lunch, dinner: dinner),
            240
        )
        XCTAssertEqual(
            MealTimeEditing.clamp(1430, slot: .dinner, breakfast: breakfast, lunch: lunch, dinner: dinner),
            1380
        )
    }
}
