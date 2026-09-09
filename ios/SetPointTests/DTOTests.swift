import XCTest
@testable import SetPoint

final class DTOTests: XCTestCase {
    func testHomeResponseDecodes() throws {
        let json = """
        {
          "goal": "BULK",
          "mode": "SMART",
          "enforcementEnabled": true,
          "ledger": {
            "consumedKcal": 1240,
            "targetKcal": 3100,
            "remainingKcal": 1860,
            "consumedProteinG": 72.5,
            "targetProteinG": 165,
            "remainingProteinG": 92.5,
            "mealsToday": 2,
            "lastMealAt": "2026-09-01T15:00:00.000Z"
          },
          "framing": { "state": "under", "accent": true, "primaryCta": "log_meal", "heroKcal": 1860 },
          "managerNote": "About 1,860 kcal to go today.",
          "activeCheckIn": {
            "id": "ci_1", "tier": 2, "status": "PENDING",
            "message": "Let's get food in now.", "deferUntil": null,
            "prescription": {
              "id": "rx_1", "totalKcal": 620, "totalProteinG": 48,
              "items": [{ "name": "White rice", "quantity": 2, "kcal": 410, "proteinG": 9 }]
            }
          }
        }
        """.data(using: .utf8)!

        let home = try JSONDecoder().decode(HomeResponse.self, from: json)
        XCTAssertEqual(home.goal, "BULK")
        XCTAssertEqual(home.ledger.remainingKcal, 1860)
        XCTAssertEqual(home.framing.state, "under")
        XCTAssertTrue(home.framing.accent)
        XCTAssertEqual(home.activeCheckIn?.prescription?.items.first?.name, "White rice")
    }

    func testHomeResponseWithoutOptionalFields() throws {
        let json = """
        {
          "goal": "DIET", "mode": "BASIC", "enforcementEnabled": false,
          "ledger": {
            "consumedKcal": 0, "targetKcal": 2000, "remainingKcal": 2000,
            "consumedProteinG": 0, "targetProteinG": null, "remainingProteinG": null,
            "mealsToday": 0, "lastMealAt": null
          },
          "framing": { "state": "on_track", "accent": false, "primaryCta": null, "heroKcal": 2000 },
          "managerNote": "Right on track.",
          "activeCheckIn": null
        }
        """.data(using: .utf8)!

        let home = try JSONDecoder().decode(HomeResponse.self, from: json)
        XCTAssertNil(home.ledger.targetProteinG)
        XCTAssertNil(home.activeCheckIn)
        XCTAssertNil(home.framing.primaryCta)
    }

    func testAuthResponseDecodes() throws {
        let json = #"{"token":"jwt.abc.def","userId":"u_123"}"#.data(using: .utf8)!
        let auth = try JSONDecoder().decode(AuthResponse.self, from: json)
        XCTAssertEqual(auth.userId, "u_123")
    }
}
