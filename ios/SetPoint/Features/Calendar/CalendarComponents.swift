import SwiftUI

// MARK: Copy and time

/// 24-hour clock strings for the calendar screens: "11:15", "12:00–15:30".
enum CalendarClock {
    static func hm(_ minutes: Int) -> String {
        let wrapped = ((minutes % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", wrapped / 60, wrapped % 60)
    }

    static func range(_ start: Int, _ end: Int) -> String {
        "\(hm(start))–\(hm(end))"
    }

    /// "45 min", "1 hour", "1½ hours", "3½ hours", "1 h 15 min".
    static func duration(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        switch rest {
        case 0: return hours == 1 ? "1 hour" : "\(hours) hours"
        case 30: return "\(hours)½ hours"
        default: return "\(hours) h \(rest) min"
        }
    }
}

enum CalendarCopy {
    static func slotName(_ slot: String) -> String {
        switch slot {
        case "breakfast": return "Breakfast"
        case "lunch": return "Lunch"
        case "dinner": return "Dinner"
        default: return slot.capitalized
        }
    }

    static func previousMeal(_ slot: String) -> String {
        slot == "dinner" ? "lunch" : "breakfast"
    }

    /// "Busy 12:00–15:30, so lunch is earlier." / "Busy 12:00–15:30. Lunch stays at 13:00."
    static func headline(slot: String, busy: CalendarWeekResponse.Span, kept: Bool, usualMin: Int) -> String {
        let range = CalendarClock.range(busy.startMin, busy.endMin)
        let meal = slotName(slot)
        return kept
            ? "Busy \(range). \(meal) stays at \(CalendarClock.hm(usualMin))."
            : "Busy \(range), so \(meal.lowercased()) is earlier."
    }

    static func keepTitle(slot: String, usualMin: Int) -> String {
        "Keep \(slotName(slot).lowercased()) at \(CalendarClock.hm(usualMin))"
    }

    static func moveTitle(slot: String, earlyMin: Int) -> String {
        "Move \(slotName(slot).lowercased()) to \(CalendarClock.hm(earlyMin))"
    }

    /// The day screen's "Why 11:15?" body. The heads-up comes at the moved time.
    static func why(
        eventName: String?,
        slot: String,
        busy: CalendarWeekResponse.Span,
        earlyMin: Int,
        usualMin: Int,
        reason: String?,
        kept: Bool,
        leadMin: Int
    ) -> String {
        let name = eventName ?? "A busy stretch"
        let meal = slotName(slot).lowercased()
        let start = CalendarClock.hm(busy.startMin)
        if kept {
            return "\(name) runs \(CalendarClock.range(busy.startMin, busy.endMin)). You kept \(meal) at \(CalendarClock.hm(usualMin)), so nothing comes early."
        }
        let length = CalendarClock.duration(busy.endMin - busy.startMin)
        if reason == "floor" {
            return "\(name) starts \(start) and runs \(length). \(CalendarClock.hm(earlyMin)) is as early as it goes — never closer than 90 min after \(previousMeal(slot))."
        }
        return "\(name) starts \(start) and runs \(length). Your heads-up is \(leadMin) min before it starts, so \(meal) moves to \(CalendarClock.hm(earlyMin))."
    }

    /// "1 hour or longer"
    static func minBlock(_ minutes: Int) -> String {
        "\(CalendarClock.duration(minutes)) or longer"
    }
}

/// Mirrors the backend's qualifying-block rules, for labelling events on the day screen.
enum CalendarRules {
    enum Verdict: Equatable {
        case counts
        case tooShort
        case allDayOff
        case weekend
    }

    static func verdict(durationMin: Int, allDay: Bool, weekday: Int, minBlockMin: Int, workdaysOnly: Bool, includeAllDay: Bool) -> Verdict {
        if workdaysOnly && (weekday == 0 || weekday == 6) { return .weekend }
        if allDay && !includeAllDay { return .allDayOff }
        if durationMin < minBlockMin { return .tooShort }
        return .counts
    }

    static func label(_ verdict: Verdict) -> String? {
        switch verdict {
        case .counts: return nil
        case .tooShort: return "Too short to count"
        case .allDayOff: return "All-day events are off"
        case .weekend: return "Weekend — doesn't count"
        }
    }
}

// MARK: Drawing

/// Diagonal stripes — the "busy" texture used everywhere on the calendar screens.
struct BusyHatch: View {
    var cornerRadius: CGFloat = 10
    var faded = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Canvas { context, size in
            let spacing: CGFloat = 9
            var path = Path()
            var x: CGFloat = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += spacing
            }
            context.stroke(path, with: .color(Palette.ink.opacity(faded ? 0.06 : 0.13)), lineWidth: 3.5)
        }
        .background(Palette.ink.opacity(faded ? 0.03 : 0.07))
        .clipShape(shape)
        .accessibilityHidden(true)
    }
}

