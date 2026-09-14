import EventKit
import SwiftUI

struct CalendarConnectView: View {
    var onConnected: () -> Void = {}

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SettingsScreen(title: "Calendar", subtitle: "Eat before the busy stretch.") {
            VStack(alignment: .leading, spacing: 20) {
                timeline.appearIn(2)
                calendarList.appearIn(3)
                privacy.appearIn(4)
                ActionButton(title: env.calendar.accessGranted ? "Connect" : "Allow Calendar access", kind: .primary) {
                    Task {
                        await env.calendar.connect()
                        if env.calendar.connected {
                            onConnected()
                            dismiss()
                        }
                    }
                }
                Button("Not now") { dismiss() }
                    .font(Typography.data(15, weight: .bold))
                    .foregroundStyle(Palette.inkSoft)
                    .frame(maxWidth: .infinity)
                if let message = env.calendar.lastError {
                    SettingsErrorBanner(message: message)
                }
            }
        }
        .task { env.calendar.start(); env.calendar.refreshCalendars() }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How it works").sectionLabelStyle()
            SettingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    step("1", "I read when you're in meetings.")
                    step("2", "Lunch check-in moves earlier.")
                    step("3", "Titles stay on this phone.")
                }
            }
        }
    }

    private func step(_ n: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(n)
                .font(Typography.data(13, weight: .heavy))
                .foregroundStyle(Palette.background)
                .frame(width: 28, height: 28)
                .background(Palette.ink, in: Circle())
            Text(text)
                .font(Typography.data(15))
                .foregroundStyle(Palette.ink)
        }
    }

    private var calendarList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Calendars").sectionLabelStyle()
            SettingsCard(padding: 0) {
                if env.calendar.calendars.isEmpty {
                    Text("Allow access, then pick which calendars count as busy.")
                        .font(Typography.data(14))
                        .foregroundStyle(Palette.inkSoft)
                        .padding(16)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(env.calendar.calendars.enumerated()), id: \.element.calendarIdentifier) { index, calendar in
                            Toggle(isOn: Binding(
                                get: { env.calendar.selectedIds.contains(calendar.calendarIdentifier) },
                                set: { _ in env.calendar.toggleCalendar(calendar.calendarIdentifier) }
                            )) {
                                Text(calendar.title)
                                    .font(Typography.data(15, weight: .bold))
                                    .foregroundStyle(Palette.ink)
                            }
                            .tint(Palette.accent)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            if index < env.calendar.calendars.count - 1 {
                                Divider().overlay(Palette.hairline).padding(.leading, 16)
                            }
                        }
                    }
                }
            }
        }
    }

    private var privacy: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.inkSoft)
            Text("Only busy times are uploaded. Event names never leave this phone.")
                .font(Typography.data(13))
                .foregroundStyle(Palette.inkSoft)
        }
    }
}

