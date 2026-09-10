import SwiftUI

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var model: SettingsViewModel?
    @State private var confirmingDelete = false

    init(previewModel: SettingsViewModel? = nil) {
        _model = State(initialValue: previewModel)
    }

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView()
            }
        }
        .task {
            if model == nil {
                let vm = SettingsViewModel(
                    api: env.api,
                    onUnauthorized: { env.auth.handleUnauthorized() },
                    onDeleted: { env.auth.signOut() }
                )
                model = vm
                await vm.load()
            }
        }
    }

    @ViewBuilder
    private func content(_ model: SettingsViewModel) -> some View {
        @Bindable var model = model
        switch model.phase {
        case .loading:
            ProgressView()
        case let .failed(message):
            ContentUnavailableView("Couldn't load settings", systemImage: "gearshape", description: Text(message))
        case .loaded:
            Form {
                Section("Goal") {
                    Picker("Goal", selection: $model.goal) {
                        ForEach(Goal.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if model.goal.hasWeightTarget {
                        HStack {
                            Text("Target weight")
                            Spacer()
                            TextField("—", value: $model.targetWeightKg, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 64)
                            Text("kg").foregroundStyle(Palette.inkFaint)
                        }
                        Picker("Pace", selection: $model.pace) {
                            ForEach(GoalPace.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        if let current = model.currentWeightKg {
                            Text("Now around \(Int(current.rounded())) kg · \(model.pace.blurb(for: model.goal)). SetPoint sets the daily calories from this.")
                                .font(Typography.data(12))
                                .foregroundStyle(Palette.inkFaint)
                        }
                    } else {
                        Text("No deficit or surplus — SetPoint keeps you at maintenance.")
                            .font(Typography.data(12))
                            .foregroundStyle(Palette.inkFaint)
                    }

                    Text(model.mode == "SMART" ? "Smart mode — biosignal-aware." : "Basic mode — scheduled check-ins.")
                        .font(Typography.data(12))
                        .foregroundStyle(Palette.inkFaint)
                }

                if model.mode == "SMART", env.health.isAvailable {
                    Section("Health") {
                        if env.health.connected {
                            Label("Connected", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Palette.dayOnTrack)
                        } else {
                            Button("Connect Health") { Task { await env.health.connect() } }
                        }
                    }
                }

                Section("Daily targets") {
                    Stepper("Calories: \(model.kcalTarget)", value: $model.kcalTarget, in: 1200 ... 6000, step: 50)
                    Stepper(
                        "Protein: \(model.proteinTarget.map { "\($0) g" } ?? "—")",
                        value: Binding(get: { model.proteinTarget ?? 0 }, set: { model.proteinTarget = $0 }),
                        in: 0 ... 350, step: 5
                    )
                }

                Section("Meal times") {
                    minutesRow("Breakfast", $model.mealTimes.breakfastMin)
                    minutesRow("Lunch", $model.mealTimes.lunchMin)
                    minutesRow("Dinner", $model.mealTimes.dinnerMin)
                }

                Section("Quiet hours") {
                    minutesRow("From", $model.quietHours.startMin)
                    minutesRow("Until", $model.quietHours.endMin)
                }

                Section {
                    Toggle("Pause check-ins", isOn: $model.checkInsPaused)
                        .tint(Palette.accent)
                } footer: {
                    Text("SetPoint keeps tracking your intake, but won't nudge you to eat.")
                }

                Section("Avoiding") {
                    RestrictionChips(selected: $model.restrictions)
                }

                if !model.enforcementEnabled {
                    Section {
                        Text(enforcementNote(model.enforcementDisabledReason))
                            .font(Typography.data(13))
                            .foregroundStyle(Palette.inkSoft)
                    }
                }

                Section {
                    Button("Sign out") { env.auth.signOut() }
                    Button("Delete account", role: .destructive) { confirmingDelete = true }
                }

                if let error = model.error {
                    Section { Text(error).foregroundStyle(Palette.accent).font(Typography.data(13)) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .appearIn()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if model.dirty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(model.saving ? "Saving…" : "Save") { Task { await model.save() } }
                            .disabled(model.saving)
                    }
                }
            }
            .confirmationDialog(
                "Delete your account?",
                isPresented: $confirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete everything", role: .destructive) { Task { await model.deleteAccount() } }
                Button("Keep my account", role: .cancel) {}
            } message: {
                Text("This permanently removes your profile, meals, and check-ins. It can't be undone.")
            }
        }
    }

    private func minutesRow(_ label: String, _ minutes: Binding<Int>) -> some View {
        DatePicker(
            label,
            selection: Binding(
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
            ),
            displayedComponents: .hourAndMinute
        )
    }

    private func enforcementNote(_ reason: String?) -> String {
        switch reason {
        case "EATING_DISORDER_SCREEN":
            return "SetPoint is tracking your intake without pushing you to eat. If eating is hard right now, a professional can help."
        case "MEDICAL_SUPERVISION":
            return "SetPoint is tracking your intake without pushing you to eat — that's your care team's call, not an app's."
        default:
            return "Check-ins are off."
        }
    }
}

/// Selectable allergen / restriction chips — common ones plus anything already set.
private struct RestrictionChips: View {
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

#if DEBUG
#Preview {
    NavigationStack { SettingsView() }
        .environment(AppEnvironment.preview())
}
#endif
