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
        if minutes < 60 { return L10n( "\(minutes) min") }
        let hours = minutes / 60
        let rest = minutes % 60
        switch rest {
        case 0: return hours == 1 ? L10n("1 hour") : L10n("\(hours) hours")
        case 30: return L10n( "\(hours)½ hours")
        default: return L10n( "\(hours) h \(rest) min")
        }
    }
}

enum CalendarCopy {
    static func slotName(_ slot: String) -> String {
        switch slot {
        case "breakfast": return L10n( "Breakfast")
        case "lunch": return L10n( "Lunch")
        case "dinner": return L10n( "Dinner")
        default: return slot.capitalized
        }
    }

    static func previousMeal(_ slot: String) -> String {
        slot == "dinner" ? slotName("lunch") : slotName("breakfast")
    }

    /// "Busy 12:00–15:30, so lunch is earlier." / "Busy 12:00–15:30. Lunch stays at 13:00."
    static func headline(slot: String, busy: CalendarWeekResponse.Span, kept: Bool, usualMin: Int) -> String {
        let range = CalendarClock.range(busy.startMin, busy.endMin)
        let meal = slotName(slot)
        return kept
            ? L10n( "Busy \(range). \(meal) stays at \(CalendarClock.hm(usualMin)).")
            : L10n( "Busy \(range), so \(meal.lowercased()) is earlier.")
    }

    static func keepTitle(slot: String, usualMin: Int) -> String {
        L10n( "Keep \(slotName(slot).lowercased()) at \(CalendarClock.hm(usualMin))")
    }

    static func moveTitle(slot: String, earlyMin: Int) -> String {
        L10n( "Move \(slotName(slot).lowercased()) to \(CalendarClock.hm(earlyMin))")
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
        let name = eventName ?? L10n( "A busy stretch")
        let meal = slotName(slot).lowercased()
        let start = CalendarClock.hm(busy.startMin)
        if kept {
            return L10n( "\(name) runs \(CalendarClock.range(busy.startMin, busy.endMin)). You kept \(meal) at \(CalendarClock.hm(usualMin)), so nothing comes early.")
        }
        let length = CalendarClock.duration(busy.endMin - busy.startMin)
        if reason == "floor" {
            return L10n( "\(name) starts \(start) and runs \(length). \(CalendarClock.hm(earlyMin)) is as early as it goes — never closer than 90 min after \(previousMeal(slot).lowercased()).")
        }
        return L10n( "\(name) starts \(start) and runs \(length). Your heads-up is \(leadMin) min before it starts, so \(meal) moves to \(CalendarClock.hm(earlyMin)).")
    }

    /// "1 hour or longer"
    static func minBlock(_ minutes: Int) -> String {
        L10n( "\(CalendarClock.duration(minutes)) or longer")
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
        case .tooShort: return L10n( "Too short to count")
        case .allDayOff: return L10n( "All-day events are off")
        case .weekend: return L10n( "Weekend — doesn't count")
        }
    }
}

// MARK: Rows

struct CalendarLockLine: View {
    var text = "Only start and end times leave this phone."

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock")
                .font(.system(size: 12, weight: .semibold))
            Text(LocalizedStringKey(text))
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
            return keep
                ? L10n("Keeping \(meal) at \(CalendarClock.hm(usualMin))")
                : L10n("Moving \(meal) to \(CalendarClock.hm(earlyMin))")
        case let .done(kept):
            let name = CalendarCopy.slotName(slot)
            return kept
                ? L10n("\(name) kept at \(CalendarClock.hm(usualMin))")
                : L10n("\(name) moved to \(CalendarClock.hm(earlyMin))")
        }
    }

    var body: some View {
        let busy = stage == .saving
        let done = stage != .idle && !busy
        Button {
            guard stage == .idle else { return }
            Task { await run() }
        } label: {
            BusyLabel(title: title, busy: busy, done: done, tint: done ? Palette.positive : Palette.ink)
                .font(Typography.data(style == .card ? 15 : 13, weight: .regular))
                .foregroundStyle(done ? Palette.positive : Palette.ink)
                .lineLimit(1)
                .frame(maxWidth: style == .card ? .infinity : nil)
                .padding(.horizontal, style == .card ? 16 : 12)
                .padding(.vertical, style == .card ? 14 : 8)
                .background {
                    switch style {
                    case .card:
                        Capsule(style: .continuous)
                            .fill(done ? Palette.positive.opacity(0.12) : Color.white.opacity(0.06))
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(done ? Palette.positive.opacity(0.35) : Color.white.opacity(0.10), lineWidth: 1)
                            )
                    case .chip:
                        Capsule().fill(done ? Palette.positive.opacity(0.14) : Color.white.opacity(0.06))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableCard())
        .allowsHitTesting(stage == .idle)
        .animation(Motion.adaptive(Motion.settle, reduceMotion: reduceMotion), value: stage)
        .accessibilityLabel(LocalizedStringKey(title))
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
        Text("Connected · Apple Calendar")
            .font(Typography.data(12, weight: .regular))
            .foregroundStyle(Palette.positive)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Palette.positive.opacity(0.10), in: Capsule())
    }
}