struct CalendarDashedRing: View {
    var size: CGFloat = 12
    var color: Color = Palette.accent

    var body: some View {
        Circle()
            .strokeBorder(color, style: StrokeStyle(lineWidth: 1.6, dash: [2.6, 2.2]))
            .frame(width: size, height: size)
    }
}

// MARK: Rows

struct CalendarCardLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(Typography.data(11, weight: .heavy))
            .foregroundStyle(Palette.inkFaint)
            .tracking(0.6)
    }
}

/// "11:15 · (fork) Lunch · usually 13:00" and "12:00 · (hatch) Busy · until 15:30".
struct CalendarMoveRows: View {
    let slot: String
    let atMin: Int
    let usualMin: Int
    let kept: Bool
    let busy: CalendarWeekResponse.Span

    var body: some View {
        VStack(spacing: 10) {
            row(
                time: CalendarClock.hm(atMin),
                timeColor: kept ? Palette.ink : Palette.accentDeep,
                background: kept ? Palette.surfaceSunk : Palette.accentTint
            ) {
                Image(systemName: "fork.knife")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(kept ? Palette.ink : .white)
                    .frame(width: 34, height: 34)
                    .background(kept ? Palette.surface : Palette.accent, in: Circle())
            } title: {
                Text(CalendarCopy.slotName(slot))
            } detail: {
                if kept {
                    Text("your usual time")
                } else {
                    HStack(spacing: 3) {
                        Text("usually")
                        Text(CalendarClock.hm(usualMin)).strikethrough()
                    }
                }
            }
            row(time: CalendarClock.hm(busy.startMin), timeColor: Palette.ink, background: Palette.surfaceSunk) {
                BusyHatch(cornerRadius: 17)
                    .frame(width: 34, height: 34)
            } title: {
                Text("Busy")
            } detail: {
                Text("until \(CalendarClock.hm(busy.endMin))")
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func row<Icon: View, Title: View, Detail: View>(
        time: String,
        timeColor: Color,
        background: Color,
        @ViewBuilder icon: () -> Icon,
        @ViewBuilder title: () -> Title,
        @ViewBuilder detail: () -> Detail
    ) -> some View {
        HStack(spacing: 12) {
            Text(time)
                .font(Typography.data(20, weight: .heavy))
                .foregroundStyle(timeColor)
                .monospacedDigit()
                .contentTransition(.numericText())
                .frame(width: 64, alignment: .leading)
            icon()
            VStack(alignment: .leading, spacing: 1) {
                title()
                    .font(Typography.data(15, weight: .bold))
                    .foregroundStyle(Palette.ink)
                detail()
                    .font(Typography.data(12))
                    .foregroundStyle(Palette.inkSoft)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct CalendarToggleRow: View {
    var symbol: String? = nil
    var colorHex: UInt32? = nil
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 14) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 36, height: 36)
                        .background(Palette.surfaceSunk, in: Circle())
                } else if let colorHex {
                    Circle()
                        .fill(Color(hex: colorHex))
                        .frame(width: 10, height: 10)
                        .padding(.horizontal, 2)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Typography.data(16, weight: .bold))
                        .foregroundStyle(Palette.ink)
                    Text(subtitle)
                        .font(Typography.data(12))
                        .foregroundStyle(Palette.inkSoft)
                        .lineLimit(2)
                }
            }
        }
        .tint(Palette.accent)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// A card of calendar on/off rows with hairlines between them.
struct CalendarChoicesCard: View {
    let choices: [CalendarChoice]
    let isOn: (CalendarChoice) -> Bool
    let set: (CalendarChoice, Bool) -> Void

    var body: some View {
        SettingsCard(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(choices.enumerated()), id: \.element.id) { index, choice in
                    CalendarToggleRow(
                        colorHex: choice.colorHex,
                        title: choice.title,
                        subtitle: choice.subtitle,
                        isOn: Binding(get: { isOn(choice) }, set: { set(choice, $0) })
                    )
                    if index < choices.count - 1 {
                        Divider().overlay(Palette.hairline).padding(.leading, 16)
                    }
                }
            }
        }
    }
}

struct CalendarLockLine: View {
    var text = "Only start and end times leave this phone."

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock")
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(Typography.data(13))
        }
        .foregroundStyle(Palette.inkSoft)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}

/// "Keep lunch at 13:00" / "Move lunch to 11:15". Shows dots while the change
/// saves, a check once it lands, then settles on the new action.
struct CalendarKeepButton: View {
    enum Style { case card, chip }

    var style: Style = .card
    let slot: String
    let keep: Bool
    let usualMin: Int
    let earlyMin: Int
    let action: () async -> Bool

    private enum Stage: Equatable { case idle, saving, done(keep: Bool) }

    @State private var stage: Stage = .idle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var meal: String { CalendarCopy.slotName(slot).lowercased() }

