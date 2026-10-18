import SwiftUI

// MARK: B1 · Week

struct CalendarWeekView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var openDay: String?

    var body: some View {
        let calendar = env.calendar
        SettingsScreen(
            title: "Calendar",
            subtitle: "I plan meals around busy stretches.",
            accessory: AnyView(CalendarConnectedPill()),
            headline: "Calendar."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                if !calendar.ownChoices.isEmpty {
                    CalendarChoicesCard(
                        choices: calendar.ownChoices,
                        isOn: { calendar.isSelected($0.id) },
                        set: { choice, on in _ = calendar.setSelected(choice.id, on) }
                    )
                    .appearIn(1, rise: 14)
                }

                rulesCard.appearIn(2, rise: 14)

                if let week = calendar.week {
                    weekCard(week).appearIn(3, rise: 14)
                    nextSection(week).appearIn(4, rise: 14)
                }

                linksCard.appearIn(5, rise: 14)
                CalendarLockLine()
            }
        }
        .navigationDestination(item: $openDay) { date in
            CalendarDayView(date: date)
        }
    }

    /// "Move a meal earlier when I'm busy for at least … and eat this long before it starts."
    private var rulesCard: some View {
        let calendar = env.calendar
        return VStack(alignment: .leading, spacing: 10) {
            Text("Move a meal earlier when I’m busy for at least")
                .font(Typography.data(14, weight: .regular))
                .foregroundStyle(Color(hex: 0xD4D4D8))
            SegmentedPills(
                options: [60, 90, 120],
                selection: Binding(
                    get: { [60, 90, 120].min { abs($0 - calendar.minBlockMin) < abs($1 - calendar.minBlockMin) } ?? 60 },
                    set: {
                        guard $0 != calendar.minBlockMin else { return }
                        calendar.minBlockMin = $0
                        calendar.rulesChanged()
                    }
                ),
                title: { $0 == 60 ? "1 h" : $0 == 90 ? "1½ h" : "2 h" }
            )
            Text("and eat this long before it starts")
                .font(Typography.data(14, weight: .regular))
                .foregroundStyle(Color(hex: 0xD4D4D8))
            SegmentedPills(
                options: [30, 45, 60],
                selection: Binding(
                    get: { calendar.leadMin },
                    set: {
                        guard $0 != calendar.leadMin else { return }
                        calendar.leadMin = $0
                        calendar.rulesChanged()
                    }
                ),
                title: { "\($0) min" }
            )
        }
        .padding(16)
        .glass(radius: 22)
    }

    /// "This week · 3 meals moved" with a dot per day — tap a day to see it.
    private func weekCard(_ week: CalendarWeekResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            (Text("This week · ").foregroundColor(Palette.ink)
                + Text(week.movedCount == 0 ? "nothing moved" : "\(week.movedCount) \(week.movedCount == 1 ? "meal" : "meals") moved").foregroundColor(Palette.amber))
                .font(Typography.data(14, weight: .regular))
            HStack {
                ForEach(week.days) { day in
                    Button { openDay = day.date } label: {
                        VStack(spacing: 6) {
                            dayDot(day)
                                .frame(width: 18, height: 18)
                            Text(CalendarDates.shortWeekday(day.weekday))
                                .font(Typography.mono(10))
                                .foregroundStyle(day.date == week.today ? Palette.ink : Palette.inkFaint)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableCard())
                    .accessibilityLabel(dayLabel(day))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glass(radius: 20, fill: Palette.ember.opacity(0.06), stroke: Color(hex: 0xFF8A50, opacity: 0.25))
    }

    @ViewBuilder
    private func dayDot(_ day: CalendarWeekResponse.Day) -> some View {
        if day.meals.contains(where: \.moved) {
            Circle().fill(Palette.ember).frame(width: 12, height: 12)
                .shadow(color: Palette.ember.opacity(0.7), radius: 6)
        } else if day.blocks.contains(where: \.counts) {
            Circle().fill(Color.white.opacity(0.3)).frame(width: 10, height: 10)
        } else {
            Circle().fill(Color.white.opacity(0.1)).frame(width: 8, height: 8)
        }
    }

    private func dayLabel(_ day: CalendarWeekResponse.Day) -> String {
        let moved = day.meals.filter(\.moved)
        var parts = [CalendarDates.longWeekday(day.weekday)]
        if moved.isEmpty {
            parts.append(day.blocks.contains(where: \.counts) ? "busy, nothing moved" : "free")
        } else {
            parts += moved.map { "\(CalendarCopy.slotName($0.slot)) moved to \(CalendarClock.hm($0.atMin))" }
        }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private func nextSection(_ week: CalendarWeekResponse) -> some View {
        if let next = week.next {
            let weekday = week.day(next.date)?.weekday ?? 1
            VStack(alignment: .leading, spacing: 12) {
                Text(CalendarDates.relativeLabel(next.date, today: week.today, weekday: weekday)).sectionLabelStyle()
                Headline(CalendarCopy.headline(slot: next.slot, busy: next.busy, kept: next.kept, usualMin: next.usualMin), size: 22)
                CalendarMoveRows(slot: next.slot, atMin: next.atMin, usualMin: next.usualMin, kept: next.kept, busy: next.busy)
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

    private var linksCard: some View {
        GlassList {
            NavigationLink { BusyRulesView() } label: {
                CalendarLinkRow(title: "More busy rules", detail: "Workdays, all-day events, free time")
            }
            ListDivider()
            NavigationLink { CalendarsView() } label: {
                CalendarLinkRow(title: "All calendars", detail: "Subscribed calendars · disconnect")
            }
        }
        .buttonStyle(.plain)
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
