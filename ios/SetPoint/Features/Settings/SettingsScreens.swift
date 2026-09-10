import SwiftUI

struct GoalSettingsView: View {
    @Bindable var model: SettingsViewModel
    @State private var highlightTargetWeight = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                header
                    .appearIn(0)

                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("Direction").sectionLabelStyle()

                    HStack(spacing: Space.xs) {
                        ForEach(Goal.allCases) { goal in
                            GoalDirectionCard(
                                goal: goal,
                                selected: model.goal == goal
                            ) {
                                choose(goal)
                            }
                        }
                    }
                }
                .appearIn(1)

                if model.goal.hasWeightTarget {
                    trajectoryCard
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .appearIn(2)
                } else {
                    ManagerNote(
                        text: "Steady target. Watching for drift."
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                dailyTargets
                    .appearIn(3)

                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("Foods to avoid").sectionLabelStyle()
                    Text("Excluded from suggestions.")
                        .font(Typography.data(13))
                        .foregroundStyle(Palette.inkSoft)
                    Card {
                        RestrictionChips(selected: $model.restrictions)
                    }
                }

                if let error = model.error {
                    Text(error)
                        .font(Typography.data(13))
                        .foregroundStyle(Palette.accentDeep)
                        .padding(Space.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.accentTint, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.md)
            .padding(.bottom, Space.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Goal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Palette.background, for: .navigationBar)
        .saveWhenDirty(model)
        .onDisappear { model.revertToOriginal() }
        .animation(Motion.settle, value: model.goal)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("Your goal")
                .font(Typography.display(32))
                .foregroundStyle(Palette.ink)
            Text("Set direction and targets.")
                .font(Typography.voice(17))
                .foregroundStyle(Palette.inkSoft)
        }
    }

    private var trajectoryCard: some View {
        Card(tint: Palette.surfaceRaised, padding: Space.md) {
            VStack(alignment: .leading, spacing: Space.md) {
                Text("Your path").sectionLabelStyle()

                HStack(alignment: .center, spacing: Space.sm) {
                    weightPoint(
                        label: "Now",
                        value: model.currentWeightKg.map { "\(Int($0.rounded()))" } ?? "—",
                        unit: model.currentWeightKg == nil ? nil : "kg"
                    )

                    HStack(spacing: 5) {
                        Rectangle()
                            .fill(Palette.accentSoft)
                            .frame(height: 2)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Palette.accent)
                    }

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Target")
                            .font(Typography.data(12, weight: .semibold))
                            .foregroundStyle(Palette.inkFaint)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            TextField("—", value: $model.targetWeightKg, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .font(Typography.data(28, weight: .semibold))
                                .foregroundStyle(Palette.accentDeep)
                                .frame(minWidth: 48, maxWidth: 76)
                            Text("kg")
                                .font(Typography.data(13))
                                .foregroundStyle(Palette.inkFaint)
                        }
                    }
                    .padding(8)
                    .background(
                        highlightTargetWeight ? Palette.accentTint : Color.clear,
                        in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .strokeBorder(highlightTargetWeight ? Palette.accent.opacity(0.55) : Color.clear)
                    }
                    .animation(Motion.settle, value: highlightTargetWeight)
                    .onChange(of: model.targetWeightKg) { _, _ in
                        highlightTargetWeight = false
                    }
                }

                Divider().overlay(Palette.hairline)

                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Pace").sectionLabelStyle()
                    HStack(spacing: Space.xs) {
                        ForEach(GoalPace.allCases) { pace in
                            PaceCard(
                                pace: pace,
                                goal: model.goal,
                                selected: model.pace == pace
                            ) {
                                model.pace = pace
                            }
                        }
                    }
                }

                Text("Changes recalculate your daily target.")
                    .font(Typography.data(12))
                    .foregroundStyle(Palette.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var dailyTargets: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Daily targets").sectionLabelStyle()
            Text("Adjust as needed.")
                .font(Typography.data(13))
                .foregroundStyle(Palette.inkSoft)

            VStack(spacing: Space.xs) {
                TargetAdjuster(
                    title: "Energy",
                    value: $model.kcalTarget,
                    range: 1200 ... 6000,
                    step: 50,
                    unit: "kcal"
                )
                TargetAdjuster(
                    title: "Protein",
                    value: Binding(
                        get: { model.proteinTarget ?? 0 },
                        set: { model.proteinTarget = $0 }
                    ),
                    range: 0 ... 350,
                    step: 5,
                    unit: "g"
                )
            }
        }
    }

    private func weightPoint(label: String, value: String, unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Typography.data(12, weight: .semibold))
                .foregroundStyle(Palette.inkFaint)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(Typography.data(28, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .monospacedDigit()
                if let unit {
                    Text(unit)
                        .font(Typography.data(13))
                        .foregroundStyle(Palette.inkFaint)
                }
            }
        }
    }

    private func choose(_ goal: Goal) {
        let directionChanged = model.goal != goal
        model.goal = goal
        if goal.hasWeightTarget,
           model.targetWeightKg == nil,
           let current = model.currentWeightKg {
            model.targetWeightKg = (current + (goal == .bulk ? 4 : -5)).rounded()
        }
        highlightTargetWeight = directionChanged && goal.hasWeightTarget
    }
}

