import SwiftUI

// MARK: - The sell (no inputs, no progress thread)

/// Beat 1 — the hook, alone. No card, no list, nothing to read but one line.
struct HookStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Spacer(minLength: Space.xl)

            Text("SetPoint")
                .font(Typography.data(13, weight: .semibold))
                .tracking(2)
                .textCase(.uppercase)
                .foregroundStyle(Palette.inkFaint)
                .appearIn(0)

            Text("Eat enough. I'll make sure of it.")
                .font(Typography.display(34))
                .foregroundStyle(Palette.ink)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .appearIn(1)

            Text("Most apps just track. This one follows up.")
                .font(Typography.data(16))
                .foregroundStyle(Palette.inkSoft)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .appearIn(2)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Beat 2 — show, don't tell. A real check-in preview, its own uncrowded
/// screen, so it lands as a moment rather than competing with headline text.
struct DemoStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Spacer(minLength: Space.lg)

            Text("Here's what that looks like.")
                .font(Typography.display(28))
                .foregroundStyle(Palette.ink)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .appearIn(0)

            Text("Fall behind your rhythm, and I'll say something — with a specific fix, not a nag.")
                .font(Typography.data(15))
                .foregroundStyle(Palette.inkSoft)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .appearIn(1)

            VStack(alignment: .leading, spacing: Space.xs) {
                CheckInContent(checkIn: previewCheckIn, restingElevation: .floating)
                    .allowsHitTesting(false)
                Text("A preview — there's nothing to answer here.")
                    .font(Typography.data(11))
                    .foregroundStyle(Palette.inkFaint)
            }
            .appearIn(2)

            Text("Ignore it and I get firmer, then we just talk it through. No streaks, no punishment — just food, on time.")
                .font(Typography.data(13))
                .foregroundStyle(Palette.inkSoft)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .appearIn(3)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Sample data only — never sent anywhere, just what a real check-in looks like.
    private var previewCheckIn: HomeResponse.ActiveCheckIn {
        .init(
            id: "onboarding_preview",
            tier: 2,
            status: "PENDING",
            message: "You're 5 hours past your usual lunch. Let's get food in now.",
            deferUntil: nil,
            prescription: .init(
                id: "onboarding_preview_rx",
                totalKcal: 480,
                totalProteinG: 32,
                items: [
                    .init(name: "2 eggs", quantity: 1, kcal: 150, proteinG: 12),
                    .init(name: "Toast", quantity: 2, kcal: 330, proteinG: 20),
                ]
            )
        )
    }
}

// MARK: - Setup (one decision per screen)

/// Beat 3 — intent, before any numbers. Tapping a card commits and moves on.
struct GoalStep: View {
    @Bindable var model: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            ManagerLine(line: "Choose your goal.", aside: "Pick a direction.")

