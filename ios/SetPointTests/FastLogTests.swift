import XCTest
@testable import SetPoint

final class FastLogTests: XCTestCase {
    func testLogMealRequestEncodesSavedMealIdWithoutText() throws {
        let req = LogMealRequest(savedMealId: "sm_oats", clientId: "7d3f1a52-51c2-4a39-9a7e-0f6c1f1f8b10")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(req)) as? [String: Any])
        XCTAssertEqual(json["savedMealId"] as? String, "sm_oats")
        XCTAssertNil(json["text"])
        XCTAssertNil(json["macros"])
        XCTAssertNil(json["barcode"])
    }

    func testLogMealRequestEncodesBarcodeAndServings() throws {
        let req = LogMealRequest(barcode: "3017620422003", servings: 1.5)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(req)) as? [String: Any])
        XCTAssertEqual(json["barcode"] as? String, "3017620422003")
        XCTAssertEqual(json["servings"] as? Double, 1.5)
        XCTAssertNil(json["text"])
    }

    func testBarcodePortionScalesFromPer100g() {
        let food = BarcodeFood.sampleYogurt
        let one = food.portion(servings: 1)
        XCTAssertEqual(one.grams, 170, accuracy: 0.01)
        XCTAssertEqual(one.kcal, Int((97 * 1.7).rounded()))
        let two = food.portion(servings: 2)
        XCTAssertEqual(two.kcal, Int((97 * 3.4).rounded()))
    }

    func testMealSummaryLabelsScannedAndSavedSources() {
        let scanned = MealSummary.sample(id: "a", kcal: 150, protein: 14, source: "BARCODE", summary: "Yogurt")
        let saved = MealSummary.sample(id: "b", kcal: 420, protein: 18, source: "SAVED", summary: "Oats")
        XCTAssertTrue(scanned.isScanned)
        XCTAssertEqual(scanned.sourceLabel, "Scanned")
        XCTAssertFalse(saved.isScanned)
        XCTAssertEqual(saved.sourceLabel, "My meal")
    }

    func testSavedMealDraftWriteDerivesTotalsFromItems() {
        let draft = SavedMealDraft(from: SavedMeal.samples[0])
        XCTAssertEqual(draft.write?.name, "Usual oats")
        XCTAssertEqual(draft.write?.useInCheckIns, true)
        XCTAssertEqual(draft.write?.suggestSlot, "breakfast")
        XCTAssertEqual(draft.totals.kcal, 420)
    }

    @MainActor
    func testQuickLogPreviewHasSuggestedMealAndRecents() {
        let vm = LogMealViewModel.sampleQuickLog
        XCTAssertEqual(vm.savedMeals.count, 2)
        XCTAssertEqual(vm.savedMeals.first?.suggested, true)
        XCTAssertEqual(vm.recents.count, 2)
        XCTAssertTrue(vm.recents.contains(where: \.isScanned))
    }
}