private struct GoalDirectionCard: View {
    let goal: Goal
    let selected: Bool
    let action: () -> Void

    private var symbol: String {
        switch goal {
        case .bulk: return "arrow.up.right"
        case .diet: return "arrow.down.right"
        case .maintain: return "arrow.right"
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Space.sm) {
                ZStack {
                    Circle()
                        .fill(selected ? Palette.accent : Palette.surfaceSunk)
                        .frame(width: 34, height: 34)
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(selected ? Color.white : Palette.inkSoft)
                }
                Text(goal.title)
                    .font(Typography.data(14, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(selected ? Palette.accentTint : Palette.surface)
                    .elevation(selected ? .floating : .resting)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(selected ? Palette.accent.opacity(0.4) : Palette.hairline)
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(goal.title): \(goal.blurb)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct PaceCard: View {
    let pace: GoalPace
    let goal: Goal
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(pace.title)
                        .font(Typography.data(15, weight: .semibold))
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                    }
                }
                Text(pace.blurb(for: goal))
                    .font(Typography.data(11))
                    .foregroundStyle(Palette.inkSoft)
            }
            .foregroundStyle(Palette.ink)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selected ? Palette.accentTint : Palette.surfaceSunk.opacity(0.7),
                in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(selected ? Palette.accent.opacity(0.35) : Palette.hairline)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct TargetAdjuster: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let unit: String

    var body: some View {
        Card(padding: 14) {
            HStack(spacing: Space.sm) {
                Text(title)
                    .font(Typography.data(16, weight: .semibold))
                    .foregroundStyle(Palette.ink)

                Spacer()

                adjustmentButton(symbol: "minus") {
                    value = max(range.lowerBound, value - step)
                }
                .disabled(value <= range.lowerBound)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(value)")
                        .font(Typography.data(20, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .monospacedDigit()
                    Text(unit)
                        .font(Typography.data(12))
                        .foregroundStyle(Palette.inkFaint)
                }
                .frame(minWidth: 88)

                adjustmentButton(symbol: "plus") {
                    value = min(range.upperBound, value + step)
                }
                .disabled(value >= range.upperBound)
            }
        }
    }

    private func adjustmentButton(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Palette.inkSoft)
                .frame(width: 32, height: 32)
                .background(Palette.surfaceSunk, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(symbol == "plus" ? "Increase" : "Decrease") \(title)")
    }
}

struct RhythmSettingsView: View {
    @Bindable var model: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Your rhythm")
                        .font(Typography.display(32))
                        .foregroundStyle(Palette.ink)
                    Text("Approximate times are enough.")
                        .font(Typography.voice(17))
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .appearIn(0)

                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("Your meal rhythm").sectionLabelStyle()
                    Card(tint: Palette.surfaceRaised, padding: 0) {
                        VStack(spacing: 0) {
                            CheckInTimeRow(
                                title: "Breakfast",
                                symbol: "sun.horizon.fill",
                                minutes: $model.mealTimes.breakfastMin
                            )
                            Divider().overlay(Palette.hairline).padding(.leading, 58)
                            CheckInTimeRow(
                                title: "Lunch",
                                symbol: "sun.max.fill",
                                minutes: $model.mealTimes.lunchMin
                            )
                            Divider().overlay(Palette.hairline).padding(.leading, 58)
                            CheckInTimeRow(
                                title: "Dinner",
                                symbol: "sunset.fill",
                                minutes: $model.mealTimes.dinnerMin
                            )
                        }
                    }
                }
                .appearIn(1)

                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("Quiet hours").sectionLabelStyle()
                    Text("No nudges.")
                        .font(Typography.data(13))
                        .foregroundStyle(Palette.inkSoft)

                    Card(tint: Palette.surfaceRaised, padding: Space.md) {
                        VStack(alignment: .leading, spacing: Space.md) {
                            HStack(spacing: Space.sm) {
                                Image(systemName: "moon.stars.fill")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(Palette.accent)
                                    .frame(width: 38, height: 38)
                                    .background(Palette.accentTint, in: Circle())
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Pause check-ins")
                                        .font(Typography.data(16, weight: .semibold))
                                        .foregroundStyle(Palette.ink)
                                    Text("Tracking continues.")
                                        .font(Typography.data(12))
                                        .foregroundStyle(Palette.inkFaint)
                                }
                            }

                            HStack(spacing: Space.xs) {
                                QuietTimeField(label: "From", minutes: $model.quietHours.startMin)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Palette.inkFaint)
                                QuietTimeField(label: "Until", minutes: $model.quietHours.endMin)
                            }
                        }
                    }
                }
                .appearIn(2)

                Card(
                    tint: model.checkInsPaused ? Palette.surfaceSunk : Palette.accentTint,
                    elevation: .resting,
                    padding: Space.md
                ) {
                    Toggle(isOn: $model.checkInsPaused) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.checkInsPaused ? "Check-ins off" : "Check-ins on")
                                .font(Typography.data(16, weight: .semibold))
                                .foregroundStyle(Palette.ink)
                            Text(model.checkInsPaused ? "No nudges." : "Nudges when behind.")
                                .font(Typography.data(12))
                                .foregroundStyle(Palette.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .tint(Palette.accent)
                }
                .appearIn(3)

                if let error = model.error {
                    SettingsErrorBanner(message: error)
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.md)
            .padding(.bottom, Space.xl)
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Rhythm")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Palette.background, for: .navigationBar)
        .saveWhenDirty(model)
        .onDisappear { model.revertToOriginal() }
        .animation(Motion.settle, value: model.checkInsPaused)
    }
}

