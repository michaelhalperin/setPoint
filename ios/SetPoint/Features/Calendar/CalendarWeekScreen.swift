import SwiftUI

// MARK: B1 · Week

/// Calendar, connected: the week as columns — busy stretches striped, each meal a
/// dot, moved meals lit with a trail back to their usual time. Tap a day.
struct CalendarWeekView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var openDay: String?

    var body: some View {
        let calendar = env.calendar
        InnerScreen(glow: .mixed, spacing: 14) {
            ScreenHeader(label: "") {
                CalendarConnectedPill()
            }

            if let week = calendar.week {
                Headline(title(week), tail: week.movedCount == 0 ? "No busy stretch hits a meal this week." : "Around this week’s busy hours.", size: 38)
                    .appearIn(0, rise: 16)
                    .opacity(calendar.refreshing ? 0.5 : 1)

                CalendarWeekColumns(week: week, onPick: { openDay = $0 })
                    .frame(height: 332)
                    .appearIn(1, rise: 14)

                CalendarLegend().appearIn(2)
            } else if let error = calendar.weekError {
                Headline("Calendar.", tail: "Couldn’t read your week.", size: 38)
                    .appearIn(0, rise: 16)
                VStack(alignment: .leading, spacing: 14) {
                    Text(error)
                        .font(Typography.data(14, weight: .regular))
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    ActionButton(title: "Try again", kind: .secondary) {
                        Task { await calendar.sync() }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 200, alignment: .center)
            } else {
                Headline("Calendar.", tail: "Reading your week…", size: 38)
                BusyDots(tint: Palette.amber).frame(maxWidth: .infinity, minHeight: 200)
            }

            HStack(spacing: 10) {
                NavigationLink { CalendarsView() } label: {
                    linkTile(title: "Calendars", value: "\(calendar.selectedChoices.count) of \(calendar.choices.count) on") {
                        HStack(spacing: 5) {
                            ForEach(calendar.ownChoices.prefix(4)) { choice in
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(hex: choice.colorHex))
                                    .frame(width: 12, height: 12)
                                    .opacity(calendar.isSelected(choice.id) ? 1 : 0.25)
                            }
                        }
                    }
                }
                NavigationLink { BusyRulesView() } label: {
                    linkTile(title: "Busy rules", value: "\(CalendarClock.duration(calendar.minBlockMin))+ · \(calendar.leadMin) min ahead") {
                        HStack(spacing: 5) {
                            BusyBlock(radius: 4).frame(width: 26, height: 12)
                            EmberDot(size: 8)
                        }
                    }
                }
            }
            .buttonStyle(PressableCard())
            .fixedSize(horizontal: false, vertical: true)
            .appearIn(3)

            if let week = calendar.week {
                nextSection(week).appearIn(4, rise: 14)
            }
        }
        .navigationDestination(item: $openDay) { date in
            CalendarDayView(date: date)
        }
    }

    private func title(_ week: CalendarWeekResponse) -> String {
        switch week.movedCount {
        case 0: return "Nothing moves."
        case 1: return "1 meal moved."
        default: return "\(week.movedCount) meals moved."
        }
    }

    private func linkTile<Mark: View>(title: String, value: String, @ViewBuilder mark: () -> Mark) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            mark().frame(height: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.data(15, weight: .regular))
                    .foregroundStyle(Palette.ink)
                Text(value)
                    .font(Typography.mono(11))
                    .foregroundStyle(Palette.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glass(radius: 22)
        .contentShape(Rectangle())
    }

    /// The next moved meal, with Keep / Move.
    @ViewBuilder
    private func nextSection(_ week: CalendarWeekResponse) -> some View {
        if let next = week.next {
            let weekday = week.day(next.date)?.weekday ?? 1
            VStack(alignment: .leading, spacing: 12) {
                Text(CalendarDates.relativeLabel(next.date, today: week.today, weekday: weekday)).sectionLabelStyle()
                Headline(CalendarCopy.headline(slot: next.slot, busy: next.busy, kept: next.kept, usualMin: next.usualMin), size: 22)
                CalendarKeepButton(
                    slot: next.slot,
                    keep: !next.kept,
                    usualMin: next.usualMin,
                    earlyMin: next.earlyMin
                ) {
                    await env.calendar.setKeep(date: next.date, slot: next.slot, keep: !next.kept)
                }
                if let message = env.calendar.lastError {
                    SettingsErrorBanner(message: message)
                }
            }
            .padding(16)
            .glass(radius: 22)
        }
    }
}

