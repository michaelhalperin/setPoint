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
            StepTitle(label: "Goal", text: "What are you", tail: "training for?")
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

// MARK: - Apple Health

/// Offers Apple Health before anything is typed: it fills height, weight and age,
/// and tells Smart from Basic mode by whether heart data is really there.
struct HealthStep: View {
    @Bindable var model: OnboardingViewModel
    @Environment(AppEnvironment.self) private var env
    @State private var connecting = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Image(systemName: "heart.fill")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(LinearGradient(colors: [Color(hex: 0xFF5E7E), Color(hex: 0xFF2D55)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: Color(hex: 0xFF2D55, opacity: 0.35), radius: 20)
                .appearIn(0, rise: 12)
                .accessibilityHidden(true)

            Headline("Connect", tail: "Apple Health.", size: 40)
                .appearIn(1, rise: 16)

            VStack(spacing: 10) {
                row("ruler", "Height and weight")
                row("waveform.path.ecg", "Heart-rate variability")
                row("heart", "Resting heart rate")
            }
            .appearIn(2, rise: 14)

            HStack(spacing: 8) {
                Image(systemName: "lock").font(.system(size: 12, weight: .medium))
                Text("Read-only. Stays on your phone.")
            }
            .font(Typography.data(13, weight: .regular))
            .foregroundStyle(Palette.inkSoft)
            .appearIn(3)

            VStack(spacing: 4) {
                ActionButton(title: "Connect Health", busy: connecting, busyTitle: "One moment") { connect() }
                    .disabled(!env.health.isAvailable)
                Button("Enter it myself") { model.advance() }
                    .font(Typography.data(14, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .disabled(connecting)
            }
            .padding(.top, Space.sm)
            .appearIn(4, rise: 14)
        }
    }

    private func row(_ symbol: String, _ title: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Palette.amber)
                .frame(width: 36, height: 36)
                .background(Palette.amber.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(LocalizedStringKey(title))
                .font(Typography.data(16, weight: .regular))
                .foregroundStyle(Palette.ink)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .frame(height: 60)
        .glass(radius: 18)
    }

    private func connect() {
        guard !connecting else { return }
        connecting = true
        Task {
            let state = await env.health.connect()
            if state == .connected {
                let profile = await env.health.readProfile()
                model.draft.apply(profile)
                model.draft.hasWearable = env.health.hasHeartData
                if profile != HealthProfile() { Haptics.landed() }
            }
            connecting = false
            model.advance()
        }
    }
}

// MARK: - About you

struct AboutStep: View {
    @Bindable var model: OnboardingViewModel
    @Environment(AppEnvironment.self) private var env
    @AppStorage(MassUnit.storageKey) private var massUnit = MassUnit.localeDefault

    @State private var editingBirthday = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            StepTitle(label: "About you", text: "About", tail: "you.")

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

    private var latestBirthDate: Date {
        Calendar.current.date(byAdding: .year, value: -OnboardingDraft.minimumAge, to: .now) ?? .now
    }
}

// MARK: - Target

/// Target weight, pace and timeframe — shown on the goal screen for a gain or
/// a cut. Maintain has no target.
struct TargetCard: View {
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

struct TargetStep: View {
    @Bindable var model: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            StepTitle(label: "Target", text: "What’s your", tail: "target?")
            TargetCard(model: model)
                .id(model.draft.goal)
                .appearIn(1, rise: 14)
        }
    }
}

// MARK: - Appetite

struct AppetiteStep: View {
    @Bindable var model: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            StepTitle(label: "Appetite", text: "How hungry are you,", tail: "most days?", size: 32)
            VStack(spacing: 10) {
                ForEach(Array(AppetiteChoice.allCases.enumerated()), id: \.element) { index, choice in
                    OptionRow(title: choice.title, selected: model.draft.appetite == choice) {
                        withAnimation(Motion.settle) { model.draft.appetite = choice }
                    }
                    .appearIn(1 + index, rise: 14)
                }
            }
        }
    }
}

// MARK: - Training

struct TrainingStep: View {
    @Bindable var model: OnboardingViewModel

    private let options: [(level: ActivityLevel, title: String)] = [
        (.light, "1–3 days"),
        (.moderate, "4–5 days"),
        (.active, "6–7 days"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            StepTitle(label: "Training", text: "How often do", tail: "you train?")
            VStack(spacing: 10) {
                ForEach(Array(options.enumerated()), id: \.element.level) { index, option in
                    OptionRow(title: option.title, selected: model.draft.activityLevel == option.level) {
                        withAnimation(Motion.settle) { model.draft.activityLevel = option.level }
                    }
                    .appearIn(1 + index, rise: 14)
                }
            }
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
            StepTitle(label: "Meal times", text: "When do you", tail: "eat?")

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
            StepTitle(label: "Foods", text: "Anything off", tail: "the menu?")

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
