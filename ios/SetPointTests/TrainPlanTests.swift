import XCTest
@testable import SetPoint

/// The Train screen's rules, worked out on the phone: they must match the
/// server's (engine/training.ts, training/status.ts).
final class TrainPlanTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Jerusalem")!
        c.firstWeekday = 1
        return c
    }()

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    private func session(_ id: String, _ start: String, _ min: Int = 60, kind: String = "STRENGTH", source: String = "PLANNED", active: Int? = nil, series: String? = nil) -> TrainSession {
        TrainSession(id: id, seriesId: series, kind: kind, source: source, start: date(start), durationMin: min, activeKcal: active)
    }

    func testBumpMatchesServer() {
        // (MET 6 − 1) × 80 kg × 1 h = 400; Apple Health energy wins; capped at 800.
        XCTAssertEqual(TrainMath.bump([session("a", "2026-10-20T14:00:00Z")], weightKg: 80), 400)
        XCTAssertEqual(TrainMath.bump([session("a", "2026-10-20T14:00:00Z", source: "HEALTHKIT", active: 333)], weightKg: 80), 350)
        XCTAssertEqual(TrainMath.bump([session("a", "2026-10-20T14:00:00Z", 180, kind: "CARDIO")], weightKg: 80), 800)
    }

    func testPlannedSessionRecordedByHealthCountsOnce() {
        let planned = session("p", "2026-10-20T14:00:00Z")
        let recorded = session("h", "2026-10-20T14:20:00Z", 50, source: "HEALTHKIT", active: 300)
        XCTAssertEqual(TrainMath.effective([planned, recorded]).map(\.id), ["h"])
        XCTAssertEqual(TrainMath.byDay([planned, recorded], calendar: calendar)["2026-10-20"]?.map(\.id), ["h"])
    }

    func testRefuelStatus() {
        let s = session("a", "2026-10-20T14:00:00Z") // ends 15:00Z
        let meal = TrainMath.Meal(at: date("2026-10-20T15:20:00Z"), kcal: 400)
        XCTAssertEqual(TrainMath.refuel([s], meals: [], now: date("2026-10-20T13:00:00Z")), .planned)
        XCTAssertEqual(TrainMath.refuel([s], meals: [], now: date("2026-10-20T15:30:00Z")), .due)
        XCTAssertEqual(TrainMath.refuel([s], meals: [], now: date("2026-10-20T16:00:00Z")), .missed)
        XCTAssertEqual(TrainMath.refuel([s], meals: [meal], now: date("2026-10-20T16:00:00Z")), .done)
        XCTAssertNil(TrainMath.refuel([], meals: [], now: .now))
    }

    func testStepsTickFromMeals() {
        let s = session("a", "2026-10-20T14:00:00Z")
        let meals = [
            TrainMath.Meal(at: date("2026-10-20T12:30:00Z"), kcal: 200), // snack before
            TrainMath.Meal(at: date("2026-10-20T15:10:00Z"), kcal: 300), // refuel
        ]
        let steps = TrainMath.steps(first: s, dinnerAt: date("2026-10-20T16:30:00Z"), meals: meals, now: date("2026-10-20T15:15:00Z"))
        XCTAssertEqual(steps, TrainMath.Steps(before: true, workout: true, refuel: true, dinner: false))
    }

    func testWeeklyRepeatKeepsClockTimeAcrossDST() {
        // Thursday 18:00 local, clocks go back on 25 Oct 2026.
        let start = date("2026-10-22T15:00:00Z")
        let until = date("2026-11-06T00:00:00Z")
        let starts = TrainMath.weeklyStarts(from: start, until: until, calendar: calendar)
        XCTAssertEqual(starts.count, 3)
        XCTAssertEqual(starts.map { TrainMath.minute($0, calendar: calendar) }, [1080, 1080, 1080])
    }

    func testRepeatOnSeveralWeekdays() {
        // From Thursday 22 Oct 18:00, Mondays and Thursdays until 6 Nov: Thu 22, Mon 26, Thu 29, Mon 2, Thu 5.
        let starts = TrainMath.plannedStarts(from: date("2026-10-22T15:00:00Z"), weekdays: [2, 5], until: date("2026-11-06T00:00:00Z"), calendar: calendar)
        XCTAssertEqual(starts.map { TrainMath.dayKey($0, calendar: calendar) }, ["2026-10-22", "2026-10-26", "2026-10-29", "2026-11-02", "2026-11-05"])
        XCTAssertEqual(Set(starts.map { TrainMath.minute($0, calendar: calendar) }), [1080])
        XCTAssertEqual(TrainMath.plannedStarts(from: date("2026-10-22T15:00:00Z"), weekdays: [], until: .distantFuture, calendar: calendar).count, 1)
    }

    func testMovingFollowingSessions() {
        // Thursdays 18:00 → Fridays 07:00: a later Thursday moves to its Friday at 07:00.
        let moved = TrainMath.moved(date("2026-10-29T16:00:00Z"), from: date("2026-10-22T15:00:00Z"), to: date("2026-10-23T04:00:00Z"), calendar: calendar)
        XCTAssertEqual(moved, date("2026-10-30T05:00:00Z"))
    }

    func testOnlyPlannedSessionsBeforeTheyStartCanBeEdited() {
        let now = date("2026-10-20T12:00:00Z")
        XCTAssertTrue(session("a", "2026-10-20T14:00:00Z").canEdit(now: now))
        XCTAssertFalse(session("a", "2026-10-20T11:30:00Z").canEdit(now: now))
        XCTAssertFalse(session("a", "2026-10-21T14:00:00Z", source: "HEALTHKIT").canEdit(now: now))
    }

    func testTargetOnlyRisesWithAddCalories() {
        XCTAssertEqual(TrainMath.target(base: 3000, bump: 400, addCalories: true), 3400)
        XCTAssertEqual(TrainMath.target(base: 3000, bump: 400, addCalories: false), 3000)
    }

    func testDecodesSessionList() throws {
        let json = """
        {"addCalories":true,"fueledWell":{"good":0,"total":0},"days":[],"horizonDays":56,"weightKg":72.5,
         "sessions":[{"id":"w1","clientId":"c1","seriesId":"s1","kind":"CARDIO","source":"PLANNED","start":"2026-10-21T15:00:00.000Z","durationMin":45,"activeKcal":null}],
         "today":{"baseKcal":3000,"bumpKcal":0,"targetKcal":3000,"workouts":[],"dinnerMin":1140,"timeline":[]}}
        """
        let week = try JSONDecoder().decode(TrainingWeekResponse.self, from: Data(json.utf8))
        XCTAssertEqual(week.sessions?.first?.seriesId, "s1")
        XCTAssertNotNil(TrainingStore.parseDate(week.sessions!.first!.start))
        XCTAssertNil(week.today.snackBefore)
    }

    func testSnackBeforeUsesAUsualPlateThenAStaple() {
        let usual = SavedMeal(
            id: "s1",
            name: "Overnight oats",
            items: [],
            kcal: 310,
            proteinG: 18,
            carbsG: 40,
            fatG: 8,
            suggestSlot: nil,
            useInCheckIns: true,
            lastUsedAt: "2026-10-20T08:00:00Z",
            useCount: 6,
            suggested: false
        )
        let picked = TrainMath.snackBefore(server: nil, saved: [usual], meals: [])
        XCTAssertEqual(picked.name, "Overnight oats")
        XCTAssertEqual(picked.source, "usual")
        XCTAssertTrue(picked.items?.isEmpty ?? true)
        let staple = TrainMath.snackBefore(server: nil, saved: [], meals: [])
        XCTAssertEqual(staple.name, "Greek yogurt")
        XCTAssertEqual(staple.source, "suggested")
        XCTAssertEqual(staple.items?.first?.name, "Greek yogurt")
    }

    func testSnackBeforePrefersALoggedSnackOverASavedPlate() {
        let usual = SavedMeal(
            id: "s1",
            name: "Overnight oats",
            items: [
                MealSummary.Item(name: "Oats", quantity: "1 bowl", kcal: 310, proteinG: 18, carbsG: 40, fatG: 8)
            ],
            kcal: 310,
            proteinG: 18,
            carbsG: 40,
            fatG: 8,
            suggestSlot: nil,
            useInCheckIns: true,
            lastUsedAt: "2026-10-20T08:00:00Z",
            useCount: 6,
            suggested: false
        )
        let logged = MealSummary(
            id: "m1",
            loggedAt: "2026-10-20T15:20:00Z",
            kcal: 240,
            proteinG: 24,
            carbsG: 8,
            fatG: 6,
            source: "TEXT",
            summary: "Cottage cheese",
            photoUrl: nil,
            notes: nil,
            items: [
                MealSummary.Item(name: "Cottage cheese", quantity: "1 cup", kcal: 240, proteinG: 24, carbsG: 8, fatG: 6)
            ],
            parseConfidence: 1
        )
        let picked = TrainMath.snackBefore(server: .init(name: "Overnight oats", kcal: 310, source: "usual"), saved: [usual], meals: [logged])
        XCTAssertEqual(picked.name, "Cottage cheese")
        XCTAssertEqual(picked.source, "history")
        XCTAssertEqual(picked.items?.first?.name, "Cottage cheese")
        XCTAssertEqual(picked.items?.first?.quantity, "1 cup")
    }

    func testSnackBeforeSkipsDislikedFoods() {
        let logged = MealSummary(
            id: "m2",
            loggedAt: "2026-10-20T15:20:00Z",
            kcal: 220,
            proteinG: 20,
            carbsG: 12,
            fatG: 5,
            source: "TEXT",
            summary: "Cottage cheese",
            photoUrl: nil,
            notes: nil,
            items: [
                MealSummary.Item(name: "Cottage cheese", quantity: "1 cup", kcal: 220, proteinG: 24, carbsG: 8, fatG: 6)
            ],
            parseConfidence: 1
        )
        let picked = TrainMath.snackBefore(server: nil, saved: [], meals: [logged], disliked: ["cottage"])
        XCTAssertEqual(picked.source, "suggested")
        XCTAssertEqual(picked.name, "Greek yogurt")
    }

    func testAteTodaySurvivesARelaunch() {
        let snack = TrainingWeekResponse.SnackBefore(
            name: "Greek yogurt",
            kcal: 220,
            source: "suggested",
            proteinG: 20,
            items: [.init(name: "Greek yogurt", quantity: "1 cup", kcal: 220, proteinG: 20)]
        )
        let today = MealSummary(
            id: "m-today",
            loggedAt: "2026-10-21T08:15:00Z",
            kcal: 220,
            proteinG: 20,
            carbsG: 12,
            fatG: 5,
            source: "TEXT",
            summary: "Greek yogurt",
            photoUrl: nil,
            notes: nil,
            items: [
                MealSummary.Item(name: "Greek yogurt", quantity: "1 cup", kcal: 220, proteinG: 20, carbsG: 12, fatG: 5)
            ],
            parseConfidence: 1
        )
        let yesterday = MealSummary(
            id: "m-yday",
            loggedAt: "2026-10-20T08:15:00Z",
            kcal: 220,
            proteinG: 20,
            carbsG: 12,
            fatG: 5,
            source: "TEXT",
            summary: "Greek yogurt",
            photoUrl: nil,
            notes: nil,
            items: nil,
            parseConfidence: 1
        )
        let now = date("2026-10-21T10:00:00Z")
        XCTAssertTrue(TrainMath.ateToday(snack, meals: [today], now: now, calendar: calendar))
        XCTAssertFalse(TrainMath.ateToday(snack, meals: [yesterday], now: now, calendar: calendar))
        XCTAssertFalse(TrainMath.ateToday(snack, meals: [], now: now, calendar: calendar))
    }

    func testDecodesSnackBeforeItems() throws {
        let json = """
        {"name":"Banana + Peanut butter","kcal":180,"source":"history","proteinG":4,
         "items":[{"name":"Banana","quantity":"1","kcal":105,"proteinG":1},
                  {"name":"Peanut butter","quantity":"1 tbsp","kcal":75,"proteinG":3}]}
        """
        let snack = try JSONDecoder().decode(TrainingWeekResponse.SnackBefore.self, from: Data(json.utf8))
        XCTAssertEqual(snack.items?.count, 2)
        XCTAssertEqual(snack.items?.last?.name, "Peanut butter")
    }
}