            VStack(spacing: Space.sm) {
                ForEach(Array(Goal.allCases.enumerated()), id: \.element) { i, goal in
                    goalChoice(goal) { choose(goal) }
                        .appearIn(2 + i)
                }
            }
        }
    }

    private func choose(_ goal: Goal) {
        withAnimation(Motion.settle) {
            if model.draft.goal != goal { model.draft.targetWeightKg = nil }
            model.draft.goal = goal
        }
        model.autoAdvance(from: .goal)
    }

    private func goalChoice(_ goal: Goal, action: @escaping () -> Void) -> some View {
        let selected = model.draft.goal == goal
        return Button(action: action) {
            HStack(spacing: Space.md) {
                Image(systemName: symbol(for: goal))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(selected ? .white : Palette.accent)
                    .frame(width: 42, height: 42)
                    .background(selected ? Palette.accent : Palette.accentTint, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(goal.title)
                        .font(Typography.data(18, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(commitment(for: goal))
                        .font(Typography.data(12))
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Palette.accent : Palette.inkFaint)
            }
            .padding(Space.md)
            .background(
                selected ? Palette.accentTint : Palette.surface,
                in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(selected ? Palette.accent.opacity(0.45) : Palette.hairline)
            )
        }
        .buttonStyle(.plain)
    }

    private func symbol(for goal: Goal) -> String {
        switch goal {
        case .bulk: return "arrow.up.right"
        case .diet: return "arrow.down.right"
        case .maintain: return "equal"
        }
    }

    private func commitment(for goal: Goal) -> String {
        switch goal {
        case .bulk: return "I'll chase the surplus down if it doesn't happen — not just log whether it did."
        case .diet: return "Enough of a deficit to move — never so much you're starving by 3pm."
        case .maintain: return "Steady doesn't mean silent. I still make sure you eat enough."
        }
    }
}

/// Beat — height and weight, one ruler apiece. The one screen where two
/// numbers share space, because they're the same gesture back to back.
struct VitalsStep: View {
    @Bindable var model: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            ManagerLine(line: "Your body, roughly.", aside: "For the energy estimate. Editable anytime.")

            VStack(alignment: .leading, spacing: Space.sm) {
                Text("Height").sectionLabelStyle()
                RulerPicker(value: heightBinding, range: 120 ... 230, unit: "cm")
            }
            .appearIn(2)

            VStack(alignment: .leading, spacing: Space.sm) {
                Text("Weight").sectionLabelStyle()
                RulerPicker(value: weightBinding, range: 35 ... 250, unit: "kg")
            }
            .appearIn(3)
        }
        .onAppear {
            if model.draft.heightCm == nil { model.draft.heightCm = 170 }
            if model.draft.weightKg == nil { model.draft.weightKg = 70 }
        }
    }

    private var heightBinding: Binding<Double> {
        Binding(get: { model.draft.heightCm ?? 170 }, set: { model.draft.heightCm = $0 })
    }

    private var weightBinding: Binding<Double> {
        Binding(get: { model.draft.weightKg ?? 70 }, set: { model.draft.weightKg = $0 })
    }
}

/// Beat — date of birth, its own screen, the native wheel.
struct BirthdateStep: View {
    @Bindable var model: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            ManagerLine(line: "When's your birthday?", aside: "Age factors into the estimate.")

            DatePicker("", selection: $model.draft.birthDate, in: ...Date.now, displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .appearIn(2)
        }
    }
}

/// Beat — sex, for the energy formula. Tapping any option (including "prefer
/// not to say") advances immediately.
struct SexStep: View {
    @Bindable var model: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            ManagerLine(
                line: "One more thing for the estimate.",
                aside: "Sex shifts the energy formula slightly. Skip it if you'd rather not say."
            )
            VStack(spacing: Space.sm) {
                ForEach(Array(Sex.allCases.enumerated()), id: \.element) { i, sex in
                    ChoiceCard(title: sex.title, selected: model.draft.sex == sex) { choose(sex) }
                        .appearIn(2 + i)
                }
            }
        }
    }

    private func choose(_ sex: Sex) {
        withAnimation(Motion.settle) { model.draft.sex = sex }
        model.autoAdvance(from: .sex)
    }
}

/// Beat — typical activity, one screen of choice cards.
struct ActivityStep: View {
    @Bindable var model: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            ManagerLine(line: "How active is a typical week?", aside: "A rough sense is enough.")
            VStack(spacing: Space.sm) {
                ForEach(Array(ActivityLevel.allCases.enumerated()), id: \.element) { i, level in
                    ChoiceCard(title: level.title, blurb: level.blurb, selected: model.draft.activityLevel == level) {
                        choose(level)
                    }
                    .appearIn(2 + i)
                }
            }
        }
    }

    private func choose(_ level: ActivityLevel) {
        withAnimation(Motion.settle) { model.draft.activityLevel = level }
        model.autoAdvance(from: .activity)
    }
}

