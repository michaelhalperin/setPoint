import SwiftUI

#if DEBUG

/// An ISO timestamp for today at a local minute of day, so sample meals land in
/// the right place on the dial wherever the preview runs.
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

extension MealSummary {
    /// A photo-logged plate with a breakdown, for the meal sheet stub.
    static let detailSample = MealSummary(
        id: "meal_bowl",
        loggedAt: "2026-10-25T12:40:00.000Z",
        kcal: 742,
        proteinG: 48,
        carbsG: 78,
        fatG: 24,
        source: "PHOTO",
        summary: "Chicken burrito bowl",
        photoUrl: nil,
        notes: "Assumed a regular bowl with one scoop of rice and about 1 tbsp of oil in the chicken.",
        items: [
            .init(name: "Grilled chicken thigh", quantity: "1 portion · ~150 g", kcal: 290, proteinG: 36, carbsG: 0, fatG: 15),
            .init(name: "Cilantro-lime rice", quantity: "1 cup · ~160 g", kcal: 210, proteinG: 4, carbsG: 45, fatG: 2),
            .init(name: "Black beans", quantity: "½ cup · ~90 g", kcal: 120, proteinG: 8, carbsG: 21, fatG: 0.5),
            .init(name: "Pico de gallo", quantity: "3 tbsp · ~50 g", kcal: 12, proteinG: 0.5, carbsG: 2.5, fatG: 0),
            .init(name: "Sour cream", quantity: "1 tbsp · ~15 g", kcal: 30, proteinG: 0.4, carbsG: 0.7, fatG: 3),
            .init(name: "Olive oil (cooking)", quantity: "1 tsp · ~5 g", kcal: 80, proteinG: 0, carbsG: 0, fatG: 9),
        ],
        parseConfidence: 0.78
    )
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
            prescription: samplePrescription,
            slot: "lunch"
        )
    )

    /// Lunch moved earlier for a 12–3 meeting block.
    static var sampleBusy: HomeResponse {
        var home = lateLunch(note: "Eat before the afternoon is locked.", checkIn: nil)
        home.nextCheckIn = .init(slot: "lunch", mealMin: 780, dueMin: 675, overdue: false)
        home.busyBlocks = [.init(startMin: 720, endMin: 900)]
        home.movedSlots = [.init(slot: "lunch", fromMin: 780, toMin: 675)]
        home.day = Day(
            nowMin: 640,
            slots: [
                .init(slot: "breakfast", atMin: 480, state: "logged", mealIds: ["meal_oats", "meal_banana"], kcal: 600),
                .init(slot: "lunch", atMin: 780, state: "upcoming", mealIds: [], kcal: 0),
                .init(slot: "dinner", atMin: 1140, state: "upcoming", mealIds: [], kcal: 0),
            ],
            pace: lateLunchDay.pace
        )
        return home
    }

    static var sampleTraining: HomeResponse {
        var home = lateLunch(note: "Session this afternoon.", checkIn: nil)
        home.training = .init(
            bumpKcal: 350,
            addCalories: true,
            workouts: [.init(id: "w1", kind: "STRENGTH", source: "PLANNED", startMin: 1020, durationMin: 60, activeKcal: 350)],
            refuelUntilMin: 1125
        )
        return home
    }

    static var sampleAppetite: HomeResponse {
        var home = lateLunch(note: "Five lighter meals today.", checkIn: nil)
        home.appetite = .init(
            mode: "SMALL_FREQUENT",
            level: "LOW",
            drinkableOk: true,
            suggestSmallerDefault: true,
            answeredToday: true,
            nextPlate: .init(slot: "lunch", atMin: 780, kcal: 450),
            extraSlots: [
                .init(slot: "snack_am", atMin: 630),
                .init(slot: "snack_pm", atMin: 960),
            ]
        )
        home.nextCheckIn = .init(slot: "lunch", mealMin: 780, dueMin: 825, overdue: true)
        return home
    }

    /// Morning ask — nothing logged, no day answer yet.
    static var sampleAppetiteAsk: HomeResponse {
        var home = sampleEmpty
        home.appetite = .init(
            mode: "NORMAL",
            level: "NORMAL",
            drinkableOk: true,
            suggestSmallerDefault: false,
            answeredToday: false,
            nextPlate: .init(slot: "breakfast", atMin: 480, kcal: 3100),
            extraSlots: []
        )
        return home
    }

    /// Low appetite answered — five slots on the dial, schedule line in the empty log.
    static var sampleAppetiteLow: HomeResponse {
        var home = sampleEmpty
        home.appetite = .init(
            mode: "NORMAL",
            level: "LOW",
            drinkableOk: true,
            suggestSmallerDefault: true,
            answeredToday: true,
            nextPlate: .init(slot: "breakfast", atMin: 480, kcal: 420),
            extraSlots: [
                .init(slot: "snack_am", atMin: 630),
                .init(slot: "snack_pm", atMin: 960),
            ]
        )
        return home
    }

    /// The same check-in, snoozed.
    static let sampleSnoozed = lateLunch(
        note: "There's a check-in waiting just below.",
        checkIn: .init(
            id: "ci_2",
            tier: 2,
            status: "DEFERRED",
            message: "You're well past your usual meal gap. Let's get food in now.",
            deferUntil: ISO8601DateFormatter().string(from: Date.now.addingTimeInterval(75 * 60)),
            prescription: samplePrescription,
            slot: "lunch"
        )
    )

    /// Tier 3 — the conversation, not another prescription.
    static let sampleTalk = lateLunch(
        note: "There's a check-in waiting just below.",
        checkIn: .init(id: "ci_3", tier: 3, status: "PENDING", message: nil, deferUntil: nil, prescription: nil)
    )

    // MARK: Closing the gap

    private static let lightLunchMeals: [MealSummary] = lateLunchMeals + [
        .sample(id: "meal_half", kcal: 280, protein: 14, source: "TEXT", summary: "Half a turkey sandwich", loggedAt: todayAt(790)),
    ]

    private static func lightLunch(checkIn: ActiveCheckIn?, nowMin: Int = 815) -> HomeResponse {
        var home = HomeResponse(
            goal: "BULK",
            mode: "BASIC",
            enforcementEnabled: true,
            ledger: .init(
                consumedKcal: 880,
                targetKcal: 3100,
                remainingKcal: 2220,
                consumedProteinG: 42,
                targetProteinG: 165,
                remainingProteinG: 123,
                mealsToday: 3,
                lastMealAt: todayAt(790)
            ),
            framing: .init(state: "under", accent: true, primaryCta: "log_meal", heroKcal: 2220),
            managerNote: "Dinner can carry more if lunch stays small.",
            meals: lightLunchMeals,
            mealTimes: .standard,
            activeCheckIn: checkIn,
            day: Day(
                nowMin: nowMin,
                slots: [
                    .init(slot: "breakfast", atMin: 480, state: "logged", mealIds: ["meal_oats", "meal_banana"], kcal: 600),
                    .init(slot: "lunch", atMin: 780, state: "logged", mealIds: ["meal_half"], kcal: 280),
                    .init(slot: "dinner", atMin: 1140, state: "upcoming", mealIds: [], kcal: 0),
                ],
                pace: .init(
                    expectedByNowKcal: 1800,
                    behindKcal: 920,
                    status: "behind",
                    next: .init(slot: "dinner", atMin: 1140, suggestedKcal: 2220)
                )
            )
        )
        home.nextCheckIn = checkIn == nil ? .init(slot: "lunch", mealMin: 780, dueMin: 835, overdue: false, light: true) : nil
        return home
    }

    /// A 280 kcal lunch: Today offers a one-tap top-up, and lunch stays open.
    static var sampleTopUp: HomeResponse {
        var home = lightLunch(checkIn: nil)
        let first: [HomeResponse.TopUp.Item] = [
            .init(name: "Olive oil", servingDesc: "1 tbsp (14 g)", quantity: 2, kcal: 238, proteinG: 0, carbsG: 0, fatG: 28, how: "Drizzle it over your plate"),
            .init(name: "Ready protein shake", servingDesc: "1 bottle (325 ml)", quantity: 1, kcal: 160, proteinG: 30, carbsG: 6, fatG: 3, how: "Sip it with the meal"),
        ]
        let second: [HomeResponse.TopUp.Item] = [
            .init(name: "Avocado", servingDesc: "1/2 medium (100 g)", quantity: 1, kcal: 160, proteinG: 2, carbsG: 9, fatG: 15, how: "Slice it onto your plate"),
            .init(name: "Tahini", servingDesc: "2 tbsp (30 g)", quantity: 1, kcal: 178, proteinG: 5, carbsG: 6, fatG: 16, how: "Pour it over your plate"),
        ]
        let third: [HomeResponse.TopUp.Item] = [
            .init(name: "Whole milk", servingDesc: "1 cup (240 ml)", quantity: 2, kcal: 298, proteinG: 16, carbsG: 24, fatG: 16, how: "A glass with the meal"),
        ]
        home.topUp = .init(
            slot: "lunch",
            behindKcal: 1187,
            totalKcal: 398,
            totalProteinG: 30,
            logText: "Top-up: 2 × olive oil + ready protein shake",
            items: first,
            options: [
                .init(totalKcal: 398, totalProteinG: 30, logText: "Top-up: 2 × olive oil + ready protein shake", items: first),
                .init(totalKcal: 338, totalProteinG: 7, logText: "Top-up: Avocado + tahini", items: second),
                .init(totalKcal: 298, totalProteinG: 16, logText: "Top-up: 2 × whole milk", items: third),
            ]
        )
        return home
    }

    /// The light-lunch follow-up check-in.
    static var sampleLightCheckIn: HomeResponse {
        lightLunch(
            checkIn: .init(
                id: "ci_light",
                tier: 1,
                status: "PENDING",
                message: "Lunch was light. Add 2 × 1 cup whole milk + 1 oz almonds to stay on pace.",
                deferUntil: nil,
                prescription: .init(
                    id: "rx_light",
                    totalKcal: 462,
                    totalProteinG: 22,
                    items: [
                        .init(name: "Whole milk", quantity: 2, kcal: 298, proteinG: 16),
                        .init(name: "Almonds", quantity: 1, kcal: 164, proteinG: 6),
                    ]
                ),
                slot: "lunch",
                kind: "TOP_UP"
            ),
            nowMin: 840
        )
    }

    /// 20:35 and the day is still 700 short: the evening close.
    static var sampleClose: HomeResponse {
        var home = lightLunch(
            checkIn: .init(
                id: "ci_close",
                tier: 1,
                status: "PENDING",
                message: "You're 700 kcal short today. A protein shake and granola closes most of it.",
                deferUntil: nil,
                prescription: .init(
                    id: "rx_close",
                    totalKcal: 650,
                    totalProteinG: 38,
                    items: [
                        .init(name: "Ready-to-drink protein shake", quantity: 1, kcal: 160, proteinG: 30),
                        .init(name: "Greek yogurt with granola", quantity: 1, kcal: 350, proteinG: 23),
                        .init(name: "Medjool dates", quantity: 1, kcal: 200, proteinG: 1),
                    ]
                ),
                slot: "dinner",
                kind: "CLOSE"
            ),
            nowMin: 1235
        )
        home.nextCheckIn = nil
        return home
    }

    // MARK: Other days

    /// Mid-afternoon, on pace, dinner next.
    static let sampleOnPace = baseOnPace.withNextCheckIn(.init(slot: "dinner", mealMin: 1140, dueMin: 1185, overdue: false))

    private static let baseOnPace = HomeResponse(
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
    static let sampleMissed = baseMissed.withNextCheckIn(.init(slot: "lunch", mealMin: 780, dueMin: 825, overdue: false))

    private static let baseMissed = HomeResponse(
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
    static let sampleEmpty = baseEmpty.withNextCheckIn(.init(slot: "breakfast", mealMin: 480, dueMin: 525, overdue: false))

    private static let baseEmpty = HomeResponse(
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
    MealDetailSheet(
        meal: .sample(
            id: "meal_1",
            kcal: 820,
            protein: 50,
            source: "PHOTO",
            summary: "Chicken burrito bowl, large"
        ),
        onSaveAsMeal: {}
    )
    .environment(AppEnvironment.preview())
}

extension HomeResponse {
    /// A copy with a scheduled check-in, for previews.
    func withNextCheckIn(_ next: NextCheckIn?) -> HomeResponse {
        var copy = self
        copy.nextCheckIn = next
        return copy
    }
}

#endif