/// Seven tall columns, 07:00–22:00, with busy blocks and meal dots.
struct CalendarWeekColumns: View {
    let week: CalendarWeekResponse
    var onPick: (String) -> Void

    private let startMin = 420
    private let endMin = 1320

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            GeometryReader { geo in
                ForEach([480, 720, 960, 1200], id: \.self) { m in
                    Text(String(format: "%02d", m / 60))
                        .font(Typography.mono(9))
                        .foregroundStyle(Palette.inkFaint)
                        .position(x: 8, y: 22 + y(m, geo.size.height - 22))
                }
            }
            .frame(width: 18)

            ForEach(week.days) { day in
                Button { onPick(day.date) } label: {
                    VStack(spacing: 6) {
                        Text("\(String(CalendarDates.shortWeekday(day.weekday).prefix(1))) \(CalendarDates.dayOfMonth(day.date))")
                            .font(Typography.mono(10))
                            .foregroundStyle(day.date == week.today ? Palette.amber : Palette.inkFaint)
                            .frame(height: 16)
                        GeometryReader { geo in
                            column(day, height: geo.size.height)
                        }
                        .background(Color.white.opacity(day.date == week.today ? 0.05 : 0.025), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(day.date == week.today ? Palette.amber.opacity(0.35) : Color.white.opacity(0.06)))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label(day))
            }
        }
    }

    private func y(_ m: Int, _ h: CGFloat) -> CGFloat {
        CGFloat(min(max(m, startMin), endMin) - startMin) / CGFloat(endMin - startMin) * h
    }

    private func column(_ day: CalendarWeekResponse.Day, height h: CGFloat) -> some View {
        ZStack(alignment: .top) {
            ForEach(Array(day.blocks.enumerated()), id: \.offset) { _, block in
                let top = y(block.allDay ? startMin : block.startMin, h)
                let bottom = y(block.allDay ? endMin : block.endMin, h)
                BusyBlock(counts: block.counts, radius: 7)
                    .frame(height: max(4, bottom - top))
                    .padding(.horizontal, 3)
                    .offset(y: top)
            }
            ForEach(day.meals) { meal in
                let usual = y(meal.usualMin, h)
                if meal.moved {
                    let at = y(meal.atMin, h)
                    Rectangle()
                        .fill(Palette.amber.opacity(0.55))
                        .frame(width: 1.5, height: max(0, usual - at))
                        .offset(y: at)
                    GhostRing(size: 9).offset(y: usual - 4.5)
                    EmberDot(size: 13).offset(y: at - 6.5)
                } else {
                    Circle()
                        .fill(meal.status == "done" ? Palette.amber : Color.white.opacity(0.42))
                        .frame(width: 7, height: 7)
                        .offset(y: y(meal.atMin, h) - 3.5)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func label(_ day: CalendarWeekResponse.Day) -> String {
        let moved = day.meals.filter(\.moved)
        var parts = [CalendarDates.longWeekday(day.weekday)]
        if moved.isEmpty {
            parts.append(day.blocks.contains(where: \.counts) ? "busy, nothing moves" : "free")
        } else {
            parts += moved.map { "\(CalendarCopy.slotName($0.slot)) moves to \(CalendarClock.hm($0.atMin))" }
        }
        return parts.joined(separator: ", ")
    }
}

struct CalendarLegend: View {
    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) { EmberDot(size: 10, glow: 0.6); Text("MOVED") }
            HStack(spacing: 6) { GhostRing(size: 8); Text("USUAL") }
            HStack(spacing: 6) { BusyBlock(radius: 3).frame(width: 12, height: 9); Text("BUSY") }
        }
        .font(Typography.mono(10))
        .foregroundStyle(Palette.inkFaint)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

/// A strip of seven day dots, lit where a meal moves — under the calendar tiles.
struct CalendarMovedStrip: View {
    let week: CalendarWeekResponse?
    let refreshing: Bool
    var title: String = "This week"

    private var moved: [(weekday: Int, slot: String, atMin: Int)] {
        (week?.days ?? []).flatMap { day in day.meals.filter(\.moved).map { (day.weekday, $0.slot, $0.atMin) } }
    }

    var body: some View {
        let count = week?.movedCount ?? moved.count
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(Typography.data(15, weight: .regular))
                    .foregroundStyle(Palette.ink)
                Spacer()
                if refreshing {
                    BusyDots(tint: Palette.amber)
                } else {
                    Text("\(count) moved")
                        .font(Typography.mono(12))
                        .foregroundStyle(Palette.amber)
                        .contentTransition(.numericText())
                }
            }
            if let days = week?.days {
                HStack {
                    ForEach(days) { day in
                        let lit = day.meals.contains(where: \.moved)
                        VStack(spacing: 6) {
                            Circle()
                                .fill(lit ? Palette.amber : Color.white.opacity(0.12))
                                .frame(width: 12, height: 12)
                                .shadow(color: Palette.amber.opacity(lit ? 0.7 : 0), radius: 5)
                            Text(String(CalendarDates.shortWeekday(day.weekday).prefix(1)))
                                .font(Typography.mono(10))
                                .foregroundStyle(Palette.inkFaint)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            Text(moved.isEmpty
                 ? "Every meal stays at its usual time."
                 : moved.map { "\(CalendarDates.shortWeekday($0.weekday))\u{00A0}\($0.slot)\u{00A0}\(CalendarClock.hm($0.atMin))" }.joined(separator: " · "))
                .font(Typography.mono(11))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glass(radius: 22, fill: Palette.ember.opacity(0.06), stroke: Color(hex: 0xFF8A50, opacity: 0.25))
        .accessibilityElement(children: .combine)
    }
}

/// Calendars as lit tiles, three across — tap to switch one on or off.
struct CalendarTiles: View {
    let choices: [CalendarChoice]
    var columns = 3
    var compact = false
    let isOn: (CalendarChoice) -> Bool
    let set: (CalendarChoice, Bool) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
            ForEach(choices) { choice in
                let on = isOn(choice)
                let color = Color(hex: choice.colorHex)
                Button { set(choice, !on) } label: {
                    Group {
                        if compact {
                            HStack(spacing: 8) {
                                swatch(color, on: on)
                                Text(choice.title)
                                    .font(Typography.data(14, weight: .regular))
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                check(on)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 18) {
                                HStack {
                                    swatch(color, on: on)
                                    Spacer()
                                    check(on)
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(choice.title)
                                        .font(Typography.data(15, weight: .medium))
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.85)
                                    Text(choice.subscribed ? choice.source : "\(choice.source) · \(choice.eventsThisWeek) this week")
                                        .font(Typography.data(11, weight: .regular))
                                        .foregroundStyle(Palette.inkSoft)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                    .foregroundStyle(Palette.ink)
                    .padding(compact ? 12 : 12)
                    .frame(maxWidth: .infinity, minHeight: compact ? 48 : 120, alignment: .topLeading)
                    .background {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(on
                                  ? AnyShapeStyle(LinearGradient(colors: [color.opacity(0.22), color.opacity(0.03)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                  : AnyShapeStyle(Color.white.opacity(0.025)))
                    }
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(on ? color.opacity(0.55) : Color.white.opacity(0.08)))
                    .shadow(color: color.opacity(on ? 0.16 : 0), radius: 14)
                    .opacity(on ? 1 : 0.8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableCard())
                .accessibilityLabel(choice.title)
                .accessibilityValue(on ? "On" : "Off")
                .accessibilityAddTraits(.isToggle)
            }
        }
    }

    private func swatch(_ color: Color, on: Bool) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(color)
            .frame(width: 12, height: 12)
            .opacity(on ? 1 : 0.35)
            .shadow(color: color.opacity(on ? 0.8 : 0), radius: 5)
    }

    private func check(_ on: Bool) -> some View {
        ZStack {
            if on {
                Circle().fill(Palette.ink)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Palette.onBone)
            } else {
                Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1.5)
            }
        }
        .frame(width: 22, height: 22)
    }
}

struct CalendarLinkRow: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.data(15, weight: .regular))
                    .foregroundStyle(Palette.ink)
                Text(detail)
                    .font(Typography.data(12, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: 0x52525B))
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
