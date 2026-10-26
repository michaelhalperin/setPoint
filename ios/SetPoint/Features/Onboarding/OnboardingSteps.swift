import SwiftUI
import UIKit

// Setup, one decision per screen: about you, goal (with its target), meal
// times, foods.
// Safety lives in OnboardingSafety.swift; the payoff in OnboardingFinish.swift.

// MARK: - Goal

struct GoalStep: View {
    @Bindable var model: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            StepTitle(label: "Goal", text: "What are we building?", tail: "Pick one.")
            VStack(spacing: 10) {
                ForEach(Array(Goal.allCases.enumerated()), id: \.element) { index, goal in
                    OptionRow(
                        title: goal.title,
                        detail: goal.tagline,
                        symbol: Self.symbol(goal),
                        selected: model.draft.goal == goal
                    ) { choose(goal) }
                    .appearIn(1 + index, rise: 14)
                }
            }
            // Gain or cut: the target slides in under the choice.
            if model.draft.goal?.hasWeightTarget == true {
                TargetCard(model: model)
                    .id(model.draft.goal)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(Motion.settle, value: model.draft.goal)
    }

    static func symbol(_ goal: Goal) -> String {
        switch goal {
        case .bulk: return "arrow.up.right"
        case .diet: return "arrow.down.right"
        case .maintain: return "equal"
        }
    }

    private func choose(_ goal: Goal) {
        withAnimation(Motion.settle) {
            if model.draft.goal != goal {
                model.draft.preferredDurationWeeks = nil
                model.draft.targetWeightKg = nil
            }
            model.draft.goal = goal
        }
    }
}

// MARK: - About you

struct AboutStep: View {
    @Bindable var model: OnboardingViewModel
    @Environment(AppEnvironment.self) private var env
    @AppStorage(MassUnit.storageKey) private var massUnit = MassUnit.localeDefault

    enum HealthFill: Equatable { case idle, reading, filled, empty }

    @State private var health: HealthFill = .idle
    @State private var editingBirthday = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            StepTitle(label: "About you", text: "A bit about you.", tail: "It sets your numbers.")

            if env.health.isAvailable {
                healthRow.appearIn(1, rise: 14)
            }

