import XCTest
@testable import SetPoint

final class CalendarBusyTests: XCTestCase {
    func testBusyRangeDropsZeroMinutes() {
        XCTAssertEqual(formatBusyRange(720, 900), "12–3")
        XCTAssertEqual(formatBusyRange(690, 815), "11:30–1:35")
    }

    func testHomeDecodesBusyBlocksAndMovedSlots() throws {
        let json = """
        {
          "goal": "BULK",
          "mode": "SMART",
          "enforcementEnabled": true,
          "ledger": {
            "consumedKcal": 600, "targetKcal": 3100, "remainingKcal": 2500,
            "consumedProteinG": 28, "targetProteinG": 165, "remainingProteinG": 137,
            "mealsToday": 2, "lastMealAt": null
          },
          "framing": { "state": "under", "accent": true, "primaryCta": "log_meal", "heroKcal": 2500 },
          "managerNote": "",
          "meals": [],
          "mealTimes": { "breakfastMin": 480, "lunchMin": 780, "dinnerMin": 1140 },
          "activeCheckIn": null,
          "busyBlocks": [{ "startMin": 720, "endMin": 900 }],
          "movedSlots": [{ "slot": "lunch", "fromMin": 780, "toMin": 675 }],
          "nextCheckIn": { "slot": "lunch", "mealMin": 780, "dueMin": 675, "overdue": false }
        }
        """.data(using: .utf8)!
        let home = try JSONDecoder().decode(HomeResponse.self, from: json)
        XCTAssertEqual(home.busyBlocks?.first?.startMin, 720)
        XCTAssertEqual(home.movedSlots?.first?.toMin, 675)
        XCTAssertEqual(home.nextCheckIn?.dueMin, 675)
    }

    func testHomeDecodesTraining() throws {
        let json = """
        {
          "goal": "BULK",
          "mode": "SMART",
          "enforcementEnabled": true,
          "ledger": {
            "consumedKcal": 600, "targetKcal": 3450, "remainingKcal": 2850,
            "consumedProteinG": 28, "targetProteinG": 165, "remainingProteinG": 137,
            "mealsToday": 2, "lastMealAt": null
          },
          "framing": { "state": "under", "accent": true, "primaryCta": "log_meal", "heroKcal": 2850 },
          "managerNote": "",
          "meals": [],
          "mealTimes": { "breakfastMin": 480, "lunchMin": 780, "dinnerMin": 1140 },
          "activeCheckIn": null,
          "training": {
            "bumpKcal": 350,
            "addCalories": true,
            "workouts": [{ "id": "w1", "kind": "STRENGTH", "source": "PLANNED", "startMin": 1020, "durationMin": 60, "activeKcal": 350 }],
            "refuelUntilMin": 1125
          }
        }
        """.data(using: .utf8)!
        let home = try JSONDecoder().decode(HomeResponse.self, from: json)
        XCTAssertEqual(home.training?.bumpKcal, 350)
        XCTAssertEqual(home.training?.workouts.first?.startMin, 1020)
    }
}
