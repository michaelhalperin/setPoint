import SwiftUI

// MARK: B2 · Day

/// One day: a strip to switch days, a spine with each meal (moved ones lit, a
/// ghost where they usually are), busy stretches with titles read on this phone,
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

        InnerScreen(glow: .mixed, spacing: 12) {
            ScreenHeader(label: "This week")

            if let week { dayStrip(week).appearIn(0) }

            Headline("\(CalendarDates.longWeekday(weekday)).", tail: tail(day), size: 32, persistTail: true)
                .appearIn(0, rise: 16)

            allDayChips(events.filter(\.allDay), weekday: weekday)

            CalendarDayTimeline(
                events: events.filter { !$0.allDay },
                meals: day?.meals ?? [],
                nowMin: date == week?.today ? nowMin : nil,
                verdict: { verdict($0, weekday: weekday) }
            )
            .appearIn(1)

            if let day, let meal = day.meals.first(where: \.canKeep), let busy = meal.busy, let early = meal.earlyMin {
                whyCard(day: day, meal: meal, busy: busy, earlyMin: early, events: events, today: week?.today ?? date)
                    .appearIn(2)
            } else {
                nothingCard(events: events, weekday: weekday).appearIn(2)
            }
        }
        .animation(Motion.settle, value: date)
    }

    private var nowMin: Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: .now)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private func tail(_ day: CalendarWeekResponse.Day?) -> String {
        guard let day else { return L10n( "Nothing planned.") }
        let moved = day.meals.filter(\.moved)
        if !moved.isEmpty {
            return moved.map { L10n("\(CalendarCopy.slotName($0.slot)) moves to \(CalendarClock.hm($0.atMin))") }.joined(separator: ", ") + "."
        }
        if let kept = day.meals.first(where: \.kept) {
            return L10n( "\(CalendarCopy.slotName(kept.slot)) stays at \(CalendarClock.hm(kept.usualMin)).")
        }
        return L10n( "Nothing moves.")
    }

    private func dayStrip(_ week: CalendarWeekResponse) -> some View {
        HStack(spacing: 0) {
            ForEach(week.days) { d in
                let selected = d.date == date
                let lit = d.meals.contains(where: \.moved)
                Button { date = d.date } label: {
                    VStack(spacing: 3) {
                        Text(String(CalendarDates.shortWeekday(d.weekday).prefix(1)))
                            .font(Typography.mono(10))
                            .opacity(0.7)
                        Text(CalendarDates.dayOfMonth(d.date))
                            .font(Typography.data(15, weight: .regular))
                        Circle()
                            .fill(lit ? Palette.ember : .clear)
                            .frame(width: 5, height: 5)
                            .shadow(color: Palette.ember.opacity(lit ? 0.9 : 0), radius: 3)
                    }
                    .foregroundStyle(selected ? Palette.onBone : Palette.ink)
                    .frame(width: 44, height: 60)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(selected ? Palette.ink : Color.white.opacity(0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(selected ? Palette.ink : (d.date == week.today ? Palette.amber.opacity(0.45) : Color.white.opacity(0.08))))
                }
                .buttonStyle(PressableCard())
                .frame(maxWidth: .infinity)
                .accessibilityLabel(CalendarDates.longWeekday(d.weekday) + (lit ? L10n(", a meal moves") : ""))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    /// Titles from EventKit when we have them; otherwise the uploaded busy blocks, untitled.
    private func dayEvents(day: CalendarWeekResponse.Day?) -> [CalendarDayEvent] {
        let local = env.calendar.events(on: date)
        if !local.isEmpty { return local }
        return (day?.blocks ?? []).enumerated().map { index, block in
            CalendarDayEvent(
                id: "block-\(index)",
                title: L10n("Busy"),
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

    @ViewBuilder
    private func allDayChips(_ events: [CalendarDayEvent], weekday: Int) -> some View {
        if !events.isEmpty {
            FlexWrap(spacing: 8, lineSpacing: 8) {
                ForEach(events) { event in
                    let counts = verdict(event, weekday: weekday) == .counts
                    HStack(spacing: 8) {
                        BusyBlock(counts: counts, radius: 5).frame(width: 18, height: 18)
                        Text(event.title)
                            .font(Typography.data(13, weight: .regular))
                            .foregroundStyle(counts ? Palette.ink : Palette.inkSoft)
                        Text(CalendarRules.label(verdict(event, weekday: weekday)) ?? L10n("all day"))
                            .font(Typography.mono(10))
                            .foregroundStyle(Palette.inkFaint)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .glassCapsule()
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
        return VStack(alignment: .leading, spacing: 8) {
            Text(meal.kept
                ? L10n("\(CalendarCopy.slotName(meal.slot)) kept at \(CalendarClock.hm(meal.usualMin))")
                : L10n("Why \(CalendarClock.hm(earlyMin))?"))
                .font(Typography.data(15, weight: .medium))
                .foregroundStyle(Palette.ink)
            Text(CalendarCopy.why(
                eventName: name,
                slot: meal.slot,
                busy: busy,
                earlyMin: earlyMin,
                usualMin: meal.usualMin,
                reason: meal.reason,
                kept: meal.kept,
                leadMin: env.calendar.leadMin
            ) + " " + L10n("Titles stay on this phone."))
            .font(Typography.data(13, weight: .regular))
            .foregroundStyle(Palette.inkSoft)
            .fixedSize(horizontal: false, vertical: true)
            if actionable {
                CalendarKeepButton(
                    slot: meal.slot,
                    keep: !meal.kept,
                    usualMin: meal.usualMin,
                    earlyMin: earlyMin
                ) {
                    await env.calendar.setKeep(date: day.date, slot: meal.slot, keep: !meal.kept)
                }
                .padding(.top, 2)
            }
            if let message = env.calendar.lastError {
                SettingsErrorBanner(message: message)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(radius: 22)
    }

    private func nothingCard(events: [CalendarDayEvent], weekday: Int) -> some View {
        let reasons: String = events.isEmpty
            ? L10n("No busy time on your calendars.")
            : events.map { event -> String in
                switch verdict(event, weekday: weekday) {
                case .counts: return L10n( "\(event.title) doesn’t touch a meal.")
                case .tooShort: return L10n( "\(event.title) is too short to count.")
                case .allDayOff: return L10n( "\(event.title) is all day, and all-day events are off.")
                case .weekend: return L10n( "\(event.title) is on a weekend, and weekend meals never move.")
                }
            }.joined(separator: " ")
        return VStack(alignment: .leading, spacing: 8) {
            Text("Nothing to move")
                .font(Typography.data(15, weight: .medium))
                .foregroundStyle(Palette.ink)
            Text(reasons)
                .font(Typography.data(13, weight: .regular))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(radius: 22)
    }
}

/// Hours down the left, a spine with the meals, busy stretches on the right.
struct CalendarDayTimeline: View {
    let events: [CalendarDayEvent]
    let meals: [CalendarWeekResponse.Meal]
    let nowMin: Int?
    let verdict: (CalendarDayEvent) -> CalendarRules.Verdict

    private let perHour: CGFloat = 25
    private let spineX: CGFloat = 46

    private var range: (start: Int, end: Int) {
        var minutes = events.flatMap { [$0.startMin, $0.endMin] }
        for meal in meals {
            minutes.append(meal.atMin)
            minutes.append(meal.usualMin)
            if let logged = meal.loggedMin { minutes.append(logged) }
        }
        let low = min(7 * 60, minutes.min() ?? 7 * 60)
        let high = max(22 * 60, minutes.max() ?? 22 * 60)
        return (max(0, low / 60 * 60), min(1440, (high + 59) / 60 * 60))
    }

    private var height: CGFloat { CGFloat(range.end - range.start) / 60 * perHour }

    private func y(_ minute: Int) -> CGFloat {
        CGFloat(min(max(minute, range.start), range.end) - range.start) / 60 * perHour
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let blockX = w * 0.56
            ZStack(alignment: .topLeading) {
                ForEach(Array(stride(from: range.start + 60, through: range.end - 60, by: 120)), id: \.self) { minute in
                    HStack(spacing: 10) {
                        Text(CalendarClock.hm(minute))
                            .font(Typography.mono(10))
                            .foregroundStyle(Palette.inkFaint)
                            .frame(width: 36, alignment: .leading)
                        Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
                    }
                    .offset(y: y(minute) - 6)
                }
                Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: height)
                    .offset(x: spineX)

                ForEach(events) { event in
                    eventBlock(event, x: blockX, width: w - blockX)
                }

                ForEach(meals) { meal in
                    mealMarks(meal, labelWidth: blockX - spineX - 22)
                }

                if let nowMin, nowMin >= range.start, nowMin <= range.end {
                    HStack(spacing: 0) {
                        Circle().fill(Palette.ink).frame(width: 7, height: 7)
                        Rectangle().fill(Palette.ink.opacity(0.7)).frame(height: 1)
                    }
                    .offset(x: spineX - 3.5, y: y(nowMin) - 3.5)
                    .accessibilityLabel("Now, \(CalendarClock.hm(nowMin))")
                }
            }
        }
        .frame(height: height)
        .padding(.vertical, 8)
    }

    private func eventBlock(_ event: CalendarDayEvent, x: CGFloat, width: CGFloat) -> some View {
        let verdict = verdict(event)
        let counts = verdict == .counts
        let top = y(event.startMin)
        let h = y(event.endMin) - top
        let pill = h < 30
        let sub = counts ? CalendarClock.range(event.startMin, event.endMin) : (CalendarRules.label(verdict)?.lowercased() ?? "")
        return Group {
            if pill {
                HStack(spacing: 6) {
                    Text(event.title).font(Typography.data(12, weight: .regular)).foregroundStyle(counts ? Palette.ink : Palette.inkSoft)
                    Text(counts ? CalendarClock.hm(event.startMin) : (verdict == .tooShort ? "too short" : "off"))
                        .font(Typography.mono(10))
                        .foregroundStyle(Palette.inkFaint)
                }
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(width: width, height: 22, alignment: .leading)
                .background(Capsule().fill(Color.white.opacity(0.02)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(counts ? 0.16 : 0.14), style: StrokeStyle(lineWidth: 1, dash: counts ? [] : [4, 3])))
                .offset(x: x, y: top - 4)
            } else {
                BusyBlock(counts: counts, radius: 12)
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title).font(Typography.data(12, weight: .regular)).foregroundStyle(counts ? Palette.ink : Palette.inkSoft)
                            Text(sub).font(Typography.mono(10)).foregroundStyle(Palette.inkFaint)
                        }
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                    }
                    .frame(width: width, height: h)
                    .offset(x: x, y: top)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(event.title), \(CalendarClock.range(event.startMin, event.endMin))\(CalendarRules.label(verdict).map { ", \($0)" } ?? "")")
    }

    @ViewBuilder
    private func mealMarks(_ meal: CalendarWeekResponse.Meal, labelWidth: CGFloat) -> some View {
        let name = CalendarCopy.slotName(meal.slot)
        if meal.status == "done" {
            mark(at: meal.loggedMin ?? meal.atMin, time: CalendarClock.hm(meal.loggedMin ?? meal.atMin), name: name + (meal.kcal.map { " · \($0)" } ?? ""), color: Palette.ink, timeColor: Palette.inkFaint, width: labelWidth) {
                Circle().fill(Palette.amber).frame(width: 12, height: 12).shadow(color: Palette.amber.opacity(0.6), radius: 4)
            }
        } else if meal.moved {
            Rectangle().fill(Palette.amber.opacity(0.6)).frame(width: 1.5, height: max(0, y(meal.usualMin) - y(meal.atMin)))
                .offset(x: spineX - 0.25, y: y(meal.atMin))
            mark(at: meal.usualMin, time: CalendarClock.hm(meal.usualMin), name: "usual time", color: Color(hex: 0x71717A), timeColor: Color(hex: 0x52525B), width: labelWidth) {
                GhostRing(size: 12)
            }
            mark(at: meal.atMin, time: CalendarClock.hm(meal.atMin), name: meal.status == "missed" ? "\(name) · missed" : name, color: Palette.amber, timeColor: Color(hex: 0xFDE6CF), width: labelWidth) {
                EmberDot(size: 18)
            }
        } else {
            mark(at: meal.atMin, time: CalendarClock.hm(meal.atMin), name: name + (meal.kept ? " · kept" : meal.status == "missed" ? " · missed" : ""), color: meal.kept ? Palette.amber : Color(hex: 0xD4D4D8), timeColor: Palette.inkFaint, width: labelWidth) {
                if meal.kept {
                    Circle().strokeBorder(Palette.amber, lineWidth: 1.5).background(Circle().fill(Palette.background)).frame(width: 10, height: 10)
                } else {
                    Circle().fill(Color.white.opacity(0.5)).frame(width: 10, height: 10)
                }
            }
        }
    }

    private func mark<Dot: View>(at minute: Int, time: String, name: String, color: Color, timeColor: Color, width: CGFloat, @ViewBuilder dot: () -> Dot) -> some View {
        ZStack(alignment: .topLeading) {
            dot()
                .frame(width: 20, height: 20)
                .offset(x: spineX - 10, y: y(minute) - 10)
            HStack(spacing: 8) {
                Text(time).font(Typography.mono(11)).foregroundStyle(timeColor)
                Text(name).font(Typography.data(13, weight: .regular)).foregroundStyle(color)
            }
            .lineLimit(1)
            .frame(width: width, alignment: .leading)
            .offset(x: spineX + 16, y: y(minute) - 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) at \(time)")
    }
}