/// Beat — target weight + pace. Comes after Vitals so a sensible default can
/// already be proposed against the current weight. Skipped entirely for Maintain.
struct TargetStep: View {
    @Bindable var model: OnboardingViewModel

    private var goal: Goal { model.draft.goal ?? .bulk }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            ManagerLine(
                context: "\(goal.title) is the direction.",
                line: "What's the target weight?",
                aside: "A starting point — change it anytime."
            )

            RulerPicker(value: targetBinding, range: 25 ... 350, unit: "kg")
                .appearIn(2)

            if let message = model.targetWeightMessage {
                Text(message)
                    .font(Typography.data(12, weight: .medium))
                    .foregroundStyle(Palette.accent)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }

            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Pace").sectionLabelStyle()
                HStack(spacing: Space.xs) {
                    ForEach(GoalPace.allCases) { pace in paceButton(pace) }
                }
            }
            .appearIn(3)
        }
        .animation(Motion.settle, value: model.targetWeightMessage)
        .onAppear { proposeTargetIfNeeded() }
    }

    private var targetBinding: Binding<Double> {
        Binding(
            get: { model.draft.targetWeightKg ?? (model.draft.weightKg ?? 70) },
            set: { model.draft.targetWeightKg = $0 }
        )
    }

    private func paceButton(_ pace: GoalPace) -> some View {
        let selected = model.draft.pace == pace
        return Button {
            withAnimation(Motion.settle) { model.draft.pace = pace }
        } label: {
            VStack(spacing: 2) {
                Text(pace.title)
                    .font(Typography.data(14, weight: .semibold))
                Text(pace.blurb(for: goal))
                    .font(Typography.data(10))
            }
            .foregroundStyle(selected ? Color.white : Palette.inkSoft)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(selected ? Palette.ink : Palette.surface, in: RoundedRectangle(cornerRadius: Radius.sm))
        }
        .buttonStyle(.plain)
    }

    private func proposeTargetIfNeeded() {
        guard model.draft.targetWeightKg == nil, let weight = model.draft.weightKg else { return }
        switch goal {
        case .bulk: model.draft.targetWeightKg = (weight + 4).rounded()
        case .diet:
            let floor = model.draft.heightCm.map { HealthyWeight.minKg(heightCm: $0) } ?? 0
            model.draft.targetWeightKg = max((weight - 5).rounded(), floor)
        case .maintain: break
        }
    }
}

/// Beat — meal rhythm as one tap on a preset, not five time pickers. Quiet
/// hours are derived from the pick, never asked (editable later in Settings).
struct RhythmStep: View {
    @Bindable var model: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            ManagerLine(line: "When do you usually eat?", aside: "Approximate is fine — this teaches me your rhythm.")

            VStack(spacing: Space.sm) {
                ForEach(Array(MealRhythmPreset.allCases.enumerated()), id: \.element) { i, preset in
                    ChoiceCard(
                        title: preset.title,
                        blurb: preset.subtitle,
                        selected: model.draft.mealRhythmPreset == preset
                    ) { choose(preset) }
                    .appearIn(2 + i)
                }
            }

            if model.draft.mealRhythmPreset == .custom {
                customFields
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(Motion.settle, value: model.draft.mealRhythmPreset)
    }

    private func choose(_ preset: MealRhythmPreset) {
        model.draft.mealRhythmPreset = preset
        if let times = preset.times {
            model.draft.breakfastMin = times.breakfast
            model.draft.lunchMin = times.lunch
            model.draft.dinnerMin = times.dinner
            applyDerivedQuietHours()
            model.autoAdvance(from: .rhythm)
        }
    }

