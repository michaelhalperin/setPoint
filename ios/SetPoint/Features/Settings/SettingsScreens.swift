import SwiftUI
import UIKit

// MARK: - Goal and pace

struct GoalSettingsView: View {
    @AppStorage(MassUnit.storageKey) private var massUnit = MassUnit.localeDefault
    @Bindable var model: SettingsViewModel
    @State private var editingTarget: DailyTargetField?

    var body: some View {
        InnerScreen(spacing: 14) {
            ScreenHeader(label: "Edit plan")

            goalTiles.appearIn(1, rise: 14)

            pathCard.appearIn(2, rise: 14)

            if model.goal.hasWeightTarget, model.targetWeightMessage == nil {
                paceTiles.appearIn(3, rise: 14)
            }

            if let message = model.targetWeightMessage ?? model.durationMessage {
                Text(message)
                    .font(Typography.data(13, weight: .regular))
                    .foregroundStyle(Palette.amber)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }

            yourDay.appearIn(4, rise: 14)

            if let error = model.error {
                SettingsErrorBanner(message: error)
            }
        }
        .animation(Motion.settle, value: model.goal)
        .animation(Motion.settle, value: model.pace)
        .animation(Motion.settle, value: model.durationMessage)
        .animation(Motion.settle, value: model.displayedKcalTarget)
        .settingsSaveBar(
            visible: model.goalDirty,
            note: model.goalSaveNote,
            saving: model.saving,
            disabled: model.blocksSave || model.saving
        ) {
            Task {
                await model.save()
                if model.error == nil { Haptics.landed() }
            }
        }
        .sheet(item: $editingTarget, content: dailyTargetSheet)
        .onDisappear { model.revertToOriginal() }
        .onAppear {
            proposeTargetIfNeeded()
            model.proposeDurationIfNeeded()
        }
    }

    // MARK: Goal

    private var goalTiles: some View {
        HStack(spacing: 8) {
            ForEach(Goal.allCases) { goal in
                ChoiceTile(selected: model.goal == goal, action: { pick(goal) }) {
                    VStack(alignment: .leading, spacing: 10) {
                        GoalSpark(goal: goal)
                            .stroke(model.goal == goal ? Palette.amber : Color(hex: 0x71717A), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .frame(width: 56, height: 22)
                        Text(goal.title)
                            .font(Typography.data(15, weight: .medium))
                            .foregroundStyle(Palette.ink)
                    }
                }
                .accessibilityLabel(goal.title)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func pick(_ goal: Goal) {
        withAnimation(Motion.settle) {
            let changed = model.goal != goal
            model.goal = goal
            proposeTargetIfNeeded()
            if changed { model.resetDurationForGoalChange() }
        }
    }

    // MARK: Path

    private var currentKg: Double { model.currentWeightKg ?? targetKg }

    private var pathCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(model.goal.hasWeightTarget ? "Target" : "Holding at")).sectionLabelStyle()
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(massUnit.number(model.goal.hasWeightTarget ? targetKg : currentKg, digits: 1 ... 1))
                            .font(Typography.data(40, weight: .light))
                            .tracking(-1.6)
                            .contentTransition(.numericText(value: targetKg))
                        Text(massUnit.abbreviation)
                            .font(Typography.data(14, weight: .regular))
                            .foregroundStyle(Palette.inkSoft)
                    }
                    .foregroundStyle(Palette.ink)
                }
                Spacer(minLength: 0)
                if model.goal.hasWeightTarget {
                    HStack(spacing: 8) {
                        StepCircle(symbol: "minus", label: "Lower target") { nudge(-1) }
                        StepCircle(symbol: "plus", label: "Raise target") { nudge(1) }
                    }
                }
            }

            WeightPathChart(
                currentKg: currentKg,
                targetKg: model.goal.hasWeightTarget ? targetKg : currentKg,
                weeks: model.goal.hasWeightTarget ? weeks : nil,
                otherWeeks: model.goal.hasWeightTarget ? otherPaceWeeks : nil,
                endLabel: endLabel,
                rising: model.goal != .diet
            )
            .frame(height: 150)

