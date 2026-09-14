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
        day: HomeResponse.Day? = nil,
        next: HomeResponse.NextCheckIn? = nil,
        lastMealAt: String? = nil
    ) -> HomeResponse {
        HomeResponse(
            goal: "BULK",
            mode: "BASIC",
            enforcementEnabled: enforcement,
            ledger: .init(
                consumedKcal: 3000 - heroKcal, targetKcal: 3000, remainingKcal: heroKcal,
                consumedProteinG: 60, targetProteinG: 160, remainingProteinG: 100,
                mealsToday: 1, lastMealAt: lastMealAt
            ),
            framing: .init(state: state, accent: state == "under", primaryCta: nil, heroKcal: heroKcal),
            managerNote: "Note",
            meals: [],
            mealTimes: .standard,
            activeCheckIn: checkIn,
            day: day,
            nextCheckIn: next
        )
    }

    // MARK: Moment

    private func next(_ slot: String = "lunch", due: Int = 825, overdue: Bool = false) -> HomeResponse.NextCheckIn {
        .init(slot: slot, mealMin: due - 45, dueMin: due, overdue: overdue)
    }

    func testACheckInTakesOverToday() {
        var pending = checkIn()
        pending.slot = "lunch"
        XCTAssertEqual(TodayMoment.resolve(home(checkIn: pending)), .checkIn(.lunch))
        XCTAssertTrue(TodayMoment.resolve(home(checkIn: pending)).takesOver)
        XCTAssertEqual(TodayMoment.resolve(home(checkIn: checkIn(tier: 3))), .conversation)
        XCTAssertEqual(TodayMoment.resolve(home(checkIn: checkIn(status: "DEFERRED"))), .snoozed(until: nil))
        XCTAssertFalse(TodayMoment.resolve(home(checkIn: checkIn(status: "DEFERRED"))).takesOver)
    }

    func testUnderTargetWatchesTheNextCheckIn() {
        XCTAssertEqual(TodayMoment.resolve(home(next: next())), .watching(.lunch, dueMin: 825, overdue: false))
        XCTAssertEqual(TodayMoment.resolve(home(heroKcal: 450)), .toGo(kcal: 450)) // nothing scheduled
    }

    func testMetTargetIsCoveredAndQuietModeSaysNothing() {
        XCTAssertEqual(TodayMoment.resolve(home(state: "on_track", heroKcal: 40, next: next())), .covered)
        XCTAssertEqual(TodayMoment.resolve(home(state: "over", heroKcal: -250)), .covered)
        XCTAssertEqual(TodayMoment.resolve(home(enforcement: false, day: day())), .quiet)
    }

    // MARK: Copy

    func testHeadlinesStayShort() {
        XCTAssertEqual(TodayCopy.headline(.watching(.lunch, dueMin: 825, overdue: false)), "Lunch is next.")
        XCTAssertEqual(TodayCopy.headline(.checkIn(.dinner)), "Dinner slipped.")
        XCTAssertEqual(TodayCopy.headline(.checkIn(nil)), "Time to eat.")
        XCTAssertEqual(TodayCopy.headline(.covered), "Day covered.")
    }

    func testSinceLastMealOnlyCountsToday() {
        let now = ISO8601DateFormatter().date(from: "2026-09-10T15:20:00Z")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(TodayCopy.sinceLastMeal(home(lastMealAt: "2026-09-09T20:00:00Z"), now: now, calendar: calendar), "Nothing logged yet today.")
        XCTAssertTrue(TodayCopy.sinceLastMeal(home(lastMealAt: "2026-09-10T08:05:00Z"), now: now, calendar: calendar).hasPrefix("Nothing since"))
    }

    func testDialStatesComeFromTheDay() {
        let states = TodayCopy.dialStates(home(day: day()))
        XCTAssertEqual(states[.breakfast], .logged)
        XCTAssertEqual(states[.lunch], .now)
        XCTAssertEqual(states[.dinner], .upcoming)
    }

    func testMealsGroupBySlotInBackendOrder() {
        let meals: [MealSummary] = [
            .init(id: "a", loggedAt: "2026-09-10T08:00:00Z", kcal: 1, proteinG: 0, carbsG: 0, fatG: 0, source: "TEXT", summary: nil, photoUrl: nil, notes: nil, items: nil, parseConfidence: nil),
            .init(id: "b", loggedAt: "2026-09-10T09:00:00Z", kcal: 2, proteinG: 0, carbsG: 0, fatG: 0, source: "TEXT", summary: nil, photoUrl: nil, notes: nil, items: nil, parseConfidence: nil),
        ]
        let slot = HomeResponse.Day.Slot(slot: "breakfast", atMin: 480, state: "logged", mealIds: ["b", "missing", "a"], kcal: 3)
        XCTAssertEqual(TodayLayout.meals(in: slot, from: meals).map(\.id), ["b", "a"])
    }

    func testSlotUsesHalfwayBoundaries() {
        let times = MealTimesPayload.standard // 08:00 / 13:00 / 19:00 → 10:30 and 16:00
        XCTAssertEqual(TodayLayout.slot(forMinute: 600, times: times), .breakfast) // 10:00
        XCTAssertEqual(TodayLayout.slot(forMinute: 770, times: times), .lunch)     // 12:50
        XCTAssertEqual(TodayLayout.slot(forMinute: 900, times: times), .lunch)     // 15:00
        XCTAssertEqual(TodayLayout.slot(forMinute: 990, times: times), .dinner)    // 16:30
    }

    func testInsertingAMealLandsInTheSlotWithoutWaitingOnReload() {
        let before = home(day: day())
        let meal = MealSummary(
            id: "new", loggedAt: "2026-09-10T08:00:00Z", kcal: 420, proteinG: 22,
            carbsG: 40, fatG: 12, source: "TEXT", summary: "Oats", photoUrl: nil,
            notes: nil, items: nil, parseConfidence: nil
        )
        let after = before.inserting(meal, into: .breakfast)
        XCTAssertEqual(after.meals.map(\.id), ["new"])
        XCTAssertEqual(after.day?.slots[0].state, "logged")
        XCTAssertEqual(after.day?.slots[0].mealIds, ["m1", "new"])
        XCTAssertEqual(after.day?.slots[0].kcal, 920)
        XCTAssertEqual(after.ledger.consumedKcal, before.ledger.consumedKcal + 420)
        XCTAssertEqual(after.ledger.mealsToday, before.ledger.mealsToday + 1)
        XCTAssertEqual(after.inserting(meal, into: .breakfast).meals.count, 1)
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
        XCTAssertEqual(CheckInActions.snoozeChoices(nextMealMinutes: nil).map(\.title), ["1 hour", "2 hours"])
        XCTAssertEqual(CheckInActions.snoozeChoices(nextMealMinutes: nil).map(\.minutes), [60, 120])
        XCTAssertEqual(CheckInActions.snoozeChoices(nextMealMinutes: 30).map(\.minutes), [60, 120])
        XCTAssertEqual(CheckInActions.snoozeChoices(nextMealMinutes: 200).map(\.minutes), [60, 120, 200])
        XCTAssertEqual(CheckInActions.snoozeChoices(nextMealMinutes: 900).last?.minutes, 360)
        XCTAssertTrue(CheckInActions.snoozeChoices(nextMealMinutes: 200).last?.title.hasPrefix("After ") == true)
    }

    // MARK: Again?

    @MainActor
    func testRecentsAreNewestFirstOneEachAndNamed() {
        func meal(_ id: String, _ at: String, _ summary: String?) -> MealSummary {
            .init(id: id, loggedAt: at, kcal: 500, proteinG: 30, carbsG: 40, fatG: 10, source: "TEXT",
                  summary: summary, photoUrl: nil, notes: nil, items: nil, parseConfidence: nil)
        }
        let recents = LogMealViewModel.distinctRecents([
            meal("a", "2026-09-13T08:00:00Z", "Oats"),
            meal("b", "2026-09-14T08:00:00Z", "oats"),
            meal("c", "2026-09-14T12:00:00Z", "Chicken wrap"),
            meal("d", "2026-09-14T13:00:00Z", nil),
        ])
        XCTAssertEqual(recents.map(\.id), ["c", "b"])
    }
}
