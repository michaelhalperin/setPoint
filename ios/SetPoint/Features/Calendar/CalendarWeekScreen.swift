import SwiftUI

// MARK: B1 · Week

struct CalendarWeekView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var openDay: String?

    var body: some View {
        let calendar = env.calendar
        SettingsScreen(
            title: "Calendar",
            subtitle: "I plan meals around your busy stretches.",
            accessory: AnyView(CalendarConnectedPill())
        ) {
            VStack(alignment: .leading, spacing: 16) {
                if let week = calendar.week {
                    weekCard(week).appearIn(2)
                    nextSection(week).appearIn(3)
                } else {
                    SettingsCard {
                        VStack(alignment: .leading, spacing: 10) {
                            CalendarCardLabel(text: "This week")
                            RoundedRectangle(cornerRadius: 12).fill(Palette.surfaceSunk).frame(height: 300)
                        }
                    }
                    .redacted(reason: .placeholder)
                }
                linksCard.appearIn(4)
            }
        }
        .navigationDestination(item: $openDay) { date in
            CalendarDayView(date: date)
        }
    }

    private func weekCard(_ week: CalendarWeekResponse) -> some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    CalendarCardLabel(text: "This week")
                    Text(week.movedCount == 0
                        ? "No meals moved"
                        : "\(week.movedCount) \(week.movedCount == 1 ? "meal" : "meals") moved earlier")
                        .font(Typography.display(24))
                        .foregroundStyle(Palette.ink)
                }
                CalendarWeekGrid(week: week, onSelect: { openDay = $0 })
                HStack(spacing: 16) {
                    legend { BusyHatch(cornerRadius: 3).frame(width: 14, height: 10) } label: { "Busy" }
                    legend { Circle().fill(Palette.accent).frame(width: 10, height: 10) } label: { "Moved" }
                    legend { CalendarDashedRing(size: 11) } label: { "Usual time" }
                }
                .padding(.top, 2)
            }
        }
    }

    private func legend<Swatch: View>(@ViewBuilder swatch: () -> Swatch, label: () -> String) -> some View {
        HStack(spacing: 6) {
            swatch()
            Text(label())
                .font(Typography.data(12, weight: .semibold))
                .foregroundStyle(Palette.inkSoft)
        }
    }

    @ViewBuilder
    private func nextSection(_ week: CalendarWeekResponse) -> some View {
        if let next = week.next {
            let weekday = week.day(next.date)?.weekday ?? 1
            VStack(alignment: .leading, spacing: 10) {
                Text(CalendarDates.relativeLabel(next.date, today: week.today, weekday: weekday))
                    .sectionLabelStyle()
                    .padding(.horizontal, 4)
                SettingsCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(CalendarCopy.headline(slot: next.slot, busy: next.busy, kept: next.kept, usualMin: next.usualMin))
                            .font(Typography.display(24))
                            .foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
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
                }
            }
        } else {
            SettingsCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Nothing moves in the next 7 days.")
                        .font(Typography.display(22))
                        .foregroundStyle(Palette.ink)
                    Text("When a busy stretch covers a meal, it shows up here.")
                        .font(Typography.data(14))
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var linksCard: some View {
        let calendar = env.calendar
        let names = calendar.selectedChoices.map(\.title)
        return SettingsCard(padding: 0) {
            VStack(spacing: 0) {
                NavigationLink { CalendarsView() } label: {
                    CalendarLinkRow(
                        symbol: "calendar",
                        title: "Calendars",
                        detail: names.isEmpty ? "Pick which count" : names.joined(separator: ", "),
                        badge: names.isEmpty ? nil : "\(names.count)"
                    )
                }
                Divider().overlay(Palette.hairline).padding(.leading, 66)
                NavigationLink { BusyRulesView() } label: {
                    CalendarLinkRow(
                        symbol: "slider.horizontal.3",
                        title: "Busy rules",
                        detail: "Remind \(calendar.leadMin) min before · \(CalendarClock.duration(calendar.minBlockMin))+ counts"
                    )
                }
            }
            .buttonStyle(.plain)
        }
    }
}