            HStack {
                Text(L10n("Now · \(massUnit.number(currentKg, digits: 1 ... 1))"))
                Spacer()
                Text(model.goal.hasWeightTarget ? L10n("\(max(weeks, otherPaceWeeks ?? weeks)) weeks") : L10n("6 months"))
            }
            .font(Typography.mono(10))
            .textCase(.uppercase)
            .foregroundStyle(Palette.inkFaint)
        }
        .padding(16)
        .glass(radius: 26)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.goal.hasWeightTarget
            ? L10n("From \(massUnit.formatKg(currentKg)) to \(massUnit.formatKg(targetKg)) in about \(weeks) weeks")
            : L10n("Holding at \(massUnit.formatKg(currentKg))"))
    }

    private var endLabel: String {
        guard model.goal.hasWeightTarget else { return L10n( "±1 \(massUnit.abbreviation) band") }
        return L10n( "\(massUnit.formatKg(targetKg, digits: 0)) · \(Self.monthYear(weeksFromNow: weeks))")
    }

    private static func monthYear(weeksFromNow weeks: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: weeks * 7, to: .now) ?? .now
        return date.formatted(.dateTime.month(.abbreviated).year().locale(AppLanguage.current.locale))
    }

    // MARK: Pace

    private func paceWeeks(_ pace: GoalPace) -> Int? {
        guard let current = model.currentWeightKg else { return nil }
        let remaining = WeightPace.remainingKg(goal: model.goal, currentKg: current, targetKg: targetKg)
        let rate = WeightPace.clampKgPerWeek(goal: model.goal, weightKg: current, pace: pace.kgPerWeek(for: model.goal))
        return WeightPace.etaWeeks(remainingKg: remaining, paceKgPerWeek: rate)
    }

    private var otherPaceWeeks: Int? {
        paceWeeks(model.pace == .gentle ? .steady : .gentle)
    }

    private var paceTiles: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(GoalPace.allCases) { pace in
                    let on = model.pace == pace
                    Button { withAnimation(Motion.settle) { model.applyPaceShortcut(pace) } } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(pace.title)
                                    .font(Typography.data(15, weight: .medium))
                                    .foregroundStyle(Palette.ink)
                                Spacer(minLength: 4)
                                Text("\(model.goal == .diet ? "−" : "+")\(pace.kgPerWeek(for: model.goal).formatted()) kg/wk")
                                    .font(Typography.mono(10))
                                    .foregroundStyle(on ? Palette.amber : Color(hex: 0x71717A))
                            }
                            Text(paceNote(pace))
                                .font(Typography.data(12, weight: .regular))
                                .foregroundStyle(Palette.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(on ? 0.07 : 0.025)))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(on ? Palette.amber.opacity(0.55) : Color.white.opacity(0.08)))
                    }
                    .buttonStyle(PressableCard())
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            StepperRow(
                name: "Timeframe",
                note: timeframeStepperNote,
                value: "\(weeks) wk",
                canDown: weeks > 1,
                onDown: { withAnimation(Motion.settle) { model.setDurationWeeks(weeks - 1) } },
                onUp: { withAnimation(Motion.settle) { model.setDurationWeeks(weeks + 1) } }
            )
            .padding(.horizontal, 14)
            .glass(radius: 20)
        }
    }

    private func paceNote(_ pace: GoalPace) -> String {
        let feel = pace == .gentle ? "easier to eat" : "faster, a bit more food"
        guard let w = paceWeeks(pace) else { return feel.capitalized }
        return L10n( "\(w) weeks · \(Self.monthYear(weeksFromNow: w)) · \(feel)")
    }

    private var weeks: Int { model.preferredDurationWeeks ?? model.honestDurationWeeks ?? 12 }

    private var timeframeStepperNote: String {
        if model.durationMessage != nil { return L10n("I'll hold a safe pace") }
        let remaining = WeightPace.remainingKg(goal: model.goal, currentKg: currentKg, targetKg: targetKg)
        guard remaining > 0, weeks > 0 else { return L10n("or set the weeks yourself") }
        let rate = remaining / Double(weeks)
        return L10n("\(massUnit.formatKg(rate, digits: 2))/wk · \(Self.monthYear(weeksFromNow: weeks))")
    }

    // MARK: Your day

    /// The day the plan works out to — tap a number to set it yourself.
    private var yourDay: some View {
        CalloutCard(spacing: 10) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your day").sectionLabelStyle(Palette.amber)
                    Button { editingTarget = .kcal } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(model.displayedKcalTarget.formatted())
                                .font(Typography.data(38, weight: .light))
                                .tracking(-1.5)
                                .foregroundStyle(Palette.ink)
                                .contentTransition(.numericText(value: Double(model.displayedKcalTarget)))
                            Text("kcal")
                                .font(Typography.data(14, weight: .regular))
                                .foregroundStyle(Palette.inkSoft)
                            if model.displayedKcalTarget != model.savedKcalTarget {
                                Text(model.savedKcalTarget.formatted())
                                    .font(Typography.mono(12))
                                    .strikethrough()
                                    .foregroundStyle(Palette.inkFaint)
                            }
                        }
                    }
                    .buttonStyle(PressableCard())
                    .accessibilityLabel(L10n("\(model.displayedKcalTarget) calories a day. Set it yourself."))
                }
                Spacer(minLength: 8)
                if let protein = model.proteinTarget {
                    Button { editingTarget = .protein } label: {
                        Text(L10n("\(protein) g protein"))
                            .font(Typography.mono(12))
                            .foregroundStyle(Palette.amber)
                            .padding(.bottom, 6)
                    }
                    .buttonStyle(PressableCard())
                    .accessibilityLabel(L10n("\(protein) grams of protein. Set it yourself."))
                }
            }
            HStack(spacing: 6) {
                dayChip(model.dailyTargetsEdited ? "Set by you" : "From your goal", tint: nil)
                if model.goal.hasWeightTarget, let eta = model.planDurationWeeks {
                    dayChip(L10n("~\(eta) weeks to target"), tint: Palette.amber)
                }
            }
            Text("Tap a number to set it yourself.")
                .font(Typography.data(12, weight: .regular))
                .foregroundStyle(Palette.inkFaint)
                .hintCopy()
        }
    }

    private func dayChip(_ text: String, tint: Color?) -> some View {
        Text(LocalizedStringKey(text))
            .font(Typography.mono(11))
            .foregroundStyle(tint ?? Color(hex: 0xD4D4D8))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background((tint ?? .white).opacity(tint == nil ? 0.05 : 0.14), in: Capsule())
            .overlay(Capsule().strokeBorder((tint ?? .white).opacity(tint == nil ? 0.10 : 0.45)))
    }

    @ViewBuilder
    private func dailyTargetSheet(_ field: DailyTargetField) -> some View {
        DailyTargetSheet(field: field, model: model)
            .presentationDetents([.height(320)])
            .presentationDragIndicator(.visible)
            .presentationBackground(Palette.sheet)
            .presentationCornerRadius(32)
    }

    private var targetKg: Double {
        model.targetWeightKg ?? model.currentWeightKg ?? 70
    }

    private func nudge(_ delta: Double) {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(Motion.settle) {
            model.targetWeightKg = min(350, max(25, massUnit.nudge(kg: targetKg, by: delta)))
        }
    }

    private func proposeTargetIfNeeded() {
        guard model.goal.hasWeightTarget, model.targetWeightKg == nil, let current = model.currentWeightKg else { return }
        model.targetWeightKg = (current + (model.goal == .bulk ? 4 : -5)).rounded()
    }
}

/// The little line on a goal tile: up for gain, down for cut, a wave for maintain.
private struct GoalSpark: Shape {
    let goal: Goal

    func path(in r: CGRect) -> Path {
        var p = Path()
        switch goal {
        case .bulk:
            p.move(to: CGPoint(x: r.minX + 2, y: r.maxY - 4))
            p.addCurve(to: CGPoint(x: r.maxX - 2, y: r.minY + 4), control1: CGPoint(x: r.midX - 8, y: r.maxY - 4), control2: CGPoint(x: r.midX + 2, y: r.minY + 4))
        case .diet:
            p.move(to: CGPoint(x: r.minX + 2, y: r.minY + 4))
            p.addCurve(to: CGPoint(x: r.maxX - 2, y: r.maxY - 4), control1: CGPoint(x: r.midX - 8, y: r.minY + 4), control2: CGPoint(x: r.midX + 2, y: r.maxY - 4))
        case .maintain:
            p.move(to: CGPoint(x: r.minX + 2, y: r.midY))
            p.addCurve(to: CGPoint(x: r.midX, y: r.midY), control1: CGPoint(x: r.minX + 12, y: r.midY - 6), control2: CGPoint(x: r.midX - 10, y: r.midY + 6))
            p.addCurve(to: CGPoint(x: r.maxX - 2, y: r.midY), control1: CGPoint(x: r.midX + 10, y: r.midY - 6), control2: CGPoint(x: r.maxX - 12, y: r.midY + 6))
        }
        return p
    }
}

/// Weight from now to the target: the chosen pace bright, the other dashed.
private struct WeightPathChart: View {
    let currentKg: Double
    let targetKg: Double
    /// nil when maintaining — a flat line inside a ±1 kg band.
    let weeks: Int?
    let otherWeeks: Int?
    let endLabel: String
    let rising: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let maxW = Double(max(weeks ?? 26, otherWeeks ?? 0, 4))
            let lo = min(currentKg, targetKg) - 1.5, hi = max(currentKg, targetKg) + 1.5
            let x = { (wk: Double) in 8 + CGFloat(wk / maxW) * (w - 16) }
            let y = { (kg: Double) in h - 22 - CGFloat((kg - lo) / (hi - lo)) * (h - 44) }
            let end = CGPoint(x: x(Double(weeks ?? Int(maxW))), y: y(targetKg))

