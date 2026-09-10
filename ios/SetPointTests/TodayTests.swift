import XCTest
@testable import SetPoint

final class TodayTests: XCTestCase {
    private func checkIn(tier: Int = 2, status: String = "PENDING") -> HomeResponse.ActiveCheckIn {
        .init(id: "ci", tier: tier, status: status, message: "Eat now.", deferUntil: nil, prescription: nil)
    }

    private func day(status: String = "behind", behind: Int = 600, next: HomeResponse.Day.Next? = nil) -> HomeResponse.Day {
        .init(
            nowMin: 750,
            slots: [
                .init(slot: "breakfast", atMin: 480, state: "logged", mealIds: ["m1"], kcal: 500),
                .init(slot: "lunch", atMin: 780, state: "now", mealIds: [], kcal: 0),
                .init(slot: "dinner", atMin: 1140, state: "upcoming", mealIds: [], kcal: 0),
            ],
            pace: .init(expectedByNowKcal: 1100, behindKcal: behind, status: status, next: next)
        )
    }

    private func home(
        state: String = "under",
        heroKcal: Int = 1200,
        enforcement: Bool = true,
        checkIn: HomeResponse.ActiveCheckIn? = nil,
        day: HomeResponse.Day? = nil
    ) -> HomeResponse {
        HomeResponse(
            goal: "BULK",
            mode: "BASIC",
            enforcementEnabled: enforcement,
            ledger: .init(
                consumedKcal: 3000 - heroKcal, targetKcal: 3000, remainingKcal: heroKcal,
                consumedProteinG: 60, targetProteinG: 160, remainingProteinG: 100,
                mealsToday: 1, lastMealAt: nil
            ),
            framing: .init(state: state, accent: state == "under", primaryCta: nil, heroKcal: heroKcal),
            managerNote: "Note",
            meals: [],
            mealTimes: .standard,
            activeCheckIn: checkIn,
            day: day
        )
    }

    // MARK: Next card

    func testACheckInAlwaysOwnsTheNextCard() {
        XCTAssertEqual(TodayNext.resolve(home(checkIn: checkIn())), .checkIn)
        XCTAssertEqual(TodayNext.resolve(home(checkIn: checkIn(status: "DEFERRED"))), .snoozed)
        XCTAssertEqual(TodayNext.resolve(home(checkIn: checkIn(tier: 3))), .conversation)
    }

    func testUnderTargetPointsAtTheNextMeal() {
        let next = HomeResponse.Day.Next(slot: "lunch", atMin: 780, suggestedKcal: 1200)
        XCTAssertEqual(TodayNext.resolve(home(day: day(next: next))), .meal(.lunch, atMin: 780, suggestedKcal: 1200))
        XCTAssertEqual(TodayNext.resolve(home(heroKcal: 450, day: day(next: nil))), .toGo(kcal: 450))
        XCTAssertEqual(TodayNext.resolve(home(heroKcal: 450, day: nil)), .toGo(kcal: 450))
    }

    func testMetOrPassedTargetIsCoveredAndQuietModeSaysNothing() {
        XCTAssertEqual(TodayNext.resolve(home(state: "on_track", heroKcal: 40)), .covered)
        XCTAssertEqual(TodayNext.resolve(home(state: "over", heroKcal: -250)), .covered)
        XCTAssertEqual(TodayNext.resolve(home(enforcement: false, day: day())), .quiet)
    }

    // MARK: Copy

    func testPaceLineOnlySpeaksWhileThereIsFoodToEat() {
        XCTAssertEqual(TodayCopy.paceLine(home(day: day(status: "behind", behind: 600))), "About 600 kcal behind your usual pace")
        XCTAssertEqual(TodayCopy.paceLine(home(day: day(status: "on_pace"))), "On pace with your usual meals")
        XCTAssertEqual(TodayCopy.paceLine(home(day: day(status: "ahead"))), "Ahead of your usual pace")
        XCTAssertNil(TodayCopy.paceLine(home(state: "over", heroKcal: -250, day: day())))
        XCTAssertNil(TodayCopy.paceLine(home(enforcement: false, day: day())))
        XCTAssertNil(TodayCopy.paceLine(home(day: nil)))
    }

    func testHeroCaptionFollowsTheSign() {
        XCTAssertEqual(TodayCopy.heroCaption(.init(state: "under", accent: true, primaryCta: nil, heroKcal: 900)), "kcal left")
        XCTAssertEqual(TodayCopy.heroCaption(.init(state: "over", accent: false, primaryCta: nil, heroKcal: -250)), "kcal past target")
    }

