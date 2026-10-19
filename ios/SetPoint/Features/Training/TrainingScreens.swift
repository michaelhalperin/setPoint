import SwiftUI

struct TrainingScreen: View {
    var preview: TrainingWeekResponse? = nil
    /// Shown as the Training tab rather than pushed from somewhere.
    var isTabRoot = false

    @Environment(AppEnvironment.self) private var env
    @State private var week: TrainingWeekResponse?
    @State private var error: String?
    @State private var adding = false
    @State private var newKind = "STRENGTH"
    @State private var newDuration = 60
    @State private var newStart = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var openDay: String?

    var body: some View {
        SettingsScreen(
            title: "Train",
            accessory: AnyView(RoundIconButton("plus", label: "Add a session") { adding = true }),
            showsBack: !isTabRoot,
            glow: .haze,
            showsHeadline: false
        ) {
            if let week {
                content(week)
            } else if let error {
                SettingsErrorBanner(message: error)
                ActionButton(title: "Try again", kind: .secondary) { Task { await load() } }
            } else {
                BusyDots(tint: Palette.hazeSoft)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .task { await load() }
        .sheet(isPresented: $adding) { addSheet }
    }

    @ViewBuilder
    private func content(_ week: TrainingWeekResponse) -> some View {
        Text(weekLine(week))
            .font(Typography.mono(11))
            .tracking(1.3)
            .foregroundStyle(Palette.inkFaint)

        TrainTodayCard(today: week.today)
            .appearIn(1, rise: 14)

        TrainWeekCard(week: week, todayISO: todayISO, selected: $openDay)
            .appearIn(2, rise: 14)

        healthRow
            .appearIn(3, rise: 14)

        howItWorks(week).appearIn(4, rise: 14)
    }

    private var todayISO: String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: .now)
    }

    /// "13–19 OCT · 4 SESSIONS"
    private func weekLine(_ week: TrainingWeekResponse) -> String {
        let sessions = week.days.reduce(0) { $0 + $1.workouts.count }
        var utc = Date.FormatStyle.dateTime
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        var range = ""
        if let first = week.days.first.flatMap({ WeekStation.parse($0.date) }),
           let last = week.days.last.flatMap({ WeekStation.parse($0.date) }) {
            range = "\(first.formatted(utc.day()))–\(last.formatted(utc.day().month(.abbreviated))) · "
        }
        return (range + (sessions == 1 ? "1 session" : "\(sessions) sessions")).uppercased()
    }

    /// Where sessions come from, and a way to add one by hand.
    private var healthRow: some View {
        Button { adding = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(hex: 0xFF375F))
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text(env.health.connected ? "Sessions come from Apple Health" : "Apple Health is off")
                        .font(Typography.data(15, weight: .regular))
                        .foregroundStyle(Palette.ink)
                    Text(env.health.connected ? "Did one without your watch? Add it." : "Add sessions here, or turn it on in You.")
                        .font(Typography.data(12, weight: .regular))
                        .foregroundStyle(Palette.inkSoft)
                }
                Spacer(minLength: 8)
                Text("Add")
                    .font(Typography.data(13, weight: .medium))
                    .foregroundStyle(Palette.hazeSoft)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .glass(radius: 22, fill: Color.white.opacity(0.03))
        }
        .buttonStyle(PressableCard())
    }

    private func howItWorks(_ week: TrainingWeekResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How it works").sectionLabelStyle()
            GlassList {
                Toggle(isOn: addCaloriesBinding(week)) {
                    Text("Add calories on training days")
                        .font(Typography.data(15, weight: .regular))
                        .foregroundStyle(Palette.ink)
                }
                .tint(Palette.haze)
                .padding(.vertical, 14)
                ListDivider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nudge before a session if you haven’t eaten")
                        .font(Typography.data(15, weight: .regular))
                        .foregroundStyle(Palette.ink)
                    SegmentedPills(
                        options: [0, 60, 90, 120],
                        selection: nudgeBinding(week),
                        title: { $0 == 0 ? "Off" : $0 == 120 ? "2 h" : "\($0) min" }
                    )
                }
                .padding(.vertical, 14)
                ListDivider()
                HStack {
                    Text("Apple Health workouts")
                        .font(Typography.data(15, weight: .regular))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Text(env.health.connected ? "On" : "Off")
                        .font(Typography.data(13, weight: .regular))
                        .foregroundStyle(env.health.connected ? Palette.positive : Palette.inkSoft)
                }
                .frame(minHeight: 50)
            }
        }
    }

    private var addSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Headline("Add a session.", tail: "I’ll plan food around it.", size: 30)
            SegmentedPills(
                options: ["STRENGTH", "CARDIO", "MIXED"],
                selection: $newKind,
                title: { $0 == "CARDIO" ? "Cardio" : $0 == "MIXED" ? "Mixed" : "Strength" }
            )
            GlassList {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(newStart.formatted(.dateTime.weekday(.wide)))
                            .font(Typography.mono(10))
                            .tracking(1.2)
                            .textCase(.uppercase)
                            .foregroundStyle(Palette.inkFaint)
                        Text("Starts at")
                            .font(Typography.data(15, weight: .regular))
                            .foregroundStyle(Palette.ink)
                    }
                    Spacer()
                    DatePicker("", selection: $newStart, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .tint(Palette.hazeSoft)
                }
                .padding(.vertical, 10)
            }
            SegmentedPills(
                options: [30, 45, 60, 90],
                selection: $newDuration,
                title: { "\($0) min" }
            )
            ActionButton(title: "Add session", kind: .primary, symbol: "plus") {
                Task { await addPlanned() }
            }
        }
        .padding(Space.gutter)
        .padding(.top, Space.xs)
        .presentationDetents([.height(440)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.sheet)
        .presentationCornerRadius(32)
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
            self.error = UserFacingError.message(for: error, fallback: "Couldn’t load your training week.")
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
            self.error = UserFacingError.message(for: error, fallback: "Couldn’t add that session. Try again.")
        }
    }
}

