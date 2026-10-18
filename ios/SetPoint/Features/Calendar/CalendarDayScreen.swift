import SwiftUI

// MARK: B2 · Day

/// One day: events with titles (read on this phone only), where each meal lands,
/// and why a moved meal moved.
struct CalendarDayView: View {
    @State var date: String

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let calendar = env.calendar
        let week = calendar.week
        let day = week?.day(date)
        let weekday = day?.weekday ?? CalendarDates.date(date).map { Calendar.current.component(.weekday, from: $0) - 1 } ?? 1
        let events = dayEvents(day: day)

        SettingsScreen(
            title: CalendarDates.longWeekday(weekday),
            subtitle: "Titles show on this phone only.",
            accessory: AnyView(pager(week))
        ) {
            VStack(alignment: .leading, spacing: 16) {
                allDayChips(events.filter(\.allDay), weekday: weekday)
                CalendarDayTimeline(
                    events: events.filter { !$0.allDay },
                    meals: day?.meals ?? [],
                    nowMin: date == week?.today ? nowMin : nil,
                    verdict: { verdict($0, weekday: weekday) }
                )
                .appearIn(2)
                if let day, let meal = day.meals.first(where: \.canKeep), let busy = meal.busy, let early = meal.earlyMin {
                    whyCard(day: day, meal: meal, busy: busy, earlyMin: early, events: events, today: week?.today ?? date)
                        .appearIn(3)
                }
            }
        }
        .animation(.default, value: date)
    }

    private var nowMin: Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: .now)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// Titles from EventKit when we have them; otherwise the uploaded busy blocks, untitled.
    private func dayEvents(day: CalendarWeekResponse.Day?) -> [CalendarDayEvent] {
        let local = env.calendar.events(on: date)
        if !local.isEmpty { return local }
        return (day?.blocks ?? []).enumerated().map { index, block in
            CalendarDayEvent(
                id: "block-\(index)",
                title: "Busy",
                calendar: "",
                startMin: block.startMin,
                endMin: block.endMin,
                allDay: block.allDay
            )
        }
    }

    private func verdict(_ event: CalendarDayEvent, weekday: Int) -> CalendarRules.Verdict {
        CalendarRules.verdict(
            durationMin: event.endMin - event.startMin,
            allDay: event.allDay,
            weekday: weekday,
            minBlockMin: env.calendar.minBlockMin,
            workdaysOnly: env.calendar.workdaysOnly,
            includeAllDay: env.calendar.includeAllDay
        )
    }

    private func pager(_ week: CalendarWeekResponse?) -> some View {
        let dates = week?.days.map(\.date) ?? []
        let index = dates.firstIndex(of: date)
        let previous = index.flatMap { $0 > 0 ? dates[$0 - 1] : nil }
        let next = index.flatMap { $0 < dates.count - 1 ? dates[$0 + 1] : nil }
        return HStack(spacing: 8) {
            pagerButton("arrow.left", label: "Previous day", target: previous)
            pagerButton("arrow.right", label: "Next day", target: next)
        }
    }

    private func pagerButton(_ symbol: String, label: String, target: String?) -> some View {
        Button {
            if let target { date = target }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(target == nil ? Palette.inkFaint : Palette.ink)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.06), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(target == nil)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private func allDayChips(_ events: [CalendarDayEvent], weekday: Int) -> some View {
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(events) { event in
                    let counts = verdict(event, weekday: weekday) == .counts
                    HStack(spacing: 10) {
                        BusyHatch(cornerRadius: 6, faded: !counts).frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(event.title)
                                .font(Typography.data(14, weight: .bold))
                                .foregroundStyle(counts ? Palette.ink : Palette.inkSoft)
                            Text(CalendarRules.label(verdict(event, weekday: weekday)) ?? "All day · counts as busy")
                                .font(Typography.data(12))
                                .foregroundStyle(Palette.inkSoft)
                        }
                    }
                }
            }
        }
    }

    private func whyCard(
        day: CalendarWeekResponse.Day,
        meal: CalendarWeekResponse.Meal,
        busy: CalendarWeekResponse.Span,
        earlyMin: Int,
        events: [CalendarDayEvent],
        today: String
    ) -> some View {
        let name = events.first { !$0.allDay && $0.startMin == busy.startMin && $0.title != "Busy" }?.title
        let actionable = day.date >= today && meal.status == "upcoming"
        return SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Palette.ember)
                        .frame(width: 32, height: 32)
                        .background(Palette.ember.opacity(0.12), in: Circle())
                    Text(meal.kept
                        ? "\(CalendarCopy.slotName(meal.slot)) kept at \(CalendarClock.hm(meal.usualMin))"
                        : "Why \(CalendarClock.hm(earlyMin))?")
                        .font(Typography.data(17, weight: .bold))
                        .foregroundStyle(Palette.ink)
                }
                Text(CalendarCopy.why(
                    eventName: name,
                    slot: meal.slot,
                    busy: busy,
                    earlyMin: earlyMin,
                    usualMin: meal.usualMin,
                    reason: meal.reason,
                    kept: meal.kept,
                    leadMin: env.calendar.leadMin
                ))
                .font(Typography.data(14))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                if actionable {
                    CalendarKeepButton(
                        style: .chip,
                        slot: meal.slot,
                        keep: !meal.kept,
                        usualMin: meal.usualMin,
                        earlyMin: earlyMin
                    ) {
                        await env.calendar.setKeep(date: day.date, slot: meal.slot, keep: !meal.kept)
                    }
                }
                if let message = env.calendar.lastError {
                    SettingsErrorBanner(message: message)
                }
            }
        }
    }
}

