import SwiftUI
import UIKit

// MARK: - Goal and pace

struct GoalSettingsView: View {
    @AppStorage(MassUnit.storageKey) private var massUnit = MassUnit.localeDefault
    @Bindable var model: SettingsViewModel
    @State private var editingTarget: DailyTargetField?

    var body: some View {
        SettingsScreen(title: "Edit plan", subtitle: "Change anything.", headline: "Your plan.") {
            VStack(alignment: .leading, spacing: 14) {
                SegmentedPills(
                    options: Goal.allCases,
                    selection: Binding(
                        get: { model.goal },
                        set: { goal in
                            withAnimation(Motion.settle) {
                                let changed = model.goal != goal
                                model.goal = goal
                                proposeTargetIfNeeded()
                                if changed { model.resetDurationForGoalChange() }
                            }
                        }
                    ),
                    title: { $0.title }
                )
                .appearIn(1, rise: 14)

                if model.goal.hasWeightTarget {
                    targetCard.appearIn(2, rise: 14)
                }

                yourDay.appearIn(3, rise: 14)

                if let error = model.error {
                    SettingsErrorBanner(message: error)
                }
            }
        }
        .animation(Motion.settle, value: model.goal)
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

    private var targetCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("Target weight").sectionLabelStyle()
                Spacer(minLength: 0)
                StepCircle(symbol: "minus", label: "Lower target") { nudge(-1) }
                Text("\(massUnit.number(targetKg, digits: 0 ... 0)) \(massUnit.abbreviation)")
                    .font(Typography.mono(18))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 76)
                    .contentTransition(.numericText(value: targetKg))
                    .accessibilityLabel("Target \(massUnit.number(targetKg, digits: 0 ... 0)) \(massUnit.spokenName)")
                StepCircle(symbol: "plus", label: "Raise target") { nudge(1) }
            }

            if model.targetWeightMessage == nil {
                SegmentedPills(
                    options: GoalPace.allCases,
                    selection: Binding(
                        get: { model.pace },
                        set: { model.applyPaceShortcut($0) }
                    ),
                    title: { $0.title },
                    detail: { $0.blurb(for: model.goal) }
                )
                ListDivider()
                StepperRow(
                    name: "Timeframe",
                    note: model.currentWeightKg.map { "from \(massUnit.formatKg($0)) now" },
                    value: "\(weeks) wk",
                    canDown: weeks > 1,
                    onDown: { model.setDurationWeeks(weeks - 1) },
                    onUp: { model.setDurationWeeks(weeks + 1) }
                )
            }

            if let message = model.targetWeightMessage ?? model.durationMessage {
                Text(message)
                    .font(Typography.data(13, weight: .regular))
                    .foregroundStyle(Palette.amber)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .glass(radius: 22)
    }

    private var weeks: Int { model.preferredDurationWeeks ?? model.honestDurationWeeks ?? 12 }

    /// The day the plan works out to — tap a number to set it yourself.
    private var yourDay: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Your day").sectionLabelStyle(Palette.amber)
                Spacer()
                Text(model.dailyTargetsEdited ? "Set by you" : "From your goal")
                    .font(Typography.data(12, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Button { editingTarget = .kcal } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(model.kcalTarget.formatted())
                            .font(Typography.data(36, weight: .light))
                            .tracking(-1.1)
                            .foregroundStyle(Palette.ink)
                        Text("kcal")
                            .font(Typography.data(15, weight: .regular))
                            .foregroundStyle(Palette.inkSoft)
                        if model.kcalEdited {
                            Text(model.savedKcalTarget.formatted())
                                .font(Typography.mono(13))
                                .strikethrough()
                                .foregroundStyle(Palette.inkFaint)
                        }
                    }
                }
                .buttonStyle(PressableCard())
                .accessibilityLabel("\(model.kcalTarget) calories a day. Set it yourself.")
                if let protein = model.proteinTarget {
                    Text("·").foregroundStyle(Palette.inkFaint)
                    Button { editingTarget = .protein } label: {
                        Text("\(protein) g protein")
                            .font(Typography.data(15, weight: .regular))
                            .foregroundStyle(Palette.inkSoft)
                            .strikethrough(false)
                    }
                    .buttonStyle(PressableCard())
                    .accessibilityLabel("\(protein) grams of protein. Set it yourself.")
                }
            }
            Text(dayLine)
                .font(Typography.data(13, weight: .regular))
                .foregroundStyle(Palette.inkSoft)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [Palette.ember.opacity(0.10), Palette.ember.opacity(0.03)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color(hex: 0xFF8A50, opacity: 0.35)))
        }
    }

    private var dayLine: String {
        var parts: [String] = []
        if model.goal.hasWeightTarget, let eta = model.honestDurationWeeks {
            parts.append("About \(eta) weeks to target")
        }
        parts.append("Tap a number to set it yourself")
        return parts.joined(separator: " · ")
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
            Text(field == .kcal ? "Daily calories" : "Daily protein")
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
            value = field == .kcal ? Double(model.kcalTarget) : Double(model.proteinTarget ?? 40)
        }
    }
}

