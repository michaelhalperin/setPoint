import SwiftUI

#if DEBUG

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
        managerNote: "About 1,860 kcal to go today. Keep it moving — a solid meal now makes the rest easy.",
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
        activeCheckIn: nil
    )
}

#endif
