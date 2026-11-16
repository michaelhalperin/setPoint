import SwiftUI

// Progress: the way to the target weight, the week's days as orbs filled to how
// much went in, how each meal landed (with one late-meal pattern to fix), and a
// plan check when the numbers say so.

private func oneDecimal(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(1)))
}

// MARK: - Days closed

/// The week's headline for someone who can't eat enough: each day an orb filled
/// to how much of the target went in. Closed days glow full. Tap a day for its meals.
struct DayOrbsCard: View {
    let gap: SettlementResponse.Gap?
    let stations: [WeekStation]
    let onSelect: (WeekStation) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Headline(headline, tail: subline, size: 26, persistTail: true)

            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(stations.enumerated()), id: \.element.id) { index, station in
                    Button { onSelect(station) } label: {
                        VStack(spacing: 6) {
                            orb(station, index: index)
                            Text(letter(station))
                                .font(Typography.mono(10))
                                .foregroundStyle(station.isToday ? Palette.ink : Palette.inkFaint)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableCard())
                    .accessibilityLabel(L10n("\(station.accessibilityTitle), \(station.kcalConsumed) of \(station.kcalTarget) kilocalories, \(station.kindLabel)"))
                }
            }

            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(RadialGradient(colors: [Color(hex: 0xFFE0B8), Palette.ember], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 7))
                        .frame(width: 10, height: 10)
                    Text("Closed").font(Typography.data(12, weight: .regular)).foregroundStyle(Palette.inkSoft)
                }
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.white.opacity(0.03))
                        .overlay(alignment: .bottom) { Rectangle().fill(Palette.amber.opacity(0.5)).frame(height: 5) }
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.25)))
                        .frame(width: 10, height: 10)
                    Text("Short · filled to how much").font(Typography.data(12, weight: .regular)).foregroundStyle(Palette.inkSoft)
                }
            }
            .accessibilityHidden(true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(radius: 26)
    }

    private func closed(_ station: WeekStation) -> Bool {
        station.kind == "ON_TRACK" || station.kind == "OVER"
    }

    private func orb(_ station: WeekStation, index: Int) -> some View {
        let size: CGFloat = 36
        let isClosed = closed(station) && !station.isToday || (station.isToday && station.fill >= 1)
        return ZStack(alignment: .bottom) {
            Circle().fill(Color.white.opacity(0.03))
            if isClosed {
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: 0xFFE0B8), Palette.ember, Color(hex: 0x8E2C12)], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.75))
            } else {
                Rectangle()
                    .fill(LinearGradient(colors: [Palette.amber.opacity(0.32), Palette.ember.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                    .frame(height: size * CGFloat(station.fill))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            if station.isToday {
                Circle().strokeBorder(Palette.amber, lineWidth: 1.5)
            } else if !isClosed {
                Circle().strokeBorder(Color.white.opacity(0.14))
            }
        }
        .shadow(color: Palette.ember.opacity(isClosed ? 0.45 : 0), radius: 7)
        .appearIn(index, rise: 6)
    }

    private func letter(_ station: WeekStation) -> String {
        guard let date = WeekStation.parse(station.date) else { return "" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = AppLanguage.current.locale
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.veryShortWeekdaySymbols[calendar.component(.weekday, from: date) - 1]
    }

    private var headline: String {
        guard let gap, gap.totalDays > 0 else { return L10n( "Week one.") }
        return L10n( "\(gap.closedDays) of \(gap.totalDays) days closed.")
    }

    private var subline: String {
        guard let gap, gap.totalDays > 0 else { return L10n( "Your first day settles tonight.") }
        if gap.closedDays == gap.totalDays { return L10n( "Every day hit its target.") }
        if let short = gap.avgShortfallKcal { return L10n( "Short days ran \(short.formatted()) under.") }
        return L10n( "Keep closing the gap.")
    }
}

// MARK: - How meals landed

/// Breakfast, lunch and dinner across the week: on time, after a nudge, or
/// missed — then one late-meal pattern to fix, if there is one.
struct LandedCard: View {
    let record: SettlementResponse.Record
    var pattern: SettlementResponse.Record.Pattern?
    var patternApplied = false
    var patternBusy = false
    var onApply: () -> Void = {}
    var onKeep: () -> Void = {}

    private static let slots = ["Breakfast", "Lunch", "Dinner"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("How meals landed").sectionLabelStyle()
                Spacer()
                Text(record.checkIns == 0 ? L10n("NO CHECK-INS") : record.checkIns == 1 ? L10n("1 CHECK-IN") : L10n("\(record.checkIns) CHECK-INS"))
                    .font(Typography.mono(11))
                    .foregroundStyle(Palette.inkFaint)
            }

            if !record.days.isEmpty {
                grid
            }

            HStack(alignment: .top, spacing: 8) {
                stat(record.onTime, L10n("on time"), tint: Palette.amber) { Circle().fill(Palette.amber) }
                stat(record.afterCheckIn, L10n("after a nudge"), tint: Palette.ink) { Circle().strokeBorder(Palette.amber, lineWidth: 1.5) }
                stat(record.missed, L10n("missed"), tint: Palette.inkSoft) {
                    Capsule().fill(Color.white.opacity(0.35)).frame(height: 2)
                }
            }

            if let pattern {
                patternCallout(pattern)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(radius: 26)
    }

    private var grid: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(Self.slots.enumerated()), id: \.offset) { slotIndex, title in
                HStack(spacing: 10) {
                    Text(LocalizedStringKey(title))
                        .font(Typography.data(12, weight: .regular))
                        .foregroundStyle(Palette.inkSoft)
                        .frame(width: 66, alignment: .leading)
                    HStack(spacing: 0) {
                        ForEach(record.days) { day in
                            cell(day.slots.indices.contains(slotIndex) ? day.slots[slotIndex] : "open")
                                .frame(width: 12, height: 12)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            HStack(spacing: 10) {
                Color.clear.frame(width: 66, height: 1)
                HStack(spacing: 0) {
                    ForEach(record.days) { day in
                        Text(letter(day.date))
                            .font(Typography.mono(9))
                            .foregroundStyle(Palette.inkFaint)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n("This week: \(record.onTime) meals on time, \(record.afterCheckIn) after a nudge, \(record.missed) missed"))
    }

    @ViewBuilder
    private func cell(_ state: String) -> some View {
        switch state {
        case "on_time":
            Circle().fill(Palette.amber).shadow(color: Palette.amber.opacity(0.6), radius: 3)
        case "after_check_in":
            Circle().strokeBorder(Palette.amber, lineWidth: 2)
        case "missed":
            Capsule().fill(Color.white.opacity(0.32)).frame(height: 2)
        default:
            Circle().strokeBorder(Color.white.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
        }
    }

    private func stat(_ value: Int, _ label: String, tint: Color, @ViewBuilder glyph: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)")
                .font(Typography.data(22, weight: .light))
                .foregroundStyle(tint)
                .contentTransition(.numericText(value: Double(value)))
            HStack(spacing: 6) {
                glyph().frame(width: 8, height: 8)
                Text(LocalizedStringKey(label))
                    .font(Typography.data(11, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func patternCallout(_ pattern: SettlementResponse.Record.Pattern) -> some View {
        let title = MealSlot(rawValue: pattern.slot)?.title ?? L10n("A meal")
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n("\(title) ran late \(pattern.lateDays) of \(pattern.ofDays) workdays."))
                    .font(Typography.data(14, weight: .regular))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if patternApplied {
                    Text(L10n("Expecting it at \(clock24(pattern.suggestedMin)) now."))
                        .font(Typography.data(12, weight: .regular))
                        .foregroundStyle(Palette.inkSoft)
                } else {
                    Button(L10n("Keep \(clock24(pattern.currentMin))"), action: onKeep)
                        .font(Typography.data(12, weight: .regular))
                        .foregroundStyle(Palette.inkSoft)
                        .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 8)
            Button(action: onApply) {
                BusyLabel(title: patternApplied ? L10n("Moved") : L10n("Move to \(clock24(pattern.suggestedMin))"), busy: patternBusy, tint: Palette.onBone)
                    .font(Typography.data(13, weight: .medium))
                    .foregroundStyle(patternApplied ? Palette.positive : Palette.onBone)
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(patternApplied ? Palette.positive.opacity(0.10) : Palette.ink, in: Capsule())
                    .overlay(Capsule().strokeBorder(patternApplied ? Palette.positive.opacity(0.4) : .clear))
            }
            .buttonStyle(PressableCard())
            .disabled(patternBusy || patternApplied)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Palette.haze.opacity(0.12), Palette.haze.opacity(0.03)], startPoint: .top, endPoint: .bottom))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Palette.hazeSoft.opacity(0.30))
        }
    }

    private func letter(_ iso: String) -> String {
        guard let date = WeekStation.parse(iso) else { return "" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = AppLanguage.current.locale
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.veryShortWeekdaySymbols[calendar.component(.weekday, from: date) - 1]
    }
}

// MARK: - Weight

// MARK: - Plan check

struct TargetReviewCard: View {
    let review: SettlementResponse.TargetReview
    var busy = false
    let onAccept: () -> Void
    let onLater: () -> Void

    @AppStorage(MassUnit.storageKey) private var massUnit = MassUnit.localeDefault

    /// "gaining 0.1 lb a week" — the server sends kg, shown in the user's unit.
    private var trendLine: String {
        let rate = massUnit.fromKg(abs(review.trendKgPerWeek))
        let digits = massUnit == .lb ? 1 : 2
        let amount = L10n("\(rate.formatted(.number.precision(.fractionLength(digits)))) \(massUnit.abbreviation) a week")
        if rate < 0.005 { return L10n( "weight holding steady") }
        return review.trendKgPerWeek > 0 ? L10n("gaining \(amount)") : L10n("losing \(amount)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Plan check").sectionLabelStyle(Palette.amber)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(review.previousKcal.formatted())
                    .font(Typography.mono(22))
                    .foregroundStyle(Palette.inkFaint)
                    .strikethrough(color: Color.white.opacity(0.3))
                Image(systemName: "arrow.forward")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.amber)
                Text(review.proposedKcal.formatted())
                    .font(Typography.mono(30))
                    .foregroundStyle(Palette.amber)
                Text("a day")
                    .font(Typography.data(13, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n("From \(review.previousKcal) to \(review.proposedKcal) kilocalories a day"))
            Text(review.reason)
                .font(Typography.data(15, weight: .regular))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(L10n("Based on \(review.weighInCount) weigh-ins · \(trendLine)"))
                .font(Typography.mono(11))
                .foregroundStyle(Palette.inkFaint)
            HStack(spacing: 8) {
                Button(action: onAccept) {
                    BusyLabel(title: review.deltaKcal >= 0 ? L10n("Raise it") : L10n("Lower it"), busy: busy, tint: Palette.onBone)
                        .font(Typography.data(15, weight: .medium))
                        .foregroundStyle(Palette.onBone)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Palette.ink, in: Capsule())
                }
                .buttonStyle(PressableCard())
                .disabled(busy)
                Button(action: onLater) {
                    Text(L10n("Keep \(review.previousKcal.formatted())"))
                        .font(Typography.data(15, weight: .regular))
                        .foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .glassCapsule(fill: Color.white.opacity(0.06), stroke: Color.white.opacity(0.10))
                }
                .buttonStyle(PressableCard())
            }
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(colors: [Palette.ember.opacity(0.11), Palette.ember.opacity(0.03)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color(hex: 0xFF8A50, opacity: 0.4)))
        }
    }
}