// MARK: - Meal times

struct RhythmSettingsView: View {
    @Bindable var model: SettingsViewModel
    @State private var rhythmSet: RhythmSet = .weekdays

    private enum RhythmSet: String, CaseIterable, Identifiable {
        case weekdays, weekends
        var id: String { rawValue }
        var title: String {
            switch self {
            case .weekdays: return "Weekdays"
            case .weekends: return "Weekends"
            }
        }
    }

    private var editingWeekends: Bool { rhythmSet == .weekends }

    private var activeTimes: MealTimesPayload {
        editingWeekends ? model.resolvedWeekendTimes : model.mealTimes
    }

    var body: some View {
        SettingsScreen(title: "Meal times", subtitle: "I watch these times.", headline: "When do you eat?") {
            VStack(alignment: .leading, spacing: 20) {
                SegmentedPills(
                    options: RhythmSet.allCases,
                    selection: $rhythmSet,
                    title: { $0.title }
                )
                .appearIn(1)

                if let suggestion = model.weekendSuggestion, editingWeekends {
                    suggestionBanner(suggestion).appearIn(2)
                }

                mealRows.appearIn(2, rise: 14)
                if editingWeekends {
                    weekendDaysCard.appearIn(4)
                }
                quietCard.appearIn(5)
                if let error = model.error {
                    SettingsErrorBanner(message: error)
                }
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
        .animation(Motion.settle, value: model.checkInsPaused)
        .animation(Motion.settle, value: rhythmSet)
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
                    Text("Weekends are running \(suggestion.lateByMin) min later")
                        .font(Typography.data(14, weight: .medium))
                        .foregroundStyle(Palette.ink)
                    Text("Set weekend breakfast to \(formatMinutes(suggestion.breakfastMin)).")
                        .font(Typography.data(13))
                        .foregroundStyle(Palette.inkSoft)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .glass(radius: 20, fill: Palette.ember.opacity(0.08), stroke: Palette.amber.opacity(0.3))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Use suggested weekend breakfast \(formatMinutes(suggestion.breakfastMin))")
    }

    private var mealRows: some View {
        GlassList {
            ForEach(Array(MealSlot.allCases.enumerated()), id: \.element) { index, slot in
                if index > 0 { ListDivider() }
                let t = activeTimes[slot]
                let weekday = model.mealTimes[slot]
                StepperRow(
                    name: slot.title,
                    note: (editingWeekends && t != weekday ? "weekdays \(formatMinutes(weekday)) · " : "")
                        + "check-in \(formatMinutes(CheckInSchedule.minute(afterMeal: t)))",
                    value: formatMinutes(t),
                    onDown: { withAnimation(Motion.settle) { setTime(t - 15, slot: slot) } },
                    onUp: { withAnimation(Motion.settle) { setTime(t + 15, slot: slot) } }
                )
            }
        }
    }

    private func mealBinding(_ slot: MealSlot) -> Binding<Int> {
        Binding(
            get: { activeTimes[slot] },
            set: { setTime($0, slot: slot) }
        )
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

    private var weekendDaysCard: some View {
        SettingsCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Weekend days")
                    .font(Typography.data(15, weight: .medium))
                    .foregroundStyle(Palette.ink)
                Text("Check-ins follow this set on these days.")
                    .font(Typography.data(13))
                    .foregroundStyle(Palette.inkSoft)
                HStack(spacing: 6) {
                    ForEach(Array(WeekendDays.bitsInDisplayOrder.enumerated()), id: \.offset) { index, bit in
                        let on = WeekendDays.contains(model.weekendDays, weekday: bit)
                        Button {
                            withAnimation(Motion.settle) {
                                model.weekendDays = WeekendDays.toggling(model.weekendDays, weekday: bit)
                            }
                        } label: {
                            Text(WeekendDays.labels[index])
                                .font(Typography.mono(12))
                                .foregroundStyle(on ? Palette.onBone : Palette.ink)
                                .frame(width: 38, height: 38)
                                .background(on ? Palette.ink : Color.white.opacity(0.06), in: Circle())
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(WeekendDays.names[index])
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
        }
    }

    private var quietSpanMinutes: Int {
        (model.quietHours.endMin - model.quietHours.startMin + 1440) % 1440
    }

    private var quietSpanLabel: String {
        let hours = quietSpanMinutes / 60
        let mins = quietSpanMinutes % 60
        if hours == 0 { return "\(mins) min overnight" }
        if mins == 0 { return hours == 1 ? "1 hour overnight" : "\(hours) hours overnight" }
        return "\(hours) hr \(mins) min overnight"
    }

    private var quietCard: some View {
        SettingsCard(padding: 16) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    Image(systemName: "moon")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Palette.hazeSoft)
                        .frame(width: 36, height: 36)
                        .background(Palette.haze.opacity(0.14), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Quiet hours")
                            .font(Typography.data(15, weight: .medium))
                            .foregroundStyle(Palette.ink)
                        Text("No check-ins while you sleep.")
                            .font(Typography.data(13))
                            .foregroundStyle(Palette.inkSoft)
                    }
                }

                HStack(alignment: .center, spacing: 10) {
                    quietWell("Starts", $model.quietHours.startMin)
                    quietBridge
                    quietWell("Until", $model.quietHours.endMin)
                }

                Text(quietSpanLabel)
                    .font(Typography.mono(11))
                    .foregroundStyle(Palette.inkFaint)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
            }
        }
    }

    private var quietBridge: some View {
        VStack(spacing: 6) {
            Capsule()
                .fill(Palette.hairline)
                .frame(width: 1, height: 10)
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.inkFaint)
            Capsule()
                .fill(Palette.hairline)
                .frame(width: 1, height: 10)
        }
        .frame(width: 22)
        .accessibilityHidden(true)
    }