struct CalendarDayTimeline: View {
    let events: [CalendarDayEvent]
    let meals: [CalendarWeekResponse.Meal]
    let nowMin: Int?
    let verdict: (CalendarDayEvent) -> CalendarRules.Verdict

    private let perHour: CGFloat = 44
    private let labelWidth: CGFloat = 50

    private var range: (start: Int, end: Int) {
        var minutes = events.flatMap { [$0.startMin, $0.endMin] }
        for meal in meals {
            minutes.append(meal.atMin)
            minutes.append(meal.usualMin)
            if let logged = meal.loggedMin { minutes.append(logged) }
        }
        let low = min(8 * 60, minutes.min() ?? 8 * 60)
        let high = max(20 * 60, minutes.max() ?? 20 * 60)
        let start = max(0, low / 120 * 120)
        let end = min(1440, (high + 119) / 120 * 120)
        return (start, end)
    }

    private var height: CGFloat { CGFloat(range.end - range.start) / 60 * perHour }

    private func y(_ minute: Int) -> CGFloat {
        CGFloat(minute - range.start) / 60 * perHour
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ZStack(alignment: .topLeading) {
                ForEach(Array(stride(from: range.start, through: range.end, by: 120)), id: \.self) { minute in
                    Text(CalendarClock.hm(minute))
                        .font(Typography.data(11, weight: .semibold))
                        .foregroundStyle(Palette.inkFaint)
                        .monospacedDigit()
                        .offset(y: y(minute) - 7)
                }
            }
            .frame(width: labelWidth, height: height, alignment: .topLeading)

            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .topLeading) {
                    ForEach(Array(stride(from: range.start, through: range.end, by: 120)), id: \.self) { minute in
                        Rectangle().fill(Palette.hairline).frame(height: 1).offset(y: y(minute))
                    }
                    ForEach(Array(laidOut.enumerated()), id: \.element.event.id) { _, item in
                        eventBlock(item.event, indent: item.indent, width: width * 0.62)
                    }
                    ForEach(meals) { meal in
                        mealMarkers(meal, width: width)
                    }
                    if let nowMin, nowMin >= range.start, nowMin <= range.end {
                        HStack(spacing: 0) {
                            Circle().fill(Palette.ink).frame(width: 9, height: 9)
                            Rectangle().fill(Palette.ink).frame(height: 1.5)
                        }
                        .offset(x: -4, y: y(nowMin) - 4.5)
                        .accessibilityLabel("Now, \(CalendarClock.hm(nowMin))")
                    }
                }
            }
            .frame(height: height)
        }
        .padding(.vertical, 24)
    }

    /// Overlapping events step right so both stay readable.
    private var laidOut: [(event: CalendarDayEvent, indent: CGFloat)] {
        var result: [(CalendarDayEvent, CGFloat)] = []
        for event in events.sorted(by: { $0.startMin < $1.startMin }) {
            let overlaps = result.filter { $0.0.endMin > event.startMin }.count
            result.append((event, CGFloat(min(overlaps, 2)) * 14))
        }
        return result.map { (event: $0.0, indent: $0.1) }
    }

    private func eventBlock(_ event: CalendarDayEvent, indent: CGFloat, width: CGFloat) -> some View {
        let verdict = verdict(event)
        let counts = verdict == .counts
        let top = y(max(event.startMin, range.start))
        let blockHeight = max(22, y(min(event.endMin, range.end)) - top)
        let detail = CalendarRules.label(verdict)
            ?? [event.calendar, CalendarClock.range(event.startMin, event.endMin)].filter { !$0.isEmpty }.joined(separator: " · ")
        return ZStack(alignment: blockHeight > 60 ? .center : .leading) {
            BusyHatch(cornerRadius: 12, faded: !counts)
            let layout = blockHeight >= 34 ? AnyLayout(VStackLayout(alignment: .leading, spacing: 1)) : AnyLayout(HStackLayout(spacing: 6))
            layout {
                Text(event.title)
                    .font(Typography.data(13, weight: .bold))
                    .foregroundStyle(counts ? Palette.ink : Palette.inkFaint)
                    .lineLimit(1)
                Text(detail)
                    .font(Typography.data(11))
                    .foregroundStyle(counts ? Palette.inkSoft : Palette.inkFaint)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
        }
        .frame(width: width - indent, height: blockHeight)
        .offset(x: 8 + indent, y: top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(event.title), \(CalendarClock.range(event.startMin, event.endMin))\(CalendarRules.label(verdict).map { ", \($0)" } ?? "")")
    }

    @ViewBuilder
    private func mealMarkers(_ meal: CalendarWeekResponse.Meal, width: CGFloat) -> some View {
        let name = CalendarCopy.slotName(meal.slot)
        switch (meal.status, meal.moved, meal.kept) {
        case ("done", _, _):
            marker(title: name, detail: [meal.loggedMin.map(CalendarClock.hm), meal.kcal.map { "\($0) kcal" }].compactMap { $0 }.joined(separator: " · "),
                   minute: meal.loggedMin ?? meal.atMin, width: width) {
                Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(Palette.background)
                    .frame(width: 28, height: 28).background(Palette.ink, in: Circle())
            }
        case (_, true, _):
            marker(title: "Usual \(name.lowercased())", detail: CalendarClock.hm(meal.usualMin), minute: meal.usualMin, width: width, faded: true) {
                CalendarDashedRing(size: 26)
            }
            marker(title: name, detail: meal.status == "missed" ? "missed · \(CalendarClock.hm(meal.atMin))" : "moved · heads-up \(CalendarClock.hm(meal.atMin))",
                   minute: meal.atMin, width: width) {
                Image(systemName: "fork.knife").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.onEmber)
                    .frame(width: 28, height: 28).background(Palette.ember, in: Circle())
            }
        default:
            let detail = meal.status == "missed"
                ? "missed · \(CalendarClock.hm(meal.atMin))"
                : meal.kept ? "kept · \(CalendarClock.hm(meal.atMin))" : CalendarClock.hm(meal.atMin)
            marker(title: name, detail: detail, minute: meal.atMin, width: width, faded: meal.status == "missed") {
                Image(systemName: "fork.knife").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.ink)
                    .frame(width: 28, height: 28).background(Color.white.opacity(0.06), in: Circle())
            }
        }
    }

    private func marker<Icon: View>(
        title: String,
        detail: String,
        minute: Int,
        width: CGFloat,
        faded: Bool = false,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(title)
                    .font(Typography.data(13, weight: .bold))
                    .foregroundStyle(faded ? Palette.inkSoft : Palette.ink)
                Text(detail)
                    .font(Typography.data(11))
                    .foregroundStyle(Palette.inkSoft)
                    .monospacedDigit()
            }
            icon()
        }
        .fixedSize()
        .frame(width: width, alignment: .trailing)
        .offset(y: y(minute) - 16)
        .accessibilityElement(children: .combine)
    }
}
