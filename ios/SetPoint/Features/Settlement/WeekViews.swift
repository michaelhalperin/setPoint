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
            Headline(headline, tail: subline, size: 26)

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
                    .accessibilityLabel("\(station.accessibilityTitle), \(station.kcalConsumed) of \(station.kcalTarget) kilocalories, \(station.kindLabel)")
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
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.veryShortWeekdaySymbols[calendar.component(.weekday, from: date) - 1]
    }

    private var headline: String {
        guard let gap, gap.totalDays > 0 else { return "Week one." }
        return "\(gap.closedDays) of \(gap.totalDays) days closed."
    }

    private var subline: String {
        guard let gap, gap.totalDays > 0 else { return "Your first day settles tonight." }
        if gap.closedDays == gap.totalDays { return "Every day hit its target." }
        if let short = gap.avgShortfallKcal { return "Short days ran \(short.formatted()) under." }
        return "Keep closing the gap."
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
                Text(record.checkIns == 0 ? "NO CHECK-INS" : "\(record.checkIns) CHECK-IN\(record.checkIns == 1 ? "" : "S")")
                    .font(Typography.mono(11))
                    .foregroundStyle(Palette.inkFaint)
            }

            if !record.days.isEmpty {
                grid
            }

            HStack(alignment: .top, spacing: 8) {
                stat(record.onTime, "on time", tint: Palette.amber) { Circle().fill(Palette.amber) }
                stat(record.afterCheckIn, "after a nudge", tint: Palette.ink) { Circle().strokeBorder(Palette.amber, lineWidth: 1.5) }
                stat(record.missed, "missed", tint: Palette.inkSoft) {
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
                    Text(title)
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
        .accessibilityLabel("This week: \(record.onTime) meals on time, \(record.afterCheckIn) after a nudge, \(record.missed) missed")
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
                Text(label)
                    .font(Typography.data(11, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func patternCallout(_ pattern: SettlementResponse.Record.Pattern) -> some View {
        let title = MealSlot(rawValue: pattern.slot)?.title ?? "A meal"
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(title) ran late \(pattern.lateDays) of \(pattern.ofDays) workdays.")
                    .font(Typography.data(14, weight: .regular))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if patternApplied {
                    Text("Expecting it at \(clock24(pattern.suggestedMin)) now.")
                        .font(Typography.data(12, weight: .regular))
                        .foregroundStyle(Palette.inkSoft)
                } else {
                    Button("Keep \(clock24(pattern.currentMin))", action: onKeep)
                        .font(Typography.data(12, weight: .regular))
                        .foregroundStyle(Palette.inkSoft)
                        .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 8)
            Button(action: onApply) {
                BusyLabel(title: patternApplied ? "Moved" : "Move to \(clock24(pattern.suggestedMin))", busy: patternBusy, tint: Palette.onBone)
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
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.veryShortWeekdaySymbols[calendar.component(.weekday, from: date) - 1]
    }
}

// MARK: - Weight

/// The way to the target weight: the weigh-ins as a line climbing (or falling)
/// toward a dashed ring at the target, against the straight route there, with
/// today's weight as a lit orb at the end of the line. Tap to weigh in.
struct WeightJourneyCard: View {
    let goal: SettlementResponse.WeightGoal
    let entries: [WeightHistoryResponse.Entry]
    let busy: Bool
    let onWeighIn: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(MassUnit.storageKey) private var massUnit = MassUnit.localeDefault
    @State private var drawn: CGFloat = 0

    private var rising: Bool { goal.goal != "DIET" }

    var body: some View {
        Button(action: onWeighIn) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(label).sectionLabelStyle(Palette.amber)
                    Spacer(minLength: 8)
                    Group {
                        if busy {
                            BusyDots(tint: Palette.amber)
                        } else {
                            Text("Weigh in")
                                .font(Typography.data(12, weight: .regular))
                                .foregroundStyle(Palette.amber)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Palette.ember.opacity(0.14), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color(hex: 0xFF8A50, opacity: 0.5)))
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(goal.currentWeightKg.map { massUnit.number($0, digits: 1 ... 1) } ?? "—")
                        .font(Typography.data(54, weight: .light))
                        .tracking(-2.2)
                        .foregroundStyle(Palette.ink)
                        .contentTransition(.numericText())
                    Text(massUnit.abbreviation)
                        .font(Typography.data(15, weight: .regular))
                        .foregroundStyle(Palette.inkSoft)
                    if let left = toGoLine {
                        Text(left)
                            .font(Typography.data(15, weight: .regular))
                            .foregroundStyle(Palette.inkFaint)
                            .padding(.leading, 4)
                    }
                }

                chart
                    .frame(height: 112)
                    .padding(.bottom, 14)
                    .onAppear {
                        guard !reduceMotion else { drawn = 1; return }
                        withAnimation(.easeOut(duration: 1.2).delay(0.25)) { drawn = 1 }
                    }

                HStack(spacing: 14) {
                    if let rate = rateLine {
                        Text(rate)
                            .font(Typography.mono(11))
                            .foregroundStyle(Palette.amber)
                    }
                    if let status = statusLine {
                        Text(status)
                            .font(Typography.mono(11))
                            .foregroundStyle(goal.status == "behind" ? Palette.amber : Palette.inkFaint)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(LinearGradient(colors: [Palette.ember.opacity(0.14), Color.white.opacity(0.02)], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Color(hex: 0xFF8A50, opacity: goal.needsWeighIn ? 0.55 : 0.30))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCard())
        .disabled(busy)
        .accessibilityLabel(accessibility)
    }

    // MARK: Chart

    private struct Point { let x: Double; let kg: Double }

    /// Weigh-ins as (days since the first, kg), plus where the route ends.
    private var series: (points: [Point], endDay: Double, startKg: Double, targetKg: Double) {
        let parsed = entries.compactMap { entry -> (Date, Double)? in
            guard let date = MealFormat.parse(entry.measuredAt) else { return nil }
            return (date, entry.weightKg)
        }
        .sorted { $0.0 < $1.0 }
        let current = goal.currentWeightKg ?? parsed.last?.1 ?? 0
        let startKg = goal.startWeightKg ?? parsed.first?.1 ?? current
        let targetKg = goal.targetWeightKg ?? current
        guard let first = parsed.first?.0 else {
            return ([Point(x: 0, kg: current)], 56, startKg, targetKg)
        }
        let points = parsed.map { Point(x: $0.0.timeIntervalSince(first) / 86_400, kg: $0.1) }
        let span = points.last?.x ?? 0
        let ahead = Double((goal.etaWeeks ?? 8) * 7)
        return (points, max(span + ahead, span + 14, 28), startKg, targetKg)
    }

    private var chart: some View {
        let s = series
        let lo = min(s.startKg, s.targetKg, s.points.map(\.kg).min() ?? s.startKg)
        let hi = max(s.startKg, s.targetKg, s.points.map(\.kg).max() ?? s.targetKg)
        let span = max(hi - lo, 0.5)
        return GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let px = { (day: Double) -> CGFloat in 8 + CGFloat(day / s.endDay) * (w - 26) }
            let py = { (kg: Double) -> CGFloat in 14 + CGFloat(1 - (kg - lo) / span) * (h - 30) }
            let route = Path { p in
                p.move(to: CGPoint(x: px(0), y: py(s.startKg)))
                p.addLine(to: CGPoint(x: px(s.endDay), y: py(s.targetKg)))
            }
            let line = Path { p in
                for (i, point) in s.points.enumerated() {
                    let c = CGPoint(x: px(point.x), y: py(point.kg))
                    if i == 0 { p.move(to: c) } else { p.addLine(to: c) }
                }
            }
            let last = s.points.last.map { CGPoint(x: px($0.x), y: py($0.kg)) } ?? CGPoint(x: px(0), y: py(s.startKg))
            let target = CGPoint(x: px(s.endDay), y: py(s.targetKg))
            ZStack(alignment: .topLeading) {
                route.stroke(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 1.2, dash: [3, 5]))
                if s.points.count >= 2 {
                    Path { p in
                        p.addPath(line)
                        p.addLine(to: CGPoint(x: last.x, y: h))
                        p.addLine(to: CGPoint(x: px(0), y: h))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [Palette.ember.opacity(0.26), Palette.ember.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .opacity(Double(drawn))
                    line.trim(from: 0, to: drawn)
                        .stroke(Palette.amber, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                        .shadow(color: Palette.amber.opacity(0.5), radius: 4)
                }
                Circle()
                    .strokeBorder(Palette.amber.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5]))
                    .frame(width: 18, height: 18)
                    .position(target)
                Text(massUnit.number(s.targetKg, digits: 1 ... 1))
                    .font(Typography.mono(10))
                    .foregroundStyle(Palette.amber)
                    .fixedSize()
                    .position(x: target.x - 34, y: target.y)
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: 0xFFE9CC), Palette.amber, Color(hex: 0xF06A2E), Color(hex: 0x6E220E)], center: UnitPoint(x: 0.34, y: 0.28), startRadius: 0, endRadius: 11))
                    .frame(width: 18, height: 18)
                    .shadow(color: Palette.ember.opacity(0.75), radius: 9)
                    .position(last)
                Text(startCaption(s.startKg))
                    .font(Typography.mono(10))
                    .foregroundStyle(Palette.inkFaint)
                    .fixedSize()
                    .frame(width: w, alignment: .leading)
                    .position(x: w / 2, y: h + 6)
                if let eta = etaCaption {
                    Text(eta)
                        .font(Typography.mono(10))
                        .foregroundStyle(Palette.inkFaint)
                        .fixedSize()
                        .frame(width: w, alignment: .trailing)
                        .position(x: w / 2, y: h + 6)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func startCaption(_ kg: Double) -> String {
        var text = massUnit.number(kg, digits: 1 ... 1)
        if let first = entries.compactMap({ MealFormat.parse($0.measuredAt) }).min() {
            text += " · " + first.formatted(.dateTime.day().month(.abbreviated)).uppercased()
        }
        return text
    }

    // MARK: Copy

    private var label: String {
        let word = goal.status == "reached" ? "Reached" : rising ? "Gaining" : "Losing"
        guard let target = goal.targetWeightKg else { return word }
        return "\(word) · to \(massUnit.formatKg(target))"
    }

    private var toGoLine: String? {
        guard goal.status != "reached", let remaining = goal.remainingKg else { return nil }
        return "\(massUnit.number(abs(remaining), digits: 1 ... 1)) to go"
    }

    /// Kg a week from the first to the last weigh-in, once they're a week apart.
    private var rateLine: String? {
        let parsed = entries.compactMap { e in MealFormat.parse(e.measuredAt).map { ($0, e.weightKg) } }.sorted { $0.0 < $1.0 }
        guard let first = parsed.first, let last = parsed.last else { return nil }
        let weeks = last.0.timeIntervalSince(first.0) / (7 * 86_400)
        guard weeks >= 1 else { return nil }
        let rate = massUnit.fromKg((last.1 - first.1) / weeks)
        let digits = massUnit == .lb ? 1 : 2
        return "\(rate >= 0 ? "+" : "−")\(abs(rate).formatted(.number.precision(.fractionLength(digits)))) / WK NOW"
    }

    private var statusLine: String? {
        switch goal.status {
        case "ahead": return "AHEAD OF PLAN"
        case "on_pace": return "ON PACE"
        case "behind": return "BEHIND PLAN"
        case "reached": return "TARGET REACHED"
        default: return goal.needsWeighIn ? "WEIGH-IN DUE" : nil
        }
    }

    private var etaCaption: String? {
        guard goal.status != "reached", let weeks = goal.etaWeeks, weeks > 0 else { return nil }
        return weeks == 1 ? "~1 WEEK TO GO" : "~\(weeks) WEEKS TO GO"
    }

    private var accessibility: String {
        var parts = ["Weight \(goal.currentWeightKg.map { massUnit.number($0, digits: 1 ... 1) } ?? "unknown") \(massUnit.spokenName)"]
        if let left = toGoLine { parts.append(left) }
        if let status = statusLine { parts.append(status.lowercased()) }
        parts.append("Log a weigh-in")
        return parts.joined(separator: ". ")
    }
}

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
        let amount = "\(rate.formatted(.number.precision(.fractionLength(digits)))) \(massUnit.abbreviation) a week"
        if rate < 0.005 { return "weight holding steady" }
        return review.trendKgPerWeek > 0 ? "gaining \(amount)" : "losing \(amount)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Plan check").sectionLabelStyle(Palette.amber)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(review.previousKcal.formatted())
                    .font(Typography.mono(22))
                    .foregroundStyle(Palette.inkFaint)
                    .strikethrough(color: Color.white.opacity(0.3))
                Image(systemName: "arrow.right")
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
            .accessibilityLabel("From \(review.previousKcal) to \(review.proposedKcal) kilocalories a day")
            Text(review.reason)
                .font(Typography.data(15, weight: .regular))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Based on \(review.weighInCount) weigh-ins · \(trendLine)")
                .font(Typography.mono(11))
                .foregroundStyle(Palette.inkFaint)
            HStack(spacing: 8) {
                Button(action: onAccept) {
                    BusyLabel(title: review.deltaKcal >= 0 ? "Raise it" : "Lower it", busy: busy, tint: Palette.onBone)
                        .font(Typography.data(15, weight: .medium))
                        .foregroundStyle(Palette.onBone)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Palette.ink, in: Capsule())
                }
                .buttonStyle(PressableCard())
                .disabled(busy)
                Button(action: onLater) {
                    Text("Keep \(review.previousKcal.formatted())")
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

// MARK: - Weigh-in

struct WeighInSheet: View {
    /// The last weigh-in, to start the ruler there and show the change.
    let lastKg: Double?
    /// Returns whether the weigh-in saved — on success the sheet shows a brief
    /// "Saved" beat, then dismisses itself.
    let onSubmit: (Double) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var value: Double
    @State private var phase: Phase = .idle

    private enum Phase { case idle, saving, saved }

    init(lastKg: Double?, onSubmit: @escaping (Double) async -> Bool) {
        self.lastKg = lastKg
        self.onSubmit = onSubmit
        let unit = MassUnit.current
        _value = State(initialValue: ((unit.fromKg(lastKg ?? 70) * 10).rounded() / 10))
    }

    private var range: ClosedRange<Double> {
        let unit = MassUnit.current
        let base = unit.fromKg(lastKg ?? 70).rounded()
        let span = unit.fromKg(20)
        return max(unit.fromKg(25), base - span) ... min(unit.fromKg(400), base + span)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Headline("Weigh-in.", tail: "Morning, before food.", size: 30)

            HStack {
                StepCircle(symbol: "minus", label: "Less", size: 56) { nudge(-0.1) }
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(oneDecimal(value))
                        .font(.system(size: 64, weight: .light))
                        .tracking(-2.5)
                        .foregroundStyle(Palette.ink)
                        .contentTransition(.numericText(value: value))
                    Text(MassUnit.current.abbreviation)
                        .font(Typography.data(18, weight: .regular))
                        .foregroundStyle(Palette.inkSoft)
                }
                .accessibilityElement(children: .combine)
                Spacer()
                StepCircle(symbol: "plus", label: "More", size: 56) { nudge(0.1) }
            }

            RulerPicker(value: $value, range: range, step: 0.1, unit: MassUnit.current.abbreviation, majorStep: 1, fractionDigits: 1, showsValue: false)

            if let lastKg {
                let lastDisplay = MassUnit.current.fromKg(lastKg)
                let delta = value - lastDisplay
                Text(abs(delta) < 0.05 ? "Same as last time" : "\(delta > 0 ? "+" : "−")\(oneDecimal(abs(delta))) \(MassUnit.current.abbreviation) since last time")
                    .font(Typography.data(13, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
                    .frame(maxWidth: .infinity)
                    .contentTransition(.numericText())
            }

            ActionButton(
                title: "Save",
                busy: phase == .saving,
                busyTitle: "Saving",
                done: phase == .saved,
                doneTitle: "Saved",
                symbol: "checkmark"
            ) { save() }
            .animation(Motion.adaptive(Motion.settle, reduceMotion: reduceMotion), value: phase)
        }
        .padding(Space.gutter)
        .padding(.top, Space.xs)
        .frame(maxWidth: .infinity)
        .presentationDetents([.height(lastKg == nil ? 400 : 430)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.sheet)
        .presentationCornerRadius(32)
    }

    private func nudge(_ delta: Double) {
        withAnimation(Motion.settle) {
            value = min(range.upperBound, max(range.lowerBound, ((value + delta) * 10).rounded() / 10))
        }
    }

    private func save() {
        guard phase == .idle else { return }
        Task {
            phase = .saving
            let ok = await onSubmit(MassUnit.current.toKg((value * 10).rounded() / 10))
            guard ok else { phase = .idle; return }
            phase = .saved
            Haptics.landed()
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 480))
            dismiss()
        }
    }
}