    private func quietWell(_ title: String, _ minutes: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).sectionLabelStyle()
            MinutesChip(
                minutes: Binding(
                    get: { minutes.wrappedValue },
                    set: { value in
                        withAnimation(Motion.settle) { minutes.wrappedValue = value }
                    }
                ),
                name: title
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(radius: 16, fill: Color.white.opacity(0.04))
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
    @State private var customText = ""
    @State private var pantryDraft = ""
    @State private var dislikeDraft = ""

    private static let allergies = ["Peanuts", "Tree nuts", "Shellfish", "Fish", "Sesame", "Eggs", "Soy"]
    private static let intolerances = ["Dairy", "Gluten"]
    private static let dontEat = ["Pork", "Beef", "Vegetarian", "Vegan"]
    private static var known: [String] { allergies + intolerances + dontEat }

    private var customRestrictions: [String] {
        model.restrictions.filter { item in
            !Self.known.contains { $0.caseInsensitiveCompare(item) == .orderedSame }
        }
    }

    var body: some View {
        SettingsScreen(title: "Foods I avoid", subtitle: "Hard rule.", headline: "Never suggest these.") {
            VStack(alignment: .leading, spacing: 20) {
                chipGroup("Allergies", Self.allergies).appearIn(2)
                chipGroup("Intolerances", Self.intolerances).appearIn(3)
                chipGroup("I don’t eat", Self.dontEat).appearIn(4)
                if !customRestrictions.isEmpty {
                    chipGroup("Yours", customRestrictions).appearIn(5)
                }
                addYourOwn.appearIn(6)
                tokenField("What I have around", text: $pantryDraft, tokens: $model.pantryTokens).appearIn(7)
                tokenField("I don’t like", text: $dislikeDraft, tokens: $model.dislikedFoods).appearIn(8)
                reassurance.appearIn(9)
            }
        }
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

    private func chipGroup(_ title: String, _ options: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).sectionLabelStyle()
            FlowChips(options: options, selected: $model.restrictions)
        }
    }

    private var addYourOwn: some View {
        addField("Something else…", text: $customText, onAdd: submitCustom)
    }