            ZStack(alignment: .topLeading) {
                if weeks == nil {
                    Path { p in
                        p.addRect(CGRect(x: 8, y: y(targetKg + 1), width: w - 16, height: y(targetKg - 1) - y(targetKg + 1)))
                    }
                    .fill(Palette.amber.opacity(0.07))
                }
                if let otherWeeks {
                    curve(to: Double(otherWeeks), x: x, y: y, maxW: maxW)
                        .stroke(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 1.5, dash: [3, 5]))
                }
                curve(to: Double(weeks ?? Int(maxW)), x: x, y: y, maxW: maxW)
                    .stroke(Palette.amber, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .shadow(color: Palette.amber.opacity(0.6), radius: 6)

                Circle().fill(Palette.ink).frame(width: 10, height: 10)
                    .position(x: x(0), y: y(currentKg))
                EmberDot(size: 20)
                    .position(end)
                Text(endLabel)
                    .font(Typography.mono(11))
                    .foregroundStyle(Palette.amber)
                    .fixedSize()
                    .position(x: min(end.x, w - 70), y: rising ? end.y - 20 : end.y + 22)
            }
            .animation(Motion.settle, value: weeks)
            .animation(Motion.settle, value: targetKg)
        }
        .accessibilityHidden(true)
    }

    private func curve(to wk: Double, x: (Double) -> CGFloat, y: (Double) -> CGFloat, maxW: Double) -> Path {
        Path { p in
            let a = CGPoint(x: x(0), y: y(currentKg))
            let b = CGPoint(x: x(wk), y: y(targetKg))
            p.move(to: a)
            p.addCurve(to: b, control1: CGPoint(x: a.x + (b.x - a.x) * 0.45, y: a.y), control2: CGPoint(x: a.x + (b.x - a.x) * 0.55, y: b.y))
            if wk < maxW { p.addLine(to: CGPoint(x: x(maxW), y: b.y)) }
        }
    }
}

private enum DailyTargetField: String, Identifiable {
    case kcal, protein
    var id: String { rawValue }
}

private struct DailyTargetSheet: View {
    let field: DailyTargetField
    @Bindable var model: SettingsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var value: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text(LocalizedStringKey(field == .kcal ? "Daily calories" : "Daily protein"))
                .sectionLabelStyle()
            if field == .kcal {
                RulerPicker(value: $value, range: 1200 ... 6000, step: 50, unit: "kcal", majorStep: 500)
            } else {
                RulerPicker(value: $value, range: 40 ... 300, step: 5, unit: "g", majorStep: 50)
            }
            ActionButton(title: "Done") {
                if field == .kcal {
                    model.kcalTarget = Int(value.rounded())
                } else {
                    model.proteinTarget = Int(value.rounded())
                }
                dismiss()
            }
        }
        .padding(Space.gutter)
        .onAppear {
            value = field == .kcal ? Double(model.displayedKcalTarget) : Double(model.proteinTarget ?? 40)
        }
    }
}

// MARK: - Meal times

struct RhythmSettingsView: View {
    @Bindable var model: SettingsViewModel
    @State private var rhythmSet: RhythmSet
    @State private var selected: DialItem = .meal(.lunch)

    init(model: SettingsViewModel, startOnWeekends: Bool = false) {
        self.model = model
        _rhythmSet = State(initialValue: startOnWeekends ? .weekends : .weekdays)
    }

    private enum RhythmSet: String, CaseIterable, Identifiable {
        case weekdays, weekends
        var id: String { rawValue }
        var title: String {
            switch self {
            case .weekdays: return L10n( "Weekdays")
            case .weekends: return L10n( "Weekends")
            }
        }
    }

    enum DialItem: Hashable {
        case meal(MealSlot)
        case quietStart
        case quietEnd

        var title: String {
            switch self {
            case let .meal(slot): return slot.title
            case .quietStart: return L10n( "Quiet from")
            case .quietEnd: return L10n( "Quiet until")
            }
        }

        var isQuiet: Bool { if case .meal = self { return false } else { return true } }

        static let order: [DialItem] = [.meal(.breakfast), .meal(.lunch), .meal(.dinner), .quietStart, .quietEnd]
    }

    private var editingWeekends: Bool { rhythmSet == .weekends }

    private var activeTimes: MealTimesPayload {
        editingWeekends ? model.resolvedWeekendTimes : model.mealTimes
    }

    var body: some View {
        InnerScreen(spacing: 14) {
            ZStack {
                HStack {
                    RoundIconButton("chevron.backward", label: "Back") { dismiss() }
                    Spacer()
                    SegmentedPills(options: RhythmSet.allCases, selection: $rhythmSet, title: { $0.title })
                        .frame(width: 196)
                }
            }

            HStack(spacing: 6) {
                Text(editingWeekends ? "SAT · SUN" : "MON – FRI")
                    .font(Typography.mono(10))
                    .tracking(1.2)
                    .foregroundStyle(editingWeekends ? Palette.hazeSoft : Palette.amber)
                if model.hasWeekendMealOverrides {
                    Text("·")
                        .foregroundStyle(Palette.inkFaint)
                    Text(L10n(editingWeekends
                        ? "Weekdays \(formatMinutes(model.mealTimes.breakfastMin))–\(formatMinutes(model.mealTimes.dinnerMin))"
                        : "Weekends \(formatMinutes(model.resolvedWeekendTimes.breakfastMin))–\(formatMinutes(model.resolvedWeekendTimes.dinnerMin))"))
                        .font(Typography.mono(10))
                        .foregroundStyle(Palette.inkFaint)
                }
            }
            .frame(maxWidth: .infinity)
            .contentTransition(.opacity)

            Headline(editingWeekends ? "Weekends run later." : "Three plates a day.", tail: tail, size: 34, persistTail: true)
                .appearIn(0, rise: 16)

            if let suggestion = model.weekendSuggestion, editingWeekends {
                suggestionBanner(suggestion).appearIn(1)
            }

            MealClock(
                times: activeTimes,
                quietStart: model.quietHours.startMin,
                quietEnd: model.quietHours.endMin,
                selected: $selected,
                minute: minute(of:),
                note: note(for:),
                onMove: { item, minute in
                    if selected != item { selected = item }
                    setMinute(minute, for: item)
                }
            )
            .frame(width: 300, height: 300)
            .frame(maxWidth: .infinity)
            .appearIn(2, rise: 14)

            controlBar.appearIn(3)

            if editingWeekends {
                weekendDays.transition(.opacity.combined(with: .move(edge: .top)))
            }

            if let error = model.error {
                SettingsErrorBanner(message: error)
            }
        }
        .settingsSaveBar(
            visible: model.mealTimesDirty,
            note: model.mealTimesSaveNote,
            saving: model.saving,
            disabled: model.saving
        ) {
            Task {
                await model.save()
                if model.error == nil { Haptics.landed() }
            }
        }
        .onDisappear { model.revertToOriginal() }
        .animation(Motion.settle, value: rhythmSet)
        .animation(Motion.settle, value: selected)
    }

    @Environment(\.dismiss) private var dismiss

    private var tail: String {
        let start = formatMinutes(activeTimes.breakfastMin)
        let end = formatMinutes(activeTimes.dinnerMin)
        return editingWeekends
            ? L10n("Lit days, \(start) to \(end).")
            : L10n("\(start) to \(end), quiet overnight.")
    }

