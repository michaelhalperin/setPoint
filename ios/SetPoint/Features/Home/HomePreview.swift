import SwiftUI

#if DEBUG

/// An ISO timestamp for today at a local minute of day, so sample meals land in
/// the right place on the day track wherever the preview runs.
private func todayAt(_ minute: Int) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: TodayLayout.today(atMin: minute))
}

extension MealSummary {
    static func sample(
        id: String,
        kcal: Int,
        protein: Double,
        source: String,
        summary: String,
        loggedAt: String = "2026-09-08T12:30:00.000Z",
        notes: String? = nil,
        items: [Item] = []
    ) -> MealSummary {
        MealSummary(
            id: id,
            loggedAt: loggedAt,
            kcal: kcal,
            proteinG: protein,
            carbsG: 40,
            fatG: 12,
            source: source,
            summary: summary,
            photoUrl: nil,
            notes: notes,
            items: items,
            parseConfidence: nil
        )
    }
}

extension HomeResponse {
    // MARK: Lunch running late (13:30) — shared by the check-in samples

    private static let lateLunchMeals: [MealSummary] = [
        .sample(id: "meal_oats", kcal: 420, protein: 22, source: "TEXT", summary: "Overnight oats with berries", loggedAt: todayAt(485)),
        .sample(id: "meal_banana", kcal: 180, protein: 6, source: "TEXT", summary: "Coffee and a banana", loggedAt: todayAt(610)),
    ]

    private static let lateLunchDay = Day(
        nowMin: 810,
        slots: [
            .init(slot: "breakfast", atMin: 480, state: "logged", mealIds: ["meal_oats", "meal_banana"], kcal: 600),
            .init(slot: "lunch", atMin: 780, state: "now", mealIds: [], kcal: 0),
            .init(slot: "dinner", atMin: 1140, state: "upcoming", mealIds: [], kcal: 0),
        ],
        pace: .init(
            expectedByNowKcal: 1720,
            behindKcal: 1120,
            status: "behind",
            next: .init(slot: "lunch", atMin: 780, suggestedKcal: 1250)
        )
    )

    private static func lateLunch(note: String, checkIn: ActiveCheckIn?) -> HomeResponse {
        HomeResponse(
            goal: "BULK",
            mode: "SMART",
            enforcementEnabled: true,
            ledger: .init(
                consumedKcal: 600,
                targetKcal: 3100,
                remainingKcal: 2500,
                consumedProteinG: 28,
                targetProteinG: 165,
                remainingProteinG: 137,
                mealsToday: 2,
                lastMealAt: todayAt(610)
            ),
            framing: .init(state: "under", accent: true, primaryCta: "log_meal", heroKcal: 2500),
            managerNote: note,
            meals: lateLunchMeals,
            mealTimes: .standard,
            activeCheckIn: checkIn,
            day: lateLunchDay
        )
    }

    private static let samplePrescription = ActiveCheckIn.Prescription(
        id: "rx_1",
        totalKcal: 670,
        totalProteinG: 44,
        items: [
            .init(name: "Rotisserie chicken", quantity: 1, kcal: 260, proteinG: 35),
            .init(name: "White rice", quantity: 2, kcal: 410, proteinG: 9),
        ]
    )

    /// A tier-2 check-in waiting for an answer.
    static let sampleUnder = lateLunch(
        note: "There's a check-in waiting just below.",
        checkIn: .init(
            id: "ci_1",
            tier: 2,
            status: "PENDING",
            message: "You're well past your usual meal gap. Let's get food in now.",
            deferUntil: nil,
            prescription: samplePrescription
        )
    )

    /// The same check-in, snoozed.
    static let sampleSnoozed = lateLunch(
        note: "There's a check-in waiting just below.",
        checkIn: .init(
            id: "ci_2",
            tier: 2,
            status: "DEFERRED",
            message: "You're well past your usual meal gap. Let's get food in now.",
            deferUntil: ISO8601DateFormatter().string(from: Date.now.addingTimeInterval(75 * 60)),
            prescription: samplePrescription
        )
    )

    /// Tier 3 — the conversation, not another prescription.
    static let sampleTalk = lateLunch(
        note: "There's a check-in waiting just below.",
        checkIn: .init(id: "ci_3", tier: 3, status: "PENDING", message: nil, deferUntil: nil, prescription: nil)
    )

