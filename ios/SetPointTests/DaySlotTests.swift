import XCTest
@testable import SetPoint

final class DaySlotTests: XCTestCase {
    private let times = MealTimesPayload.standard // 08:00 / 13:00 / 19:00

    func testSplitsAtMealTimes() {
        // 08:00 breakfast / 13:00 lunch / 19:00 dinner.
        XCTAssertEqual(DaySlot.assigning(minutesFromMidnight: 0, times: times), .breakfast)
        XCTAssertEqual(DaySlot.assigning(minutesFromMidnight: 480, times: times), .breakfast)
        XCTAssertEqual(DaySlot.assigning(minutesFromMidnight: 779, times: times), .breakfast)
        XCTAssertEqual(DaySlot.assigning(minutesFromMidnight: 780, times: times), .lunch)
        XCTAssertEqual(DaySlot.assigning(minutesFromMidnight: 1139, times: times), .lunch)
        XCTAssertEqual(DaySlot.assigning(minutesFromMidnight: 1140, times: times), .dinner)
        XCTAssertEqual(DaySlot.assigning(minutesFromMidnight: 1439, times: times), .dinner)
    }

    func testUsesTheUsersMealTimes() {
        let late = MealTimesPayload(breakfastMin: 600, lunchMin: 840, dinnerMin: 1200) // 10:00 / 14:00 / 20:00
        XCTAssertEqual(DaySlot.assigning(minutesFromMidnight: 780, times: late), .breakfast) // 13:00 still breakfast
        XCTAssertEqual(DaySlot.assigning(minutesFromMidnight: 840, times: late), .lunch)
        XCTAssertEqual(DaySlot.assigning(minutesFromMidnight: 1199, times: late), .lunch)
        XCTAssertEqual(DaySlot.assigning(minutesFromMidnight: 1200, times: late), .dinner)
    }

    func testFirstEmptyWalksTheDay() {
        XCTAssertEqual(DaySlot.firstEmpty(filled: []), .breakfast)
        XCTAssertEqual(DaySlot.firstEmpty(filled: [.breakfast]), .lunch)
        XCTAssertEqual(DaySlot.firstEmpty(filled: [.breakfast, .lunch]), .dinner)
        XCTAssertNil(DaySlot.firstEmpty(filled: [.breakfast, .lunch, .dinner]))
        XCTAssertEqual(DaySlot.firstEmpty(filled: [.lunch]), .breakfast)
    }
}