    private var reassurance: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.positive)
            Text("Every check-in, top-up and evening close skips these.")
                .font(Typography.data(13, weight: .regular))
                .foregroundStyle(Palette.inkSoft)
        }
    }

    private func addField(_ prompt: String, text: Binding<String>, onAdd: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            TextField(prompt, text: text)
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

    private func submitCustom() {
        model.addCustomRestriction(customText)
        customText = ""
    }

    private func tokenField(_ title: String, text: Binding<String>, tokens: Binding<[String]>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).sectionLabelStyle()
            if !tokens.wrappedValue.isEmpty {
                FlowChips(options: tokens.wrappedValue, selected: tokens)
            }
            addField("Add…", text: text) { addToken(text, into: tokens) }
        }
    }

    private func addToken(_ text: Binding<String>, into tokens: Binding<[String]>) {
        let value = text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        if !tokens.wrappedValue.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) {
            tokens.wrappedValue.append(value)
        }
        text.wrappedValue = ""
    }
}

// MARK: - Apple Health

struct HealthSettingsView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        SettingsScreen(title: "Apple Health", subtitle: "Workouts in, meals out.", headline: "Apple Health.") {
            VStack(alignment: .leading, spacing: 20) {
                hero.appearIn(2)

                VStack(alignment: .leading, spacing: 10) {
                    Text("SetPoint writes").sectionLabelStyle()
                    GlassList {
                        writeToggle("Calories", "Today \(env.health.todayWrittenKcal) kcal", \.energy)
                        ListDivider()
                        writeToggle("Protein", nil, \.protein)
                        ListDivider()
                        writeToggle("Carbs", nil, \.carbs)
                        ListDivider()
                        writeToggle("Fat", nil, \.fat)
                        ListDivider()
                        writeToggle("Weight you log here", "Optional", \.bodyMass)
                    }
                    Text("Edits and deletes in SetPoint overwrite the same meal in Health.")
                        .font(Typography.data(13, weight: .regular))
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .appearIn(3)

                VStack(alignment: .leading, spacing: 10) {
                    Text("SetPoint reads").sectionLabelStyle()
                    FlexWrap(spacing: 8, lineSpacing: 8) {
                        ForEach(readChips, id: \.self) { chip in
                            Text(chip)
                                .font(Typography.data(14, weight: .regular))
                                .foregroundStyle(Palette.ink)
                                .padding(.horizontal, 14)
                                .frame(height: 38)
                                .glassCapsule()
                        }
                    }
                }
                .appearIn(4)

                privacyNote.appearIn(5)

                ActionButton(title: "Manage in the Health app", kind: .secondary, action: openHealth)
                    .appearIn(6)
            }
        }
        .task {
            env.health.refreshTodayWritten()
            await loadWritePreferences()
        }
    }

    private var readChips: [String] {
        ["Heart rate variability", "Resting heart rate", "Weight", "Height, age, sex"]
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color(hex: 0xFF3B5C))
                    .frame(width: 44, height: 44)
                    .background(Palette.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(env.health.connected ? "Connected" : "Not connected")
                        .font(Typography.data(15, weight: .medium))
                        .foregroundStyle(Palette.ink)
                    Text(env.health.connected ? env.health.statusLine : "Workouts in, so refuels come on time")
                        .font(Typography.data(13, weight: .regular))
                        .foregroundStyle(Palette.inkSoft)
                }
                Spacer(minLength: 8)
                if !env.health.connected {
                    Button {
                        Task { await env.health.connect() }
                    } label: {
                        Group {
                            if env.health.connecting {
                                BusyDots(tint: Palette.onBone)
                            } else {
                                Text("Connect")
                            }
                        }
                        .font(Typography.data(13, weight: .medium))
                        .foregroundStyle(Palette.onBone)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(Palette.ink, in: Capsule())
                    }
                    .buttonStyle(PressableCard())
                    .disabled(env.health.connecting)
                } else {
                    Circle().fill(Palette.positive).frame(width: 8, height: 8)
                }
            }

            Text(heroDetail)
                .font(Typography.data(13, weight: .regular))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            if env.health.connected && env.health.needsMorePermissions {
                ActionButton(title: "Allow meals and workouts", kind: .secondary) {
                    Task { await env.health.grantMorePermissions() }
                }
            }

            if env.health.state == .connected && !env.health.hasHeartData {
                Text("No heart data yet. Wear your Apple Watch, or check SetPoint’s access in Health → Sharing → Apps.")
                    .font(Typography.data(13, weight: .regular))
                    .foregroundStyle(Palette.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let message = env.health.lastError, !env.health.connected {
                Text(message)
                    .font(Typography.data(13, weight: .regular))
                    .foregroundStyle(Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(radius: 22)
    }

    private var heroDetail: String {
        if env.health.connected {
            return "Meals you log write to Apple Health. Recovery and weight still flow the other way."
        }
        return "Connect to write meals into Health and fill in your body stats."
    }

    private func writeToggle(
        _ title: String,
        _ caption: String?,
        _ keyPath: WritableKeyPath<HealthWritePreferences, Bool>
    ) -> some View {
        Toggle(isOn: Binding(
            get: { env.health.writePreferences[keyPath: keyPath] },
            set: {
                env.health.writePreferences[keyPath: keyPath] = $0
                env.health.persistWritePreferences()
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.data(15, weight: .regular))
                    .foregroundStyle(Palette.ink)
                if let caption {
                    Text(caption)
                        .font(Typography.data(12, weight: .regular))
                        .foregroundStyle(Palette.inkFaint)
                }
            }
        }
        .tint(Palette.ember)
        .padding(.vertical, 12)
    }

    private func loadWritePreferences() async {
        guard let settings: SettingsResponse = try? await env.api.get("/api/settings"),
              let payload = settings.healthWrite
        else { return }
        env.health.applyServerWritePreferences(.from(payload))
    }

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.inkSoft)
                .padding(.top, 2)
            (
                Text("Raw readings stay on this phone.").foregroundColor(Palette.ink)
                + Text(" Nutrition you log is written into Health. I only send how far today is from your normal.").foregroundColor(Palette.inkSoft)
            )
            .font(Typography.data(13, weight: .regular))
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(radius: 18, fill: Color.white.opacity(0.03))
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
    @State private var confirmingDelete: Bool

    init(model: SettingsViewModel, startDeleting: Bool = false) {
        self.model = model
        _confirmingDelete = State(initialValue: startDeleting)
    }

    var body: some View {
        SettingsScreen(title: "Account", subtitle: "Yours to take or delete.", headline: "Your data.") {
            VStack(alignment: .leading, spacing: 20) {
                if !model.enforcementEnabled {
                    ManagerNote(text: enforcementNote(model.enforcementDisabledReason))
                        .appearIn(2)
                }

                GlassList {
                    accountRow("Signed in with", value: "Apple")
                    ListDivider()
                    Button(action: openNotificationSettings) {
                        accountRow("Notifications", value: notificationsValue, chevron: true)
                    }
                    .buttonStyle(.plain)
                    ListDivider()
                    accountRow("Time zone", value: timezoneValue)
                }
                .appearIn(3, rise: 14)

                GlassList {
                    legalRow("Privacy policy", url: privacyURL)
                    ListDivider()
                    legalRow("Terms", url: termsURL)
                    ListDivider()
                    legalRow("Contact support", url: supportURL)
                }
                .appearIn(4, rise: 14)

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
                .appearIn(5, rise: 14)

                Text("Deleting removes your meals, weigh-ins, check-ins and plan from our servers right away, and revokes Sign in with Apple. SetPoint \(shortVersion).")
                    .font(Typography.data(12, weight: .regular))
                    .foregroundStyle(Palette.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    .appearIn(6)

                if let error = model.error {
                    SettingsErrorBanner(message: error)
                }
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

    private func accountRow(_ title: String, value: String?, chevron: Bool = false) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(Typography.data(15, weight: .regular))
                .foregroundStyle(Palette.ink)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(Typography.data(13, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
                    .lineLimit(1)
            }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x52525B))
            }
        }
        .frame(minHeight: 50)
        .contentShape(Rectangle())
    }

    private var notificationsValue: String {
        switch env.push.authorizationStatus {
        case .authorized, .provisional: return "On"
        case .denied: return "Off"
        default: return "Not set"
        }
    }

    private var timezoneValue: String {
        TimeZone(identifier: model.timezone)?.localizedName(for: .generic, locale: .current) ?? model.timezone
    }

    private var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var privacyURL: URL { APIConfig.baseURL.appending(path: "privacy") }
    private var termsURL: URL { APIConfig.baseURL.appending(path: "terms") }
    private var supportURL: URL { URL(string: "mailto:support@setpoint.app")! }

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
