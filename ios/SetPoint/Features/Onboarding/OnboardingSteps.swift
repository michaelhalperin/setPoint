import SwiftUI
import UIKit

// Setup, one decision per screen: goal, about you, target, rhythm, restrictions.
// Safety lives in OnboardingSafety.swift; the payoff in OnboardingFinish.swift.

// MARK: - Goal

struct GoalStep: View {
    @Bindable var model: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            StepHeadline(text: "What’s the goal?")
            VStack(spacing: 14) {
                ForEach(Array(Goal.allCases.enumerated()), id: \.element) { index, goal in
                    GoalTile(goal: goal, selected: model.draft.goal == goal) { choose(goal) }
                        .appearIn(1 + index)
                }
            }
        }
    }

    private func choose(_ goal: Goal) {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(Motion.settle) {
            if model.draft.goal != goal {
                model.draft.preferredDurationWeeks = nil
            }
            model.draft.goal = goal
        }
        model.autoAdvance(from: .goal, after: 0.55)
    }
}

private struct GoalTile: View {
    let goal: Goal
    let selected: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: CGFloat = 1

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                GoalSparkline(goal: goal)
                    .trim(from: 0, to: drawn)
                    .stroke(selected ? Palette.accent : Palette.inkSoft,
                            style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .frame(width: 72, height: 50)
                    .frame(width: 100, height: 80)
                    .background(selected ? Palette.accentTint : Palette.surfaceSunk,
                                in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(goal.title)
                        .font(Typography.data(23, weight: .bold))
                        .foregroundStyle(Palette.ink)
                    Text(goal.tagline)
                        .font(Typography.data(15))
                        .foregroundStyle(Palette.inkSoft)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.md)
            .frame(height: 132)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(selected ? Palette.surfaceRaised : Palette.surface)
                    .elevation(selected ? .floating : .resting)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(selected ? Palette.accent : Palette.hairline, lineWidth: selected ? 2 : 1)
                    )
            }
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Palette.accent, in: Circle())
                        .padding(16)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .scaleEffect(selected ? 1 : 0.985)
        }
        .buttonStyle(PressableCard())
        .accessibilityLabel("\(goal.title): \(goal.tagline)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .onChange(of: selected) { _, isSelected in
            guard isSelected, !reduceMotion else { return }
            drawn = 0
            withAnimation(.easeOut(duration: 0.9)) { drawn = 1 }
        }
    }
}

// MARK: - About you

struct AboutStep: View {
    @Bindable var model: OnboardingViewModel
    @Environment(AppEnvironment.self) private var env

    enum Field: String, Identifiable {
        case height, weight, age, activity
        var id: String { rawValue }
    }

    enum HealthFill: Equatable { case idle, reading, filled, empty }

    @State private var editing: Field?
    @State private var health: HealthFill = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            StepHeadline(text: "A bit about you.")

            if env.health.isAvailable {
                healthButton.appearIn(1)
                HStack(spacing: Space.sm) {
                    Rectangle().fill(Palette.inkFaint.opacity(0.35)).frame(height: 1)
                    Text("or set it")
                        .font(Typography.data(12, weight: .semibold))
                        .foregroundStyle(Palette.inkFaint)
                        .fixedSize()
                    Rectangle().fill(Palette.inkFaint.opacity(0.35)).frame(height: 1)
                }
                .appearIn(2)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                statTile("Height", value: model.draft.heightCm.map { "\(Int($0.rounded()))" }, unit: "cm") { editing = .height }
                statTile("Weight", value: model.draft.weightKg.map { $0.formatted(.number.precision(.fractionLength(0 ... 1))) }, unit: "kg") { editing = .weight }
                statTile("Age", value: "\(model.draft.age)", unit: "yrs") { editing = .age }
                sexTile
            }
            .appearIn(3)

