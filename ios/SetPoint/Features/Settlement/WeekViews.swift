import SwiftUI

// Week (§5.7) as the manager's record: a small dial per day, how often a
// check-in saved a meal, one late-meal pattern it can fix in a tap, then weight
// and intake.

private func oneDecimal(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(1)))
}

// MARK: - Seven dials

struct WeekDials: View {
    let stations: [WeekStation]
    let record: SettlementResponse.Record?
    let onSelect: (WeekStation) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(stations.enumerated()), id: \.element.id) { index, station in
                Button { onSelect(station) } label: {
                    VStack(spacing: 6) {
                        MiniDayDial(
                            marks: record?.days.first { $0.date == station.date }?.slots ?? [],
                            today: station.isToday
                        )
                        .frame(width: 44, height: 44)
                        Text(letter(station))
                            .font(Typography.data(12, weight: station.isToday ? .heavy : .bold))
                            .foregroundStyle(station.isToday ? Palette.ink : Palette.inkFaint)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PressableCard())
                .appearIn(index)
                .accessibilityLabel(accessibility(station))
            }
        }
    }

    private func letter(_ station: WeekStation) -> String {
        guard let date = WeekStation.parse(station.date) else { return "" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let weekday = calendar.component(.weekday, from: date)
        return String(calendar.veryShortWeekdaySymbols[weekday - 1])
    }

    private func accessibility(_ station: WeekStation) -> String {
        let marks = record?.days.first { $0.date == station.date }?.slots ?? []
        let words = zip(MealSlot.allCases, marks).map { slot, mark in
            "\(slot.title) \(MiniDayDial.word(mark))"
        }
        return ([station.accessibilityTitle] + words).joined(separator: ", ")
    }
}

/// One day as a tiny ring: breakfast, lunch, dinner as dots — ink when eaten on
/// time, terracotta when a check-in got it eaten, an open ring when it slipped.
struct MiniDayDial: View {
    let marks: [String]
    var today = false

    static func word(_ mark: String) -> String {
        switch mark {
        case "on_time": return "on time"
        case "after_check_in": return "after a check-in"
        case "missed": return "missed"
        default: return "still open"
        }
    }

    var body: some View {
        Canvas { context, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) / 2 - 5
            let ring = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            context.stroke(ring, with: .color(today ? Palette.accentSoft : Color(hex: 0xE4D9CA)), lineWidth: 3.5)

            for (index, minute) in [480, 780, 1140].enumerated() {
                let angle = Double(minute) / 1440 * 2 * .pi
                let p = CGPoint(x: c.x + r * CGFloat(sin(angle)), y: c.y - r * CGFloat(cos(angle)))
                let mark = index < marks.count ? marks[index] : "open"
                switch mark {
                case "on_time":
                    context.fill(Path(ellipseIn: CGRect(x: p.x - 4.5, y: p.y - 4.5, width: 9, height: 9)), with: .color(Palette.ink))
                case "after_check_in":
                    context.fill(Path(ellipseIn: CGRect(x: p.x - 4.5, y: p.y - 4.5, width: 9, height: 9)), with: .color(Palette.accent))
                case "missed":
                    let dot = Path(ellipseIn: CGRect(x: p.x - 3.6, y: p.y - 3.6, width: 7.2, height: 7.2))
                    context.fill(dot, with: .color(Palette.background))
                    context.stroke(dot, with: .color(Palette.accent), lineWidth: 1.8)
                default:
                    let dot = Path(ellipseIn: CGRect(x: p.x - 3.2, y: p.y - 3.2, width: 6.4, height: 6.4))
                    context.fill(dot, with: .color(Palette.background))
                    context.stroke(dot, with: .color(Palette.dayMissed), lineWidth: 1.5)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - The record

struct RecordCard: View {
    let record: SettlementResponse.Record

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            VStack(alignment: .leading, spacing: 0) {
                Text(record.checkIns == 0 ? "No check-ins needed." : "I stepped in \(record.checkIns) \(record.checkIns == 1 ? "time" : "times").")
                    .font(Typography.display(28))
                    .foregroundStyle(Palette.background)
                Text(record.checkIns == 0 ? "You kept your own rhythm." : "You ate \(record.afterCheckIn) of them.")
                    .font(Typography.voiceItalic(28))
                    .foregroundStyle(Color(hex: 0xFFE3D3))
            }
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Space.sm) {
                stat(record.onTime, "on time")
                stat(record.afterCheckIn, "saved")
                stat(record.missed, "missed")
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Palette.accent)
                .elevation(.floating)
        }
        .accessibilityElement(children: .combine)
    }

    private func stat(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(Typography.data(34, weight: .heavy))
                .foregroundStyle(Palette.background)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(value)))
            Text(label)
                .font(Typography.data(12, weight: .semibold))
                .foregroundStyle(Palette.background.opacity(0.75))
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

    private var slotTitle: String {
        MealSlot(rawValue: pattern.slot)?.title ?? "A meal"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("\(slotTitle) runs late on workdays.")
                .font(Typography.display(22))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Late \(pattern.lateDays) of \(pattern.ofDays) workdays this week.")
                .font(Typography.data(14))
                .foregroundStyle(Palette.inkSoft)
            HStack(spacing: 8) {
                Button(action: onApply) {
                    Text(busy ? "Moving…" : "Expect it at \(formatMinutes(pattern.suggestedMin))")
                        .font(Typography.data(15, weight: .bold))
                        .foregroundStyle(Palette.accentDeep)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Palette.accentTint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(PressableCard())
                .disabled(busy)
                Button(action: onKeep) {
                    Text("Keep")
                        .font(Typography.data(15, weight: .bold))
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 46)
                        .background(Palette.surfaceSunk, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(PressableCard())
            }
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Palette.surface)
                .elevation(.resting)
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.hairline))
        }
    }
}

