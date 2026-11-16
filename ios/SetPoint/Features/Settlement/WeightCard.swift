import SwiftUI

/// The first card on Progress. Most of the week it is a trail: stations on the way to the target,
/// you as the lit orb, and the next stop named. Weighing in turns the same card into a ruler
/// (no sheet): drag or tap to set the weight, Save or Cancel. A due weigh-in opens the card as
/// the ruler.
struct WeightCard: View {
    let goal: SettlementResponse.WeightGoal
    let entries: [WeightHistoryResponse.Entry]
    var error: String? = nil
    @Binding var weighing: Bool
    /// Saves a weigh-in in kg; true when it saved.
    let onSave: (Double) async -> Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(MassUnit.storageKey) private var massUnit = MassUnit.localeDefault
    @State private var value: Double = 0
    @State private var phase: Phase = .idle
    @State private var drawn: CGFloat = 0

    private enum Phase { case idle, saving, saved }

    // MARK: Body

    var body: some View {
        // Both faces are always laid out, so the card is as tall as the taller one and never
        // changes size: only which face shows changes.
        ZStack(alignment: .top) {
            trail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .opacity(weighing ? 0 : 1)
                .allowsHitTesting(!weighing)
                .accessibilityHidden(weighing)
            ruler
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .opacity(weighing ? 1 : 0)
                .allowsHitTesting(weighing)
                .accessibilityHidden(!weighing)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(LinearGradient(colors: [Palette.ember.opacity(weighing ? 0.10 : 0.15), Color.white.opacity(0.02)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Color(hex: 0xFF8A50, opacity: weighing || goal.needsWeighIn ? 0.55 : 0.30))
        }
        .shadow(color: Palette.ember.opacity(weighing ? 0.20 : 0), radius: 26)
        .animation(Motion.adaptive(Motion.settle, reduceMotion: reduceMotion), value: weighing)
        .onAppear { resetValue() }
        .onChange(of: weighing) { _, on in if on { resetValue(); phase = .idle } }
    }

    // MARK: The ruler

    private var lastKg: Double? { entries.last?.weightKg ?? goal.currentWeightKg }

    private var range: ClosedRange<Double> {
        let base = massUnit.fromKg(lastKg ?? 70).rounded()
        let span = massUnit.fromKg(20)
        return max(massUnit.fromKg(25), base - span) ... min(massUnit.fromKg(400), base + span)
    }

    private func resetValue() {
        value = (massUnit.fromKg(lastKg ?? 70) * 10).rounded() / 10
    }

    private var ruler: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(goal.needsWeighIn ? "Weigh-in · this week" : "Weigh-in").sectionLabelStyle(Palette.amber)
                Spacer(minLength: 8)
                Button {
                    Haptics.select()
                    withAnimation(Motion.settle) { weighing = false }
                } label: {
                    Text("Cancel")
                        .font(Typography.data(14, weight: .regular))
                        .foregroundStyle(Palette.inkSoft)
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, -12)
                .disabled(phase != .idle)
            }
            .padding(.top, -6)

            HStack {
                StepCircle(symbol: "minus", label: "Less", size: 52) { nudge(-0.1) }
                Spacer(minLength: 4)
                VStack(spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(oneDecimal(value))
                            .font(.system(size: 66, weight: .light))
                            .tracking(-2.8)
                            .foregroundStyle(Palette.ink)
                            .contentTransition(.numericText(value: value))
                            .minimumScaleFactor(0.8)
                            .lineLimit(1)
                        Text(massUnit.abbreviation)
                            .font(Typography.data(16, weight: .regular))
                            .foregroundStyle(Palette.inkSoft)
                    }
                    .accessibilityElement(children: .combine)
                    if let lastKg {
                        let delta = value - massUnit.fromKg(lastKg)
                        Text(abs(delta) < 0.05 ? L10n("Same as last time") : L10n("\(delta > 0 ? "+" : "−")\(oneDecimal(abs(delta))) \(massUnit.abbreviation) since last time"))
                            .font(Typography.data(13, weight: .regular))
                            .foregroundStyle(abs(delta) < 0.05 ? Palette.inkSoft : Color(hex: 0x86EFAC))
                            .contentTransition(.numericText())
                    }
                }
                Spacer(minLength: 4)
                StepCircle(symbol: "plus", label: "More", size: 52) { nudge(0.1) }
            }
            .animation(Motion.adaptive(Motion.settle, reduceMotion: reduceMotion), value: value)

            RulerPicker(value: $value, range: range, step: 0.1, unit: massUnit.abbreviation, majorStep: 1, fractionDigits: 1, showsValue: false)