struct CalendarSettingsView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Group {
            if env.calendar.connected {
                connected
            } else {
                CalendarConnectView()
            }
        }
        .task {
            env.calendar.start()
            await env.calendar.refreshStatus()
            if env.calendar.accessGranted { env.calendar.refreshCalendars() }
            await env.calendar.uploadBusy()
        }
    }

    private var connected: some View {
        SettingsScreen(title: "Calendar") {
            VStack(alignment: .leading, spacing: 20) {
                hero.appearIn(2)
                weekGrid.appearIn(3)
                lead.appearIn(4)
                whatCounts.appearIn(5)
                calendarsCard.appearIn(6)
                Button(role: .destructive) {
                    Task { await env.calendar.disconnect() }
                } label: {
                    Text("Disconnect calendar")
                        .font(Typography.data(15, weight: .bold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.accentDeep)
                .padding(.vertical, 12)
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connected")
                .font(Typography.data(12, weight: .heavy))
                .foregroundStyle(Palette.onInkPositive)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Palette.dayOnTrack.opacity(0.25), in: Capsule())
            Text("\(env.calendar.mealsMovedThisWeek) meals moved earlier this week")
                .font(Typography.display(28))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.hairline))
    }

    private var weekGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This week").sectionLabelStyle()
            SettingsCard {
                BusyWeekGrid(blocks: env.calendar.week)
            }
        }
    }

    private var lead: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Warn me").sectionLabelStyle()
            SegmentedPills(
                options: [30, 45, 60],
                selection: Binding(
                    get: { env.calendar.leadMin },
                    set: {
                        env.calendar.leadMin = $0
                        env.calendar.persistPrefs()
                    }
                ),
                title: { "\($0) min" }
            )
        }
    }

    private var whatCounts: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What counts as busy").sectionLabelStyle()
            SettingsCard(padding: 0) {
                VStack(spacing: 0) {
                    Toggle("Workdays only", isOn: Binding(
                        get: { env.calendar.workdaysOnly },
                        set: { env.calendar.workdaysOnly = $0; env.calendar.persistPrefs() }
                    ))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    Divider().overlay(Palette.hairline).padding(.leading, 16)
                    Toggle("All-day events", isOn: Binding(
                        get: { env.calendar.includeAllDay },
                        set: { env.calendar.includeAllDay = $0; env.calendar.persistPrefs() }
                    ))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .font(Typography.data(15, weight: .bold))
                .tint(Palette.accent)
            }
        }
    }

    private var calendarsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Calendars").sectionLabelStyle()
            SettingsCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(env.calendar.calendars.enumerated()), id: \.element.calendarIdentifier) { index, calendar in
                        Toggle(isOn: Binding(
                            get: { env.calendar.selectedIds.contains(calendar.calendarIdentifier) },
                            set: { _ in env.calendar.toggleCalendar(calendar.calendarIdentifier) }
                        )) {
                            Text(calendar.title)
                                .font(Typography.data(15, weight: .bold))
                        }
                        .tint(Palette.accent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        if index < env.calendar.calendars.count - 1 {
                            Divider().overlay(Palette.hairline).padding(.leading, 16)
                        }
                    }
                }
            }
        }
    }
}

/// Mini 8:00–20:00 busy grid for the coming week.
struct BusyWeekGrid: View {
    let blocks: [CalendarWeekBlock]

    private let startHour = 8
    private let endHour = 20

    var body: some View {
        let days = grouped
        HStack(alignment: .top, spacing: 6) {
            ForEach(days, id: \.date) { day in
                VStack(spacing: 4) {
                    Text(dayLabel(day.date))
                        .font(Typography.data(10, weight: .bold))
                        .foregroundStyle(Palette.inkFaint)
                    GeometryReader { geo in
                        ZStack(alignment: .top) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Palette.surfaceSunk)
                            ForEach(Array(day.blocks.enumerated()), id: \.offset) { _, block in
                                let y = CGFloat(block.startMin - startHour * 60) / CGFloat((endHour - startHour) * 60)
                                let h = CGFloat(block.endMin - block.startMin) / CGFloat((endHour - startHour) * 60)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Palette.ink.opacity(0.45))
                                    .frame(height: max(3, geo.size.height * h))
                                    .offset(y: geo.size.height * max(0, y))
                            }
                        }
                    }
                    .frame(height: 88)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Busy times this week")
    }

    private var grouped: [(date: String, blocks: [CalendarWeekBlock])] {
        var map: [String: [CalendarWeekBlock]] = [:]
        for block in blocks {
            map[block.date, default: []].append(block)
        }
        let keys = map.keys.sorted()
        if keys.isEmpty {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return (0..<7).map { offset in
                let day = Calendar.current.date(byAdding: .day, value: offset, to: .now) ?? .now
                return (formatter.string(from: day), [])
            }
        }
        return keys.prefix(7).map { ($0, map[$0] ?? []) }
    }

    private func dayLabel(_ iso: String) -> String {
        let parts = iso.split(separator: "-")
        guard parts.count == 3, let d = Int(parts[2]) else { return iso }
        return "\(d)"
    }
}
