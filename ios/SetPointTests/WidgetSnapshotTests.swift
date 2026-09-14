import XCTest
@testable import SetPoint

final class WidgetSnapshotTests: XCTestCase {
    func testSnapshotRoundTripsThroughAppGroup() throws {
        let snap = TodaySnapshot.preview
        snap.save()
        let loaded = TodaySnapshot.load()
        XCTAssertEqual(loaded.remainingKcal, 1240)
        XCTAssertEqual(loaded.nextSlot, "lunch")
        XCTAssertEqual(loaded.savedMeals.map(\.name), ["Usual lunch", "Shake"])
        XCTAssertEqual(loaded.progress, 1880.0 / 3120.0, accuracy: 0.001)
        XCTAssertEqual(loaded.nextLine, "Lunch · 13:45")
    }

    func testYesterdaysSnapshotDoesNotShowAsToday() {
        var snap = TodaySnapshot.preview
        snap.day = "2020-01-01"
        snap.save()
        let loaded = TodaySnapshot.load()
        XCTAssertEqual(loaded.consumedKcal, 0)
        XCTAssertEqual(loaded.remainingKcal, loaded.targetKcal)
        XCTAssertNil(loaded.nextLine)
        XCTAssertEqual(loaded.savedMeals.count, 2)
    }

    func testEmptySnapshotHasNoNextLine() {
        XCTAssertNil(TodaySnapshot.empty.nextLine)
        XCTAssertEqual(TodaySnapshot.empty.progress, 0)
    }
}