            Spacer(minLength: 0)

            ActionButton(
                title: "Save",
                busy: phase == .saving,
                busyTitle: "Saving",
                done: phase == .saved,
                doneTitle: "Saved",
                symbol: "checkmark"
            ) { save() }

            if let error {
                Text(LocalizedStringKey(error))
                    .font(Typography.data(13, weight: .regular))
                    .foregroundStyle(Palette.danger)
            } else if goal.status != "reached", let remaining = goal.remainingKg {
                Text(goalLine(remaining))
                    .font(Typography.mono(11))
                    .foregroundStyle(Palette.inkFaint)
                    .textCase(.uppercase)
                    .frame(maxWidth: .infinity)
            }
        }
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
            let ok = await onSave(massUnit.toKg((value * 10).rounded() / 10))
            guard ok else { phase = .idle; return }
            phase = .saved
            Haptics.landed()
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 700))
            withAnimation(Motion.settle) { weighing = false }
            phase = .idle
        }
    }

    private func goalLine(_ remainingKg: Double) -> String {
        var parts = [L10n("Goal \(massUnit.formatKg(goal.targetWeightKg ?? 0, digits: 0))"), L10n("\(massUnit.number(abs(remainingKg), digits: 1 ... 1)) to go")]
        if let weeks = goal.etaWeeks, weeks > 0 { parts.append(L10n("about \(weeks) weeks")) }
        return parts.joined(separator: " · ")
    }

    // MARK: The trail

    private var currentKg: Double? { goal.currentWeightKg ?? entries.last?.weightKg }

    private var trail: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Next stop").sectionLabelStyle(Palette.amber)
                Spacer(minLength: 8)
                if goal.needsWeighIn {
                    HStack(spacing: 6) {
                        Circle().fill(Palette.amber).frame(width: 6, height: 6)
                        Text("Weigh-in due").font(Typography.data(12, weight: .regular)).foregroundStyle(Palette.amber)
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 28)
                    .background(Palette.amber.opacity(0.14), in: Capsule())
                    .overlay(Capsule().strokeBorder(Palette.amber.opacity(0.5)))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                headline
                Text(sentence)
                    .font(Typography.data(14, weight: .regular))
                    .foregroundStyle(Palette.ink.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let current = currentKg, let start = goal.startWeightKg ?? entries.first?.weightKg, let target = goal.targetWeightKg {
                TrailView(start: massUnit.fromKg(start), current: massUnit.fromKg(current), target: massUnit.fromKg(target), step: stationStep, drawn: drawn)
                    .frame(height: 112)
                    .padding(.top, 4)
                    .onAppear {
                        guard !reduceMotion else { drawn = 1; return }
                        drawn = 0
                        withAnimation(.easeOut(duration: 1.1).delay(0.2)) { drawn = 1 }
                    }
            }

            Spacer(minLength: 0)

            Divider().overlay(Color.white.opacity(0.08))

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(lastLine).font(Typography.data(13, weight: .regular)).foregroundStyle(Palette.ink.opacity(0.85))
                    if let rate = rateLine {
                        Text(rate).font(Typography.mono(10)).foregroundStyle(Palette.inkFaint)
                    }
                }
                Spacer(minLength: 8)
                Button {
                    Haptics.select()
                    withAnimation(Motion.settle) { weighing = true }
                } label: {
                    Text("Weigh in")
                        .font(Typography.data(15, weight: goal.needsWeighIn ? .semibold : .regular))
                        .foregroundStyle(goal.needsWeighIn ? Palette.onBone : Palette.ink)
                        .padding(.horizontal, 18)
                        .frame(height: 44)
                        .background(goal.needsWeighIn ? AnyShapeStyle(Palette.ink) : AnyShapeStyle(Color.white.opacity(0.08)), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(goal.needsWeighIn ? 0 : 0.16)))
                }
                .buttonStyle(PressableCard())
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Trail copy

    private var rising: Bool { goal.goal != "DIET" }

    /// Whole units between stations: about six or fewer from start to target.
    private var stationStep: Double {
        let start = massUnit.fromKg(goal.startWeightKg ?? currentKg ?? 0)
        let target = massUnit.fromKg(goal.targetWeightKg ?? start)
        let span = abs(target - start)
        let options: [Double] = massUnit == .lb ? [2, 5, 10, 20, 50] : [1, 2, 5, 10, 20]
        return options.first { span / $0 <= 6 } ?? options.last!
    }

    /// The next station (or the target) still ahead of the current weight, in display units.
    private var nextStop: Double? {
        guard let current = currentKg.map(massUnit.fromKg), let target = goal.targetWeightKg.map(massUnit.fromKg) else { return nil }
        let step = stationStep
        if rising {
            let next = (floor(current / step) + 1) * step
            return min(next, target)
        } else {
            let next = (ceil(current / step) - 1) * step
            return max(next, target)
        }
    }

    private var headline: some View {
        Group {
            if goal.status == "reached" {
                Text("Target reached.")
                    .font(Typography.display(40))
                    .tracking(-1.4)
                    .foregroundStyle(Palette.ink)
            } else if let stop = nextStop {
                (Text(stop.formatted(.number.precision(.fractionLength(0 ... 1))))
                    .font(Typography.display(44)).tracking(-1.6).foregroundColor(Palette.ink)
                 + Text(" \(massUnit.abbreviation)")
                    .font(Typography.data(20, weight: .regular)).foregroundColor(Palette.inkSoft)
                 + Text(inWeeks.map { "  " + $0 } ?? "")
                    .font(Typography.data(18, weight: .regular)).foregroundColor(Palette.inkFaint))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            } else {
                Text("Your first weigh-in.")
                    .font(Typography.display(36))
                    .tracking(-1.2)
                    .foregroundStyle(Palette.ink)
            }
        }
    }

    /// "in about 2 weeks" to the next stop, from the plan's time to the target.
    private var inWeeks: String? {
        guard let eta = goal.etaWeeks, eta > 0,
              let current = currentKg.map(massUnit.fromKg), let target = goal.targetWeightKg.map(massUnit.fromKg),
              let stop = nextStop, abs(target - current) > 0.01 else { return nil }
        let weeks = Int((Double(eta) * abs(stop - current) / abs(target - current)).rounded(.up))
        return weeks <= 1 ? L10n("in about a week") : L10n("in about \(weeks) weeks")
    }

    private var sentence: String {
        guard let current = currentKg else {
            return goal.targetWeightKg.map { L10n("It starts your line to \(massUnit.formatKg($0, digits: 0)). One a week is enough.") } ?? ""
        }
        let now = massUnit.formatKg(current)
        let target = massUnit.formatKg(goal.targetWeightKg ?? current, digits: 0)
        switch goal.status {
        case "reached": return L10n("You’re at \(now). Target reached.")
        case "behind": return L10n("You’re at \(now). A little behind plan.")
        case "ahead": return L10n("You’re at \(now). Ahead of plan.")
        case "on_pace":
            if let eta = goal.etaWeeks, eta > 0, let date = Calendar.current.date(byAdding: .day, value: eta * 7, to: .now) {
                let month = date.formatted(.dateTime.month(.wide).locale(AppLanguage.current.locale))
                return L10n("You’re at \(now). On pace for \(target) by \(month).")
            }
            return L10n("You’re at \(now). On pace.")
        default: return L10n("You’re at \(now).")
        }
    }

    private var lastLine: String {
        guard let raw = goal.lastWeighInAt ?? entries.last?.measuredAt, let date = MealFormat.parse(raw) else { return L10n("No weigh-ins yet") }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: date), to: Calendar.current.startOfDay(for: .now)).day ?? 0
        let when: String
        switch days {
        case ...0: when = L10n("today")
        case 1: when = L10n("yesterday")
        case 2 ..< 7: when = date.formatted(.dateTime.weekday(.wide).locale(AppLanguage.current.locale))
        default: when = L10n("\(days) days ago")
        }
        return L10n("Last weigh-in · \(when)")
    }

    /// Per week from the first to the last weigh-in, once they're a week apart.
    private var rateLine: String? {
        let parsed = entries.compactMap { e in MealFormat.parse(e.measuredAt).map { ($0, e.weightKg) } }.sorted { $0.0 < $1.0 }
        guard let first = parsed.first, let last = parsed.last else { return nil }
        let weeks = last.0.timeIntervalSince(first.0) / (7 * 86_400)
        guard weeks >= 1 else { return nil }
        let rate = massUnit.fromKg((last.1 - first.1) / weeks)
        let digits = massUnit == .lb ? 1 : 2
        let sign = rate >= 0 ? "+" : "−"
        let value = abs(rate).formatted(.number.precision(.fractionLength(digits)))
        return L10n("\(sign)\(value) \(massUnit.abbreviation) A WEEK")
    }
}