            if !model.draft.isOldEnough {
                Text("SetPoint is for people \(OnboardingDraft.minimumAge) or older.")
                    .font(Typography.data(14, weight: .semibold))
                    .foregroundStyle(Palette.accentDeep)
            }

            activityTile
                .appearIn(4)
        }
        .animation(Motion.settle, value: health)
        .sheet(item: $editing) { field in
            editor(for: field)
                .presentationDragIndicator(.visible)
                .presentationBackground(Palette.background)
                .presentationCornerRadius(28)
        }
    }

    // MARK: Apple Health

    private var healthButton: some View {
        Button(action: fillFromHealth) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Palette.background.opacity(0.12))
                    if health == .reading {
                        ProgressView().tint(Palette.background)
                    } else {
                        Image(systemName: health == .filled ? "checkmark" : "heart.fill")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(health == .filled ? Palette.background : Color(hex: 0xFF8A73))
                    }
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 2) {
                    Text(healthTitle)
                        .font(Typography.data(17, weight: .bold))
                        .foregroundStyle(Palette.background)
                    Text(healthDetail)
                        .font(Typography.data(13))
                        .foregroundStyle(Palette.background.opacity(0.65))
                }
                Spacer(minLength: 0)
                if health == .idle {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.background)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(Palette.ink, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .elevation(.floating)
        }
        .buttonStyle(PressableCard())
        .disabled(health == .reading)
    }

    private var healthTitle: String {
        switch health {
        case .idle: return "Fill from Apple Health"
        case .reading: return "Reading Health…"
        case .filled: return "Filled from Health"
        case .empty: return "Nothing in Health yet"
        }
    }

    private var healthDetail: String {
        switch health {
        case .idle, .reading: return "Height, weight and age in one tap."
        case .filled: return "Check the numbers below."
        case .empty: return "Set them below instead."
        }
    }

    /// Connect Health, prefill what it knows, and let the heart-rate probe pick
    /// Smart vs Basic mode from a real device rather than a toggle (§1).
    private func fillFromHealth() {
        health = .reading
        Task {
            let state = await env.health.connect()
            guard state == .connected else {
                health = .idle
                return
            }
            let profile = await env.health.readProfile()
            withAnimation(Motion.settle) { model.draft.apply(profile) }
            model.draft.hasWearable = env.health.hasHeartData
            health = profile == HealthProfile() ? .empty : .filled
            if health == .filled { Haptics.landed() }
        }
    }

    // MARK: Tiles

    private func statTile(_ label: String, value: String?, unit: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(label).sectionLabelStyle()
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(value ?? "—")
                        .font(Typography.data(30, weight: .bold))
                        .foregroundStyle(value == nil ? Palette.inkFaint : Palette.ink)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    if value != nil {
                        Text(unit)
                            .font(Typography.data(15, weight: .medium))
                            .foregroundStyle(Palette.inkFaint)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .modifier(TileBackground())
        }
        .buttonStyle(PressableCard())
        .accessibilityLabel("\(label), \(value.map { "\($0) \(unit)" } ?? "not set")")
    }

    private var sexTile: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sex").sectionLabelStyle()
            HStack(spacing: 6) {
                sexChip("M", .male)
                sexChip("F", .female)
                sexChip("–", .unspecified)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .modifier(TileBackground())
    }

    private func sexChip(_ label: String, _ sex: Sex) -> some View {
        let on = model.draft.sex == sex
        return Button {
            withAnimation(Motion.settle) { model.draft.sex = sex }
        } label: {
            Text(label)
                .font(Typography.data(15, weight: .bold))
                .foregroundStyle(on ? Palette.background : Palette.ink)
                .frame(width: 34, height: 34)
                .background(on ? Palette.ink : Palette.surfaceSunk, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(sex.title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var activityTile: some View {
        let level = ActivityLevel.allCases.firstIndex(of: model.draft.activityLevel) ?? 2
        return Button { editing = .activity } label: {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Activity").sectionLabelStyle()
                    Text(model.draft.activityLevel.title)
                        .font(Typography.data(22, weight: .bold))
                        .foregroundStyle(Palette.ink)
                }
                Spacer()
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(0 ..< ActivityLevel.allCases.count, id: \.self) { bar in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(bar <= level ? Palette.accent : Palette.surfaceSunk)
                            .frame(width: 8, height: CGFloat(10 + bar * 6))
                    }
                }
                .animation(Motion.settle, value: level)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .modifier(TileBackground())
        }
        .buttonStyle(PressableCard())
        .accessibilityLabel("Activity, \(model.draft.activityLevel.title)")
    }

    // MARK: Editors

    @ViewBuilder
    private func editor(for field: Field) -> some View {
        switch field {
        case .height:
            rulerSheet("Height", value: optionalBinding(\.heightCm, default: 170), range: 120 ... 230, unit: "cm")
        case .weight:
            rulerSheet("Weight", value: optionalBinding(\.weightKg, default: 70), range: 35 ... 250, unit: "kg")
        case .age:
            VStack(spacing: Space.md) {
                Text("Birthday").sectionLabelStyle()
                DatePicker("", selection: $model.draft.birthDate, in: ...latestBirthDate, displayedComponents: .date)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                ActionButton(title: "Done") { editing = nil }
            }
            .padding(Space.gutter)
            .presentationDetents([.height(380)])
        case .activity:
            VStack(alignment: .leading, spacing: Space.sm) {
                Text("How active is a typical week?")
                    .font(Typography.display(26))
                    .foregroundStyle(Palette.ink)
                    .padding(.bottom, 4)
                ForEach(ActivityLevel.allCases) { level in
                    ChoiceCard(title: level.title, blurb: level.blurb, selected: model.draft.activityLevel == level) {
                        withAnimation(Motion.settle) { model.draft.activityLevel = level }
                        editing = nil
                    }
                }
            }
            .padding(Space.gutter)
            .padding(.top, Space.xs)
            .presentationDetents([.large])
        }
    }

    private func rulerSheet(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String) -> some View {
        VStack(spacing: Space.md) {
            Text(title).sectionLabelStyle()
            RulerPicker(value: value, range: range, unit: unit)
            ActionButton(title: "Done") { editing = nil }
        }
        .padding(Space.gutter)
        .presentationDetents([.height(320)])
        .onAppear { value.wrappedValue = value.wrappedValue } // commit the default if unset
    }

    private func optionalBinding(_ keyPath: WritableKeyPath<OnboardingDraft, Double?>, default fallback: Double) -> Binding<Double> {
        Binding(
            get: { model.draft[keyPath: keyPath] ?? fallback },
            set: { model.draft[keyPath: keyPath] = $0 }
        )
    }

    private var latestBirthDate: Date {
        Calendar.current.date(byAdding: .year, value: -OnboardingDraft.minimumAge, to: .now) ?? .now
    }
}

private struct TileBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Palette.surface)
                .elevation(.resting)
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.hairline))
        }
    }
}

