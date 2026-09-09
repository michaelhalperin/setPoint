import SwiftUI

struct GoalStep: View {
    @Bindable var model: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeader(title: "What are you working on?", subtitle: "This sets the direction. You can change it later.")
            VStack(spacing: 12) {
                ForEach(Goal.allCases) { goal in
                    ChoiceCard(title: goal.title, blurb: goal.blurb, selected: model.draft.goal == goal) {
                        model.draft.goal = goal
                    }
                }
            }
        }
    }
}

struct AboutYouStep: View {
    @Bindable var model: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeader(title: "A bit about you", subtitle: "Used once, to set a realistic daily target.")

            VStack(spacing: 12) {
                MeasureField(label: "Height", unit: "cm", range: 120 ... 230, value: $model.draft.heightCm)
                MeasureField(label: "Weight", unit: "kg", range: 35 ... 250, value: $model.draft.weightKg)

                HStack {
                    Text("Born")
                        .font(Typography.data(15))
                        .foregroundStyle(Palette.inkSoft)
                    Spacer()
                    DatePicker("", selection: $model.draft.birthDate, in: ...Date.now, displayedComponents: .date)
                        .labelsHidden()
                }
                .padding(14)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Text("Sex").sectionLabelStyle()
            Picker("Sex", selection: $model.draft.sex) {
                ForEach(Sex.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            Text("Day-to-day activity").sectionLabelStyle()
            VStack(spacing: 8) {
                ForEach(ActivityLevel.allCases) { level in
                    ChoiceCard(title: level.title, selected: model.draft.activityLevel == level) {
                        model.draft.activityLevel = level
                    }
                }
            }
        }
    }
}

struct RhythmStep: View {
    @Bindable var model: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeader(
                title: "When do you usually eat?",
                subtitle: "SetPoint learns your gaps from these — no need to be exact."
            )

            VStack(spacing: 4) {
                MinutesField(label: "Breakfast", minutes: $model.draft.breakfastMin)
                Divider().overlay(Palette.ink.opacity(0.06))
                MinutesField(label: "Lunch", minutes: $model.draft.lunchMin)
                Divider().overlay(Palette.ink.opacity(0.06))
                MinutesField(label: "Dinner", minutes: $model.draft.dinnerMin)
            }
            .padding(12)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text("Quiet hours").sectionLabelStyle()
            Text("No check-ins during this window.")
                .font(Typography.data(13))
                .foregroundStyle(Palette.inkSoft)
            VStack(spacing: 4) {
                MinutesField(label: "From", minutes: $model.draft.quietStartMin)
                Divider().overlay(Palette.ink.opacity(0.06))
                MinutesField(label: "Until", minutes: $model.draft.quietEndMin)
            }
            .padding(12)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

struct WearableStep: View {
    @Bindable var model: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeader(
                title: "Do you wear a heart-rate tracker?",
                subtitle: "An Apple Watch, Oura ring, or similar. It makes check-ins smarter — SetPoint can tell when you're running low before you feel it."
            )
            VStack(spacing: 12) {
                ChoiceCard(title: "Yes, I have one", blurb: "Smart mode — biosignal-aware check-ins.", selected: model.draft.hasWearable) {
                    model.draft.hasWearable = true
                }
                ChoiceCard(title: "No, or not right now", blurb: "Basic mode — scheduled check-ins from your meal times.", selected: !model.draft.hasWearable) {
                    model.draft.hasWearable = false
                }
            }
            if model.draft.hasWearable {
                Text("You'll be asked for Health access after setup.")
                    .font(Typography.data(12))
                    .foregroundStyle(Palette.inkFaint)
            }
        }
    }
}

struct RestrictionsStep: View {
    @Bindable var model: OnboardingViewModel

    private let common = ["Dairy", "Eggs", "Gluten", "Peanuts", "Tree nuts", "Soy", "Fish", "Shellfish", "Sesame", "Pork", "Beef", "Vegetarian", "Vegan"]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeader(
                title: "Anything to keep off the list?",
                subtitle: "Allergies and hard restrictions. Prescriptions will never include these."
            )

            FlowChips(options: common, selected: $model.draft.restrictions)

            Text("Anything else").sectionLabelStyle()
            TextField("e.g. no red meat, low FODMAP", text: $model.draft.restrictionsFreeText, axis: .vertical)
                .font(Typography.data(15))
                .lineLimit(1 ... 3)
                .padding(14)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

struct HealthStep: View {
    @Bindable var model: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepHeader(
                title: "A few health questions",
                subtitle: "Honest answers here keep SetPoint safe for you. Your answers are private."
            )

