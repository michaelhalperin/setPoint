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
            subtitle: "· this week",
            accessory: AnyView(RoundIconButton("plus", label: "Add a session") { adding = true }),
            showsBack: !isTabRoot,
            glow: .haze
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
        HStack(spacing: 10) {
            statTile("Fueled", value: "\(week.fueledWell.good)", unit: "of \(week.fueledWell.total) sessions")
            statTile("Extra food earned", value: "+\(week.days.reduce(0) { $0 + $1.bumpKcal }.formatted())", unit: "kcal")
        }
        .appearIn(1, rise: 14)

        VStack(spacing: 6) {
            ForEach(Array(week.days.enumerated()), id: \.element.id) { index, day in
                dayRow(day, week: week)
                    .appearIn(2 + index, rise: 10)
            }
        }

        howItWorks(week).appearIn(9, rise: 14)
    }

    private func statTile(_ label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Typography.mono(10))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(Palette.inkFaint)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(Typography.data(24, weight: .light))
                    .foregroundStyle(Palette.ink)
                Text(unit)
                    .font(Typography.data(13, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(radius: 20)
    }

    /// One row per day: the session (or rest) and what it adds. Today opens to
    /// show the fuel around the session.
    private func dayRow(_ day: TrainingWeekResponse.Day, week: TrainingWeekResponse) -> some View {
        let isToday = day.date == todayISO
        let open = openDay == day.date || (openDay == nil && isToday && !day.rest)
        return Button {
            withAnimation(Motion.settle) { openDay = open ? "" : day.date }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Text(weekdayShort(day.date))
                        .font(Typography.mono(11))
                        .foregroundStyle(isToday ? Palette.hazeSoft : Palette.inkFaint)
                        .frame(width: 34, alignment: .leading)
                    Text(dayTitle(day))
                        .font(Typography.data(15, weight: .regular))
                        .foregroundStyle(day.rest ? Palette.inkSoft : Palette.ink)
                    Spacer(minLength: 8)
                    Text(day.rest ? "rest" : "+\(day.bumpKcal) kcal")
                        .font(Typography.data(12, weight: .regular))
                        .foregroundStyle(day.rest ? Palette.inkFaint : Palette.hazeSoft)
                }
                if open, isToday {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(week.today.timeline) { event in
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(event.kind == "workout" ? Palette.haze : event.kind == "refuel" ? Palette.hazeSoft : Palette.amber)
                                    .frame(width: 7, height: 7)
                                Text(formatMinutes(event.atMin))
                                    .font(Typography.mono(11))
                                    .foregroundStyle(Palette.inkSoft)
                                    .frame(width: 44, alignment: .leading)
                                Text(event.label)
                                    .font(Typography.data(14, weight: .regular))
                                    .foregroundStyle(Palette.ink)
                                Spacer(minLength: 0)
                                if event.nudge == true {
                                    Text("nudge")
                                        .font(Typography.mono(10))
                                        .foregroundStyle(Palette.hazeSoft)
                                }
                            }
                        }
                        Text("\(week.today.targetKcal.formatted()) kcal today = \(week.today.baseKcal.formatted()) + \(week.today.bumpKcal)")
                            .font(Typography.mono(11))
                            .foregroundStyle(Palette.inkFaint)
                            .padding(.top, 2)
                    }
                    .padding(.leading, 46)
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(
                radius: 20,
                fill: isToday ? Palette.haze.opacity(0.08) : (day.rest ? Color.white.opacity(0.025) : Palette.glass),
                stroke: isToday ? Palette.haze.opacity(0.35) : Palette.hairline
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCard())
        .accessibilityLabel("\(weekdayShort(day.date)), \(dayTitle(day)), \(day.rest ? "rest" : "plus \(day.bumpKcal) calories")")
    }

    private var todayISO: String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: .now)
    }

    private func dayTitle(_ day: TrainingWeekResponse.Day) -> String {
        guard let first = day.workouts.first else { return day.rest ? "Rest" : "Training" }
        let kind: String
        switch first.kind {
        case "CARDIO": kind = "Cardio"
        case "MIXED": kind = "Mixed"
        default: kind = "Strength"
        }
        return "\(kind) · \(formatMinutes(first.startMin))"
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

    private func weekdayShort(_ iso: String) -> String {
        let parts = iso.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2])
        else { return "·" }
        var comps = DateComponents()
        comps.year = y
        comps.month = m
        comps.day = d
        guard let date = Calendar.current.date(from: comps) else { return "·" }
        return date.formatted(.dateTime.weekday(.abbreviated))
    }
}

/// The Training tab without a subscription: what it does, and the way in.
struct TrainingLockedView: View {
    @State private var showingPaywall = false

    var body: some View {
        SettingsScreen(title: "Train", subtitle: "· with Pro", showsBack: false, glow: .haze) {
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