    // MARK: Layout

    func testTrackSpansTheMealTimesWithAir() {
        let layout = DayTrackLayout(mealTimes: .standard, nowMin: 750)
        XCTAssertEqual(layout.startMin, 390)   // 06:30
        XCTAssertEqual(layout.endMin, 1290)    // 21:30
        XCTAssertEqual(layout.fraction(390), 0)
        XCTAssertEqual(layout.fraction(840), 0.5)
        XCTAssertEqual(layout.fraction(2000), 1)
    }

    func testTrackStretchesToIncludeNow() {
        XCTAssertEqual(DayTrackLayout(mealTimes: .standard, nowMin: 1430).endMin, 1440)
        XCTAssertEqual(DayTrackLayout(mealTimes: .standard, nowMin: 300).startMin, 270)
    }

    func testMealsGroupBySlotInBackendOrder() {
        let meals: [MealSummary] = [
            .init(id: "a", loggedAt: "2026-09-10T08:00:00Z", kcal: 1, proteinG: 0, carbsG: 0, fatG: 0, source: "TEXT", summary: nil, photoUrl: nil, notes: nil, items: nil, parseConfidence: nil),
            .init(id: "b", loggedAt: "2026-09-10T09:00:00Z", kcal: 2, proteinG: 0, carbsG: 0, fatG: 0, source: "TEXT", summary: nil, photoUrl: nil, notes: nil, items: nil, parseConfidence: nil),
        ]
        let slot = HomeResponse.Day.Slot(slot: "breakfast", atMin: 480, state: "logged", mealIds: ["b", "missing", "a"], kcal: 3)
        XCTAssertEqual(TodayLayout.meals(in: slot, from: meals).map(\.id), ["b", "a"])
    }

    func testBackdateLandsOnTodayAtTheMealTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = ISO8601DateFormatter().date(from: "2026-09-10T15:20:00Z")!
        let at = TodayLayout.today(atMin: 480, now: now, calendar: calendar)
        XCTAssertEqual(ISO8601DateFormatter().string(from: at), "2026-09-10T08:00:00Z")
    }

    // MARK: Decoding

    func testHomeDecodesTheDayAndToleratesItsAbsence() throws {
        let base = """
        "goal": "BULK", "mode": "BASIC", "enforcementEnabled": true,
        "ledger": { "consumedKcal": 500, "targetKcal": 3000, "remainingKcal": 2500, "consumedProteinG": 30,
                    "targetProteinG": 160, "remainingProteinG": 130, "mealsToday": 1, "lastMealAt": null },
        "framing": { "state": "under", "accent": true, "primaryCta": "log_meal", "heroKcal": 2500 },
        "managerNote": "Note", "meals": [], "activeCheckIn": null
        """
        let withDay = """
        { \(base), "day": {
            "nowMin": 750,
            "slots": [{ "slot": "breakfast", "atMin": 480, "state": "logged", "mealIds": ["m1"], "kcal": 500 }],
            "pace": { "expectedByNowKcal": 1100, "behindKcal": 600, "status": "behind",
                      "next": { "slot": "lunch", "atMin": 780, "suggestedKcal": 1250 } } } }
        """
        let decoded = try JSONDecoder().decode(HomeResponse.self, from: Data(withDay.utf8))
        XCTAssertEqual(decoded.day?.slots.first?.meal, .breakfast)
        XCTAssertEqual(decoded.day?.slots.first?.slotState, .logged)
        XCTAssertEqual(decoded.day?.pace?.next?.suggestedKcal, 1250)

        let quiet = try JSONDecoder().decode(HomeResponse.self, from: Data("{ \(base), \"day\": { \"nowMin\": 600, \"slots\": [], \"pace\": null } }".utf8))
        XCTAssertNil(quiet.day?.pace)

        let old = try JSONDecoder().decode(HomeResponse.self, from: Data("{ \(base) }".utf8))
        XCTAssertNil(old.day)
    }

    // MARK: Snooze

    func testSnoozeChoicesOnlyOfferTheNextMealWhenItIsFarEnough() {
        XCTAssertEqual(CheckInActions.snoozeChoices(nextMealMinutes: nil).map(\.minutes), [60, 120])
        XCTAssertEqual(CheckInActions.snoozeChoices(nextMealMinutes: 30).map(\.minutes), [60, 120])
        XCTAssertEqual(CheckInActions.snoozeChoices(nextMealMinutes: 200).map(\.minutes), [60, 120, 200])
        XCTAssertEqual(CheckInActions.snoozeChoices(nextMealMinutes: 900).last?.minutes, 360)
    }
}