private func oneDecimal(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(1)))
}

/// Stations on a gently winding path from where you started to the target: passed ones filled, the
/// next one ringed, the target a flag, and you the lit orb between them.
private struct TrailView: View {
    let start: Double
    let current: Double
    let target: Double
    let step: Double
    var drawn: CGFloat

    private var direction: Double { target >= start ? 1 : -1 }

    /// 0 at the start, 1 at the target.
    private func fraction(_ kg: Double) -> Double {
        let span = target - start
        guard abs(span) > 0.0001 else { return 1 }
        return min(1, max(0, (kg - start) / span))
    }

    /// Whole-step stations strictly between start and target.
    private var stations: [Double] {
        var out: [Double] = []
        var kg = direction > 0 ? (floor(start / step) + 1) * step : (ceil(start / step) - 1) * step
        while (direction > 0 && kg < target - 0.0001) || (direction < 0 && kg > target + 0.0001) {
            out.append(kg)
            kg += direction * step
        }
        return out
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width - 28
            let mid = geo.size.height * 0.42
            let x = { (f: Double) -> CGFloat in 14 + CGFloat(f) * width }
            let y = { (f: Double) -> CGFloat in mid - CGFloat(sin(f * 3.4)) * 16 }
            let samples = stride(from: 0.0, through: 1.0, by: 0.01).map { CGPoint(x: x($0), y: y($0)) }
            let now = fraction(current)
            let done = samples.filter { Double(($0.x - 14) / width) <= now + 0.0001 }

            ZStack(alignment: .topLeading) {
                Path { p in
                    for (i, point) in samples.enumerated() { i == 0 ? p.move(to: point) : p.addLine(to: point) }
                }
                .stroke(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 7]))

