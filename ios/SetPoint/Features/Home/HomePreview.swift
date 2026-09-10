import SwiftUI

#if DEBUG

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
    static let sampleUnder = HomeResponse(
        goal: "BULK",
        mode: "SMART",
        enforcementEnabled: true,
        ledger: .init(
            consumedKcal: 1240,
            targetKcal: 3100,
            remainingKcal: 1860,
            consumedProteinG: 72,
            targetProteinG: 165,
            remainingProteinG: 93,
            mealsToday: 2,
            lastMealAt: nil
        ),
        framing: .init(state: "under", accent: true, primaryCta: "log_meal", heroKcal: 1860),
        managerNote: "About 1,860 kcal to go. Dinner around 950 kcal keeps the rest easy.",
        meals: [
            .sample(id: "meal_1", kcal: 420, protein: 22, source: "TEXT", summary: "Overnight oats with berries", loggedAt: "2026-09-08T12:10:00.000Z"),
            .sample(id: "meal_2", kcal: 820, protein: 50, source: "PHOTO", summary: "Chicken burrito bowl, large", loggedAt: "2026-09-08T16:40:00.000Z", notes: "Assumed a regular-size bowl with one scoop of rice.", items: [
                .init(name: "Grilled chicken", quantity: "1 serving", kcal: 280, proteinG: 32, carbsG: 2, fatG: 9),
                .init(name: "Cilantro-lime rice", quantity: "1 cup", kcal: 208, proteinG: 4, carbsG: 44, fatG: 3),
                .init(name: "Black beans", quantity: "1 scoop", kcal: 150, proteinG: 5, carbsG: 22, fatG: 2),
            ]),
        ],
        mealTimes: .standard,
        activeCheckIn: .init(
            id: "ci_1",
            tier: 2,
            status: "PENDING",
            message: "You're well past your usual meal gap. Let's get food in now.",
            deferUntil: nil,
            prescription: .init(
                id: "rx_1",
                totalKcal: 620,
                totalProteinG: 48,
                items: [
                    .init(name: "Rotisserie chicken", quantity: 1, kcal: 260, proteinG: 35),
                    .init(name: "White rice", quantity: 2, kcal: 410, proteinG: 9),
                ]
            )
        )
    )

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
            lastMealAt: nil
        ),
        framing: .init(state: "over", accent: false, primaryCta: nil, heroKcal: -250),
        managerNote: "A bit past target today. Nothing to fix — just steer back tomorrow.",
        meals: [
            .sample(id: "meal_a", kcal: 380, protein: 28, source: "TEXT", summary: "Greek yogurt and honey"),
            .sample(id: "meal_b", kcal: 640, protein: 42, source: "PHOTO", summary: "Salmon and rice"),
            .sample(id: "meal_c", kcal: 720, protein: 35, source: "MANUAL", summary: "Pasta with meat sauce"),
            .sample(id: "meal_d", kcal: 610, protein: 45, source: "TEXT", summary: "Late snack plate"),
        ],
        mealTimes: .standard,
        activeCheckIn: nil
    )

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
        managerNote: "About 3,100 kcal today. A real breakfast around 1,050 kcal keeps lunch and dinner ordinary.",
        meals: [],
        mealTimes: .standard,
        activeCheckIn: nil
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