    private func minute(of item: DialItem) -> Int {
        switch item {
        case let .meal(slot): return activeTimes[slot]
        case .quietStart: return model.quietHours.startMin
        case .quietEnd: return model.quietHours.endMin
        }
    }

    private func note(for item: DialItem) -> String {
        switch item {
        case let .meal(slot):
            let t = activeTimes[slot]
            let weekday = model.mealTimes[slot]
            let checkIn = L10n( "check-in \(formatMinutes(CheckInSchedule.minute(afterMeal: t)))")
            return editingWeekends && t != weekday
                ? L10n( "weekdays \(formatMinutes(weekday)) · \(checkIn)")
                : checkIn
        case .quietStart, .quietEnd:
            let span = (model.quietHours.endMin - model.quietHours.startMin + 1440) % 1440
            let h = span / 60, m = span % 60
            return m > 0
                ? L10n( "no check-ins for \(h) h \(m) min")
                : L10n( "no check-ins for \(h) h")
        }
    }

    private var controlBar: some View {
        HStack(spacing: 8) {
            StepCircle(symbol: "minus", label: "15 minutes earlier") { shift(-15) }
            Button {
                let i = DialItem.order.firstIndex(of: selected) ?? 0
                selected = DialItem.order[(i + 1) % DialItem.order.count]
            } label: {
                (Text(L10n("Next: \(DialItem.order[((DialItem.order.firstIndex(of: selected) ?? 0) + 1) % DialItem.order.count].title.lowercased()) "))
                    + Text("›").foregroundColor(Palette.inkFaint))
                    .font(Typography.data(13, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            StepCircle(symbol: "plus", label: "15 minutes later") { shift(15) }
        }
        .padding(6)
        .glassCapsule()
    }

    private func shift(_ delta: Int) {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(Motion.settle) {
            setMinute(minute(of: selected) + delta, for: selected)
        }
    }

    private func setMinute(_ minute: Int, for item: DialItem) {
        switch item {
        case let .meal(slot):
            setTime(minute, slot: slot)
        case .quietStart:
            model.quietHours.startMin = MealTimeEditing.snap(minute)
        case .quietEnd:
            model.quietHours.endMin = MealTimeEditing.snap(minute)
        }
    }

    private func setTime(_ minute: Int, slot: MealSlot) {
        if editingWeekends {
            model.setWeekendTime(minute, slot: slot)
        } else {
            let clamped = MealTimeEditing.clamp(
                minute, slot: slot,
                breakfast: model.mealTimes.breakfastMin,
                lunch: model.mealTimes.lunchMin,
                dinner: model.mealTimes.dinnerMin
            )
            model.mealTimes[slot] = clamped
        }
    }

    private func suggestionBanner(_ suggestion: WeekendSuggestion) -> some View {
        Button {
            withAnimation(Motion.settle) { model.applyWeekendSuggestion() }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "clock.badge.questionmark")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Palette.amber)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n("Weekends are running \(suggestion.lateByMin) min later"))
                        .font(Typography.data(14, weight: .medium))
                        .foregroundStyle(Palette.ink)
                    Text(L10n("Set weekend breakfast to \(formatMinutes(suggestion.breakfastMin))."))
                        .font(Typography.data(13))
                        .foregroundStyle(Palette.inkSoft)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .glass(radius: 20, fill: Palette.ember.opacity(0.08), stroke: Palette.amber.opacity(0.3))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n("Use suggested weekend breakfast \(formatMinutes(suggestion.breakfastMin))"))
    }