                Path { p in
                    for (i, point) in done.enumerated() { i == 0 ? p.move(to: point) : p.addLine(to: point) }
                }
                .trim(from: 0, to: drawn)
                .stroke(Palette.amber, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .shadow(color: Palette.amber.opacity(0.6), radius: 5)

                station(at: 0, label: label(start), kind: .start, x: x, y: y)
                ForEach(stations, id: \.self) { kg in
                    station(at: fraction(kg), label: label(kg), kind: isPassed(kg) ? .passed : isNext(kg) ? .next : .ahead, x: x, y: y)
                }
                station(at: 1, label: label(target), kind: .goal, x: x, y: y)

                Circle()
                    .fill(RadialGradient(colors: [Color(hex: 0xFFE9CC), Palette.amber, Color(hex: 0xF06A2E), Color(hex: 0x6E220E)], center: UnitPoint(x: 0.34, y: 0.28), startRadius: 0, endRadius: 14))
                    .frame(width: 26, height: 26)
                    .shadow(color: Palette.ember.opacity(0.8), radius: 10)
                    .position(x: x(now), y: y(now))
                    .opacity(Double(drawn))
            }
        }
        .accessibilityHidden(true)
    }

    private func label(_ kg: Double) -> String {
        kg.formatted(.number.precision(.fractionLength(0 ... 1)))
    }

    private func isPassed(_ kg: Double) -> Bool { direction > 0 ? kg <= current : kg >= current }
    private func isNext(_ kg: Double) -> Bool { !isPassed(kg) && stations.first(where: { !isPassed($0) }) == kg }

    private enum Kind { case start, passed, next, ahead, goal }

    @ViewBuilder
    private func station(at f: Double, label: String, kind: Kind, x: (Double) -> CGFloat, y: (Double) -> CGFloat) -> some View {
        let point = CGPoint(x: x(f), y: y(f))
        ZStack {
            switch kind {
            case .start, .passed:
                Circle().fill(Palette.amber).frame(width: 12, height: 12)
            case .next:
                Circle().strokeBorder(Palette.amber, lineWidth: 2).frame(width: 22, height: 22)
                Circle().fill(Palette.amber).frame(width: 8, height: 8)
            case .ahead:
                Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1.6).background(Circle().fill(Palette.background)).frame(width: 11, height: 11)
            case .goal:
                Image(systemName: "flag.fill").font(.system(size: 15)).foregroundStyle(Palette.amber).offset(y: -9)
                Circle().strokeBorder(Palette.amber, lineWidth: 1.5).background(Circle().fill(Palette.background)).frame(width: 8, height: 8).offset(y: 5)
            }
        }
        .position(point)
        Text(label)
            .font(Typography.mono(10))
            .foregroundStyle(kind == .next || kind == .goal ? Palette.amber : kind == .ahead ? Palette.inkFaint : Palette.inkSoft)
            .fixedSize()
            .position(x: point.x, y: point.y + (kind == .next ? 30 : 26))
    }
}