private struct CheckInTimeRow: View {
    let title: String
    let symbol: String
    @Binding var minutes: Int

    var body: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Palette.accent)
                .frame(width: 34, height: 34)
                .background(Palette.accentTint, in: Circle())

            Text(title)
                .font(Typography.data(16, weight: .semibold))
                .foregroundStyle(Palette.ink)

            Spacer(minLength: Space.xs)

            DatePicker("", selection: minutesBinding($minutes), displayedComponents: .hourAndMinute)
                .labelsHidden()
                .tint(Palette.accent)
        }
        .padding(Space.md)
    }
}

private struct QuietTimeField: View {
    let label: String
    @Binding var minutes: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(label).sectionLabelStyle()
            DatePicker("", selection: minutesBinding($minutes), displayedComponents: .hourAndMinute)
                .labelsHidden()
                .tint(Palette.accent)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceSunk.opacity(0.75), in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }
}

struct HealthSettingsView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Form {
            Section {
                if env.health.connected {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Palette.dayOnTrack)
                    Text("Reads HRV, resting heart rate, and weight. Raw data stays on this phone.")
                        .font(Typography.data(13))
                        .foregroundStyle(Palette.inkSoft)
                } else {
                    Button("Connect") { Task { await env.health.connect() } }
                    Text("Used for Smart mode.")
                        .font(Typography.data(13))
                        .foregroundStyle(Palette.inkSoft)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .navigationTitle("Health")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AccountSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Bindable var model: SettingsViewModel
    @State private var confirmingDelete = false

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text("Account")
                            .font(Typography.display(32))
                            .foregroundStyle(Palette.ink)
                    }
                    .appearIn(0)