    private var title: String {
        switch stage {
        case .idle:
            return keep ? CalendarCopy.keepTitle(slot: slot, usualMin: usualMin) : CalendarCopy.moveTitle(slot: slot, earlyMin: earlyMin)
        case .saving:
            return keep ? "Keeping \(meal) at \(CalendarClock.hm(usualMin))" : "Moving \(meal) to \(CalendarClock.hm(earlyMin))"
        case let .done(kept):
            let name = CalendarCopy.slotName(slot)
            return kept ? "\(name) kept at \(CalendarClock.hm(usualMin))" : "\(name) moved to \(CalendarClock.hm(earlyMin))"
        }
    }

    var body: some View {
        let busy = stage == .saving
        let done = stage != .idle && !busy
        Button {
            guard stage == .idle else { return }
            Task { await run() }
        } label: {
            BusyLabel(title: title, busy: busy, done: done, tint: done ? Palette.dayOnTrack : Palette.ink)
                .font(Typography.data(style == .card ? 15 : 13, weight: .bold))
                .foregroundStyle(done ? Palette.dayOnTrack : Palette.ink)
                .lineLimit(1)
                .frame(maxWidth: style == .card ? .infinity : nil)
                .padding(.horizontal, style == .card ? 16 : 12)
                .padding(.vertical, style == .card ? 14 : 8)
                .background {
                    switch style {
                    case .card:
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(done ? Palette.dayOnTrack.opacity(0.12) : Palette.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(done ? Palette.dayOnTrack.opacity(0.35) : Palette.hairline, lineWidth: 1)
                            )
                    case .chip:
                        Capsule().fill(done ? Palette.dayOnTrack.opacity(0.14) : Palette.surfaceSunk)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableCard())
        .allowsHitTesting(stage == .idle)
        .animation(Motion.adaptive(Motion.settle, reduceMotion: reduceMotion), value: stage)
        .accessibilityLabel(title)
        .accessibilityAddTraits(busy ? .updatesFrequently : [])
    }

    private func run() async {
        stage = .saving
        let started = Date.now
        let ok = await action()
        // Long enough that the dots read as "saving", not a flicker.
        let elapsed = Date.now.timeIntervalSince(started)
        if elapsed < 0.45 { try? await Task.sleep(for: .seconds(0.45 - elapsed)) }
        guard ok else {
            stage = .idle
            return
        }
        Haptics.landed()
        stage = .done(keep: keep)
        try? await Task.sleep(for: .seconds(1.2))
        stage = .idle
    }
}

struct CalendarConnectedPill: View {
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .heavy))
            Text("Connected")
                .font(Typography.data(12, weight: .bold))
        }
        .foregroundStyle(Palette.dayOnTrack)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Palette.dayOnTrack.opacity(0.16), in: Capsule())
    }
}

/// Top of Calendars and Busy rules: what the current settings do to this week,
/// recalculating live as you change them.
struct CalendarImpactCard: View {
    let week: CalendarWeekResponse?
    let refreshing: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var moved: [(weekday: Int, slot: String, atMin: Int)] {
        (week?.days ?? []).flatMap { day in
            day.meals.filter(\.moved).map { (day.weekday, $0.slot, $0.atMin) }
        }
    }

    var body: some View {
        let count = week?.movedCount ?? 0
        HStack(alignment: .center, spacing: 14) {
            Text("\(count)")
                .font(Typography.data(30, weight: .heavy))
                .foregroundStyle(count > 0 ? Palette.accent : Palette.inkSoft)
                .monospacedDigit()
                .contentTransition(.numericText())
                .frame(width: 52, height: 52)
                .background(count > 0 ? Palette.surface : Palette.surfaceSunk, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .opacity(refreshing ? 0.45 : 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(count == 1 ? "meal moves earlier this week" : "meals move earlier this week")
                    .font(Typography.data(15, weight: .bold))
                    .foregroundStyle(Palette.ink)
                Group {
                    if refreshing {
                        HStack(spacing: 6) {
                            BusyDots(tint: Palette.inkSoft)
                            Text("Updating your week")
                        }
                        .transition(.opacity)
                    } else {
                        Text(detail)
                            .lineLimit(2)
                            .transition(.opacity)
                    }
                }
                .font(Typography.data(13))
                .foregroundStyle(Palette.inkSoft)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(count > 0 ? Palette.accentTint : Palette.surfaceSunk.opacity(0.6), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .animation(Motion.adaptive(Motion.settle, reduceMotion: reduceMotion), value: refreshing)
        .animation(Motion.adaptive(Motion.settle, reduceMotion: reduceMotion), value: count)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var detail: String {
        if moved.isEmpty { return "Your meals already fit around your busy time." }
        return moved
            // Non-breaking spaces keep "Fri lunch 11:45" on one line.
            .map { "\(CalendarDates.shortWeekday($0.weekday))\u{00A0}\($0.slot)\u{00A0}\(CalendarClock.hm($0.atMin))" }
            .joined(separator: " · ")
    }
}