// MARK: - Target

/// Target weight + pace. Skipped for Maintain.
struct TargetStep: View {
    @Bindable var model: OnboardingViewModel

    private var goal: Goal { model.draft.goal ?? .bulk }
    private var target: Double { model.draft.targetWeightKg ?? (model.draft.weightKg ?? 70) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            StepHeadline(text: "Where to?")

            TargetCurve(falling: goal == .diet, startLabel: startLabel)
                .frame(height: 180)
                .appearIn(1)

            HStack {
                stepperButton("minus", delta: -1)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(target.formatted(.number.precision(.fractionLength(0 ... 1))))
                        .font(Typography.data(80, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: target))
                        .foregroundStyle(Palette.ink)
                    Text("kg")
                        .font(Typography.data(22, weight: .semibold))
                        .foregroundStyle(Palette.inkFaint)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Target \(Int(target.rounded())) kilograms")
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
            .appearIn(2)

            if let message = model.targetWeightMessage {
                Text(message)
                    .font(Typography.data(13, weight: .semibold))
                    .foregroundStyle(Palette.accentDeep)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }

            if model.targetWeightMessage == nil {
                Text("How long?")
                    .font(Typography.data(13, weight: .semibold))
                    .foregroundStyle(Palette.inkFaint)
                    .frame(maxWidth: .infinity)
                    .appearIn(3)

                WeeksStepper(
                    weeks: Binding(
                        get: { model.draft.preferredDurationWeeks ?? model.etaWeeks ?? 12 },
                        set: { model.setDurationWeeks($0) }
                    ),
                    large: true
                )
                .appearIn(3)

                SegmentedPills(
                    options: GoalPace.allCases,
                    selection: Binding(
                        get: { model.draft.pace },
                        set: { model.applyPaceShortcut($0) }
                    ),
                    title: { $0.title },
                    detail: { $0.blurb(for: goal) }
                )
                .appearIn(4)

                if let message = model.durationMessage {
                    Text(message)
                        .font(Typography.data(13, weight: .semibold))
                        .foregroundStyle(Palette.accentDeep)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }
            }
        }
        .animation(Motion.settle, value: model.targetWeightMessage)
        .animation(Motion.settle, value: model.etaWeeks)
        .animation(Motion.settle, value: model.durationMessage)
        .onAppear {
            proposeTargetIfNeeded()
            model.proposeDurationIfNeeded()
        }
    }