// MARK: - Weight

struct WeightTrendCard: View {
    let goal: SettlementResponse.WeightGoal
    let entries: [WeightHistoryResponse.Entry]
    let busy: Bool
    let onWeighIn: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(goal.currentWeightKg.map(oneDecimal) ?? "—")
                        .font(Typography.data(36, weight: .heavy))
                        .foregroundStyle(Palette.ink)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("kg")
                        .font(Typography.data(15, weight: .semibold))
                        .foregroundStyle(Palette.inkFaint)
                }
                Spacer()
                if let status = statusLabel {
                    HStack(spacing: 6) {
                        Circle().fill(statusTint).frame(width: 6, height: 6)
                        Text(status)
                    }
                    .font(Typography.data(13, weight: .bold))
                    .foregroundStyle(statusTint)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(statusTint.opacity(0.13), in: Capsule())
                }
            }

            if entries.count >= 2 {
                Sparkline(values: entries.map(\.weightKg))
                    .trim(from: 0, to: drawn)
                    .stroke(Palette.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .frame(height: 54)
                    .onAppear {
                        guard !reduceMotion else { drawn = 1; return }
                        withAnimation(.easeOut(duration: 1.2).delay(0.3)) { drawn = 1 }
                    }
            } else {
                GeometryReader { box in
                    Capsule().fill(Palette.surfaceSunk)
                        .overlay(alignment: .leading) {
                            Capsule().fill(Palette.accent)
                                .frame(width: box.size.width * min(1, max(0, goal.fractionComplete ?? 0)))
                        }
                }
                .frame(height: 6)
            }

            HStack {
                Text(goal.startWeightKg.map { "\(oneDecimal($0)) start" } ?? "Start")
                    .foregroundStyle(Palette.inkFaint)
                Spacer()
                if let remaining = goal.remainingKg, let target = goal.targetWeightKg, goal.status != "reached" {
                    Text("\(oneDecimal(remaining)) kg to \(oneDecimal(target))")
                        .foregroundStyle(Palette.ink)
                }
            }
            .font(Typography.data(12, weight: .bold))
            .monospacedDigit()

            Divider().overlay(Palette.hairline)

            Button(action: onWeighIn) {
                HStack(spacing: 12) {
                    Image(systemName: "scalemass")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 38, height: 38)
                        .background(Palette.surfaceSunk, in: Circle())
                    Text("Weigh-in")
                        .font(Typography.data(16, weight: .bold))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Text(busy ? "Saving…" : goal.needsWeighIn ? "Due" : "Log weight")
                        .font(Typography.data(14, weight: .bold))
                        .foregroundStyle(goal.needsWeighIn ? Palette.accent : Palette.inkSoft)
                }
            }
            .buttonStyle(PressableCard())
            .disabled(busy)
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Palette.surface)
                .elevation(.resting)
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.hairline))
        }
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
        goal.status == "behind" ? Palette.accent : Palette.dayOnTrack
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

// MARK: - Intake

struct IntakeStrip: View {
    let stations: [WeekStation]

    private var settled: [WeekStation] { stations.filter { !$0.isToday } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Intake").sectionLabelStyle()
                Spacer()
                Text("\(settled.filter { $0.kind == "ON_TRACK" }.count) of \(settled.count) days on target")
                    .font(Typography.data(13, weight: .bold))
                    .foregroundStyle(Palette.ink)
            }
            HStack(spacing: 5) {
                ForEach(stations) { station in
                    Capsule()
                        .fill(Palette.day(station.kind))
                        .frame(height: 6)
                        .opacity(station.isToday ? 0.45 : 1)
                }
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Palette.surface)
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.hairline))
        }
        .accessibilityElement(children: .combine)
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
        _value = State(initialValue: ((lastKg ?? 70) * 10).rounded() / 10)
    }

    private var range: ClosedRange<Double> {
        let base = (lastKg ?? 70).rounded()
        return max(25, base - 20) ... min(400, base + 20)
    }

    var body: some View {
        VStack(spacing: Space.md) {
            Text("Weigh-in · \(Date.now.formatted(.dateTime.weekday(.wide)))")
                .sectionLabelStyle()

            RulerPicker(value: $value, range: range, step: 0.1, unit: "kg", majorStep: 1, fractionDigits: 1)

            if let lastKg {
                let delta = value - lastKg
                Text(abs(delta) < 0.05 ? "Same as last time" : "\(delta > 0 ? "+" : "−")\(oneDecimal(abs(delta))) kg since last time")
                    .font(Typography.data(14, weight: .bold))
                    .foregroundStyle(Palette.inkSoft)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Palette.surfaceSunk, in: Capsule())
                    .contentTransition(.numericText())
            }

            ActionButton(title: phase == .idle ? "Save" : phase == .saving ? "Saving…" : "✓ Saved") { save() }
                .disabled(phase != .idle)
                .animation(Motion.adaptive(Motion.settle, reduceMotion: reduceMotion), value: phase)
        }
        .padding(Space.gutter)
        .padding(.top, Space.xs)
        .frame(maxWidth: .infinity)
        .presentationDetents([.height(lastKg == nil ? 330 : 380)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.background)
        .presentationCornerRadius(28)
    }

    private func save() {
        guard phase == .idle else { return }
        Task {
            phase = .saving
            let ok = await onSubmit((value * 10).rounded() / 10)
            guard ok else { phase = .idle; return }
            phase = .saved
            Haptics.landed()
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 480))
            dismiss()
        }
    }
}