    private var customFields: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            fieldGroup {
                MinutesField(label: "Breakfast", minutes: $model.draft.breakfastMin)
                Divider().overlay(Palette.hairline)
                MinutesField(label: "Lunch", minutes: $model.draft.lunchMin)
                Divider().overlay(Palette.hairline)
                MinutesField(label: "Dinner", minutes: $model.draft.dinnerMin)
            }
            if !model.mealAnchorsAreValid {
                Text("Use morning-to-evening order.")
                    .font(Typography.data(11, weight: .medium))
                    .foregroundStyle(Palette.accent)
            }
        }
        .onChange(of: model.draft.breakfastMin) { applyDerivedQuietHours() }
        .onChange(of: model.draft.dinnerMin) { applyDerivedQuietHours() }
    }

    private func applyDerivedQuietHours() {
        let quiet = derivedQuietHours(breakfastMin: model.draft.breakfastMin, dinnerMin: model.draft.dinnerMin)
        model.draft.quietStartMin = quiet.start
        model.draft.quietEndMin = quiet.end
    }

    @ViewBuilder
    private func fieldGroup<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: Space.xxs) { content() }
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(Palette.surface).elevation(.resting)
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(Palette.hairline))
            }
    }
}

/// Beat — the optional biosignal. Picking "Meal rhythm" advances immediately;
/// "Wearable" runs the real Health connect and advances once it resolves, so
/// the confirmation line ("Connected — I'll use your heart-rate data") is seen.
struct WearableStep: View {
    @Bindable var model: OnboardingViewModel
    @Environment(AppEnvironment.self) private var env

    enum WearableProbe: Equatable {
        case idle, connecting, connectedWithData, connectedNoData, denied, unavailable
    }
    @State private var probe: WearableProbe = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            ManagerLine(
                line: "One more signal, if you've got it.",
                aside: "Optional. A wearable lets me notice you're running low from your body, not just the clock."
            )

            HStack(spacing: Space.xs) {
                modeButton("Meal rhythm", symbol: "clock", wearable: false)
                modeButton("Wearable", symbol: "heart.text.square", wearable: true)
            }
            .appearIn(2)

            if let note = probeNote {
                Text(note)
                    .font(Typography.data(12))
                    .foregroundStyle(probe == .denied ? Palette.accentDeep : Palette.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .task { if !env.health.isAvailable { probe = .unavailable } }
        .animation(Motion.settle, value: probe)
    }

    private var probeNote: String? {
        switch probe {
        case .idle: return model.draft.hasWearable ? "Heart-rate data connected." : nil
        case .connecting: return "Checking for heart-rate data…"
        case .connectedWithData: return "Connected. I'll use your heart-rate data."
        case .connectedNoData: return "Connected — no recent heart-rate data yet. I'll use meal timing until your device syncs."
        case .denied: return "Health access was declined. Staying on meal timing — you can connect later in Settings."
        case .unavailable: return "No Health data on this device. Meal timing it is."
        }
    }

    private func chooseMealRhythm() {
        model.draft.hasWearable = false
        probe = .idle
        model.autoAdvance(from: .wearable)
    }

    /// Runs the real Health connect + a data probe, so the chosen mode reflects
    /// an actually-connected device (§1), not a toggle.
    private func chooseWearable() {
        guard env.health.isAvailable else {
            probe = .unavailable
            model.autoAdvance(from: .wearable, after: 1.1)
            return
        }
        probe = .connecting
        Task {
            let ok = await env.health.connect()
            guard ok else {
                model.draft.hasWearable = false
                probe = .denied
                model.autoAdvance(from: .wearable, after: 1.1)
                return
            }
            let hasData = await env.health.hasRecentSignal()
            model.draft.hasWearable = true
            probe = hasData ? .connectedWithData : .connectedNoData
            model.autoAdvance(from: .wearable, after: 1.1)
        }
    }

    private func modeButton(_ title: String, symbol: String, wearable: Bool) -> some View {
        let selected = model.draft.hasWearable == wearable
        let disabled = wearable && probe == .unavailable
        return Button {
            guard probe != .connecting else { return }
            wearable ? chooseWearable() : chooseMealRhythm()
        } label: {
            VStack(alignment: .leading, spacing: Space.xs) {
                if wearable && probe == .connecting {
                    ProgressView().controlSize(.small).tint(selected ? Color.white : Palette.inkSoft)
                        .frame(height: 21, alignment: .leading)
                } else {
                    Image(systemName: selected ? "\(symbol).fill" : symbol)
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(title)
                    .font(Typography.data(13, weight: .semibold))
            }
            .foregroundStyle(selected ? Color.white : Palette.inkSoft)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                selected ? Palette.ink : Palette.surface,
                in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(selected ? Color.clear : Palette.hairline)
            )
            .opacity(disabled ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

/// Beat — allergies and other restrictions. Chips only, nothing else on screen.
struct RestrictionsStep: View {
    @Bindable var model: OnboardingViewModel

    private let common = ["Dairy", "Eggs", "Gluten", "Peanuts", "Tree nuts", "Soy", "Fish", "Shellfish", "Sesame", "Pork", "Beef", "Vegetarian", "Vegan"]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            ManagerLine(line: "Anything to avoid?", aside: "Excluded from every suggestion I make. Skip if nothing applies.")

            FlowChips(options: common, selected: $model.draft.restrictions)
                .appearIn(2)

            TextField("Other restrictions", text: $model.draft.restrictionsFreeText, axis: .vertical)
                .font(Typography.data(15))
                .lineLimit(1 ... 3)
                .padding(14)
                .background {
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(Palette.surface).elevation(.resting)
                        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(Palette.hairline))
                }
                .appearIn(3)
        }
    }
}

/// Beat — the one question that can quietly turn off enforcement. Its own
/// screen, plain stakes, no allergy chips competing for attention.
struct MedicalStep: View {
    @Bindable var model: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            ManagerLine(
                line: "Is your nutrition medically supervised?",
                aside: "Includes clinician-led diets. If yes, I switch to quiet tracking — no push, ever."
            )
            HStack(spacing: Space.xs) {
                answerButton("No", value: false)
                answerButton("Yes", value: true)
            }
            .appearIn(2)
        }
    }