            GlassList {
                StepperRow(
                    name: "Height",
                    value: model.draft.heightCm.map { L10n("\(Int($0.rounded())) cm") } ?? "—",
                    valueWidth: 76,
                    onDown: { nudgeHeight(-1) },
                    onUp: { nudgeHeight(1) }
                )
                ListDivider()
                StepperRow(
                    name: "Weight",
                    value: model.draft.weightKg.map { "\(massUnit.number($0)) \(massUnit.abbreviation)" } ?? "—",
                    valueWidth: 76,
                    onDown: { nudgeWeight(-1) },
                    onUp: { nudgeWeight(1) }
                )
                ListDivider()
                Button { editingBirthday = true } label: {
                    HStack {
                        Text("Age")
                            .font(Typography.data(15, weight: .regular))
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Text("\(model.draft.age) yrs")
                            .font(Typography.mono(16))
                            .foregroundStyle(Palette.ink)
                        Image(systemName: "chevron.forward")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x52525B))
                    }
                    .padding(.vertical, 18)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                ListDivider()
                StepperRow(
                    name: "Activity",
                    note: model.draft.activityLevel.blurb,
                    value: model.draft.activityLevel.title,
                    valueWidth: 86,
                    canDown: model.draft.activityLevel != ActivityLevel.allCases.first,
                    canUp: model.draft.activityLevel != ActivityLevel.allCases.last,
                    onDown: { stepActivity(-1) },
                    onUp: { stepActivity(1) }
                )
            }
            .appearIn(2, rise: 14)

            VStack(alignment: .leading, spacing: 8) {
                Text("Sex").sectionLabelStyle()
                SegmentedPills(
                    options: [Sex.male, .female, .unspecified],
                    selection: $model.draft.sex,
                    title: { $0 == .unspecified ? "Skip" : $0.title }
                )
            }
            .appearIn(3, rise: 14)

            if !model.draft.isOldEnough {
                Text("SetPoint is for people \(OnboardingDraft.minimumAge) or older.")
                    .font(Typography.data(13, weight: .regular))
                    .foregroundStyle(Palette.danger)
            }
        }
        .animation(Motion.settle, value: health)
        .sheet(isPresented: $editingBirthday) {
            VStack(spacing: Space.md) {
                Text("Birthday").sectionLabelStyle()
                DatePicker("", selection: $model.draft.birthDate, in: ...latestBirthDate, displayedComponents: .date)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                ActionButton(title: "Done") { editingBirthday = false }
            }
            .padding(Space.gutter)
            .presentationDetents([.height(380)])
            .presentationDragIndicator(.visible)
            .presentationBackground(Palette.sheet)
            .presentationCornerRadius(32)
        }
    }

    // MARK: Apple Health

    private var healthRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "heart.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color(hex: 0xFF3B5C))
                .frame(width: 44, height: 44)
                .background(Palette.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("Apple Health")
                    .font(Typography.data(15, weight: .medium))
                    .foregroundStyle(Palette.ink)
                Text(healthDetail)
                    .font(Typography.data(13, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
            }
            Spacer(minLength: 8)
            Button(action: fillFromHealth) {
                Group {
                    if health == .reading {
                        BusyDots(tint: Palette.onBone)
                    } else {
                        Text(health == .filled ? "Filled" : "Fill in")
                    }
                }
                .font(Typography.data(13, weight: .medium))
                .foregroundStyle(health == .filled ? Palette.ink : Palette.onBone)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(Capsule().fill(health == .filled ? Color.white.opacity(0.08) : Palette.ink))
            }
            .buttonStyle(PressableCard())
            .disabled(health == .reading || health == .filled)
        }
        .padding(16)
        .glass(radius: 22)
    }

    private var healthDetail: String {
        switch health {
        case .idle, .reading: return L10n( "Height, weight and age in one tap")
        case .filled: return L10n( "Check the numbers below")
        case .empty: return L10n( "Nothing there yet — set them below")
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

    // MARK: Steppers

    private func nudgeHeight(_ delta: Double) {
        withAnimation(Motion.settle) {
            let current = model.draft.heightCm ?? 170
            model.draft.heightCm = model.draft.heightCm == nil ? current : min(230, max(120, current + delta))
        }
    }

    private func nudgeWeight(_ delta: Double) {
        withAnimation(Motion.settle) {
            let current = model.draft.weightKg ?? 70
            model.draft.weightKg = model.draft.weightKg == nil ? current : min(250, max(35, massUnit.nudge(kg: current, by: delta)))
        }
    }

    private func stepActivity(_ delta: Int) {
        let all = ActivityLevel.allCases
        guard let index = all.firstIndex(of: model.draft.activityLevel) else { return }
        let next = min(all.count - 1, max(0, index + delta))
        withAnimation(Motion.settle) { model.draft.activityLevel = all[next] }
    }

    private var latestBirthDate: Date {
        Calendar.current.date(byAdding: .year, value: -OnboardingDraft.minimumAge, to: .now) ?? .now
    }
}

// MARK: - Target

/// Target weight, pace and timeframe — shown on the goal screen for a gain or
/// a cut. Maintain has no target.
private struct TargetCard: View {
    @Bindable var model: OnboardingViewModel
    @AppStorage(MassUnit.storageKey) private var massUnit = MassUnit.localeDefault

    private var goal: Goal { model.draft.goal ?? .bulk }
    private var target: Double { model.draft.targetWeightKg ?? (model.draft.weightKg ?? 70) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Target weight").sectionLabelStyle()
                    Spacer()
                    if let weight = model.draft.weightKg {
                        Text("from \(massUnit.number(weight)) \(massUnit.abbreviation)")
                            .font(Typography.mono(12))
                            .foregroundStyle(Palette.inkSoft)
                    }
                }
                HStack {
                    StepCircle(symbol: "minus", label: "Lower target", size: 48) { nudge(-1) }
                    Spacer()
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(massUnit.number(target))
                            .font(Typography.data(44, weight: .light))
                            .tracking(-1.3)
                            .foregroundStyle(Palette.ink)
                            .contentTransition(.numericText(value: target))
                        Text(massUnit.abbreviation)
                            .font(Typography.data(16, weight: .regular))
                            .foregroundStyle(Palette.inkSoft)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Target \(massUnit.number(target, digits: 0 ... 0)) \(massUnit.spokenName)")
                    Spacer()
                    StepCircle(symbol: "plus", label: "Raise target", size: 48) { nudge(1) }
                }

                if model.targetWeightMessage == nil {
                    SegmentedPills(
                        options: GoalPace.allCases,
                        selection: Binding(
                            get: { model.draft.pace },
                            set: { model.applyPaceShortcut($0) }
                        ),
                        title: { $0.title },
                        detail: { $0.blurb(for: goal) }
                    )
                }

                Text(paceLine)
                    .font(Typography.data(13, weight: .regular))
                    .foregroundStyle(model.targetWeightMessage == nil && model.durationMessage == nil ? Palette.inkSoft : Palette.amber)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
            }
            .padding(16)
            .glass(radius: 22)

            if model.targetWeightMessage == nil {
                GlassList {
                    StepperRow(
                        name: "Timeframe",
                        note: timeframeStepperNote,
                        value: L10n("\(weeks) wk"),
                        canDown: weeks > 1,
                        onDown: { model.setDurationWeeks(weeks - 1) },
                        onUp: { model.setDurationWeeks(weeks + 1) }
                    )
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

    private var weeks: Int { model.draft.preferredDurationWeeks ?? model.etaWeeks ?? 12 }

    private var remainingKg: Double {
        WeightPace.remainingKg(goal: goal, currentKg: model.draft.weightKg ?? target, targetKg: target)
    }

    private var timeframeStepperNote: String {
        if model.durationMessage != nil { return L10n("I'll hold a safe pace") }
        guard remainingKg > 0, weeks > 0 else { return L10n("Shorter isn’t always safe") }
        let rate = remainingKg / Double(weeks)
        return L10n("\(massUnit.number(rate, digits: 2 ... 2)) \(massUnit.abbreviation)/wk")
    }

    private var paceLine: String {
        if let message = model.targetWeightMessage { return message }
        if let message = model.durationMessage { return message }
        guard remainingKg > 0, weeks > 0 else { return " " }
        let rate = remainingKg / Double(weeks)
        return L10n("About \(weeks) weeks at \(massUnit.formatKg(rate, digits: 2))/wk.")
    }

    private func nudge(_ delta: Double) {
        withAnimation(Motion.settle) {
            model.draft.targetWeightKg = min(350, max(25, massUnit.nudge(kg: target, by: delta)))
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

// MARK: - Meal times

/// Breakfast, lunch and dinner as ± rows (15-minute steps), each with the time
/// its check-in would come. Quiet hours follow the times.
struct RhythmStep: View {
    @Bindable var model: OnboardingViewModel

    var body: some View {
        let d = model.draft
        VStack(alignment: .leading, spacing: Space.md) {
            StepTitle(label: "Meal times", text: "When do you eat?", tail: "I watch these times.")

            GlassList {
                row("Breakfast", d.breakfastMin, range: 300 ... d.lunchMin - 60) { model.draft.breakfastMin = $0 }
                ListDivider()
                row("Lunch", d.lunchMin, range: d.breakfastMin + 60 ... d.dinnerMin - 60) { model.draft.lunchMin = $0 }
                ListDivider()
                row("Dinner", d.dinnerMin, range: d.lunchMin + 60 ... 1380) { model.draft.dinnerMin = $0 }
            }
            .appearIn(1, rise: 14)

            HStack(spacing: 12) {
                Image(systemName: "moon")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Palette.hazeSoft)
                    .frame(width: 36, height: 36)
                    .background(Palette.haze.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Quiet hours")
                        .font(Typography.data(15, weight: .regular))
                        .foregroundStyle(Palette.ink)
                    Text("Never between \(formatMinutes(d.quietStartMin)) and \(formatMinutes(d.quietEndMin))")
                        .font(Typography.data(12, weight: .regular))
                        .foregroundStyle(Palette.inkSoft)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .glass(radius: 20)
            .appearIn(2, rise: 14)
        }
    }

    private func row(_ name: String, _ minute: Int, range: ClosedRange<Int>, set: @escaping (Int) -> Void) -> some View {
        StepperRow(
            name: name,
            note: "check-in \(formatMinutes(CheckInSchedule.minute(afterMeal: minute)))",
            value: formatMinutes(minute),
            canDown: minute - 15 >= range.lowerBound,
            canUp: minute + 15 <= range.upperBound,
            onDown: { change(minute - 15, set) },
            onUp: { change(minute + 15, set) }
        )
    }

    private func change(_ minute: Int, _ set: (Int) -> Void) {
        withAnimation(Motion.settle) {
            set(minute)
            let d = model.draft
            model.draft.mealRhythmPreset = MealRhythmPreset.closest(breakfast: d.breakfastMin, lunch: d.lunchMin, dinner: d.dinnerMin)
            model.draft.applyDerivedQuietHours()
        }
    }
}

// MARK: - Foods

struct RestrictionsStep: View {
    @Bindable var model: OnboardingViewModel

    private let common = ["Dairy", "Eggs", "Gluten", "Peanuts", "Tree nuts", "Soy", "Fish", "Shellfish", "Sesame", "Pork", "Beef", "Vegetarian", "Vegan"]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            StepTitle(label: "Foods", text: "Anything I should never suggest?", tail: "Hard rule.", size: 32)

            FlowChips(options: common, selected: $model.draft.restrictions)
                .appearIn(1, rise: 14)

            VStack(alignment: .leading, spacing: 8) {
                Text("Something else").sectionLabelStyle()
                GlassField(prompt: "Type it — I’ll skip it too", text: $model.draft.restrictionsFreeText)
                    .submitLabel(.done)
                Text("Top-ups and the evening close never use these.")
                    .font(Typography.data(13, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
            }
            .appearIn(2, rise: 14)
        }
    }
}
