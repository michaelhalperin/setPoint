import SwiftUI

/// The opening beat — the manager says what the deal is before asking for
/// anything. No form, no progress thread. Sets the "coach, not alarm" tone (§6).
struct WelcomeStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Spacer(minLength: Space.xl)

            Text("SetPoint")
                .font(Typography.data(13, weight: .semibold))
                .tracking(2)
                .textCase(.uppercase)
                .foregroundStyle(Palette.inkFaint)
                .appearIn(0)

            Text("Eat to your goal.")
                .font(Typography.display(34))
                .foregroundStyle(Palette.ink)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .appearIn(1)

            Text("One daily target. Check-ins when needed.")
                .font(Typography.data(15))
                .foregroundStyle(Palette.inkSoft)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .appearIn(2)

            Card(tint: Palette.surfaceRaised, padding: Space.md) {
                VStack(spacing: Space.md) {
                    promise("scope", "One target", "Your daily number.")
                    Divider().overlay(Palette.hairline)
                    promise("waveform.path.ecg", "Your rhythm", "Flexible meal timing.")
                    Divider().overlay(Palette.hairline)
                    promise("text.bubble.fill", "Useful help", "Food when needed.")
                }
            }
            .appearIn(3)

            Text("About two minutes. Editable anytime.")
                .font(Typography.data(12))
                .foregroundStyle(Palette.inkFaint)
                .appearIn(4)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func promise(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: Space.sm) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .frame(width: 34, height: 34)
                .background(Palette.accentTint, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.data(15, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text(detail)
                    .font(Typography.data(12))
                    .foregroundStyle(Palette.inkFaint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The minimum baseline needed to calculate a defensible starting target.
struct YouStep: View {
    @Bindable var model: OnboardingViewModel

    private var goal: Goal { model.draft.goal ?? .maintain }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            ManagerLine(
                context: "\(goal.title) is the direction.",
                line: "Your starting point.",
                aside: "Sets your first targets."
            )

            VStack(spacing: Space.sm) {
                MeasureField(label: "Height", unit: "cm", range: 120 ... 230, value: $model.draft.heightCm)
                MeasureField(label: "Weight", unit: "kg", range: 35 ... 250, value: $model.draft.weightKg)

                inputRow("Date of birth") {
                    DatePicker("", selection: $model.draft.birthDate, in: ...Date.now, displayedComponents: .date)
                        .labelsHidden()
                }

                inputRow("Typical activity") {
                    Picker("Typical activity", selection: $model.draft.activityLevel) {
                        ForEach(ActivityLevel.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .tint(Palette.ink)
                }
            }
            .appearIn(2)

            VStack(alignment: .leading, spacing: Space.xs) {
                Text("For energy estimate").sectionLabelStyle()
                Picker("Sex", selection: $model.draft.sex) {
                    ForEach(Sex.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            .appearIn(3)

            if goal.hasWeightTarget, model.draft.weightKg != nil {
                Card(tint: Palette.accentTint, elevation: .floating) {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text("Target weight")
                            .font(Typography.voice(19))
                            .foregroundStyle(Palette.ink)
                        Text("Editable anytime.")
                            .font(Typography.data(12))
                            .foregroundStyle(Palette.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                        MeasureField(
                            label: "Target weight",
                            unit: "kg",
                            range: 25 ... 350,
                            value: $model.draft.targetWeightKg
                        )
                        if model.draft.targetWeightKg != nil, !model.targetWeightIsValid {
                            Text(goal == .bulk ? "Above current weight." : "Below current weight.")
                                .font(Typography.data(11, weight: .medium))
                                .foregroundStyle(Palette.accent)
                        }
                        HStack(spacing: Space.xs) {
                            ForEach(GoalPace.allCases) { pace in
                                paceButton(pace)
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                .appearIn(4)
            }
        }
        .onAppear { proposeTargetIfNeeded() }
        .onChange(of: model.draft.weightKg) { _, _ in proposeTargetIfNeeded() }
    }

    private func inputRow<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
        HStack {
            Text(label)
                .font(Typography.data(15))
                .foregroundStyle(Palette.inkSoft)
            Spacer()
            content()
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Palette.surface).elevation(.resting)
                .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(Palette.hairline))
        }
    }

    private func paceButton(_ pace: GoalPace) -> some View {
        let selected = model.draft.pace == pace
        return Button {
            model.draft.pace = pace
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
        case .diet: model.draft.targetWeightKg = (weight - 5).rounded()
        case .maintain: break
        }
    }
}

/// The first decision is intent. Numbers come after the user has chosen what
/// those numbers are meant to do.
struct GoalStep: View {
    @Bindable var model: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            ManagerLine(
                line: "Choose your goal.",
                aside: "Pick a direction."
            )

            VStack(spacing: Space.sm) {
                ForEach(Array(Goal.allCases.enumerated()), id: \.element) { i, goal in
                    goalChoice(goal) {
                        withAnimation(Motion.settle) {
                            if model.draft.goal != goal {
                                model.draft.targetWeightKg = nil
                            }
                            model.draft.goal = goal
                        }
                    }
                    .appearIn(2 + i)
                }
            }

            if let goal = model.draft.goal {
                Text(commitment(for: goal))
                    .font(Typography.voice(16))
                    .foregroundStyle(Palette.accent)
                    .padding(.horizontal, Space.xs)
                    .transition(.opacity)
            }
        }
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
                    Text(goal.blurb)
                        .font(Typography.data(12))
                        .foregroundStyle(Palette.inkSoft)
                        .lineLimit(2)
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
        case .bulk: return "Protect surplus."
        case .diet: return "Protect intake floor."
        case .maintain: return "Hold steady."
        }
    }
}

/// A few anchors teach the manager when the day is drifting. These are not
/// reminder alarms and do not require exact meal times.
struct CheckinsStep: View {
    @Bindable var model: OnboardingViewModel

    private var goalContext: String? {
        guard let goal = model.draft.goal else { return nil }
        if goal.hasWeightTarget, let t = model.draft.targetWeightKg {
            return "\(goal.directionVerb) \(Int(t.rounded())) kg."
        }
        return "\(goal.title)."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            ManagerLine(
                context: goalContext,
                line: "Set your rhythm.",
                aside: "Approximate times are enough."
            )

            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Meal anchors").sectionLabelStyle()
                fieldGroup {
                    MinutesField(label: "Breakfast", minutes: $model.draft.breakfastMin)
                    Divider().overlay(Palette.hairline)
                    MinutesField(label: "Lunch", minutes: $model.draft.lunchMin)
                    Divider().overlay(Palette.hairline)
                    MinutesField(label: "Dinner", minutes: $model.draft.dinnerMin)
                }
                Text("No alarms.")
                    .font(Typography.data(12))
                    .foregroundStyle(Palette.inkFaint)
                if !model.mealAnchorsAreValid {
                    Text("Use morning-to-evening order.")
                        .font(Typography.data(11, weight: .medium))
                        .foregroundStyle(Palette.accent)
                }
            }
            .appearIn(2)

            VStack(alignment: .leading, spacing: Space.xs) {
                HStack {
                    Text("Quiet hours").sectionLabelStyle()
                    Spacer()
                    Text("No check-ins")
                        .font(Typography.data(11, weight: .medium))
                        .foregroundStyle(Palette.inkFaint)
                }
                fieldGroup {
                    MinutesField(label: "From", minutes: $model.draft.quietStartMin)
                    Divider().overlay(Palette.hairline)
                    MinutesField(label: "Until", minutes: $model.draft.quietEndMin)
                }
            }
            .appearIn(3)

            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Signal").sectionLabelStyle()
                Text("Wearable is optional.")
                    .font(Typography.data(13))
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Space.xs) {
                    modeButton("Meal rhythm", symbol: "clock", wearable: false)
                    modeButton("Wearable", symbol: "heart.text.square", wearable: true)
                }
                if model.draft.hasWearable {
                    Text("Health access comes next.")
                        .font(Typography.data(12))
                        .foregroundStyle(Palette.inkFaint)
                        .transition(.opacity)
                }
            }
            .appearIn(4)
        }
    }

    private func modeButton(_ title: String, symbol: String, wearable: Bool) -> some View {
        let selected = model.draft.hasWearable == wearable
        return Button {
            model.draft.hasWearable = wearable
        } label: {
            VStack(alignment: .leading, spacing: Space.xs) {
                Image(systemName: selected ? "\(symbol).fill" : symbol)
                    .font(.system(size: 16, weight: .semibold))
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
        }
        .buttonStyle(.plain)
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

/// Beat 4 — everything that bounds what the manager will do: allergies, medical
/// supervision, and the eating-disorder screen (§3). Framed as safety, never
/// judgment.
struct SafetyStep: View {
    @Bindable var model: OnboardingViewModel

    private let common = ["Dairy", "Eggs", "Gluten", "Peanuts", "Tree nuts", "Soy", "Fish", "Shellfish", "Sesame", "Pork", "Beef", "Vegetarian", "Vegan"]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            ManagerLine(
                line: "Set boundaries.",
                aside: "Keep suggestions safe."
            )

            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Avoid").sectionLabelStyle()
                Text("Exclude from suggestions.")
                    .font(Typography.data(13))
                    .foregroundStyle(Palette.inkSoft)
                FlowChips(options: common, selected: $model.draft.restrictions)
                TextField("Other restrictions", text: $model.draft.restrictionsFreeText, axis: .vertical)
                    .font(Typography.data(15))
                    .lineLimit(1 ... 3)
                    .padding(14)
                    .background {
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(Palette.surface).elevation(.resting)
                            .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(Palette.hairline))
                    }
            }
            .appearIn(2)

            Card(padding: 14) {
                Toggle(isOn: $model.draft.medicalSupervisionRequired) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("My nutrition is medically supervised")
                            .font(Typography.data(15, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                        Text("Includes clinician-led diets.")
                            .font(Typography.data(12))
                            .foregroundStyle(Palette.inkSoft)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .tint(Palette.accent)
            }
            .appearIn(3)

            SafetyQuestionFlow(model: model)
            .appearIn(4)
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

/// Beat 5 — the manager reads back what it has.
struct ReviewStep: View {
    @Bindable var model: OnboardingViewModel

    var body: some View {
        let d = model.draft
        VStack(alignment: .leading, spacing: Space.lg) {
            ManagerLine(
                line: "Review your plan.",
                aside: "Everything stays editable."
            )

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
                        detail: "Meal anchors"
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

            if enforcementOn, model.draft.hasWearable, !healthHandled, env.health.isAvailable {
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
