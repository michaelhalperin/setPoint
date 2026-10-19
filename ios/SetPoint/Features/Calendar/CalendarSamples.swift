#if DEBUG
import Foundation

extension CalendarChoice {
    static let samples: [CalendarChoice] = [
        .init(id: "work", title: "Work", source: "Google", colorHex: 0x5B7BA6, subscribed: false, eventsThisWeek: 14),
        .init(id: "family", title: "Family", source: "iCloud", colorHex: 0x6E8A67, subscribed: false, eventsThisWeek: 3),
        .init(id: "home", title: "Home", source: "iCloud", colorHex: 0xD5613A, subscribed: false, eventsThisWeek: 2),
        .init(id: "birthdays", title: "Birthdays", source: "Contacts", colorHex: 0xAAA093, subscribed: true, eventsThisWeek: 0),
        .init(id: "holidays", title: "Holidays", source: "Subscribed", colorHex: 0xAAA093, subscribed: true, eventsThisWeek: 0),
    ]
}

extension CalendarPreviewResponse {
    static let sample = CalendarPreviewResponse(
        movedCount: 3,
        moved: [
            .init(date: "2026-09-15", weekday: 2, slot: "lunch", usualMin: 780, atMin: 675),
            .init(date: "2026-09-17", weekday: 4, slot: "dinner", usualMin: 1140, atMin: 1035),
            .init(date: "2026-09-18", weekday: 5, slot: "lunch", usualMin: 780, atMin: 705),
        ]
    )
}

extension CalendarDayEvent {
    static let samples: [String: [CalendarDayEvent]] = [
        "2026-09-14": [
            .init(id: "m1", title: "Design review", calendar: "Work", startMin: 630, endMin: 690, allDay: false),
            .init(id: "m2", title: "Planning", calendar: "Work", startMin: 840, endMin: 960, allDay: false),
        ],
        "2026-09-15": [
            .init(id: "t1", title: "Standup", calendar: "Work", startMin: 570, endMin: 585, allDay: false),
            .init(id: "t2", title: "Client workshop", calendar: "Work", startMin: 720, endMin: 930, allDay: false),
            .init(id: "t3", title: "Dentist", calendar: "Family", startMin: 1050, endMin: 1110, allDay: false),
        ],
    ]
}

extension CalendarWeekResponse {
    private static func meal(
        _ slot: String,
        _ usual: Int,
        status: String = "upcoming",
        moved: Int? = nil,
        busy: Span? = nil,
        logged: Int? = nil,
        kcal: Int? = nil
    ) -> Meal {
        Meal(
            slot: slot,
            usualMin: usual,
            atMin: moved ?? usual,
            moved: moved != nil,
            reason: moved != nil ? "lead" : nil,
            kept: false,
            canKeep: moved != nil,
            earlyMin: moved,
            busy: busy,
            status: status,
            loggedMin: logged,
            kcal: kcal
        )
    }

    private static func block(_ start: Int, _ end: Int, counts: Bool = true) -> Block {
        Block(startMin: start, endMin: end, allDay: false, counts: counts)
    }

    private static func weekday(_ date: String, _ weekday: Int, blocks: [Block] = [], meals: [Meal]) -> Day {
        Day(date: date, weekday: weekday, blocks: blocks, meals: meals)
    }

    /// Monday 14 Sept is today; the workshop moves Tuesday's lunch to 11:15.
    static let sample: CalendarWeekResponse = {
        let workshop = Span(startMin: 720, endMin: 930)
        let days: [Day] = [
            weekday("2026-09-14", 1, blocks: [block(630, 690), block(840, 960)], meals: [
                meal("breakfast", 480, status: "done", logged: 485, kcal: 520),
                meal("lunch", 780),
                meal("dinner", 1140),
            ]),
            weekday("2026-09-15", 2, blocks: [block(570, 585, counts: false), block(720, 930), block(1050, 1110)], meals: [
                meal("breakfast", 480),
                meal("lunch", 780, moved: 675, busy: workshop),
                meal("dinner", 1140),
            ]),
            weekday("2026-09-16", 3, blocks: [block(570, 630)], meals: [
                meal("breakfast", 480), meal("lunch", 780), meal("dinner", 1140),
            ]),
            weekday("2026-09-17", 4, blocks: [block(1080, 1200)], meals: [
                meal("breakfast", 480), meal("lunch", 780),
                meal("dinner", 1140, moved: 1035, busy: .init(startMin: 1080, endMin: 1200)),
            ]),
            weekday("2026-09-18", 5, blocks: [block(750, 840), block(900, 990)], meals: [
                meal("breakfast", 480),
                meal("lunch", 780, moved: 705, busy: .init(startMin: 750, endMin: 840)),
                meal("dinner", 1140),
            ]),
            weekday("2026-09-19", 6, meals: [meal("breakfast", 570), meal("lunch", 810), meal("dinner", 1170)]),
            weekday("2026-09-20", 0, meals: [meal("breakfast", 570), meal("lunch", 810), meal("dinner", 1170)]),
        ]
        return CalendarWeekResponse(
            enabled: true,
            leadMin: 45,
            minBlockMin: 60,
            workdaysOnly: true,
            includeAllDay: false,
            countFree: false,
            today: "2026-09-14",
            days: days,
            movedCount: 3,
            next: Next(date: "2026-09-15", slot: "lunch", usualMin: 780, atMin: 675, earlyMin: 675, kept: false, reason: "lead", busy: workshop)
        )
    }()
}
#endif