/// The Training tab without a subscription: what it does, and the way in.
struct TrainingLockedView: View {
    @State private var showingPaywall = false

    var body: some View {
        SettingsScreen(title: "Train", showsBack: false, glow: .haze, showsHeadline: false) {
            VStack(alignment: .leading, spacing: Space.md) {
                lockedRow("figure.strengthtraining.traditional", "Training days get more food", "Your target rises with the session, so the extra burn doesn’t widen the gap.")
                lockedRow("bolt.heart", "Refuel right after", "When Apple Health saves a workout, a refuel check-in follows within minutes.")
                lockedRow("fork.knife", "Eat before you train", "A nudge before a planned session if you haven’t eaten.")
            }
            .appearIn(2)
            ActionButton(title: "See Pro") { showingPaywall = true }
                .appearIn(3)
            Text("Meal check-ins, top-ups and the evening close stay free.")
                .font(Typography.data(13))
                .foregroundStyle(Palette.inkSoft)
                .appearIn(4)
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView().presentationDetents([.large])
        }
    }

    private func lockedRow(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: Space.sm) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Palette.hazeSoft)
                .frame(width: 38, height: 38)
                .background(Palette.haze.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Typography.data(15, weight: .medium))
                    .foregroundStyle(Palette.ink)
                Text(detail)
                    .font(Typography.data(14))
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
                .fill(Color.white.opacity(0.18))
                .frame(width: 40, height: 5)
                .padding(.top, 10)

            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Palette.haze.opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: 110))
                    .frame(width: 220, height: 220)
                OrbRing(progress: ringProgress, lineWidth: 5, tint: Palette.hazeSoft)
                    .frame(width: 168, height: 168)
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
            .frame(width: 200, height: 200)

            Headline("You trained.", tail: "Eat something now.", size: 30, alignment: .center)

            if let rx = checkIn.prescription {
                PrescriptionCard(prescription: rx)
            }

            ActionButton(title: "I had this", kind: .primary, action: onHadThis)
            ActionButton(title: "Dinner at \(formatMinutes(dinnerMin)) covers it", kind: .secondary, action: onCoveredByDinner)

            Button("Not now", action: onDismiss)
                .font(Typography.data(15, weight: .bold))
                .foregroundStyle(Palette.inkSoft)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.bottom, Space.lg)
        .frame(maxWidth: .infinity)
        .background(Palette.sheet.ignoresSafeArea())
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
    static var sample: TrainingWeekResponse {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        // Six days back to today: lift, rest, run, rest, lift, rest, run planned today.
        let plan: [(kind: String, source: String, startMin: Int, duration: Int, bump: Int)?] = [
            ("STRENGTH", "HEALTHKIT", 1050, 60, 280), nil, ("CARDIO", "HEALTHKIT", 1020, 50, 420), nil,
            ("STRENGTH", "HEALTHKIT", 1080, 55, 260), nil, ("CARDIO", "PLANNED", 1020, 60, 350),
        ]
        let days: [Day] = plan.enumerated().map { i, session in
            let date = f.string(from: Calendar.current.date(byAdding: .day, value: i - 6, to: .now) ?? .now)
            guard let session else { return .init(date: date, bumpKcal: 0, rest: true, workouts: []) }
            return .init(
                date: date,
                bumpKcal: session.bump,
                rest: false,
                workouts: [.init(id: "w\(i)", kind: session.kind, source: session.source, start: "\(date)T15:00:00Z", startMin: session.startMin, durationMin: session.duration, activeKcal: session.source == "HEALTHKIT" ? session.bump + 60 : nil)]
            )
        }
        let today = days[6].workouts
        return TrainingWeekResponse(
            addCalories: true,
            preWorkoutNudgeMin: 90,
            fueledWell: .init(good: 3, total: 4),
            days: days,
            today: .init(
                baseKcal: 3100,
                bumpKcal: 350,
                targetKcal: 3450,
                workouts: today,
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
}
#endif
