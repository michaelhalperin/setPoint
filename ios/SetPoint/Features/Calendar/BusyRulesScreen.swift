import SwiftUI

// MARK: B3 · Busy rules

struct BusyRulesView: View {
    @Environment(AppEnvironment.self) private var env

    private static let lengths = [30, 60, 120, 180]

    var body: some View {
        let calendar = env.calendar
        InnerScreen(spacing: 14) {
            ScreenHeader(label: "Busy rules")

            Headline("When you’re busy.", tail: "How early I step in.", size: 36)
                .appearIn(0, rise: 16)

            headsUp.appearIn(1, rise: 14)
            countsAsBusy.appearIn(2, rise: 14)
            alsoRules.appearIn(3)

            CalendarMovedStrip(week: calendar.week, refreshing: calendar.refreshing, title: "With these rules")
                .appearIn(4)
        }
    }

    // MARK: Heads-up

    /// A meeting at 12:00 and the reminder dot sliding along the morning as the lead changes.
    private var headsUp: some View {
        let calendar = env.calendar
        let meeting = calendar.week?.next?.busy.startMin ?? 12 * 60
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Heads-up").sectionLabelStyle()
                Spacer()
                Text(CalendarClock.hm(meeting - calendar.leadMin))
                    .font(Typography.mono(12))
                    .foregroundStyle(Palette.amber)
                    .contentTransition(.numericText())
            }
            GeometryReader { geo in
                let w = geo.size.width
                let from = meeting - 90, span = 150.0
                let x = { (m: Int) in CGFloat(Double(m - from) / span) * w }
                let orbX = x(meeting - calendar.leadMin)
                let meetingX = x(meeting)
                ZStack(alignment: .topLeading) {
                    BusyBlock(radius: 12)
                        .overlay(alignment: .topLeading) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Meeting").font(Typography.data(12, weight: .regular)).foregroundStyle(Palette.ink)
                                Text(CalendarClock.hm(meeting)).font(Typography.mono(10)).foregroundStyle(Palette.inkFaint)
                            }
                            .padding(8)
                        }
                        .frame(width: w - meetingX, height: 64)
                        .offset(x: meetingX, y: 10)
                    Rectangle()
                        .fill(Palette.amber.opacity(0.6))
                        .frame(width: max(0, meetingX - orbX - 15), height: 1.5)
                        .offset(x: orbX + 13, y: 42)
                                Text(L10n("\(calendar.leadMin) min"))
                        .font(Typography.mono(10))
                        .foregroundStyle(Palette.amber)
                        .fixedSize()
                        .position(x: (orbX + meetingX) / 2, y: 28)
                    EmberDot(size: 22)
                        .offset(x: orbX - 11, y: 31)
                    ForEach(0..<6, id: \.self) { i in
                        let m = from + i * 30
                        Text(CalendarClock.hm(m))
                            .font(Typography.mono(9))
                            .foregroundStyle(Palette.inkFaint)
                            .fixedSize()
                            .position(x: min(max(x(m), 14), w - 14), y: 90)
                    }
                }
                .animation(Motion.settle, value: calendar.leadMin)
            }
            .frame(height: 98)
            .accessibilityElement()
            .accessibilityLabel(L10n("Reminder at \(CalendarClock.hm(meeting - calendar.leadMin)), \(calendar.leadMin) minutes before a meeting at \(CalendarClock.hm(meeting))"))

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
                title: { L10n("\($0) min") }
            )
        }
        .padding(16)
        .glass(radius: 24)
    }

    // MARK: Counts as busy

    /// Four bars of 30 min to 3 h. Bars at or past the threshold are striped; tap one to set it.
    private var countsAsBusy: some View {
        let calendar = env.calendar
        let threshold = Self.lengths.min { abs($0 - calendar.minBlockMin) < abs($1 - calendar.minBlockMin) } ?? 60
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Counts as busy").sectionLabelStyle()
                Spacer()
                Text(CalendarCopy.minBlock(calendar.minBlockMin))
                    .font(Typography.mono(12))
                    .foregroundStyle(Palette.ink)
            }
            VStack(spacing: 4) {
                ForEach(Self.lengths, id: \.self) { length in
                    let counts = length >= threshold
                    let selected = length == threshold
                    Button {
                        guard length != calendar.minBlockMin else { return }
                        UISelectionFeedbackGenerator().selectionChanged()
                        calendar.minBlockMin = length
                        calendar.rulesChanged()
                    } label: {
                        HStack(spacing: 12) {
                            Text(length < 60 ? L10n("\(length) min") : L10n("\(length / 60) h"))
                                .font(Typography.mono(12))
                                .foregroundStyle(selected ? Palette.amber : Palette.inkSoft)
                                .frame(width: 46, alignment: .leading)
                            GeometryReader { geo in
                                BusyBlock(counts: counts, radius: 7)
                                    .frame(width: geo.size.width * CGFloat(length) / 180, height: 22)
                                    .overlay(alignment: .leading) {
                                        if selected {
                                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                .strokeBorder(Palette.amber, lineWidth: 1.5)
                                                .frame(width: geo.size.width * CGFloat(length) / 180, height: 22)
                                                .shadow(color: Palette.amber.opacity(0.35), radius: 8)
                                        }
                                    }
                                    .frame(maxHeight: .infinity)
                            }
                            .frame(height: 22)
                            Text(LocalizedStringKey(counts ? "counts" : "ignored"))
                                .font(Typography.data(12, weight: .regular))
                                .foregroundStyle(counts ? Palette.ink : Color(hex: 0x52525B))
                                .frame(width: 52, alignment: .trailing)
                        }
                        .frame(height: 40)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(CalendarCopy.minBlock(length))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .animation(Motion.settle, value: calendar.minBlockMin)
            Text("Standups and quick calls don’t move anything.")
                .font(Typography.data(12, weight: .regular))
                .foregroundStyle(Palette.inkSoft)
        }
        .padding(16)
        .glass(radius: 24)
    }

    // MARK: Also

    private var alsoRules: some View {
        let calendar = env.calendar
        let line = [
            calendar.workdaysOnly ? L10n("Weekend meals never move.") : L10n("Weekends can move too."),
            calendar.includeAllDay ? L10n("Trips and days off count as busy.") : L10n("All-day events are ignored."),
            calendar.countFree ? L10n("Free events count.") : L10n("Free, tentative and declined events never count."),
        ].joined(separator: " ")
        return VStack(alignment: .leading, spacing: 10) {
            Text("Also").sectionLabelStyle()
            FlexWrap(spacing: 8, lineSpacing: 8) {
                ToggleChip(title: "Workdays only", on: calendar.workdaysOnly, haze: true) {
                    calendar.workdaysOnly.toggle(); calendar.rulesChanged()
                }
                ToggleChip(title: "All-day events count", on: calendar.includeAllDay, haze: true) {
                    calendar.includeAllDay.toggle(); calendar.rulesChanged()
                }
                ToggleChip(title: "Free events count", on: calendar.countFree, haze: true) {
                    calendar.countFree.toggle(); calendar.rulesChanged()
                }
            }
            Text(line)
                .font(Typography.data(13, weight: .regular))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