    /// Lit days follow the weekend times.
    private var weekendDays: some View {
        HStack(spacing: 8) {
            ForEach(WeekendDays.orderedBits, id: \.self) { bit in
                let on = WeekendDays.contains(model.weekendDays, weekday: bit)
                Button {
                    withAnimation(Motion.settle) {
                        model.weekendDays = WeekendDays.toggling(model.weekendDays, weekday: bit)
                    }
                } label: {
                    Text(WeekendDays.shortLabel(bit))
                        .font(Typography.mono(12))
                        .foregroundStyle(on ? Color(hex: 0xE0E7FF) : Palette.inkFaint)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(on ? Palette.haze.opacity(0.22) : Color.white.opacity(0.04)))
                        .overlay(Circle().strokeBorder(on ? Palette.hazeSoft.opacity(0.7) : Color.white.opacity(0.08)))
                        .shadow(color: Palette.haze.opacity(on ? 0.35 : 0), radius: 7)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(WeekendDays.name(bit) + (on ? L10n( ", weekend times") : ""))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// The day as a clock: noon at the top, night at the bottom. Meals are lit dots on
/// the ring, quiet hours a haze arc; drag a ball around the ring to set its time.
private struct MealClock: View {
    let times: MealTimesPayload
    let quietStart: Int
    let quietEnd: Int
    @Binding var selected: RhythmSettingsView.DialItem
    let minute: (RhythmSettingsView.DialItem) -> Int
    let note: (RhythmSettingsView.DialItem) -> String
    let onMove: (RhythmSettingsView.DialItem, Int) -> Void

    @State private var dragging: RhythmSettingsView.DialItem?
    @State private var dragOrigin: CGPoint?
    private let radius: CGFloat = 128

    var body: some View {
        GeometryReader { geo in
            let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            ZStack {
                Circle().stroke(Color.white.opacity(0.08), lineWidth: 2)
                    .frame(width: radius * 2, height: radius * 2)
                    .position(c)
                    .allowsHitTesting(false)
                arc(from: times.breakfastMin, to: times.dinnerMin, center: c)
                    .stroke(Palette.amber.opacity(0.55), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .allowsHitTesting(false)
                arc(from: quietStart, to: quietEnd, center: c)
                    .stroke(Palette.haze.opacity(0.6), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .shadow(color: Palette.haze.opacity(0.7), radius: 10)
                    .allowsHitTesting(false)

                ForEach([(720, 12), (1080, 18), (0, 0), (360, 6)], id: \.0) { m, hour in
                    Text(DialClock.cardinalLabel(hour))
                        .font(Typography.mono(10))
                        .foregroundStyle(Palette.inkFaint)
                        .position(point(m, r: 102, c: c))
                        .allowsHitTesting(false)
                }

                VStack(spacing: 6) {
                    Text(selected.title).sectionLabelStyle(selected.isQuiet ? Palette.hazeSoft : Palette.amber)
                    Text(formatMinutes(minute(selected)))
                        .font(Typography.data(46, weight: .light))
                        .tracking(-2)
                        .foregroundStyle(Palette.ink)
                        .contentTransition(.numericText(value: Double(minute(selected))))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text(note(selected))
                        .font(Typography.mono(11))
                        .foregroundStyle(Palette.inkSoft)
                        .multilineTextAlignment(.center)
                }
                .frame(width: 170)
                .position(c)
                .allowsHitTesting(false)
                .accessibilityElement(children: .combine)

                ForEach(RhythmSettingsView.DialItem.order, id: \.self) { item in
                    let on = item == selected || dragging == item
                    knob(item, on: on)
                        .scaleEffect(dragging == item ? 1.14 : 1)
                        .frame(width: 48, height: 48)
                        .contentShape(Circle())
                        .position(point(minute(item), r: radius, c: c))
                        .gesture(drag(item, center: c))
                        .accessibilityLabel("\(item.title) \(formatMinutes(minute(item)))")
                        .accessibilityHint(L10n("Drag around the clock to change the time"))
                        .accessibilityAddTraits(on ? .isSelected : [])
                        .accessibilityAdjustableAction { direction in
                            let delta = direction == .increment ? 15 : -15
                            onMove(item, minute(item) + delta)
                        }
                }
            }
            .coordinateSpace(name: "mealClock")
        }
    }

    @ViewBuilder
    private func knob(_ item: RhythmSettingsView.DialItem, on: Bool) -> some View {
        if item.isQuiet {
            Circle()
                .fill(on ? Color(hex: 0xE0E7FF) : Palette.haze)
                .frame(width: on ? 22 : 14, height: on ? 22 : 14)
                .shadow(color: Palette.haze.opacity(0.9), radius: on ? 9 : 4)
        } else if on {
            EmberDot(size: 30)
        } else {
            Circle().fill(Palette.amber).frame(width: 16, height: 16)
                .shadow(color: Palette.amber.opacity(0.55), radius: 4)
        }
    }

    private func drag(_ item: RhythmSettingsView.DialItem, center: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("mealClock"))
            .onChanged { value in
                if dragging != item {
                    dragging = item
                    selected = item
                    dragOrigin = value.startLocation
                    return
                }
                if let origin = dragOrigin {
                    let dx = value.location.x - origin.x
                    let dy = value.location.y - origin.y
                    guard dx * dx + dy * dy > 100 else { return }
                    dragOrigin = nil
                }
                let next = snappedMinute(at: value.location, center: center, for: item)
                guard next != minute(item) else { return }
                UISelectionFeedbackGenerator().selectionChanged()
                onMove(item, next)
            }
            .onEnded { _ in
                dragging = nil
                dragOrigin = nil
            }
    }

    /// MealClock has noon at the top; `MealTimeEditing.minute` assumes midnight at the top.
    private func snappedMinute(at location: CGPoint, center: CGPoint, for item: RhythmSettingsView.DialItem) -> Int {
        let raw = (MealTimeEditing.minute(at: location, center: center) + 720) % 1440
        switch item {
        case let .meal(slot):
            return MealTimeEditing.clamp(
                raw, slot: slot,
                breakfast: times.breakfastMin,
                lunch: times.lunchMin,
                dinner: times.dinnerMin
            )
        case .quietStart, .quietEnd:
            return MealTimeEditing.snap(raw)
        }
    }

    /// Noon at the top, clockwise.
    private func angle(_ m: Int) -> Double { Double(m - 720) / 1440 * 2 * .pi }

    private func point(_ m: Int, r: CGFloat, c: CGPoint) -> CGPoint {
        CGPoint(x: c.x + r * CGFloat(sin(angle(m))), y: c.y - r * CGFloat(cos(angle(m))))
    }

    private func arc(from a: Int, to b: Int, center c: CGPoint) -> Path {
        Path { p in
            let span = (b - a + 1440) % 1440
            let steps = max(2, span / 10)
            for i in 0...steps {
                let pt = point(a + span * i / steps, r: radius, c: c)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
        }
    }
}

/// Tap the time to change it — compact picker, no extra sheet.
private struct MinutesChip: View {
    @Binding var minutes: Int
    var name: String = ""

    var body: some View {
        DatePicker("", selection: dateBinding, displayedComponents: .hourAndMinute)
            .labelsHidden()
            .tint(Palette.ink)
            .fixedSize()
            .accessibilityLabel(name.isEmpty ? formatMinutes(minutes) : "\(name) \(formatMinutes(minutes))")
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { Self.date(from: minutes) },
            set: { date in
                let next = MealTimeEditing.snap(Self.minutes(from: date))
                guard next != minutes else { return }
                UISelectionFeedbackGenerator().selectionChanged()
                minutes = next
            }
        )
    }

    private static func date(from minutes: Int) -> Date {
        var comps = DateComponents()
        comps.hour = minutes / 60
        comps.minute = minutes % 60
        return Calendar.current.date(from: comps) ?? .now
    }

    private static func minutes(from date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}

// MARK: - Foods I avoid

struct FoodsSettingsView: View {
    @Bindable var model: SettingsViewModel
    @State private var ruleDraft = ""
    @State private var dislikeDraft = ""
    @State private var pantryDraft = ""

    private static let allergies = ["Peanuts", "Tree nuts", "Shellfish", "Fish", "Sesame", "Eggs", "Soy"]
    private static let intolerances = ["Dairy", "Gluten"]
    private static let dontEat = ["Pork", "Beef", "Vegetarian", "Vegan"]
    private static var known: [String] { allergies + intolerances + dontEat }

    private static let pantrySuggestions = [
        "Oats", "Milk", "Eggs", "Rice", "Chicken", "Bread",
        "Peanut butter", "Bananas", "Greek yogurt", "Pasta",
        "Olive oil", "Cheese",
    ]

    /// Where pantry foods sit around the plate (centre x, y in a 350 × 290 box).
    private static let slots: [CGPoint] = [
        CGPoint(x: 0.5, y: 0.08), CGPoint(x: 0.82, y: 0.24), CGPoint(x: 0.18, y: 0.24), CGPoint(x: 0.85, y: 0.52),
        CGPoint(x: 0.15, y: 0.52), CGPoint(x: 0.78, y: 0.8), CGPoint(x: 0.22, y: 0.8), CGPoint(x: 0.5, y: 0.93),
    ]

    var body: some View {
        InnerScreen(spacing: 14) {
            ScreenHeader(label: "Foods") {
                Text(L10n("\(neverCount) never"))
                    .font(Typography.mono(11))
                    .foregroundStyle(Color(hex: 0xFCA5A5))
            }

            Headline("On the plate.", tail: "Off the table.", size: 38)
                .appearIn(0, rise: 16)

            plate.appearIn(1, rise: 14)

            Text("Top-ups and the evening close reach for these first.")
                .font(Typography.data(13, weight: .regular))
                .foregroundStyle(Palette.inkSoft)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)

            addField("Something you keep around…", text: $pantryDraft) { add(&pantryDraft, to: \.pantryTokens) }
                .appearIn(2)

            tray.appearIn(3, rise: 14)
        }
        .animation(Motion.settle, value: model.restrictions)
        .animation(Motion.settle, value: model.pantryTokens)
        .animation(Motion.settle, value: model.dislikedFoods)
        .settingsSaveBar(
            visible: model.restrictionsDirty,
            note: model.restrictionsSaveNote,
            saving: model.saving,
            disabled: model.saving
        ) {
            Task {
                await model.save()
                if model.error == nil { Haptics.landed() }
            }
        }
        .onDisappear { model.revertToOriginal() }
    }

    private var neverCount: Int { model.restrictions.count + model.dislikedFoods.count }

    // MARK: Plate

    private var plateSuggestions: [String] {
        let existing = Set(model.pantryTokens.map { $0.lowercased() })
        let blocked = Set(model.restrictions.map { $0.lowercased() })
        return Self.pantrySuggestions.filter { !existing.contains($0.lowercased()) && !blocked.contains($0.lowercased()) }
    }

    /// What's in the kitchen, floating around a plate that glows brighter the more there is.
    private var plate: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let items = Array(model.pantryTokens.prefix(8))
            let freeSlots = max(0, Self.slots.count - items.count)
            let hints = Array(plateSuggestions.prefix(freeSlots))
            ZStack {
                FuelOrb(size: 120, glow: 0.42)
                    .opacity(0.35 + 0.65 * min(1, Double(items.count) / 5))
                    .position(x: w / 2, y: h / 2)
                VStack(spacing: 2) {
                    Text("\(model.pantryTokens.count)")
                        .font(Typography.data(34, weight: .light))
                    Text("AT HOME")
                        .font(Typography.mono(9))
                        .tracking(1.2)
                        .foregroundStyle(Color(hex: 0xFDE6CF))
                }
                .foregroundStyle(Palette.ink)
                .shadow(color: .black.opacity(0.6), radius: 6, y: 2)
                .position(x: w / 2, y: h / 2)

                ForEach(Array(items.enumerated()), id: \.element) { index, item in
                    let slot = Self.slots[index]
                    Button {
                        model.pantryTokens.removeAll { $0 == item }
                    } label: {
                        HStack(spacing: 6) {
                            Text(item)
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Palette.inkFaint)
                        }
                        .font(Typography.data(13, weight: .regular))
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(.ultraThinMaterial.opacity(0.6), in: Capsule())
                        .background(Color(hex: 0x18181B, opacity: 0.7), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color(hex: 0xFF8A50, opacity: 0.6)))
                        .shadow(color: Palette.ember.opacity(0.22), radius: 9)
                        .fixedSize()
                    }
                    .buttonStyle(PressableCard())
                    .floating(index)
                    .position(x: slot.x * w, y: slot.y * h)
                    .accessibilityLabel(L10n("Remove \(item)"))
                }

                ForEach(Array(hints.enumerated()), id: \.element) { index, hint in
                    let slot = Self.slots[items.count + index]
                    Button {
                        withAnimation(Motion.settle) {
                            model.pantryTokens.append(hint)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 9, weight: .semibold))
                            Text(hint)
                        }
                        .font(Typography.data(12, weight: .regular))
                        .foregroundStyle(Palette.inkFaint)
                        .padding(.horizontal, 11)
                        .frame(height: 30)
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                        .fixedSize()
                    }
                    .buttonStyle(PressableCard())
                    .floating(index + 3)
                    .position(x: slot.x * w, y: slot.y * h)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    .accessibilityLabel(L10n("Add \(hint)"))
                }
            }
        }
        .frame(height: 290)
    }

    // MARK: Tray

    private var ruledOut: [(label: String, kind: String, dislike: Bool)] {
        model.restrictions.map { ($0, kind(of: $0), false) } + model.dislikedFoods.map { ($0, L10n( "Dislike"), true) }
    }

    private var suggestions: [String] {
        Self.known.filter { item in !model.restrictions.contains { $0.caseInsensitiveCompare(item) == .orderedSame } }
    }

    private func kind(of item: String) -> String {
        if Self.allergies.contains(item) { return L10n( "Allergy") }
        if Self.intolerances.contains(item) { return L10n( "Intolerant") }
        if Self.dontEat.contains(item) { return L10n( "Choice") }
        return L10n( "Yours")
    }

    private var tray: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Off the table", systemImage: "nosign")
                    .labelStyle(TrayLabelStyle())
                Spacer()
                Text("HARD RULE")
                    .font(Typography.mono(10))
                    .tracking(1)
                    .foregroundStyle(Palette.inkFaint)
            }

            FlexWrap(spacing: 8, lineSpacing: 8) {
                ForEach(ruledOut, id: \.label) { item in
                    Button {
                        if item.dislike {
                            model.dislikedFoods.removeAll { $0 == item.label }
                        } else {
                            model.restrictions.removeAll { $0 == item.label }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text(LocalizedStringKey(item.label))
                                .strikethrough(true, color: Palette.danger.opacity(0.75))
                                .font(Typography.data(14, weight: .regular))
                                .foregroundStyle(Color(hex: 0xFECACA))
                            Text(item.kind)
                                .font(Typography.mono(9))
                                .tracking(1)
                                .foregroundStyle(Palette.danger)
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .background(Palette.danger.opacity(0.10), in: Capsule())
                        .overlay(Capsule().strokeBorder(Palette.danger.opacity(0.42)))
                    }
                    .buttonStyle(PressableCard())
                    .accessibilityLabel(L10n("Allow \(L10nKey(item.label)) again"))
                }
            }
            if ruledOut.isEmpty {
                Text("Nothing yet. Tap one below.")
                    .font(Typography.data(13, weight: .regular))
                    .foregroundStyle(Palette.inkFaint)
                    .hintCopy()
            }

            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)

            Text("Common · tap to rule out")
                .font(Typography.data(12, weight: .regular))
                .foregroundStyle(Palette.inkFaint)
                .hintCopy()
            FlexWrap(spacing: 6, lineSpacing: 6) {
                ForEach(suggestions, id: \.self) { item in
                    Button { model.restrictions.append(item) } label: {
                        Text("+ \(L10nKey(item))")
                            .font(Typography.data(13, weight: .regular))
                            .foregroundStyle(Palette.inkSoft)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    }
                    .buttonStyle(PressableCard())
                }
            }

            addField("Rule out something else…", text: $ruleDraft) {
                model.addCustomRestriction(ruleDraft)
                ruleDraft = ""
            }
            addField("A food you don’t like…", text: $dislikeDraft) { add(&dislikeDraft, to: \.dislikedFoods) }

            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.positive)
                Text("Every check-in, top-up and evening close skips these.")
                    .font(Typography.data(12, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Palette.danger.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.danger.opacity(0.30), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
    }

    private func addField(_ prompt: String, text: Binding<String>, onAdd: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            TextField(LocalizedStringKey(prompt), text: text)
                .font(Typography.data(15, weight: .regular))
                .foregroundStyle(Palette.ink)
                .submitLabel(.done)
                .onSubmit(onAdd)
            StepCircle(symbol: "plus", label: "Add", action: onAdd)
        }
        .padding(.leading, 18)
        .padding(.trailing, 7)
        .frame(height: 50)
        .glassCapsule(fill: Color.white.opacity(0.05), stroke: Color.white.opacity(0.10))
    }

    private func add(_ text: inout String, to keyPath: ReferenceWritableKeyPath<SettingsViewModel, [String]>) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        if !model[keyPath: keyPath].contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) {
            model[keyPath: keyPath].append(value)
        }
        text = ""
    }
}

