import SwiftUI
import UIKit

// MARK: - Goal and pace

struct GoalSettingsView: View {
    @Bindable var model: SettingsViewModel
    @State private var editingTarget: DailyTargetField?

    var body: some View {
        SettingsScreen(title: "Goal and pace") {
            VStack(alignment: .leading, spacing: 20) {
                goalTiles.appearIn(2)

                if model.goal.hasWeightTarget {
                    targetCard.appearIn(3)
                    duration.appearIn(4)
                }

                dailyTargets.appearIn(6)

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

    private var goalTiles: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(Goal.allCases) { goal in
                let selected = model.goal == goal
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(Motion.settle) {
                        let changed = model.goal != goal
                        model.goal = goal
                        proposeTargetIfNeeded()
                        if changed { model.resetDurationForGoalChange() }
                    }
                } label: {
                    VStack(spacing: 8) {
                        GoalSparkline(goal: goal)
                            .stroke(
                                selected ? Palette.accent : Palette.inkSoft,
                                style: StrokeStyle(lineWidth: 4, lineCap: .round)
                            )
                            .frame(width: 60, height: 40)
                        Text(goal.title)
                            .font(Typography.data(15, weight: .heavy))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity)
                    .background {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(selected ? Palette.surfaceRaised : Palette.surface)
                            .elevation(selected ? .floating : .resting)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .strokeBorder(
                                        selected ? Palette.accent : Palette.hairline,
                                        lineWidth: selected ? 2 : 1
                                    )
                            )
                    }
                }
                .buttonStyle(PressableCard())
                .accessibilityLabel(goal.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private var targetCard: some View {
        SettingsCard(padding: 18) {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack {
                    Text("Target weight").sectionLabelStyle()
                    Spacer()
                    if let current = model.currentWeightKg {
                        Text("\(current.formatted(.number.precision(.fractionLength(1)))) kg now")
                            .font(Typography.data(13, weight: .bold))
                            .foregroundStyle(Palette.inkSoft)
                            .monospacedDigit()
                    }
                }

                TargetCurve(falling: model.goal == .diet, startLabel: curveStartLabel)
                    .frame(height: 112)

                stepperRow

                if let message = model.targetWeightMessage {
                    Text(message)
                        .font(Typography.data(13, weight: .semibold))
                        .foregroundStyle(Palette.accentDeep)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var stepperRow: some View {
        HStack {
            stepperButton("minus", delta: -1)
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(targetKg.formatted(.number.precision(.fractionLength(0))))
                    .font(Typography.data(60, weight: .heavy))
                    .tracking(-2)
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText(value: targetKg))
                Text("kg")
                    .font(Typography.data(20, weight: .bold))
                    .foregroundStyle(Palette.inkFaint)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Target \(Int(targetKg.rounded())) kilograms")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: nudge(1)
                case .decrement: nudge(-1)
                @unknown default: break
                }
            }
            Spacer()
            stepperButton("plus", delta: 1)
        }
    }

    private var duration: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text("How long?").sectionLabelStyle()
            WeeksStepper(
                weeks: Binding(
                    get: { model.preferredDurationWeeks ?? model.honestDurationWeeks ?? 12 },
                    set: { model.setDurationWeeks($0) }
                )
            )
            SegmentedPills(
                options: GoalPace.allCases,
                selection: Binding(
                    get: { model.pace },
                    set: { model.applyPaceShortcut($0) }
                ),
                title: { $0.title },
                detail: { $0.blurb(for: model.goal) }
            )
            if let message = model.durationMessage {
                Text(message)
                    .font(Typography.data(13, weight: .semibold))
                    .foregroundStyle(Palette.accentDeep)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var dailyTargets: some View {
        SettingsCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Daily targets").sectionLabelStyle()
                    Spacer()
                    dailyChip
                }

                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: 10),
                        count: model.proteinTarget == nil ? 1 : 2
                    ),
                    spacing: 10
                ) {
                    targetTile(
                        value: model.kcalTarget.formatted(),
                        struck: model.kcalEdited ? model.savedKcalTarget.formatted() : nil,
                        caption: "kcal a day"
                    ) { editingTarget = .kcal }

                    if let protein = model.proteinTarget {
                        targetTile(
                            value: "\(protein) g",
                            struck: model.proteinEdited ? savedProteinLabel : nil,
                            caption: "protein"
                        ) { editingTarget = .protein }
                    }
                }

                Text("Tap a number to set it yourself.")
                    .font(Typography.data(12))
                    .foregroundStyle(Palette.inkFaint)
            }
        }
    }

    private var dailyChip: some View {
        HStack(spacing: 4) {
            if !model.dailyTargetsEdited {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
            }
            Text(model.dailyTargetsEdited ? "Set by you" : "Set from your goal")
        }
        .font(Typography.data(12, weight: .bold))
        .foregroundStyle(model.dailyTargetsEdited ? Palette.inkSoft : Palette.accentDeep)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            model.dailyTargetsEdited ? Palette.surfaceSunk : Palette.accentTint,
            in: Capsule()
        )
    }

    private func targetTile(value: String, struck: String?, caption: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(value)
                        .font(Typography.data(26, weight: .heavy))
                        .foregroundStyle(Palette.ink)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let struck {
                        Text(struck)
                            .font(Typography.data(16, weight: .semibold))
                            .foregroundStyle(Palette.inkFaint)
                            .strikethrough()
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                Text(caption)
                    .font(Typography.data(12))
                    .foregroundStyle(Palette.inkSoft)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surfaceSunk, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressableCard())
        .accessibilityLabel("\(value) \(caption)")
    }

    @ViewBuilder
    private func dailyTargetSheet(_ field: DailyTargetField) -> some View {
        DailyTargetSheet(field: field, model: model)
            .presentationDetents([.height(320)])
            .presentationDragIndicator(.visible)
            .presentationBackground(Palette.background)
            .presentationCornerRadius(28)
    }

    private var targetKg: Double {
        model.targetWeightKg ?? model.currentWeightKg ?? 70
    }

    private var curveStartLabel: String {
        if let current = model.currentWeightKg {
            return "\(current.formatted(.number.precision(.fractionLength(0 ... 1)))) kg · now"
        }
        return "Now"
    }

    private var savedProteinLabel: String? {
        model.savedProteinTarget.map { "\($0) g" }
    }

    private func stepperButton(_ symbol: String, delta: Double) -> some View {
        Button { nudge(delta) } label: {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 48, height: 48)
                .background(Palette.surfaceSunk, in: Circle())
        }
        .buttonStyle(PressableCard())
        .accessibilityLabel(delta > 0 ? "Increase target" : "Decrease target")
    }

    private func nudge(_ delta: Double) {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(Motion.settle) {
            model.targetWeightKg = min(350, max(25, (targetKg + delta).rounded()))
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

    var body: some View {
        SettingsScreen(title: "Meal times", subtitle: "Drag a meal around the dial, or tap a time.") {
            VStack(alignment: .leading, spacing: 20) {
                dial.appearIn(2)
                mealRows.appearIn(3)
                quietCard.appearIn(4)
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
    }

    private var dial: some View {
        DayDial(
            breakfastMin: model.mealTimes.breakfastMin,
            lunchMin: model.mealTimes.lunchMin,
            dinnerMin: model.mealTimes.dinnerMin,
            quietStartMin: model.quietHours.startMin,
            quietEndMin: model.quietHours.endMin,
            showsHourLabels: false,
            onMove: { slot, minute in
                withAnimation(Motion.settle) { model.mealTimes[slot] = minute }
            }
        ) {
            VStack(spacing: 4) {
                Text("Your day")
                    .font(Typography.voice(22))
                    .foregroundStyle(Palette.ink)
                Text(model.checkInsPaused ? "Check-ins off" : "3 check-ins")
                    .font(Typography.data(12, weight: .bold))
                    .foregroundStyle(Palette.inkSoft)
            }
        }
        .frame(maxWidth: 300)
        .frame(maxWidth: .infinity)
    }

    private var mealRows: some View {
        SettingsCard(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(MealSlot.allCases.enumerated()), id: \.element) { index, slot in
                    if index > 0 {
                        Divider().overlay(Palette.hairline).padding(.leading, 66)
                    }
                    mealRow(slot)
                }
            }
        }
    }

    private func mealRow(_ slot: MealSlot) -> some View {
        let t = model.mealTimes[slot]
        let checkIn = CheckInSchedule.minute(afterMeal: t)
        return HStack(spacing: 14) {
            Image(systemName: slot.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .frame(width: 38, height: 38)
                .background(Palette.accentTint, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(slot.title)
                    .font(Typography.data(16, weight: .heavy))
                    .foregroundStyle(Palette.ink)
                HStack(spacing: 4) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                    Text("check-in \(formatMinutes(checkIn))")
                        .font(Typography.data(12, weight: .semibold))
                        .foregroundStyle(Palette.inkSoft)
                }
            }
            Spacer(minLength: 8)
            MinutesChip(minutes: mealBinding(slot), name: slot.title)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func mealBinding(_ slot: MealSlot) -> Binding<Int> {
        Binding(
            get: { model.mealTimes[slot] },
            set: { minute in
                let clamped = MealTimeEditing.clamp(
                    minute, slot: slot,
                    breakfast: model.mealTimes.breakfastMin,
                    lunch: model.mealTimes.lunchMin,
                    dinner: model.mealTimes.dinnerMin
                )
                withAnimation(Motion.settle) { model.mealTimes[slot] = clamped }
            }
        )
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
                    Image(systemName: "moon.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.inkSoft)
                        .frame(width: 38, height: 38)
                        .background(Palette.surfaceSunk, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Quiet hours")
                            .font(Typography.data(16, weight: .heavy))
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
                    .font(Typography.data(12, weight: .bold))
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
        .background(Palette.surfaceSunk, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        SettingsScreen(title: "Foods I avoid", subtitle: "I’ll never suggest them.") {
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
        HStack(spacing: 8) {
            TextField("Something else…", text: $customText)
                .font(Typography.data(15))
                .foregroundStyle(Palette.ink)
                .submitLabel(.done)
                .onSubmit(submitCustom)
            Button(action: submitCustom) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 38, height: 38)
                    .background(Palette.surface, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add")
        }
        .padding(.leading, 18)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(Palette.surfaceSunk, in: Capsule())
    }

    private var reassurance: some View {
        SettingsCard(padding: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Palette.dayOnTrack)
                    .frame(width: 40, height: 40)
                    .background(Palette.dayOnTrack.opacity(0.13), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Never in a suggestion")
                        .font(Typography.data(15, weight: .heavy))
                        .foregroundStyle(Palette.ink)
                    Text("Every check-in meal skips these.")
                        .font(Typography.data(13))
                        .foregroundStyle(Palette.inkSoft)
                }
            }
        }
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
            HStack(spacing: 8) {
                TextField("Add…", text: text)
                    .font(Typography.data(15))
                    .foregroundStyle(Palette.ink)
                    .submitLabel(.done)
                    .onSubmit { addToken(text, into: tokens) }
                Button { addToken(text, into: tokens) } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 38, height: 38)
                        .background(Palette.surface, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 18)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .background(Palette.surfaceSunk, in: Capsule())
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
        SettingsScreen(title: "Apple Health") {
            VStack(alignment: .leading, spacing: 20) {
                hero.appearIn(2)

                VStack(alignment: .leading, spacing: 10) {
                    Text("What I read").sectionLabelStyle()
                    SettingsCard(padding: 0) {
                        VStack(spacing: 0) {
                            readingRow(
                                symbol: "waveform.path.ecg",
                                title: "Heart rate variability",
                                reason: "Notices a rough day",
                                when: lastSyncWhen
                            )
                            Divider().overlay(Palette.hairline).padding(.leading, 66)
                            readingRow(
                                symbol: "heart",
                                title: "Resting heart rate",
                                reason: "Alongside HRV",
                                when: lastSyncWhen
                            )
                            Divider().overlay(Palette.hairline).padding(.leading, 66)
                            readingRow(
                                symbol: "scalemass",
                                title: "Weight",
                                reason: "Your weekly weigh-in",
                                when: lastSyncWhen
                            )
                            Divider().overlay(Palette.hairline).padding(.leading, 66)
                            readingRow(
                                symbol: "ruler",
                                title: "Height, age, sex",
                                reason: "Your daily target",
                                when: env.health.connected ? "At setup" : nil
                            )
                        }
                    }
                }
                .appearIn(3)

                privacyNote.appearIn(4)

                ActionButton(title: "Manage in the Health app", kind: .secondary, action: openHealth)
                    .appearIn(5)
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            LoopingPhase(period: 1.6, still: 0) { t in
                Image(systemName: "heart.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xFF8A73))
                    .frame(width: 56, height: 56)
                    .background(Palette.background.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .scaleEffect(1 + 0.08 * 0.5 * (1 - cos(t * 2 * .pi)))
            }

            Text(env.health.connected ? "Connected" : "Not connected")
                .font(Typography.display(30))
                .foregroundStyle(Palette.background)

            Text(heroDetail)
                .font(Typography.data(14))
                .foregroundStyle(Palette.background.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)

            if env.health.connected {
                Text(env.health.statusLine)
                    .font(Typography.data(12, weight: .bold))
                    .foregroundStyle(Color(hex: 0xB9D3B1))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Palette.dayOnTrack.opacity(0.25), in: Capsule())
            }

            if env.health.state == .connected && !env.health.hasHeartData {
                Text("No heart data yet. Wear your Apple Watch, or check SetPoint’s access in Health → Sharing → Apps.")
                    .font(Typography.data(13))
                    .foregroundStyle(Palette.background.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !env.health.connected {
                Button {
                    Task { await env.health.connect() }
                } label: {
                    HStack(spacing: 8) {
                        if env.health.connecting {
                            ProgressView().tint(Palette.accentDeep)
                        }
                        Text(env.health.connecting ? "Connecting…" : "Connect Apple Health")
                            .font(Typography.data(16, weight: .bold))
                            .foregroundStyle(Palette.accentDeep)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Palette.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(PressableCard())
                .disabled(env.health.connecting)

                if let message = env.health.lastError {
                    Text(message)
                        .font(Typography.data(13))
                        .foregroundStyle(Color(hex: 0xFF8A73))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                Palette.ink
                LoopingPhase(period: 3, still: 1) { t in
                    HeartbeatLine()
                        .trim(from: 0, to: t)
                        .stroke(
                            Palette.accent.opacity(0.35),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                        )
                        .offset(x: 48)
                        .padding(.vertical, 28)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .elevation(.floating)
    }

    private var heroDetail: String {
        if env.health.state == .connected && env.health.hasHeartData {
            return "Your heart-rate data is flowing in."
        }
        if env.health.state == .connected {
            return "Access may be off, or there’s no Watch data yet."
        }
        return "Connect to fill in your body stats and read recovery."
    }

    private var lastSyncWhen: String? {
        guard env.health.connected, let at = env.health.lastSyncAt else { return nil }
        return lastSyncLabel(at)
    }

    private func readingRow(symbol: String, title: String, reason: String, when: String?) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 38, height: 38)
                .background(Palette.surfaceSunk, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.data(15, weight: .heavy))
                    .foregroundStyle(Palette.ink)
                Text(reason)
                    .font(Typography.data(12))
                    .foregroundStyle(Palette.inkSoft)
            }
            Spacer(minLength: 8)
            if let when {
                Text(when)
                    .font(Typography.data(12, weight: .bold))
                    .foregroundStyle(Palette.inkFaint)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.inkSoft)
                .padding(.top, 1)
            (
                Text("Raw readings stay on this phone.")
                    .font(Typography.data(13, weight: .bold))
                    .foregroundStyle(Palette.ink)
                + Text(" I only send how far today is from your normal.")
                    .font(Typography.data(13))
                    .foregroundStyle(Palette.inkSoft)
            )
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceSunk.opacity(0.6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func lastSyncLabel(_ date: Date) -> String {
        let time = timeOnly(date)
        if Calendar.current.isDateInToday(date) { return "Today \(time)" }
        let weekday = date.formatted(.dateTime.weekday(.wide))
        return "\(weekday) \(time)"
    }

    private func timeOnly(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func openHealth() {
        if let url = URL(string: "x-apple-health://"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

private struct HeartbeatLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let y = rect.midY
        p.move(to: CGPoint(x: 0, y: y))
        p.addLine(to: CGPoint(x: rect.width * 0.28, y: y))
        p.addLine(to: CGPoint(x: rect.width * 0.36, y: y - rect.height * 0.38))
        p.addLine(to: CGPoint(x: rect.width * 0.46, y: y + rect.height * 0.32))
        p.addLine(to: CGPoint(x: rect.width * 0.54, y: y))
        p.addLine(to: CGPoint(x: rect.width, y: y))
        return p
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
        SettingsScreen(title: "Account") {
            VStack(alignment: .leading, spacing: 20) {
                if !model.enforcementEnabled {
                    ManagerNote(text: enforcementNote(model.enforcementDisabledReason))
                        .appearIn(2)
                }

                identity.appearIn(3)

                SettingsCard(padding: 0) {
                    VStack(spacing: 0) {
                        Button(action: openNotificationSettings) {
                            SettingsRow(symbol: "bell", title: "Notifications", value: notificationsValue)
                        }
                        .buttonStyle(.plain)
                        Divider().overlay(Palette.hairline).padding(.leading, 66)
                        SettingsRow(
                            symbol: "clock",
                            title: "Time zone",
                            value: timezoneValue,
                            showsChevron: false
                        )
                    }
                }
                .appearIn(4)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Legal and support").sectionLabelStyle()
                    SettingsCard(padding: 0) {
                        VStack(spacing: 0) {
                            legalRow("Privacy policy", symbol: "lock", url: privacyURL)
                            Divider().overlay(Palette.hairline).padding(.leading, 66)
                            legalRow("Terms", symbol: "doc.text", url: termsURL)
                            Divider().overlay(Palette.hairline).padding(.leading, 66)
                            legalRow("Contact support", symbol: "envelope", url: supportURL)
                        }
                    }
                }
                .appearIn(5)

                Button(action: env.auth.signOut) {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Sign out")
                    }
                    .font(Typography.data(16, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        Palette.surfaceSunk,
                        in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    )
                }
                .buttonStyle(PressableCard())
                .appearIn(6)

                HStack {
                    Text("SetPoint \(shortVersion)")
                        .font(Typography.data(13))
                        .foregroundStyle(Palette.inkFaint)
                    Spacer()
                    Button { confirmingDelete = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                                .font(.system(size: 15, weight: .semibold))
                            Text("Delete account")
                                .font(Typography.data(14, weight: .bold))
                        }
                        .foregroundStyle(Palette.accentDeep)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.deleting)
                }
                .padding(.horizontal, 4)
                .appearIn(7)

                if let error = model.error {
                    SettingsErrorBanner(message: error)
                }
            }
        }
        .sheet(isPresented: $confirmingDelete) {
            DeleteAccountConfirmation(model: model)
                .presentationDetents([.height(500)])
                .presentationDragIndicator(.visible)
                .presentationBackground(Palette.background)
                .presentationCornerRadius(28)
                .interactiveDismissDisabled(model.deleting)
        }
        .task { await env.push.syncAuthorizationStatus() }
    }

    private var identity: some View {
        SettingsCard(padding: 18) {
            HStack(spacing: 14) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Palette.background)
                    .frame(width: 52, height: 52)
                    .background(Palette.ink, in: Circle())
                Text("Signed in with Apple")
                    .font(Typography.data(17, weight: .heavy))
                    .foregroundStyle(Palette.ink)
            }
        }
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

    private func legalRow(_ title: String, symbol: String, url: URL) -> some View {
        Link(destination: url) {
            SettingsRow(symbol: symbol, title: title)
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
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "trash")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Palette.accentDeep)
                .frame(width: 56, height: 56)
                .background(Palette.accentTint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Text("Delete everything?")
                .font(Typography.display(32))
                .foregroundStyle(Palette.ink)

            Text("This can’t be undone.")
                .font(Typography.data(15))
                .foregroundStyle(Palette.inkSoft)

            VStack(alignment: .leading, spacing: 10) {
                goneRow("Every meal and photo")
                goneRow("Weight history and your plan")
                goneRow("Check-ins and your week record")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surfaceSunk, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Button {
                Task { await model.deleteAccount() }
            } label: {
                Text(model.deleting ? "Deleting…" : "Delete my account")
                    .font(Typography.data(16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Palette.accentDeep, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(model.deleting)

            Button("Keep it") { dismiss() }
                .font(Typography.data(15, weight: .bold))
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity)
                .disabled(model.deleting)
        }
        .padding(Space.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.background)
    }

    private func goneRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Palette.accentDeep)
                .frame(width: 16)
            Text(text)
                .font(Typography.data(15, weight: .semibold))
                .foregroundStyle(Palette.ink)
        }
    }
}