    // MARK: Other days

    /// Mid-afternoon, on pace, dinner next.
    static let sampleOnPace = HomeResponse(
        goal: "BULK",
        mode: "BASIC",
        enforcementEnabled: true,
        ledger: .init(
            consumedKcal: 1600,
            targetKcal: 2600,
            remainingKcal: 1000,
            consumedProteinG: 78,
            targetProteinG: 150,
            remainingProteinG: 72,
            mealsToday: 2,
            lastMealAt: todayAt(765)
        ),
        framing: .init(state: "under", accent: true, primaryCta: "log_meal", heroKcal: 1000),
        managerNote: "Good rhythm so far. Dinner next.",
        meals: [
            .sample(id: "meal_eggs", kcal: 620, protein: 30, source: "TEXT", summary: "Eggs, toast and avocado", loggedAt: todayAt(480)),
            .sample(
                id: "meal_wrap",
                kcal: 980,
                protein: 48,
                source: "PHOTO",
                summary: "Chicken wrap and fruit",
                loggedAt: todayAt(765),
                notes: "Assumed a large wrap with a regular filling.",
                items: [
                    .init(name: "Chicken wrap", quantity: "1 large", kcal: 760, proteinG: 44, carbsG: 62, fatG: 30),
                    .init(name: "Apple", quantity: "1 medium", kcal: 95, proteinG: 0.5, carbsG: 25, fatG: 0.3),
                    .init(name: "Yogurt drink", quantity: "1 bottle", kcal: 125, proteinG: 3.5, carbsG: 20, fatG: 3),
                ]
            ),
        ],
        mealTimes: .standard,
        activeCheckIn: nil,
        day: .init(
            nowMin: 900,
            slots: [
                .init(slot: "breakfast", atMin: 480, state: "logged", mealIds: ["meal_eggs"], kcal: 620),
                .init(slot: "lunch", atMin: 780, state: "logged", mealIds: ["meal_wrap"], kcal: 980),
                .init(slot: "dinner", atMin: 1140, state: "upcoming", mealIds: [], kcal: 0),
            ],
            pace: .init(
                expectedByNowKcal: 1730,
                behindKcal: 130,
                status: "on_pace",
                next: .init(slot: "dinner", atMin: 1140, suggestedKcal: 1000)
            )
        )
    )

    /// Late morning with nothing logged — breakfast passed.
    static let sampleMissed = HomeResponse(
        goal: "BULK",
        mode: "SMART",
        enforcementEnabled: true,
        ledger: .init(
            consumedKcal: 0,
            targetKcal: 3100,
            remainingKcal: 3100,
            consumedProteinG: 0,
            targetProteinG: 165,
            remainingProteinG: 165,
            mealsToday: 0,
            lastMealAt: nil
        ),
        framing: .init(state: "under", accent: true, primaryCta: "log_meal", heroKcal: 3100),
        managerNote: "Nothing logged yet — lunch needs to be a full one.",
        meals: [],
        mealTimes: .standard,
        activeCheckIn: nil,
        day: .init(
            nowMin: 690,
            slots: [
                .init(slot: "breakfast", atMin: 480, state: "missed", mealIds: [], kcal: 0),
                .init(slot: "lunch", atMin: 780, state: "upcoming", mealIds: [], kcal: 0),
                .init(slot: "dinner", atMin: 1140, state: "upcoming", mealIds: [], kcal: 0),
            ],
            pace: .init(
                expectedByNowKcal: 1030,
                behindKcal: 1030,
                status: "behind",
                next: .init(slot: "lunch", atMin: 780, suggestedKcal: 1550)
            )
        )
    )