                    if !model.enforcementEnabled {
                        ManagerNote(text: enforcementNote(model.enforcementDisabledReason))
                            .appearIn(1)
                    }

                    VStack(alignment: .leading, spacing: Space.sm) {
                        Button { env.auth.signOut() } label: {
                            HStack(spacing: Space.sm) {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Palette.inkSoft)
                                    .frame(width: 38, height: 38)
                                    .background(Palette.surfaceSunk, in: Circle())
                                Text("Sign out")
                                    .font(Typography.data(16, weight: .semibold))
                                    .foregroundStyle(Palette.ink)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Palette.inkFaint)
                            }
                            .padding(Space.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background {
                                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                    .fill(Palette.surface)
                                    .elevation(.resting)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                            .strokeBorder(Palette.hairline)
                                    )
                            }
                        }
                        .buttonStyle(PressableCard())
                    }
                    .appearIn(2)

                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text("Data").sectionLabelStyle()

                        Card(tint: Palette.surfaceRaised, padding: Space.md) {
                            VStack(alignment: .leading, spacing: Space.md) {
                                HStack(spacing: Space.sm) {
                                    Image(systemName: "archivebox.fill")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(Palette.inkSoft)
                                        .frame(width: 38, height: 38)
                                        .background(Palette.surfaceSunk, in: Circle())
                                    Text("Account data")
                                        .font(Typography.data(13))
                                        .foregroundStyle(Palette.inkSoft)
                                }

                                Divider().overlay(Palette.hairline)

                                Button(role: .destructive) {
                                    confirmingDelete = true
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text("Delete account")
                                                .font(Typography.data(15, weight: .semibold))
                                            Text("Erase all data")
                                                .font(Typography.data(12))
                                                .foregroundStyle(Palette.inkFaint)
                                        }
                                        Spacer()
                                        Image(systemName: "trash")
                                            .font(.system(size: 14, weight: .semibold))
                                    }
                                    .foregroundStyle(Palette.accentDeep)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(model.deleting)
                            }
                        }
                    }
                    .appearIn(3)

                    LegalSection()
                        .appearIn(4)

                    if model.deleting {
                        HStack(spacing: Space.xs) {
                            ProgressView()
                                .tint(Palette.accent)
                            Text("Deleting…")
                                .font(Typography.data(13))
                                .foregroundStyle(Palette.inkSoft)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    if let error = model.error {
                        SettingsErrorBanner(message: error)
                    }
                }
                .padding(.horizontal, Space.gutter)
                .padding(.top, Space.md)
                .padding(.bottom, Space.xl)
            }
            .disabled(confirmingDelete)

            if confirmingDelete {
                Palette.scrim
                    .ignoresSafeArea()
                    .onTapGesture {
                        guard !model.deleting else { return }
                        confirmingDelete = false
                    }
                    .transition(.opacity)

                DeleteAccountConfirmation(
                    deleting: model.deleting,
                    cancel: { confirmingDelete = false },
                    confirm: {
                        Task {
                            await model.deleteAccount()
                            confirmingDelete = false
                        }
                    }
                )
                .padding(.horizontal, Space.sm)
                .padding(.bottom, Space.xs)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Palette.background, for: .navigationBar)
        .animation(Motion.sheet, value: confirmingDelete)
    }
}