    private var startLabel: String {
        let weight = (model.draft.weightKg ?? 0).formatted(.number.precision(.fractionLength(0 ... 1)))
        return "\(weight) kg · now"
    }

    private func stepperButton(_ symbol: String, delta: Double) -> some View {
        Button { nudge(delta) } label: {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 56, height: 56)
                .background(Palette.surfaceSunk, in: Circle())
        }
        .buttonStyle(PressableCard())
        .accessibilityLabel(delta > 0 ? "Increase target" : "Decrease target")
    }

    private func nudge(_ delta: Double) {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(Motion.settle) {
            model.draft.targetWeightKg = min(350, max(25, (target + delta).rounded()))
        }
    }

    private func proposeTargetIfNeeded() {
        guard model.draft.targetWeightKg == nil, let weight = model.draft.weightKg else { return }
        switch goal {
        case .bulk: model.draft.targetWeightKg = (weight + 4).rounded()
        case .diet:
            let floor = model.draft.heightCm.map { HealthyWeight.minKg(heightCm: $0) } ?? 0
            model.draft.targetWeightKg = max((weight - 5).rounded(), floor.rounded(.up))
        case .maintain: break
        }
    }
}

// MARK: - Rhythm

/// Meal times on the day dial. A preset sets all three (and derived quiet hours)
/// in one tap; Custom opens the time pickers.
struct RhythmStep: View {
    @Bindable var model: OnboardingViewModel
    @State private var editingCustom = false

