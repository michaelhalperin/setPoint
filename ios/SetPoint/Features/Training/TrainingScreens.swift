import SwiftUI

struct TrainingScreen: View {
    var preview: TrainingWeekResponse? = nil

    @Environment(AppEnvironment.self) private var env
    @State private var week: TrainingWeekResponse?
    @State private var error: String?
    @State private var adding = false
    @State private var newKind = "STRENGTH"
    @State private var newDuration = 60
    @State private var newStart = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: Date()) ?? Date()

    var body: some View {
        SettingsScreen(title: "Training", subtitle: "Eat around the session. Calories follow the work.") {
            if let week {
                content(week)
            } else if let error {
                SettingsErrorBanner(message: error)
                ActionButton(title: "Try again", kind: .secondary) { Task { await load() } }
            } else {
                ProgressView().tint(Palette.accent)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .task { await load() }
        .sheet(isPresented: $adding) { addSheet }
    }

    @ViewBuilder
    private func content(_ week: TrainingWeekResponse) -> some View {
        weekStrip(week).appearIn(2)
        todayCard(week).appearIn(3)
        fuelTimeline(week).appearIn(4)
        howItWorks(week).appearIn(5)
        if week.fueledWell.total > 0 {
            Text("Fueled well on \(week.fueledWell.good) of your last \(week.fueledWell.total) training days")
                .font(Typography.data(14, weight: .semibold))
                .foregroundStyle(Palette.inkSoft)
                .appearIn(6)
        }
        ActionButton(title: "Add a session", kind: .secondary) { adding = true }
            .appearIn(7)
    }

    private func weekStrip(_ week: TrainingWeekResponse) -> some View {
        HStack(spacing: 6) {
            ForEach(week.days) { day in
                VStack(spacing: 6) {
                    Text(weekdayLetter(day.date))
                        .font(Typography.data(11, weight: .bold))
                        .foregroundStyle(Palette.inkFaint)
                    ZStack {
                        Circle()
                            .fill(day.rest ? Palette.surfaceSunk : Palette.ink)
                            .frame(width: 36, height: 36)
                        if day.rest {
                            Text("R")
                                .font(Typography.data(11, weight: .heavy))
                                .foregroundStyle(Palette.inkSoft)
                        } else {
                            Image(systemName: "dumbbell.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Palette.background)
                        }
                    }
                    Text(day.rest ? "rest" : "+\(day.bumpKcal)")
                        .font(Typography.data(10, weight: .bold))
                        .foregroundStyle(Palette.inkSoft)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func todayCard(_ week: TrainingWeekResponse) -> some View {
        let t = week.today
        return VStack(alignment: .leading, spacing: 8) {
            Text("Today").sectionLabelStyle(Palette.background.opacity(0.8))
            Text(sessionTitle(t))
                .font(Typography.display(28))
                .foregroundStyle(Palette.background)
            Text("\(t.targetKcal.formatted()) kcal = \(t.baseKcal.formatted()) + \(t.bumpKcal)")
                .font(Typography.data(15, weight: .bold))
                .foregroundStyle(Palette.background.opacity(0.85))
                .monospacedDigit()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.accent, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func fuelTimeline(_ week: TrainingWeekResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Today's fuel").sectionLabelStyle()
            SettingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(week.today.timeline) { event in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(event.kind == "workout" ? Palette.ink : Palette.accent)
                                .frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.label)
                                    .font(Typography.data(15, weight: .bold))
                                    .foregroundStyle(Palette.ink)
                                Text(formatMinutes(event.atMin))
                                    .font(Typography.data(13))
                                    .foregroundStyle(Palette.inkSoft)
                                    .monospacedDigit()
                            }
                            Spacer()
                            if event.nudge == true {
                                Text("Nudge")
                                    .font(Typography.data(10, weight: .heavy))
                                    .foregroundStyle(Palette.accentDeep)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Palette.accentTint, in: Capsule())
                            }
                        }
                    }
                }
            }
        }
    }

    private func howItWorks(_ week: TrainingWeekResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How it works").sectionLabelStyle()
            SettingsCard(padding: 0) {
                Toggle(isOn: addCaloriesBinding(week)) {
                    Text("Add calories on training days")
                        .font(Typography.data(15, weight: .bold))
                        .foregroundStyle(Palette.ink)
                }
                .tint(Palette.accent)
                .padding(16)
                Divider().overlay(Palette.hairline).padding(.leading, 16)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pre-workout nudge")
                        .font(Typography.data(15, weight: .bold))
                        .foregroundStyle(Palette.ink)
                    Picker("Nudge", selection: nudgeBinding(week)) {
                        Text("Off").tag(0)
                        Text("60 min").tag(60)
                        Text("90 min").tag(90)
                        Text("2 hours").tag(120)
                    }
                    .pickerStyle(.segmented)
                }
                .padding(16)
                Divider().overlay(Palette.hairline).padding(.leading, 16)
                SettingsRow(symbol: "heart.fill", title: "Apple Health workouts", value: env.health.connected ? "On" : "Off")
            }
        }
    }

    private var addSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Picker("Kind", selection: $newKind) {
                    Text("Strength").tag("STRENGTH")
                    Text("Cardio").tag("CARDIO")
                    Text("Mixed").tag("MIXED")
                }
                .pickerStyle(.segmented)
                DatePicker("Starts", selection: $newStart, displayedComponents: [.date, .hourAndMinute])
                Stepper("\(newDuration) min", value: $newDuration, in: 20...180, step: 5)
                ActionButton(title: "Save session", kind: .primary) {
                    Task { await addPlanned() }
                }
                Spacer()
            }
            .padding(Space.gutter)
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Add a session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { adding = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func addCaloriesBinding(_ week: TrainingWeekResponse) -> Binding<Bool> {
        Binding(
            get: { week.addCalories },
            set: { value in
                Task {
                    _ = try? await env.api.patch("/api/settings", SettingsPatch(training: .init(addCalories: value)))
                    await load()
                }
            }
        )
    }

    private func nudgeBinding(_ week: TrainingWeekResponse) -> Binding<Int> {
        Binding(
            get: { week.preWorkoutNudgeMin ?? 0 },
            set: { value in
                Task {
                    _ = try? await env.api.patch(
                        "/api/settings",
                        SettingsPatch(training: .init(preWorkoutNudgeMin: value))
                    )
                    await load()
                }
            }
        )
    }

    private func load() async {
        if let preview {
            week = preview
            return
        }
        do {
            week = try await env.api.get("/api/workouts")
            error = nil
            await env.health.uploadWorkouts()
        } catch {
            self.error = UserFacingError.message(for: error)
        }
    }

    private func addPlanned() async {
        struct Body: Encodable {
            let kind: String
            let start: Date
            let durationMin: Int
        }
        do {
            try await env.api.post("/api/workouts/planned", Body(kind: newKind, start: newStart, durationMin: newDuration))
            adding = false
            await load()
        } catch {
            self.error = UserFacingError.message(for: error)
        }
    }

    private func sessionTitle(_ today: TrainingWeekResponse.Today) -> String {
        guard let first = today.workouts.first else { return "Rest day" }
        switch first.kind {
        case "CARDIO": return "Cardio"
        case "MIXED": return "Mixed"
        default: return "Strength"
        }
    }

    private func weekdayLetter(_ iso: String) -> String {
        let parts = iso.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2])
        else { return "·" }
        var comps = DateComponents()
        comps.year = y
        comps.month = m
        comps.day = d
        guard let date = Calendar.current.date(from: comps) else { return "·" }
        return date.formatted(.dateTime.weekday(.narrow))
    }
}

