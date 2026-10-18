import SwiftUI

// MARK: B3 · Busy rules

struct BusyRulesView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var sliderValue: Double = 60

    var body: some View {
        let calendar = env.calendar
        SettingsScreen(title: "Busy rules", subtitle: "How early I remind you, and what counts as busy.") {
            VStack(alignment: .leading, spacing: 14) {
                CalendarImpactCard(week: calendar.week, refreshing: calendar.refreshing)
                    .appearIn(2)
                headsUpCard.appearIn(3)
                minBlockCard.appearIn(4)
                togglesCard.appearIn(5)
            }
        }
        .onAppear { sliderValue = Double(calendar.minBlockMin) }
    }

    // MARK: Heads-up

    private var headsUpCard: some View {
        let calendar = env.calendar
        let meeting = calendar.week?.next?.busy.startMin ?? 12 * 60
        return SettingsCard {
            VStack(alignment: .leading, spacing: 14) {
                CalendarCardLabel(text: "Heads-up")
                Text("How early before a meeting should I remind you to eat?")
                    .font(Typography.display(22))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 0) {
                    tile(symbol: "bell", label: "Reminder", time: meeting - calendar.leadMin, accent: true)
                    VStack(spacing: 2) {
                        Text("\(calendar.leadMin) min")
                            .font(Typography.data(11, weight: .bold))
                            .foregroundStyle(Palette.inkSoft)
                            .monospacedDigit()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Palette.inkSoft)
                    }
                    .frame(width: 56)
                    tile(symbol: "calendar", label: "Meeting", time: meeting, accent: false)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Reminder at \(CalendarClock.hm(meeting - calendar.leadMin)), \(calendar.leadMin) minutes before a meeting at \(CalendarClock.hm(meeting))")
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
        }
    }

    private func tile(symbol: String, label: String, time: Int, accent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                Text(label).font(Typography.data(13, weight: .bold))
            }
            .foregroundStyle(accent ? Palette.accentDeep : Palette.ink)
            Text(CalendarClock.hm(time))
                .font(Typography.data(30, weight: .heavy))
                .foregroundStyle(accent ? Palette.accent : Palette.ink)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background {
            if accent {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Palette.accentTint)
            } else {
                BusyHatch(cornerRadius: 16)
            }
        }
    }

    // MARK: Counts as busy

    private var minBlockCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    CalendarCardLabel(text: "Counts as busy")
                    Spacer()
                    Text(CalendarCopy.minBlock(Int(sliderValue)))
                        .font(Typography.data(14, weight: .bold))
                        .foregroundStyle(Palette.ink)
                        .monospacedDigit()
                }
                Slider(value: $sliderValue, in: 30...180, step: 15) { editing in
                    guard !editing else { return }
                    let value = Int(sliderValue)
                    guard value != env.calendar.minBlockMin else { return }
                    env.calendar.minBlockMin = value
                    env.calendar.rulesChanged()
                }
                .tint(Palette.accent)
                .accessibilityLabel("Counts as busy")
                .accessibilityValue(CalendarCopy.minBlock(Int(sliderValue)))
                GeometryReader { geo in
                    ForEach([(30, "30m"), (60, "1h"), (120, "2h"), (180, "3h")], id: \.0) { value, label in
                        let fraction = CGFloat(value - 30) / 150
                        Text(label)
                            .font(Typography.data(11, weight: .semibold))
                            .foregroundStyle(Palette.inkFaint)
                            .fixedSize()
                            .position(x: 14 + fraction * (geo.size.width - 28), y: 6)
                    }
                }
                .frame(height: 14)
                .accessibilityHidden(true)
                Text("Standups and quick calls don't move anything.")
                    .font(Typography.data(12))
                    .foregroundStyle(Palette.inkSoft)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: Toggles

    private var togglesCard: some View {
        let calendar = env.calendar
        return SettingsCard(padding: 0) {
            VStack(spacing: 0) {
                CalendarToggleRow(
                    symbol: "calendar",
                    title: "Workdays only",
                    subtitle: "Weekend meals never move",
                    isOn: Binding(get: { calendar.workdaysOnly }, set: { calendar.workdaysOnly = $0; calendar.rulesChanged() })
                )
                Divider().overlay(Palette.hairline).padding(.leading, 66)
                CalendarToggleRow(
                    symbol: "sun.max",
                    title: "All-day events",
                    subtitle: "Trips and days off count as busy",
                    isOn: Binding(get: { calendar.includeAllDay }, set: { calendar.includeAllDay = $0; calendar.rulesChanged() })
                )
                Divider().overlay(Palette.hairline).padding(.leading, 66)
                CalendarToggleRow(
                    symbol: "eye",
                    title: "Events marked free",
                    subtitle: "Count them too. Tentative and declined never do.",
                    isOn: Binding(get: { calendar.countFree }, set: { calendar.countFree = $0; calendar.rulesChanged() })
                )
            }
        }
    }
}