struct CalendarLinkRow: View {
    let symbol: String
    let title: String
    let detail: String
    var badge: String? = nil

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 36, height: 36)
                .background(Palette.surfaceSunk, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.data(16, weight: .bold))
                    .foregroundStyle(Palette.ink)
                Text(detail)
                    .font(Typography.data(13))
                    .foregroundStyle(Palette.inkSoft)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let badge {
                Text(badge)
                    .font(Typography.data(12, weight: .bold))
                    .foregroundStyle(Palette.inkSoft)
                    .frame(minWidth: 24, minHeight: 24)
                    .background(Palette.surfaceSunk, in: Circle())
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.inkFaint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

/// Mon–Sun, 8:00–20:00: hatched busy stretches and a dot per meal. Moved meals
/// draw a dotted line back to their usual time.
struct CalendarWeekGrid: View {
    let week: CalendarWeekResponse
    var onSelect: (String) -> Void = { _ in }

    private let startMin = 7 * 60 + 30
    private let endMin = 20 * 60 + 30
    private let height: CGFloat = 330
    private let axisWidth: CGFloat = 20
    private let dot: CGFloat = 12

    var body: some View {
        VStack(spacing: 8) {
            header
            HStack(alignment: .top, spacing: 0) {
                axis
                ZStack(alignment: .topLeading) {
                    hourLines
                    HStack(spacing: 4) {
                        ForEach(week.days) { day in
                            column(day)
                                .contentShape(Rectangle())
                                .onTapGesture { onSelect(day.date) }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(accessibility(day))
                                .accessibilityAddTraits(.isButton)
                        }
                    }
                }
                .frame(height: height)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: axisWidth, height: 1)
            HStack(spacing: 4) {
                ForEach(week.days) { day in
                    let isToday = day.date == week.today
                    Button { onSelect(day.date) } label: {
                        VStack(spacing: 1) {
                            Text(CalendarDates.shortWeekday(day.weekday))
                                .font(Typography.data(10, weight: .bold))
                            Text(CalendarDates.dayOfMonth(day.date))
                                .font(Typography.data(15, weight: .heavy))
                        }
                        .foregroundStyle(isToday ? Palette.background : Palette.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background {
                            if isToday {
                                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.ink)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var axis: some View {
        ZStack(alignment: .topLeading) {
            ForEach([8, 11, 14, 17, 20], id: \.self) { hour in
                Text("\(hour)")
                    .font(Typography.data(10, weight: .semibold))
                    .foregroundStyle(Palette.inkFaint)
                    .offset(y: y(hour * 60) - 7)
            }
        }
        .frame(width: axisWidth, height: height, alignment: .topLeading)
    }

    private var hourLines: some View {
        ZStack(alignment: .topLeading) {
            ForEach([8, 11, 14, 17, 20], id: \.self) { hour in
                Rectangle()
                    .fill(Palette.hairline)
                    .frame(height: 1)
                    .offset(y: y(hour * 60))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func column(_ day: CalendarWeekResponse.Day) -> some View {
        GeometryReader { geo in
            let midX = geo.size.width / 2
            ZStack(alignment: .topLeading) {
                if day.date == week.today {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Palette.accentTint.opacity(0.6))
                }
                ForEach(Array(day.blocks.filter(\.counts).enumerated()), id: \.offset) { _, block in
                    let top = y(max(block.startMin, startMin))
                    let bottom = y(min(block.endMin, endMin))
                    if bottom > top {
                        BusyHatch(cornerRadius: 6)
                            .frame(width: geo.size.width * 0.78, height: bottom - top)
                            .offset(x: geo.size.width * 0.11, y: top)
                    }
                }
                ForEach(day.meals) { meal in
                    mealMark(meal, midX: midX)
                }
            }
        }
    }

    @ViewBuilder
    private func mealMark(_ meal: CalendarWeekResponse.Meal, midX: CGFloat) -> some View {
        if meal.moved {
            let from = y(meal.atMin)
            let to = y(meal.usualMin)
            Path { path in
                path.move(to: CGPoint(x: midX, y: from))
                path.addLine(to: CGPoint(x: midX, y: to))
            }
            .stroke(Palette.accent, style: StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
            CalendarDashedRing(size: dot)
                .background(Circle().fill(Palette.surface))
                .position(x: midX, y: to)
            Circle()
                .fill(Palette.accent)
                .frame(width: dot, height: dot)
                .overlay(Circle().strokeBorder(Palette.surface, lineWidth: 2))
                .position(x: midX, y: from)
        } else {
            let minute = meal.status == "done" ? (meal.loggedMin ?? meal.atMin) : meal.atMin
            Group {
                switch meal.status {
                case "done":
                    Circle().fill(Palette.ink)
                case "missed":
                    Circle().fill(Palette.dayMissed)
                default:
                    Circle().strokeBorder(Palette.inkFaint, lineWidth: 1.6).background(Circle().fill(Palette.surface))
                }
            }
            .frame(width: dot, height: dot)
            .position(x: midX, y: y(min(max(minute, startMin), endMin)))
        }
    }

    private func y(_ minute: Int) -> CGFloat {
        CGFloat(minute - startMin) / CGFloat(endMin - startMin) * height
    }

    private func accessibility(_ day: CalendarWeekResponse.Day) -> String {
        let moved = day.meals.filter(\.moved)
        let busy = day.blocks.filter(\.counts).count
        var parts = [CalendarDates.longWeekday(day.weekday)]
        parts.append(busy == 0 ? "no busy stretches" : "\(busy) busy \(busy == 1 ? "stretch" : "stretches")")
        for meal in moved {
            parts.append("\(CalendarCopy.slotName(meal.slot)) moved to \(CalendarClock.hm(meal.atMin))")
        }
        return parts.joined(separator: ", ")
    }
}