struct RefuelSheet: View {
    let checkIn: HomeResponse.ActiveCheckIn
    let dinnerMin: Int
    let remainingSeconds: Int
    let onHadThis: () -> Void
    let onCoveredByDinner: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Capsule()
                .fill(Palette.inkFaint)
                .frame(width: 40, height: 5)
                .padding(.top, 10)

            ZStack {
                Circle()
                    .stroke(Palette.surfaceSunk, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: ringProgress)
                    .stroke(Palette.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text(clock)
                        .font(Typography.data(36, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.ink)
                    Text("left to refuel")
                        .font(Typography.data(13, weight: .semibold))
                        .foregroundStyle(Palette.inkSoft)
                }
            }
            .frame(width: 168, height: 168)

            Text("You trained. Eat something now.")
                .font(Typography.display(28))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)

            if let rx = checkIn.prescription {
                PrescriptionCard(prescription: rx)
            }

            ActionButton(title: "I had this", kind: .primary, action: onHadThis)
            Button(action: onCoveredByDinner) {
                Text("Dinner at \(formatMinutes(dinnerMin)) covers it")
                    .font(Typography.data(16, weight: .bold))
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Palette.hairline, lineWidth: 1.5)
                    )
            }
            .buttonStyle(PressableCard())

            Button("Not now", action: onDismiss)
                .font(Typography.data(15, weight: .bold))
                .foregroundStyle(Palette.inkSoft)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.bottom, Space.lg)
        .frame(maxWidth: .infinity)
        .background(Palette.background.ignoresSafeArea())
    }

    private var ringProgress: CGFloat {
        CGFloat(min(1, max(0, Double(remainingSeconds) / (45 * 60))))
    }

    private var clock: String {
        let m = max(0, remainingSeconds) / 60
        let s = max(0, remainingSeconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}

#if DEBUG
extension TrainingWeekResponse {
    static let sample = TrainingWeekResponse(
        addCalories: true,
        preWorkoutNudgeMin: 90,
        fueledWell: .init(good: 4, total: 5),
        days: (0..<7).map { i in
            .init(
                date: String(format: "2026-09-%02d", 14 + i),
                bumpKcal: i == 0 ? 350 : 0,
                rest: i != 0,
                workouts: i == 0
                    ? [.init(id: "w1", kind: "STRENGTH", source: "PLANNED", start: "2026-09-14T15:00:00Z", startMin: 1020, durationMin: 60, activeKcal: 350)]
                    : []
            )
        },
        today: .init(
            baseKcal: 3120,
            bumpKcal: 350,
            targetKcal: 3470,
            workouts: [.init(id: "w1", kind: "STRENGTH", source: "PLANNED", start: "2026-09-14T15:00:00Z", startMin: 1020, durationMin: 60, activeKcal: 350)],
            dinnerMin: 1170,
            timeline: [
                .init(kind: "before", atMin: 930, label: "Before you train", nudge: true),
                .init(kind: "workout", atMin: 1020, label: "Workout"),
                .init(kind: "refuel", atMin: 1080, label: "Refuel window"),
                .init(kind: "dinner", atMin: 1170, label: "Dinner"),
            ]
        )
    )
}
#endif