/// Privacy policy, terms, support, and version — required for App Store review
/// (plan §4). The pages are served by the backend at /privacy and /terms.
private struct LegalSection: View {
    private var privacyURL: URL { APIConfig.baseURL.appending(path: "privacy") }
    private var termsURL: URL { APIConfig.baseURL.appending(path: "terms") }
    private var supportURL: URL { URL(string: "mailto:support@setpoint.app")! }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "—"
        let b = info?["CFBundleVersion"] as? String ?? "—"
        return "Version \(v) (\(b))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Legal & support").sectionLabelStyle()

            VStack(spacing: 0) {
                row("Privacy Policy", systemImage: "hand.raised", url: privacyURL)
                Divider().overlay(Palette.hairline).padding(.leading, 46)
                row("Terms of Service", systemImage: "doc.text", url: termsURL)
                Divider().overlay(Palette.hairline).padding(.leading, 46)
                row("Contact support", systemImage: "envelope", url: supportURL)
            }
            .background {
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(Palette.surface)
                    .elevation(.resting)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .strokeBorder(Palette.hairline)
                    )
            }

            Text(versionText)
                .font(Typography.data(11))
                .foregroundStyle(Palette.inkFaint)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, Space.xs)
        }
    }

    private func row(_ title: String, systemImage: String, url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: Space.sm) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.inkSoft)
                    .frame(width: 30)
                Text(title)
                    .font(Typography.data(15, weight: .medium))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.inkFaint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct DeleteAccountConfirmation: View {
    let deleting: Bool
    let cancel: () -> Void
    let confirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(alignment: .top) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Palette.accentDeep)
                    .frame(width: 42, height: 42)
                    .background(Palette.accentTint, in: Circle())

                Spacer()

                Button(action: cancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Palette.inkSoft)
                        .frame(width: 34, height: 34)
                        .background(Palette.surfaceSunk, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(deleting)
                .accessibilityLabel("Close")
            }

            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Delete account?")
                    .font(Typography.display(28))
                    .foregroundStyle(Palette.ink)
                Text("Removes all data permanently. Can’t be undone.")
                    .font(Typography.data(14))
                    .foregroundStyle(Palette.inkSoft)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: Space.xs) {
                Button(action: confirm) {
                    HStack(spacing: Space.xs) {
                        if deleting {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(deleting ? "Deleting…" : "Delete account")
                    }
                    .font(Typography.data(16, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Palette.accentDeep, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(deleting)

                Button("Keep account", action: cancel)
                    .font(Typography.data(15, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Palette.surfaceSunk, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .buttonStyle(.plain)
                    .disabled(deleting)
            }
        }
        .padding(Space.md)
        .background {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(Palette.surfaceRaised)
                .elevation(.lifted)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                        .strokeBorder(Palette.hairline)
                )
        }
    }
}

private struct SettingsErrorBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(Typography.data(13))
            .foregroundStyle(Palette.accentDeep)
            .padding(Space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.accentTint, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }
}

private extension View {
    func saveWhenDirty(_ model: SettingsViewModel) -> some View {
        toolbar {
            if model.dirty {
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.saving ? "Saving…" : "Save") { Task { await model.save() } }
                        .disabled(model.saving)
                }
            }
        }
    }
}

private func minutesBinding(_ minutes: Binding<Int>) -> Binding<Date> {
    Binding(
        get: {
            var c = DateComponents()
            c.hour = minutes.wrappedValue / 60
            c.minute = minutes.wrappedValue % 60
            return Calendar.current.date(from: c) ?? .now
        },
        set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            minutes.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }
    )
}

/// Selectable allergen / restriction chips — common ones plus anything already set.
struct RestrictionChips: View {
    @Binding var selected: [String]

    private let common = ["Dairy", "Eggs", "Gluten", "Peanuts", "Tree nuts", "Soy", "Fish", "Shellfish", "Sesame", "Vegetarian", "Vegan"]

    private var options: [String] {
        common + selected.filter { s in !common.contains { $0.caseInsensitiveCompare(s) == .orderedSame } }
    }

    var body: some View {
        FlexWrap(spacing: 8, lineSpacing: 8) {
            ForEach(options, id: \.self) { option in
                let isOn = selected.contains { $0.caseInsensitiveCompare(option) == .orderedSame }
                Button {
                    if isOn {
                        selected.removeAll { $0.caseInsensitiveCompare(option) == .orderedSame }
                    } else {
                        selected.append(option)
                    }
                } label: {
                    Text(option)
                        .font(Typography.data(14, weight: .medium))
                        .foregroundStyle(isOn ? .white : Palette.inkSoft)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(isOn ? Palette.ink : Palette.surfaceSunk, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}