private struct TrayLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.danger)
            configuration.title.sectionLabelStyle(Color(hex: 0xFCA5A5))
        }
    }
}

private extension View {
    /// A slow bob, offset per item so the chips don't move in step.
    func floating(_ index: Int) -> some View {
        modifier(FloatBob(index: index))
    }
}

private struct FloatBob: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        TimelineView(.animation(paused: reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let period = 5.0 + Double(index % 3) * 0.5
            content.offset(y: reduceMotion ? 0 : CGFloat(sin((t / period + Double(index) * 0.37) * 2 * .pi)) * 4.5)
        }
    }
}

// MARK: - Apple Health

struct HealthSettingsView: View {
    @Environment(AppEnvironment.self) private var env

    private var on: Bool { env.health.connected }

    var body: some View {
        InnerScreen(glow: .mixed, spacing: 14) {
            ScreenHeader(label: "") {
                StatusPill(dot: on ? Palette.positive : Color(hex: 0x52525B), text: on ? env.health.statusLine : "Not connected")
            }

            Headline("Workouts in.", tail: "Meals out.", size: 40)
                .appearIn(0, rise: 16)

            bridge.appearIn(1, rise: 14)

            if on && env.health.needsMorePermissions {
                ActionButton(title: "Allow meals and workouts", kind: .secondary) {
                    Task { await env.health.grantMorePermissions() }
                }
            }

            if env.health.state == .connected && !env.health.hasHeartData {
                Text("No heart data yet. Wear your Apple Watch, or check SetPoint’s access in Health → Sharing → Apps.")
                    .font(Typography.data(12, weight: .regular))
                    .foregroundStyle(Palette.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let message = env.health.lastError, !on {
                Text(message)
                    .font(Typography.data(13, weight: .regular))
                    .foregroundStyle(Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Image(systemName: "lock")
                    .font(.system(size: 12, weight: .medium))
                Text("Raw readings stay on this phone. Edits in SetPoint overwrite the same meal in Health.")
                    .font(Typography.data(12, weight: .regular))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Palette.inkFaint)
            .appearIn(2)

            if on {
                ActionButton(title: "Manage in the Health app", kind: .secondary, action: openHealth)
                    .appearIn(3)
            } else {
                ActionButton(title: env.health.connecting ? L10n("Connecting") : L10n("Connect Apple Health"), busy: env.health.connecting) {
                    Task { await env.health.connect() }
                }
                .appearIn(3)
            }
        }
        .animation(Motion.settle, value: on)
        .task {
            env.health.refreshTodayWritten()
            await loadWritePreferences()
        }
    }

    private var reads: [String] {
        [L10n("Weight"), L10n("Height · age · sex"), L10n("HRV"), L10n("Resting heart rate")]
    }

    private var writes: [(title: String, value: String?, key: WritableKeyPath<HealthWritePreferences, Bool>)] {
        [
            (L10n("Calories"), env.health.todayWrittenKcal > 0 ? env.health.todayWrittenKcal.formatted() : nil, \.energy),
            (L10n("Protein"), nil, \.protein),
            (L10n("Carbs"), nil, \.carbs),
            (L10n("Fat"), nil, \.fat),
            (L10n("Weight"), nil, \.bodyMass),
        ]
    }

    /// Health at the top, SetPoint at the bottom: what's read flows down the left,
    /// what's written flows up the right. Tap a right-hand pill to stop writing it.
    private var bridge: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let mid = w / 2
            ZStack(alignment: .top) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Color(hex: 0xFF3B5C))
                    .frame(width: 56, height: 56)
                    .background(Palette.ink, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: Color(hex: 0xFF3B5C).opacity(on ? 0.45 : 0), radius: 18)
                    .position(x: mid, y: 28)

                Text("Reads ↓").sectionLabelStyle(on ? Palette.hazeSoft : Color(hex: 0x52525B))
                    .position(x: 36, y: 26)
                Text("Writes ↑").sectionLabelStyle(on ? Palette.amber : Color(hex: 0x52525B))
                    .position(x: w - 38, y: 26)

                line(x: mid - 25, color: Palette.hazeSoft)
                line(x: mid + 24, color: Color(hex: 0xFF8A50))
                if on {
                    FlowingDots(color: Palette.hazeSoft, length: 240, downward: true)
                        .position(x: mid - 25, y: 66 + 120)
                    FlowingDots(color: Palette.amber, length: 240, downward: false)
                        .position(x: mid + 24, y: 66 + 120)
                }

                VStack(alignment: .trailing, spacing: 10) {
                    ForEach(reads, id: \.self) { item in
                        Text(item)
                            .font(Typography.data(13, weight: .regular))
                            .foregroundStyle(on ? Color(hex: 0xE0E7FF) : Color(hex: 0x71717A))
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(Capsule().fill(on ? Palette.haze.opacity(0.10) : .clear))
                            .overlay(Capsule().strokeBorder(on ? Palette.hazeSoft.opacity(0.32) : Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: on ? [] : [4, 3])))
                            .fixedSize()
                    }
                }
                .frame(width: mid - 39, alignment: .trailing)
                .position(x: (mid - 39) / 2, y: 80 + 102)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(L10n("Reads \(reads.joined(separator: ", "))"))

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(writes, id: \.title) { item in
                        let lit = on && env.health.writePreferences[keyPath: item.key]
                        Button {
                            guard on else { return }
                            env.health.writePreferences[keyPath: item.key].toggle()
                            env.health.persistWritePreferences()
                        } label: {
                            HStack(spacing: 8) {
                                Text(item.title)
                                if let value = item.value {
                                    Text(value)
                                        .font(Typography.mono(11))
                                        .foregroundStyle(lit ? Palette.amber : Color(hex: 0x52525B))
                                }
                            }
                            .font(Typography.data(13, weight: .regular))
                            .foregroundStyle(lit ? Palette.ink : Color(hex: 0x71717A))
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(Capsule().fill(lit ? Palette.ember.opacity(0.12) : .clear))
                            .overlay(Capsule().strokeBorder(lit ? Color(hex: 0xFF8A50, opacity: 0.5) : Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: lit ? [] : [4, 3])))
                            .fixedSize()
                        }
                        .buttonStyle(PressableCard())
                        .accessibilityLabel(L10n("Write \(item.title) to Health"))
                        .accessibilityValue(lit ? L10n("On") : L10n("Off"))
                    }
                }
                .frame(width: mid - 38, alignment: .leading)
                .position(x: mid + 38 + (mid - 38) / 2, y: 80 + 102 + 22)

                FuelOrb(size: 56, dimmed: !on, glow: 0.45)
                    .position(x: mid, y: 340)
            }
        }
        .frame(height: 368)
    }

    private func line(x: CGFloat, color: Color) -> some View {
        Rectangle()
            .fill(color.opacity(on ? 0.45 : 0.18))
            .frame(width: 1.5, height: 240)
            .position(x: x, y: 66 + 120)
            .accessibilityHidden(true)
    }

    private func loadWritePreferences() async {
        guard let settings: SettingsResponse = try? await env.api.get("/api/settings"),
              let payload = settings.healthWrite
        else { return }
        env.health.applyServerWritePreferences(.from(payload))
    }

    private func openHealth() {
        if let url = URL(string: "x-apple-health://"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Account

struct AccountSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Bindable var model: SettingsViewModel
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.localeDefault
    @AppStorage(MassUnit.storageKey) private var massUnit = MassUnit.localeDefault
    @AppStorage(HintCopy.storageKey) private var showHints = true
    @State private var confirmingDelete: Bool
    @FocusState private var nameFocused: Bool

    init(model: SettingsViewModel, startDeleting: Bool = false) {
        self.model = model
        _confirmingDelete = State(initialValue: startDeleting)
    }

    var body: some View {
        InnerScreen(spacing: 16) {
            ScreenHeader(label: "Settings")

            identityCard
                .appearIn(0, rise: 16)

            VStack(alignment: .leading, spacing: 14) {
                if env.flags.isOn(.appLanguage) {
                    prefSwitch("Language") {
                        SegmentedPills(options: AppLanguage.allCases, selection: $language, title: { $0.title })
                    }
                }
                prefSwitch("Units") {
                    SegmentedPills(options: MassUnit.allCases, selection: $massUnit, title: { $0.abbreviation })
                }
                prefSwitch("Hints") {
                    SegmentedPills(options: [true, false], selection: $showHints, title: { $0 ? L10n("On") : L10n("Off") })
                }
            }
            .appearIn(1, rise: 14)

            GlassList {
                Button(action: openNotificationSettings) {
                    accountRow("Notifications", value: notificationsValue, chevron: true)
                }
                .buttonStyle(.plain)
                ListDivider()
                accountRow("Time zone", value: timezoneValue)
            }
            .appearIn(2, rise: 14)

            GlassList {
                legalRow("Privacy policy", url: privacyURL)
                ListDivider()
                legalRow("Terms", url: termsURL)
                ListDivider()
                legalRow("Contact support", url: supportURL)
            }
            .appearIn(3, rise: 14)

            GlassList {
                Button(action: env.auth.signOut) {
                    accountRow("Sign out", value: nil)
                }
                .buttonStyle(.plain)
                ListDivider()
                Button { confirmingDelete = true } label: {
                    Text("Delete account")
                        .font(Typography.data(15, weight: .regular))
                        .foregroundStyle(Palette.danger)
                        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(model.deleting)
            }
            .appearIn(4, rise: 14)

            Text(L10n("SetPoint \(shortVersion)"))
                .font(Typography.mono(11))
                .foregroundStyle(Palette.inkFaint)
                .frame(maxWidth: .infinity)
                .hintCopy()
                .appearIn(5)

            if let error = model.error {
                SettingsErrorBanner(message: error)
            }
        }
        .settingsSaveBar(
            visible: model.displayNameDirty,
            note: nil,
            saving: model.saving,
            disabled: model.saving
        ) {
            nameFocused = false
            Task {
                await model.saveDisplayName()
                if model.error == nil { Haptics.landed() }
            }
        }
        .sheet(isPresented: $confirmingDelete) {
            DeleteAccountConfirmation(model: model)
                .presentationDetents([.height(300)])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color(hex: 0x18181C))
                .presentationCornerRadius(32)
                .interactiveDismissDisabled(model.deleting)
        }
        .task { await env.push.syncAuthorizationStatus() }
    }

    private var identityCard: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(identityInitial)
                .font(Typography.data(22, weight: .medium))
                .foregroundStyle(Palette.onBone)
                .frame(width: 64, height: 64)
                .background(
                    RadialGradient(
                        colors: [Color(hex: 0xFFD9A8), Palette.ember],
                        center: UnitPoint(x: 0.35, y: 0.3),
                        startRadius: 0,
                        endRadius: 40
                    ),
                    in: Circle()
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                TextField("Your name", text: $model.displayName)
                    .font(Typography.data(22, weight: .regular))
                    .foregroundStyle(Palette.ink)
                    .focused($nameFocused)
                    .textContentType(.name)
                    .submitLabel(.done)
                    .onSubmit { nameFocused = false }
                    .accessibilityLabel("Name")
                if let email = model.visibleEmail {
                    Text(email)
                        .font(Typography.data(14, weight: .regular))
                        .foregroundStyle(Palette.inkSoft)
                        .textSelection(.enabled)
                        .lineLimit(1)
                } else if model.email == nil {
                    Text(L10n( "Signed in with Apple"))
                        .font(Typography.data(14, weight: .regular))
                        .foregroundStyle(Palette.inkSoft)
                        .lineLimit(1)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(radius: 24)
    }

    private var identityInitial: String {
        let name = model.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = name.first { return String(first).uppercased() }
        if let first = model.visibleEmail?.first { return String(first).uppercased() }
        return "Y"
    }

    private func prefSwitch<Content: View>(_ title: String, @ViewBuilder control: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(title)).sectionLabelStyle().padding(.horizontal, 4)
            control()
        }
    }

    private func accountRow(_ title: String, value: String?, chevron: Bool = false) -> some View {
        HStack(spacing: 12) {
            Text(LocalizedStringKey(title))
                .font(Typography.data(15, weight: .regular))
                .foregroundStyle(Palette.ink)
            Spacer(minLength: 8)
            if let value {
                Text(LocalizedStringKey(value))
                    .font(Typography.data(13, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
                    .lineLimit(1)
            }
            if chevron {
                Image(systemName: "chevron.forward")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x52525B))
            }
        }
        .frame(minHeight: 50)
        .contentShape(Rectangle())
    }

    private var notificationsValue: String {
        switch env.push.authorizationStatus {
        case .authorized, .provisional: return L10n( "On")
        case .denied: return L10n( "Off")
        default: return L10n( "Not set")
        }
    }

    private var timezoneValue: String {
        TimeZone(identifier: model.timezone)?.localizedName(for: .generic, locale: AppLanguage.current.locale) ?? model.timezone
    }

    private var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var privacyURL: URL { APIConfig.baseURL.appending(path: "privacy") }
    private var termsURL: URL { APIConfig.baseURL.appending(path: "terms") }
    private var supportURL: URL { APIConfig.supportMailto }

    private func legalRow(_ title: String, url: URL) -> some View {
        Link(destination: url) {
            accountRow(title, value: nil, chevron: true)
        }
        .buttonStyle(.plain)
    }

    private func openNotificationSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

struct DeleteAccountConfirmation: View {
    @Bindable var model: SettingsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Delete everything?")
                .font(Typography.data(20, weight: .medium))
                .foregroundStyle(Palette.ink)
            Text("Your plan, meals, weigh-ins and history go for good. This can’t be undone.")
                .font(Typography.data(14, weight: .regular))
                .foregroundStyle(Palette.inkSoft)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                ActionButton(title: "Cancel", kind: .secondary) { dismiss() }
                    .disabled(model.deleting)
                Button {
                    Task { await model.deleteAccount() }
                } label: {
                    BusyLabel(title: model.deleting ? "Deleting" : "Delete", busy: model.deleting, tint: .white)
                        .font(Typography.data(15, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color(hex: 0xDC2626), in: Capsule())
                }
                .buttonStyle(PressableCard())
                .disabled(model.deleting)
            }
            .padding(.top, 6)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