    private func answerButton(_ title: String, value: Bool) -> some View {
        let selected = model.draft.medicalSupervisionRequired == value
        return Button { choose(value) } label: {
            Text(title)
                .font(Typography.data(15, weight: .semibold))
                .foregroundStyle(value ? Palette.ink : Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(value ? Palette.surfaceSunk : Palette.ink, in: RoundedRectangle(cornerRadius: Radius.md))
                .overlay {
                    if selected {
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(Palette.accent, lineWidth: 2)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func choose(_ value: Bool) {
        withAnimation(Motion.settle) { model.draft.medicalSupervisionRequired = value }
        model.autoAdvance(from: .medical)
    }
}

/// Beat — the eating-disorder screen (§3). One reassurance line, then the
/// validated questions, one at a time. Framed as safety, never judgment.
struct SafetyStep: View {
    @Bindable var model: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            ManagerLine(line: "A quick safety check.", aside: "Five short questions.")

            Text("Answered privately. They only decide whether check-ins are safe to run for you — nothing here is judged.")
                .font(Typography.data(13))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .appearIn(2)

            SafetyQuestionFlow(model: model)
                .appearIn(3)
        }
    }
}

/// Presents the safety screen one question at a time. All five answers are
/// still required, but the user never faces a wall of clinical copy.
private struct SafetyQuestionFlow: View {
    @Bindable var model: OnboardingViewModel
    @State private var index = 0
    @State private var reviewing = false

    private let questions = [
        "Do you make yourself sick because you feel uncomfortably full?",
        "Do you worry you have lost control over how much you eat?",
        "Have you recently lost more than 6 kg in a three-month period?",
        "Do you believe yourself to be fat when others say you are too thin?",
        "Would you say that food dominates your life?"
    ]

    private var answers: [Bool?] {
        let s = model.draft.scoff
        return [s.makeSelfSick, s.lostControl, s.lostOneStone, s.believesFat, s.foodDominates]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack {
                Text("Safety check").sectionLabelStyle()
                Spacer()
                Text("\(answers.compactMap { $0 }.count) of \(questions.count)")
                    .font(Typography.data(11, weight: .medium))
                    .foregroundStyle(Palette.inkFaint)
            }

            Card(tint: Palette.surfaceRaised, padding: Space.md) {
                if model.draft.scoff.isComplete, !reviewing {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Label("Complete", systemImage: "checkmark.circle.fill")
                            .font(Typography.data(15, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                        Text("Quiet tracking is used when needed.")
                            .font(Typography.data(12))
                            .foregroundStyle(Palette.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Review") {
                            index = 0
                            reviewing = true
                        }
                            .font(Typography.data(13, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                    }
                } else {
                    VStack(alignment: .leading, spacing: Space.md) {
                        HStack(spacing: 5) {
                            ForEach(questions.indices, id: \.self) { questionIndex in
                                Capsule()
                                    .fill(questionIndex < index ? Palette.accent : questionIndex == index ? Palette.accent.opacity(0.4) : Palette.surfaceSunk)
                                    .frame(height: 3)
                            }
                        }

                        Text(questions[index])
                            .font(Typography.voice(18))
                            .foregroundStyle(Palette.ink)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: Space.xs) {
                            answerButton("No", value: false)
                            answerButton("Yes", value: true)
                        }
                    }
                    .id(index)
                    .transition(.opacity)
                }
            }

            Text("Sets check-in mode. Private.")
                .font(Typography.data(11))
                .foregroundStyle(Palette.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func answerButton(_ title: String, value: Bool) -> some View {
        Button {
            setAnswer(value, at: index)
            if index < questions.count - 1 {
                index += 1
            } else {
                reviewing = false
                model.autoAdvance(from: .safety, after: 0.5)
            }
        } label: {
            HStack(spacing: 5) {
                if answers[index] == value {
                    Image(systemName: "checkmark")
                }
                Text(title)
            }
            .font(Typography.data(14, weight: .semibold))
            .foregroundStyle(value ? Palette.ink : Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(value ? Palette.surfaceSunk : Palette.ink, in: RoundedRectangle(cornerRadius: Radius.sm))
        }
        .buttonStyle(.plain)
    }

    private func setAnswer(_ value: Bool, at index: Int) {
        switch index {
        case 0: model.draft.scoff.makeSelfSick = value
        case 1: model.draft.scoff.lostControl = value
        case 2: model.draft.scoff.lostOneStone = value
        case 3: model.draft.scoff.believesFat = value
        default: model.draft.scoff.foodDominates = value
        }
    }
}

// MARK: - Ready

/// Beat — the manager reads back what it has.
struct ReviewStep: View {
    @Bindable var model: OnboardingViewModel

    var body: some View {
        let d = model.draft
        VStack(alignment: .leading, spacing: Space.lg) {
            ManagerLine(line: "Review your plan.", aside: "Everything stays editable.")

            Card(tint: Palette.surfaceRaised, elevation: .floating, padding: Space.md) {
                VStack(spacing: Space.md) {
                    planRow(
                        symbol: "scope",
                        title: goalTitle(d),
                        detail: d.goal?.hasWeightTarget == true
                            ? "\(d.pace.title) pace · from \(Int((d.weightKg ?? 0).rounded())) kg"
                            : "Keep intake and weight steady"
                    )
                    Divider().overlay(Palette.hairline)
                    planRow(
                        symbol: "sun.horizon",
                        title: "\(clock(d.breakfastMin)) · \(clock(d.lunchMin)) · \(clock(d.dinnerMin))",
                        detail: d.mealRhythmPreset == .custom ? "Custom meal anchors" : "\(d.mealRhythmPreset.title) rhythm"
                    )
                    Divider().overlay(Palette.hairline)
                    planRow(
                        symbol: d.hasWearable ? "heart.text.square" : "clock",
                        title: d.hasWearable ? "Meal rhythm + wearable" : "Meal rhythm",
                        detail: "Quiet from \(clock(d.quietStartMin)) to \(clock(d.quietEndMin))"
                    )
                }
            }
            .appearIn(2)

            if !d.restrictions.isEmpty || !d.restrictionsFreeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack(alignment: .top, spacing: Space.xs) {
                    Image(systemName: "checkmark.shield")
                        .foregroundStyle(Palette.accent)
                    Text("Exclude: \(restrictionSummary(d)).")
                        .font(Typography.data(13))
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .appearIn(3)
            }

            Text("Your daily target is next.")
                .font(Typography.data(12))
                .foregroundStyle(Palette.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
                .appearIn(4)

            HStack(alignment: .top, spacing: Space.sm) {
                Button {
                    withAnimation(Motion.settle) { model.draft.agreedToTerms.toggle() }
                } label: {
                    Image(systemName: model.draft.agreedToTerms ? "checkmark.square.fill" : "square")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(model.draft.agreedToTerms ? Palette.accent : Palette.inkFaint)
                }
                .buttonStyle(.plain)

                (
                    Text("I've read the ")
                    + Text("[Privacy Policy](\(APIConfig.baseURL.appending(path: "privacy").absoluteString))")
                    + Text(" and ")
                    + Text("[Terms](\(APIConfig.baseURL.appending(path: "terms").absoluteString))")
                    + Text(".")
                )
                .font(Typography.data(12))
                .tint(Palette.accent)
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            }
            .appearIn(5)
        }
    }

    private func planRow(symbol: String, title: String, detail: String) -> some View {
        HStack(spacing: Space.sm) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .frame(width: 34, height: 34)
                .background(Palette.accentTint, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.data(15, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text(detail)
                    .font(Typography.data(12))
                    .foregroundStyle(Palette.inkSoft)
            }
            Spacer(minLength: 0)
        }
    }

    private func goalTitle(_ draft: OnboardingDraft) -> String {
        guard let goal = draft.goal else { return "Daily target" }
        if goal.hasWeightTarget, let target = draft.targetWeightKg {
            return "\(goal.directionVerb) \(Int(target.rounded())) kg"
        }
        return "Maintain \(Int((draft.weightKg ?? 0).rounded())) kg"
    }

    private func restrictionSummary(_ draft: OnboardingDraft) -> String {
        var items = draft.restrictions
        let freeText = draft.restrictionsFreeText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !freeText.isEmpty { items.append(freeText) }
        return items.joined(separator: ", ")
    }
}

/// The payoff — the manager delivers the number as a commitment, then the
/// permission asks it needs to actually do the job.
struct OutcomeStep: View {
    @Bindable var model: OnboardingViewModel
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pushHandled = false
    @State private var healthHandled = false
    @State private var shownKcal = 0

    private var enforcementOn: Bool {
        model.result?.enforcementDisabledReason == nil
    }

    /// "Gain to 84 kg — gently." for a weight goal.
    private var goalLine: String? {
        guard let goal = model.draft.goal, goal.hasWeightTarget,
              let target = model.result?.targetWeightKg else { return nil }
        return "\(goal.directionVerb) \(Int(target.rounded())) kg — \(model.draft.pace.title.lowercased())."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Spacer(minLength: Space.lg)

            ProgressThread(step: OnboardingViewModel.threadedSteps.count, total: OnboardingViewModel.threadedSteps.count)
                .padding(.bottom, Space.sm)
                .appearIn(0)

            switch model.result?.enforcementDisabledReason {
            case "EATING_DISORDER_SCREEN":
                headline("Quiet mode is on.")
                copy("I won't push you to eat. If eating feels hard right now, a qualified healthcare professional or local eating-disorder service can offer support that an app can't.")
                    .appearIn(1)
            case "MEDICAL_SUPERVISION":
                headline("Quiet mode is on.")
                copy("I won't push you to eat — that's your care team's call, not an app's. This isn't a substitute for their plan.")
                    .appearIn(1)
            default:
                headline("Your starting point.")
                targetReveal
            }

            if enforcementOn, !pushHandled, env.push.authorizationStatus == .notDetermined {
                VStack(alignment: .leading, spacing: Space.xs) {
                    copy("Get check-in notifications.")
                    ActionButton(title: "Turn on check-ins") {
                        Task { await env.push.requestAuthorization(); pushHandled = true }
                    }
                }
                .padding(.top, Space.xs)
                .appearIn(4)
            }

            if enforcementOn, model.draft.hasWearable, !healthHandled, env.health.isAvailable,
               !env.health.connected {
                VStack(alignment: .leading, spacing: Space.xs) {
                    copy("Use Health recovery data.")
                    ActionButton(title: "Connect Health", kind: .secondary) {
                        Task { await env.health.connect(); healthHandled = true }
                    }
                }
                .appearIn(5)
            }

            Spacer()
        }
        .padding(.horizontal, Space.xxs)
        .onAppear {
            guard let target = model.result?.dailyKcalTarget else { return }
            withAnimation(Motion.adaptive(Motion.enter, reduceMotion: reduceMotion).delay(0.4)) {
                shownKcal = target
            }
        }
    }

    @ViewBuilder
    private var targetReveal: some View {
        Card(tint: Palette.surfaceRaised, elevation: .floating, padding: Space.md) {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DAILY ENERGY")
                            .sectionLabelStyle()
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text("\(shownKcal)")
                                .font(Typography.display(34))
                                .foregroundStyle(Palette.accent)
                                .contentTransition(.numericText(value: Double(shownKcal)))
                                .monospacedDigit()
                            Text("kcal")
                                .font(Typography.data(13))
                                .foregroundStyle(Palette.inkFaint)
                        }
                    }
                    Spacer()
                    if let protein = model.result?.dailyProteinTargetG {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("PROTEIN")
                                .sectionLabelStyle()
                            Text("\(protein) g")
                                .font(Typography.data(20, weight: .semibold))
                                .foregroundStyle(Palette.ink)
                        }
                        .appearIn(2)
                    }
                }
                Divider().overlay(Palette.hairline)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your daily target.")
                        .font(Typography.voice(17))
                        .foregroundStyle(Palette.ink)
                    if let goalLine {
                        Text(goalLine)
                            .font(Typography.data(12))
                            .foregroundStyle(Palette.inkSoft)
                    }
                }
                .appearIn(3)
            }
        }
        .appearIn(1)
    }

    private func headline(_ text: String) -> some View {
        Text(text)
            .font(Typography.display(34))
            .foregroundStyle(Palette.ink)
            .fixedSize(horizontal: false, vertical: true)
            .appearIn(0)
            .firstAppearPulse()
    }

    private func copy(_ text: String) -> some View {
        Text(text)
            .font(Typography.data(15))
            .foregroundStyle(Palette.inkSoft)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private func clock(_ minutes: Int) -> String {
    String(format: "%d:%02d", minutes / 60, minutes % 60)
}

/// Wrapping selectable chips.
struct FlowChips: View {
    let options: [String]
    @Binding var selected: [String]

    var body: some View {
        FlexWrap(spacing: 8, lineSpacing: 8) {
            ForEach(options, id: \.self) { option in
                let isOn = selected.contains(option)
                Button {
                    if isOn { selected.removeAll { $0 == option } } else { selected.append(option) }
                } label: {
                    Text(option)
                        .font(Typography.data(14, weight: .medium))
                        .foregroundStyle(isOn ? .white : Palette.inkSoft)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(isOn ? Palette.ink : Palette.surfaceSunk, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Minimal flow layout (iOS 16+ Layout).
struct FlexWrap: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
