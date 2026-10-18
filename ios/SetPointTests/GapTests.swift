import XCTest
@testable import SetPoint

/// Closing the gap on Today and Week: light meals, the evening close, top-ups.
final class GapTests: XCTestCase {
    private func checkIn(kind: String, slot: String? = "lunch") -> HomeResponse.ActiveCheckIn {
        var ci = HomeResponse.ActiveCheckIn(id: "ci", tier: 1, status: "PENDING", message: nil, deferUntil: nil, prescription: nil)
        ci.slot = slot
        ci.kind = kind
        return ci
    }

    func testCheckInKindsReadAsFlavors() {
        XCTAssertEqual(CheckInFlavor(kind: "MEAL"), .meal)
        XCTAssertEqual(CheckInFlavor(kind: "TOP_UP"), .light)
        XCTAssertEqual(CheckInFlavor(kind: "CLOSE"), .close)
        XCTAssertEqual(CheckInFlavor(kind: "HEADS_UP"), .meal)
    }

    func testLightAndCloseCheckInsTakeOverWithTheirOwnWords() {
        let light = TodayMoment.resolve(.sampleLightCheckIn)
        XCTAssertEqual(light, .checkIn(.lunch, flavor: .light))
        XCTAssertTrue(light.takesOver)
        XCTAssertEqual(TodayCopy.headline(light), "Lunch was light.")
        XCTAssertEqual(TodayCopy.detail(light, home: .sampleLightCheckIn), "880 of 3,100 kcal so far.")

        let close = TodayMoment.resolve(.sampleClose)
        XCTAssertEqual(close, .checkIn(.dinner, flavor: .close))
        XCTAssertEqual(TodayCopy.headline(close), "Close the day.")
        XCTAssertEqual(TodayCopy.whyNow(.sampleClose), "2,220 kcal short · day ends soon")
    }

    func testALightMealKeepsItsSlotOpenOnTheDial() {
        let moment = TodayMoment.resolve(.sampleTopUp)
        XCTAssertEqual(moment, .watching(slot: "lunch", dueMin: 835, overdue: false, light: true))
        XCTAssertEqual(TodayCopy.headline(moment), "Lunch was light.")
        XCTAssertEqual(
            TodayCopy.detail(moment, home: .sampleTopUp),
            "A little more now keeps the day on pace. I’ll check back at \(formatMinutes(835))."
        )
    }

    func testOldPayloadsStillWatchAsBefore() {
        XCTAssertEqual(
            TodayCopy.headline(.watching(slot: "lunch", dueMin: 825, overdue: true)),
            "Lunch slipped."
        )
    }

    func testDecodesTopUpCloseAndWeekGap() throws {
        let json = """
        {
          "slot": "lunch", "behindKcal": 920, "totalKcal": 462, "totalProteinG": 22,
          "logText": "Top-up: 2 × whole milk + almonds",
          "items": [
            {"name": "Whole milk", "servingDesc": "1 cup (240 ml)", "quantity": 2, "kcal": 298, "proteinG": 16, "carbsG": 24, "fatG": 16},
            {"name": "Almonds", "servingDesc": "1 oz (28 g)", "quantity": 1, "kcal": 164, "proteinG": 6, "carbsG": 6, "fatG": 14}
          ]
        }
        """
        let topUp = try JSONDecoder().decode(HomeResponse.TopUp.self, from: Data(json.utf8))
        XCTAssertEqual(topUp.totalKcal, 462)
        XCTAssertEqual(topUp.totalCarbsG, 30, accuracy: 0.01)
        XCTAssertEqual(topUp.totalFatG, 30, accuracy: 0.01)

        let close = try JSONDecoder().decode(HomeResponse.CloseCheckIn.self, from: Data(#"{"dueMin":1230,"gapKcal":700}"#.utf8))
        XCTAssertEqual(close, .init(dueMin: 1230, gapKcal: 700))

        let gap = try JSONDecoder().decode(
            SettlementResponse.Gap.self,
            from: Data(#"{"closedDays":4,"totalDays":6,"avgShortfallKcal":null}"#.utf8)
        )
        XCTAssertEqual(gap, .init(closedDays: 4, totalDays: 6, avgShortfallKcal: nil))
    }

    func testTopUpDismissalIsPerDayAndMeal() {
        let topUp = HomeResponse.sampleTopUp.topUp!
        let day = ISO8601DateFormatter().date(from: "2026-09-10T12:00:00Z")!
        let nextDay = day.addingTimeInterval(86_400)
        XCTAssertNotEqual(TopUpDismissal.key(for: topUp, now: day), TopUpDismissal.key(for: topUp, now: nextDay))
        XCTAssertTrue(TopUpDismissal.key(for: topUp, now: day).hasSuffix(":lunch"))
    }

    func testEveningToGoNamesTheCloseTime() {
        var home = HomeResponse.sampleTopUp
        home.nextCheckIn = nil
        home.closeCheckIn = .init(dueMin: 1230, gapKcal: 700)
        let moment = TodayMoment.resolve(home)
        XCTAssertEqual(moment, .toGo(kcal: 2220))
        XCTAssertEqual(TodayCopy.detail(moment, home: home), "Still short at \(formatMinutes(1230))? I’ll check in then.")
    }
}
