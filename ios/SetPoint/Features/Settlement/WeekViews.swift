import SwiftUI

// Progress: days closed as a bar per day, weight against the planned pace, a
// plan check when the numbers say so, one late-meal pattern to fix, and how the
// check-ins went.

private func oneDecimal(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(1)))
}

// MARK: - The record

/// The week's headline for someone who can't eat enough: how many days reached
/// the target, as a bar per day against a dashed target line. Tap a bar for
/// that day's meals.
struct DaysClosedCard: View {
    let gap: SettlementResponse.Gap?
    let stations: [WeekStation]
    let onSelect: (WeekStation) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Headline(headline, tail: subline, size: 26)

            ZStack(alignment: .top) {
                Rectangle()
                    .stroke(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(height: 1)
                    .padding(.top, 10)
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(Array(stations.enumerated()), id: \.element.id) { index, station in
                        Button { onSelect(station) } label: {
                            VStack(spacing: 6) {
                                bar(station)
                                    .frame(maxWidth: 34)
                                    .frame(height: max(4, 70 * CGFloat(station.fill)))
                                    .frame(height: 70, alignment: .bottom)
                                    .appearIn(index, rise: 0)
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
                .padding(.top, 10)
            }
            .frame(height: 96)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(radius: Radius.xl)
    }

    @ViewBuilder
    private func bar(_ station: WeekStation) -> some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        switch station.kind {
        case "ON_TRACK", "OVER":
            shape
                .fill(LinearGradient(colors: [Palette.amber, Palette.ember], startPoint: .top, endPoint: .bottom))
                .shadow(color: Palette.ember.opacity(0.35), radius: 6)
                .opacity(station.isToday ? 0.6 : 1)
        case "UNDER":
            shape.fill(Palette.ember.opacity(station.isToday ? 0.35 : 0.45))
        default:
            shape.fill(Color.white.opacity(0.12))
        }
    }

    private func letter(_ station: WeekStation) -> String {
        guard let date = WeekStation.parse(station.date) else { return "" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return String(calendar.shortWeekdaySymbols[calendar.component(.weekday, from: date) - 1].prefix(2))
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

struct RecordCard: View {
    let record: SettlementResponse.Record

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Check-ins").sectionLabelStyle()
                Spacer()
                Text(record.checkIns == 0 ? "None this week" : "\(record.checkIns) this week")
                    .font(Typography.mono(11))
                    .foregroundStyle(Palette.inkFaint)
            }
            HStack(spacing: 0) {
                stat(record.onTime, "on time")
                stat(record.afterCheckIn, "after a nudge")
                stat(record.missed, "missed")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(radius: 24)
        .accessibilityElement(children: .combine)
    }

    private func stat(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(Typography.data(26, weight: .light))
                .foregroundStyle(Palette.ink)
                .contentTransition(.numericText(value: Double(value)))
            Text(label)
                .font(Typography.data(12, weight: .regular))
                .foregroundStyle(Palette.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Pattern

struct PatternCard: View {
    let pattern: SettlementResponse.Record.Pattern
    let busy: Bool
    let onApply: () -> Void
    let onKeep: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var slotTitle: String {
        MealSlot(rawValue: pattern.slot)?.title ?? "A meal"
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(slotTitle) ran late \(pattern.lateDays) of \(pattern.ofDays) workdays")
                    .font(Typography.data(15, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Keep \(formatMinutes(pattern.currentMin))", action: onKeep)
                    .font(Typography.data(13, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
                    .buttonStyle(.plain)
            }
            Spacer(minLength: 8)
            Button(action: onApply) {
                BusyLabel(title: "Expect \(formatMinutes(pattern.suggestedMin))", busy: busy, tint: Palette.onBone)
                    .font(Typography.data(13, weight: .medium))
                    .foregroundStyle(Palette.onBone)
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(Palette.ink, in: Capsule())
            }
            .buttonStyle(PressableCard())
            .disabled(busy)
            .animation(Motion.adaptive(Motion.settle, reduceMotion: reduceMotion), value: busy)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .glass(radius: 24, fill: Color.white.opacity(0.03))
    }
}

// MARK: - Weight

struct WeightTrendCard: View {
    let goal: SettlementResponse.WeightGoal
    let entries: [WeightHistoryResponse.Entry]
    let busy: Bool
    let onWeighIn: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(MassUnit.storageKey) private var massUnit = MassUnit.localeDefault
    @State private var drawn: CGFloat = 0

    var body: some View {
        Button(action: onWeighIn) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(goal.currentWeightKg.map { massUnit.number($0, digits: 1 ... 1) } ?? "—")
                            .font(Typography.data(26, weight: .light))
                            .foregroundStyle(Palette.ink)
                            .contentTransition(.numericText())
                        Text(massUnit.abbreviation)
                            .font(Typography.data(13, weight: .regular))
                            .foregroundStyle(Palette.inkSoft)
                    }
                    Text(detailLine)
                        .font(Typography.mono(11))
                        .foregroundStyle(Palette.inkSoft)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .fixedSize(horizontal: true, vertical: false)

                ZStack {
                    PlanLine(rising: goal.goal != "DIET")
                        .stroke(Color.white.opacity(0.25), style: StrokeStyle(lineWidth: 1.2, dash: [3, 4]))
                    if entries.count >= 2 {
                        Sparkline(values: entries.map(\.weightKg))
                            .trim(from: 0, to: drawn)
                            .stroke(Palette.amber, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            .shadow(color: Palette.amber.opacity(0.5), radius: 4)
                    }
                }
                .frame(height: 56)
                .frame(maxWidth: .infinity)
                .onAppear {
                    guard !reduceMotion else { drawn = 1; return }
                    withAnimation(.easeOut(duration: 1.2).delay(0.3)) { drawn = 1 }
                }

                Group {
                    if busy {
                        BusyDots(tint: Palette.amber)
                    } else {
                        Text(goal.needsWeighIn ? "Weigh in" : statusLabel ?? "Weigh in")
                    }
                }
                .font(Typography.data(12, weight: .regular))
                .foregroundStyle(goal.needsWeighIn || goal.status == "behind" ? Palette.amber : statusTint)
                .fixedSize()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .glass(radius: 24, stroke: goal.needsWeighIn ? Palette.amber.opacity(0.4) : Palette.hairline)
        }
        .buttonStyle(PressableCard())
        .disabled(busy)
        .accessibilityLabel("Weight \(goal.currentWeightKg.map { massUnit.number($0, digits: 1 ... 1) } ?? "unknown") \(massUnit.spokenName). Log a weigh-in.")
    }

    private var detailLine: String {
        if let remaining = goal.remainingKg, let target = goal.targetWeightKg, goal.status != "reached" {
            return "\(massUnit.formatKg(remaining)) to \(massUnit.formatKg(target))"
        }
        return goal.status == "reached" ? "target reached" : "weigh in weekly"
    }

    private var statusLabel: String? {
        switch goal.status {
        case "ahead": return "Ahead"
        case "on_pace": return "On pace"
        case "behind": return "Behind"
        case "reached": return "Reached"
        default: return nil
        }
    }

    private var statusTint: Color {
        goal.status == "behind" ? Palette.amber : Palette.positive
    }
}

/// The planned pace: a straight dashed line, rising or falling.
private struct PlanLine: Shape {
    let rising: Bool

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rising ? rect.maxY - 4 : rect.minY + 4))
        p.addLine(to: CGPoint(x: rect.maxX, y: rising ? rect.minY + 4 : rect.maxY - 4))
        return p
    }
}

/// A smooth line through the values, scaled to fill its frame.
private struct Sparkline: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        guard values.count >= 2, let lo = values.min(), let hi = values.max() else { return Path() }
        let span = max(hi - lo, 0.5)
        let points = values.enumerated().map { index, value in
            CGPoint(
                x: rect.minX + rect.width * CGFloat(index) / CGFloat(values.count - 1),
                y: rect.maxY - 4 - (rect.height - 8) * CGFloat((value - lo) / span)
            )
        }
        var path = Path()
        path.move(to: points[0])
        for (previous, point) in zip(points, points.dropFirst()) {
            let midX = (previous.x + point.x) / 2
            path.addCurve(to: point, control1: CGPoint(x: midX, y: previous.y), control2: CGPoint(x: midX, y: point.y))
        }
        return path
    }
}

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
        VStack(alignment: .leading, spacing: 12) {
            Text("Plan check").sectionLabelStyle(Palette.amber)
            (Text(review.deltaKcal >= 0 ? "Raise your day to " : "Lower your day to ").foregroundColor(Palette.ink)
                + Text(review.proposedKcal.formatted()).font(Typography.mono(17)).foregroundColor(Palette.amber)
                + Text("?").foregroundColor(Palette.ink))
                .font(Typography.data(17, weight: .regular))
            Text(review.reason)
                .font(Typography.data(13, weight: .regular))
                .foregroundStyle(Palette.inkSoft)
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
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [Palette.ember.opacity(0.10), Palette.ember.opacity(0.03)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color(hex: 0xFF8A50, opacity: 0.4)))
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
