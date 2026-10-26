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

    func testLogMealRequestEncodesCatalogIdAndGrams() throws {
        let req = LogMealRequest(catalogId: "cf_chicken", grams: 85)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(req)) as? [String: Any])
        XCTAssertEqual(json["catalogId"] as? String, "cf_chicken")
        XCTAssertEqual(json["grams"] as? Double, 85)
        XCTAssertNil(json["text"])
        XCTAssertNil(json["barcode"])
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
        let catalog = MealSummary.sample(id: "c", kcal: 140, protein: 26, source: "CATALOG", summary: "Chicken")
        XCTAssertTrue(scanned.isScanned)
        XCTAssertEqual(scanned.sourceLabel, "Scanned")
        XCTAssertFalse(saved.isScanned)
        XCTAssertEqual(saved.sourceLabel, "My meal")
        XCTAssertTrue(catalog.isCatalog)
        XCTAssertEqual(catalog.sourceLabel, "Foods")
    }

    func testCatalogPortionScalesFromPer100g() {
        let food = CatalogFood.sampleChicken
        let one = food.portion(grams: 85)
        XCTAssertEqual(one.grams, 85, accuracy: 0.01)
        XCTAssertEqual(one.kcal, Int((165 * 0.85).rounded()))
        XCTAssertEqual(food.defaultGrams, 85, accuracy: 0.01)
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
        XCTAssertEqual(vm.savedMeals.count, 3)
        XCTAssertEqual(SavedMealShortcuts.logSheet(from: vm.savedMeals).map(\.id), ["sm_oats", "sm_lunch"])
        XCTAssertEqual(vm.savedMeals.first?.suggested, true)
        XCTAssertEqual(vm.recents.count, 5)
        XCTAssertTrue(vm.recents.contains(where: \.isScanned))
    }

    func testLogSheetKeepsOnlyTheTwoMostRecentlyUsedSavedMeals() {
        let older = meal(id: "a", name: "Oats", lastUsedAt: "2026-10-01T08:00:00Z", useCount: 20)
        let newest = meal(id: "b", name: "Lunch box", lastUsedAt: "2026-10-21T12:00:00Z", useCount: 1)
        let unused = meal(id: "c", name: "Shake", lastUsedAt: nil, useCount: 0)
        let middle = meal(id: "d", name: "Eggs", lastUsedAt: "2026-10-18T08:00:00Z", useCount: 4)
        let recent = SavedMealShortcuts.logSheet(from: [older, unused, middle, newest])
        XCTAssertEqual(recent.map(\.id), ["b", "d"])
    }

    private func meal(id: String, name: String, lastUsedAt: String?, useCount: Int) -> SavedMeal {
        .init(
            id: id,
            name: name,
            items: [],
            kcal: 400,
            proteinG: 20,
            carbsG: 40,
            fatG: 10,
            suggestSlot: nil,
            useInCheckIns: false,
            lastUsedAt: lastUsedAt,
            useCount: useCount,
            suggested: false
        )
    }
}