            Toggle(isOn: $model.draft.medicalSupervisionRequired) {
                Text("I have a condition that needs medically supervised nutrition (e.g. diabetes, kidney disease).")
                    .font(Typography.data(15))
                    .foregroundStyle(Palette.ink)
            }
            .tint(Palette.accent)
            .padding(.vertical, 8)

            Divider().overlay(Palette.ink.opacity(0.08))

            YesNoRow(question: "Do you make yourself sick because you feel uncomfortably full?", answer: $model.draft.scoff.makeSelfSick)
            YesNoRow(question: "Do you worry you have lost control over how much you eat?", answer: $model.draft.scoff.lostControl)
            YesNoRow(question: "Have you recently lost more than 6 kg in a three-month period?", answer: $model.draft.scoff.lostOneStone)
            YesNoRow(question: "Do you believe yourself to be fat when others say you are too thin?", answer: $model.draft.scoff.believesFat)
            YesNoRow(question: "Would you say that food dominates your life?", answer: $model.draft.scoff.foodDominates)
        }
    }
}

struct ReviewStep: View {
    @Bindable var model: OnboardingViewModel

    var body: some View {
        let d = model.draft
        VStack(alignment: .leading, spacing: 16) {
            StepHeader(title: "Look right?", subtitle: "You can change any of this in Settings.")

            Card {
                VStack(alignment: .leading, spacing: 10) {
                    row("Goal", (d.goal ?? .bulk).title)
                    row("Mode", d.hasWearable ? "Smart" : "Basic")
                    row("Meals", "\(clock(d.breakfastMin)) · \(clock(d.lunchMin)) · \(clock(d.dinnerMin))")
                    row("Quiet hours", "\(clock(d.quietStartMin))–\(clock(d.quietEndMin))")
                    if !d.restrictions.isEmpty {
                        row("Avoiding", d.restrictions.joined(separator: ", "))
                    }
                }
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(Typography.data(13))
                .foregroundStyle(Palette.inkFaint)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(Typography.data(14, weight: .medium))
                .foregroundStyle(Palette.ink)
            Spacer()
        }
    }
}

struct OutcomeStep: View {
    @Bindable var model: OnboardingViewModel
    @Environment(AppEnvironment.self) private var env
    @State private var pushHandled = false
    @State private var healthHandled = false

    private var enforcementOn: Bool {
        model.result?.enforcementDisabledReason == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer(minLength: 40)
            switch model.result?.enforcementDisabledReason {
            case "EATING_DISORDER_SCREEN":
                headline("SetPoint will track your intake, quietly.")
                body("It won't push you to eat. If you're finding eating hard right now, talking to a professional can really help — the NEDA helpline is a good place to start.")
            case "MEDICAL_SUPERVISION":
                headline("SetPoint will track your intake, quietly.")
                body("It won't push you to eat — that's your care team's call, not an app's. This isn't a substitute for their plan.")
            default:
                headline("You're set.")
                if let target = model.result?.dailyKcalTarget {
                    body("Daily target: \(target) kcal" + (model.result?.dailyProteinTargetG.map { " · \($0) g protein" } ?? "") + ".")
                }
            }

            if enforcementOn, !pushHandled, env.push.authorizationStatus == .notDetermined {
                VStack(alignment: .leading, spacing: 8) {
                    body("Check-ins arrive as a notification you can act on without opening the app.")
                    ActionButton(title: "Turn on check-ins") {
                        Task {
                            await env.push.requestAuthorization()
                            pushHandled = true
                        }
                    }
                }
                .padding(.top, 8)
            }

            if enforcementOn, model.draft.hasWearable, !healthHandled, env.health.isAvailable {
                VStack(alignment: .leading, spacing: 8) {
                    body("Connect Health so SetPoint can read your HRV and resting heart rate.")
                    ActionButton(title: "Connect Health", kind: .secondary) {
                        Task {
                            await env.health.connect()
                            healthHandled = true
                        }
                    }
                }
                .padding(.top, 4)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private func headline(_ text: String) -> some View {
        Text(text)
            .font(Typography.voice(26))
            .foregroundStyle(Palette.ink)
            .fixedSize(horizontal: false, vertical: true)
            .firstAppearPulse()
    }

    private func body(_ text: String) -> some View {
        Text(text)
            .font(Typography.data(15))
            .foregroundStyle(Palette.inkSoft)
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