    var body: some View {
        let d = model.draft
        VStack(alignment: .leading, spacing: Space.md) {
            StepHeadline(text: "When do you eat?")

            DayDial(
                breakfastMin: d.breakfastMin, lunchMin: d.lunchMin, dinnerMin: d.dinnerMin,
                quietStartMin: d.quietStartMin, quietEndMin: d.quietEndMin
            ) {
                VStack(spacing: 2) {
                    Text(d.mealRhythmPreset == .custom ? "Your times" : d.mealRhythmPreset.title)
                        .font(Typography.voice(24))
                        .foregroundStyle(Palette.ink)
                    Text([d.breakfastMin, d.lunchMin, d.dinnerMin].map(hourLabel).joined(separator: " · "))
                        .font(Typography.data(13, weight: .semibold))
                        .foregroundStyle(Palette.inkSoft)
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: 340)
            .frame(maxWidth: .infinity)
            .animation(Motion.settle, value: [d.breakfastMin, d.lunchMin, d.dinnerMin])
            .appearIn(1)

            SegmentedPills(
                options: [MealRhythmPreset.early, .standard, .night],
                selection: Binding(
                    get: { model.draft.mealRhythmPreset },
                    set: { preset in withAnimation(Motion.settle) { model.draft.applyPreset(preset) } }
                ),
                title: { $0.shortTitle }
            )
            .appearIn(2)

            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .frame(width: 26, height: 26)
                        .background(Palette.accentTint, in: Circle())
                    Text("I check in if a meal doesn’t show")
                        .font(Typography.data(14, weight: .semibold))
                        .foregroundStyle(Palette.inkSoft)
                }
                Spacer(minLength: 8)
                Button("Custom") { editingCustom = true }
                    .font(Typography.data(14, weight: .bold))
                    .foregroundStyle(d.mealRhythmPreset == .custom ? Palette.accent : Palette.ink)
            }
            .appearIn(3)
        }
        .sheet(isPresented: $editingCustom) {
            CustomTimesSheet(model: model)
                .presentationDetents([.height(400)])
                .presentationDragIndicator(.visible)
                .presentationBackground(Palette.background)
                .presentationCornerRadius(28)
        }
    }

    private func hourLabel(_ minutes: Int) -> String {
        minutes % 60 == 0 ? "\(minutes / 60)" : String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
}

private struct CustomTimesSheet: View {
    @Bindable var model: OnboardingViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var breakfast = 480
    @State private var lunch = 780
    @State private var dinner = 1140

    private var valid: Bool { breakfast < lunch && lunch < dinner }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text("Your meal times")
                .font(Typography.display(26))
                .foregroundStyle(Palette.ink)
            VStack(spacing: Space.xxs) {
                MinutesField(label: "Breakfast", minutes: $breakfast)
                Divider().overlay(Palette.hairline)
                MinutesField(label: "Lunch", minutes: $lunch)
                Divider().overlay(Palette.hairline)
                MinutesField(label: "Dinner", minutes: $dinner)
            }
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(Palette.surface).elevation(.resting)
            }
            Text(valid ? "Quiet hours follow these times." : "Use morning-to-evening order.")
                .font(Typography.data(13, weight: .medium))
                .foregroundStyle(valid ? Palette.inkFaint : Palette.accentDeep)
            ActionButton(title: "Use these times") {
                withAnimation(Motion.settle) {
                    model.draft.breakfastMin = breakfast
                    model.draft.lunchMin = lunch
                    model.draft.dinnerMin = dinner
                    model.draft.mealRhythmPreset = MealRhythmPreset.closest(breakfast: breakfast, lunch: lunch, dinner: dinner)
                    model.draft.applyDerivedQuietHours()
                }
                dismiss()
            }
            .opacity(valid ? 1 : 0.4)
            .allowsHitTesting(valid)
        }
        .padding(Space.gutter)
        .padding(.top, Space.xs)
        .onAppear {
            breakfast = model.draft.breakfastMin
            lunch = model.draft.lunchMin
            dinner = model.draft.dinnerMin
        }
    }
}

// MARK: - Restrictions

struct RestrictionsStep: View {
    @Bindable var model: OnboardingViewModel

    private let common = ["Dairy", "Eggs", "Gluten", "Peanuts", "Tree nuts", "Soy", "Fish", "Shellfish", "Sesame", "Pork", "Beef", "Vegetarian", "Vegan"]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            StepHeadline(text: "Anything off the menu?", detail: "I’ll never suggest it — including anything you type below.")

            FlowChips(options: common, selected: $model.draft.restrictions)
                .appearIn(2)

            TextField("Something else", text: $model.draft.restrictionsFreeText)
                .font(Typography.data(16, weight: .medium))
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(Palette.surfaceSunk, in: Capsule())
                .submitLabel(.done)
                .appearIn(3)
        }
    }
}