    /// Early morning, nothing yet.
    static let sampleEmpty = HomeResponse(
        goal: "BULK",
        mode: "SMART",
        enforcementEnabled: true,
        ledger: .init(
            consumedKcal: 0,
            targetKcal: 3100,
            remainingKcal: 3100,
            consumedProteinG: 0,
            targetProteinG: 165,
            remainingProteinG: 165,
            mealsToday: 0,
            lastMealAt: nil
        ),
        framing: .init(state: "under", accent: true, primaryCta: "log_meal", heroKcal: 3100),
        managerNote: "A real breakfast now keeps lunch and dinner ordinary.",
        meals: [],
        mealTimes: .standard,
        activeCheckIn: nil,
        day: .init(
            nowMin: 450,
            slots: [
                .init(slot: "breakfast", atMin: 480, state: "now", mealIds: [], kcal: 0),
                .init(slot: "lunch", atMin: 780, state: "upcoming", mealIds: [], kcal: 0),
                .init(slot: "dinner", atMin: 1140, state: "upcoming", mealIds: [], kcal: 0),
            ],
            pace: .init(
                expectedByNowKcal: 0,
                behindKcal: 0,
                status: "on_pace",
                next: .init(slot: "breakfast", atMin: 480, suggestedKcal: 1050)
            )
        )
    )

    /// Evening, past target — quiet, neutral, nothing to push (§5.2).
    static let sampleOver = HomeResponse(
        goal: "DIET",
        mode: "BASIC",
        enforcementEnabled: true,
        ledger: .init(
            consumedKcal: 2350,
            targetKcal: 2100,
            remainingKcal: -250,
            consumedProteinG: 150,
            targetProteinG: 160,
            remainingProteinG: 10,
            mealsToday: 4,
            lastMealAt: todayAt(1235)
        ),
        framing: .init(state: "over", accent: false, primaryCta: nil, heroKcal: -250),
        managerNote: "A bit past target today. Nothing to fix — steer back tomorrow.",
        meals: [
            .sample(id: "meal_a", kcal: 380, protein: 28, source: "TEXT", summary: "Greek yogurt and honey", loggedAt: todayAt(470)),
            .sample(id: "meal_b", kcal: 640, protein: 42, source: "PHOTO", summary: "Salmon and rice", loggedAt: todayAt(785)),
            .sample(id: "meal_c", kcal: 720, protein: 35, source: "MANUAL", summary: "Pasta with meat sauce", loggedAt: todayAt(1150)),
            .sample(id: "meal_d", kcal: 610, protein: 45, source: "TEXT", summary: "Late snack plate", loggedAt: todayAt(1235)),
        ],
        mealTimes: .standard,
        activeCheckIn: nil,
        day: .init(
            nowMin: 1245,
            slots: [
                .init(slot: "breakfast", atMin: 480, state: "logged", mealIds: ["meal_a"], kcal: 380),
                .init(slot: "lunch", atMin: 780, state: "logged", mealIds: ["meal_b"], kcal: 640),
                .init(slot: "dinner", atMin: 1140, state: "logged", mealIds: ["meal_c", "meal_d"], kcal: 1330),
            ],
            pace: .init(expectedByNowKcal: 2100, behindKcal: 0, status: "on_pace", next: nil)
        )
    )

    /// Quiet mode (screening turned check-ins off): no pace, no Next, no missed meals.
    static let sampleQuiet = HomeResponse(
        goal: "MAINTAIN",
        mode: "BASIC",
        enforcementEnabled: false,
        ledger: .init(
            consumedKcal: 450,
            targetKcal: 2200,
            remainingKcal: 1750,
            consumedProteinG: 24,
            targetProteinG: nil,
            remainingProteinG: nil,
            mealsToday: 1,
            lastMealAt: todayAt(500)
        ),
        framing: .init(state: "under", accent: true, primaryCta: "log_meal", heroKcal: 1750),
        managerNote: "Here's today so far.",  // quiet mode: descriptive only
        meals: [
            .sample(id: "meal_toast", kcal: 450, protein: 24, source: "TEXT", summary: "Toast and eggs", loggedAt: todayAt(500)),
        ],
        mealTimes: .standard,
        activeCheckIn: nil,
        day: .init(
            nowMin: 1000,
            slots: [
                .init(slot: "breakfast", atMin: 480, state: "logged", mealIds: ["meal_toast"], kcal: 450),
                .init(slot: "lunch", atMin: 780, state: "missed", mealIds: [], kcal: 0),
                .init(slot: "dinner", atMin: 1140, state: "upcoming", mealIds: [], kcal: 0),
            ],
            pace: nil
        )
    )
}

#Preview("Meal detail") {
    MealDetailSheet(meal: .sample(
        id: "meal_1",
        kcal: 820,
        protein: 50,
        source: "PHOTO",
        summary: "Chicken burrito bowl, large"
    ))
}

#endif
