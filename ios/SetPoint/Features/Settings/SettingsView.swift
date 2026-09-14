import SwiftUI

/// You tab — identity header plus destination rows (Airbnb profile, not a Form dump).
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var model: SettingsViewModel?
    @AppStorage(MassUnit.storageKey) private var massUnit = MassUnit.localeDefault
    @AppStorage("you.seen.calendar") private var seenCalendar = false
    #if DEBUG
    @State private var showingDevOnboarding = false
    @State private var showingDevMealConfirm = false
    @State private var showingDevCheckIn = false
    @State private var showingDevConversation = false
    #endif

    init(previewModel: SettingsViewModel? = nil) {
        _model = State(initialValue: previewModel)
    }

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                SettingsSkeletonView()
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
        switch model.phase {
        case .loading:
            SettingsSkeletonView()
        case let .failed(message):
            VStack(spacing: 14) {
                Text(message)
                    .font(Typography.data(15))
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
                ActionButton(title: "Try again", kind: .secondary) { Task { await model.load() } }
                    .frame(maxWidth: 200)
            }
            .padding(28)
        case .loaded:
            profile(model)
        }
    }

    @ViewBuilder
    private func profile(_ model: SettingsViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                planCard(model)
                    .appearIn(0)

                checkInsCard(model)
                    .appearIn(1)

                youSection("Your day") {
                    NavigationLink { RhythmSettingsView(model: model) } label: {
                        YouRow(symbol: "clock", title: "Meal times", value: mealTimesSubtitle(model))
                    }
                    rowDivider
                    NavigationLink {
                        CalendarSettingsView()
                            .onAppear { seenCalendar = true }
                    } label: {
                        YouRow(
                            symbol: "calendar",
                            title: "Calendar",
                            value: env.calendar.connected ? "Connected" : "Off",
                            isNew: !seenCalendar
                        )
                    }
                }
                .appearIn(2)

                youSection("Food") {
                    NavigationLink { GoalSettingsView(model: model) } label: {
                        YouRow(symbol: "scope", title: "Goal and pace", value: goalSubtitle(model))
                    }
                    rowDivider
                    NavigationLink { FoodsSettingsView(model: model) } label: {
                        YouRow(symbol: "nosign", title: "Foods I avoid", value: restrictionsSubtitle(model))
                    }
                }
                .appearIn(3)

                youSection("Connected") {
                    if env.health.isAvailable {
                        NavigationLink { HealthSettingsView() } label: {
                            YouRow(symbol: "heart", title: "Apple Health", value: healthRowValue)
                        }
                        rowDivider
                    }
                    NavigationLink { AccountSettingsView(model: model) } label: {
                        YouRow(symbol: "person", title: "Account", value: nil)
                    }
                    rowDivider
                    Button {
                        massUnit = massUnit == .kg ? .lb : .kg
                    } label: {
                        YouRow(symbol: "scalemass", title: "Units", value: massUnit.title)
                    }
                }
                .appearIn(4)

                if let error = model.error {
                    Text(error)
                        .font(Typography.data(13))
                        .foregroundStyle(Palette.accentDeep)
                        .padding(Space.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.accentTint, in: RoundedRectangle(cornerRadius: Radius.sm))
                }

                #if DEBUG
                developerTools
                #endif
            }
            .padding(Space.gutter)
        }
        .background(Palette.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        #if DEBUG
        .fullScreenCover(isPresented: $showingDevOnboarding) {
            DevOnboardingPreview()
        }
        .fullScreenCover(isPresented: $showingDevMealConfirm) {
            DevMealConfirmPreview()
        }
        .fullScreenCover(isPresented: $showingDevCheckIn) {
            DevCheckInPreview()
        }
        .fullScreenCover(isPresented: $showingDevConversation) {
            DevConversationPreview()
        }
        #endif
    }

    #if DEBUG
    private var developerTools: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Developer")
                .sectionLabelStyle()
                .padding(.top, Space.sm)
                .appearIn(5)

            Button {
                showingDevOnboarding = true
            } label: {
                DestinationRow(title: "Onboarding")
            }
            .buttonStyle(PressableCard())
            .appearIn(6)

            Button {
                showingDevMealConfirm = true
            } label: {
                DestinationRow(title: "Meal confirm", subtitle: "Demo data")
            }
            .buttonStyle(PressableCard())
            .appearIn(7)

            Button {
                showingDevCheckIn = true
            } label: {
                DestinationRow(title: "Check-in", subtitle: "Full-screen, demo data")
            }
            .buttonStyle(PressableCard())
            .appearIn(8)

            Button {
                showingDevConversation = true
            } label: {
                DestinationRow(title: "Let’s talk", subtitle: "Starts a real conversation")
            }
            .buttonStyle(PressableCard())
            .appearIn(9)
        }
    }
    #endif

    private func youSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).sectionLabelStyle()
            VStack(spacing: 0) { content() }
                .buttonStyle(.plain)
                .background {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Palette.surface)
                        .elevation(.resting)
                        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.hairline))
                }
        }
    }

    private var rowDivider: some View {
        Divider().overlay(Palette.hairline).padding(.leading, 66)
    }

    private var healthRowValue: String {
        switch env.health.state {
        case .connected:
            return env.health.hasHeartData ? "Connected" : "No heart data yet"
        case .notConnected, .unavailable:
            return "Not connected"
        }
    }

    private func planCard(_ model: SettingsViewModel) -> some View {
        NavigationLink {
            GoalSettingsView(model: model)
        } label: {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack {
                    Text("Your plan")
                        .sectionLabelStyle(Palette.background.opacity(0.75))
                    Spacer()
                    Text("Edit")
                        .font(Typography.data(13, weight: .bold))
                        .foregroundStyle(Palette.background)
                }

                Text(planTitle(model))
                    .font(Typography.display(30))
                    .foregroundStyle(Palette.background)

                if let progress = planProgress(model) {
                    GeometryReader { box in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Palette.background.opacity(0.22))
                            Capsule().fill(Palette.background)
                                .frame(width: box.size.width * progress)
                            Circle()
                                .fill(Palette.background)
                                .overlay(Circle().strokeBorder(Palette.accent, lineWidth: 4))
                                .frame(width: 18, height: 18)
                                .offset(x: box.size.width * progress - 9)
                        }
                    }
                    .frame(height: 18)
                }

                HStack(spacing: Space.md) {
                    planMetric(model.kcalTarget.formatted(), label: "kcal a day")
                    if let protein = model.proteinTarget {
                        planMetric("\(protein) g", label: "protein")
                    }
                    if let current = model.currentWeightKg, model.goal.hasWeightTarget {
                        planMetric(massUnit.number(current, digits: 1 ... 1), label: "\(massUnit.abbreviation) now")
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Palette.accent)
                    .elevation(.floating)
            }
        }
        .buttonStyle(PressableCard())
    }

    private func planMetric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(Typography.data(24, weight: .heavy))
                .foregroundStyle(Palette.background)
                .monospacedDigit()
            Text(label)
                .font(Typography.data(12))
                .foregroundStyle(Palette.background.opacity(0.75))
        }
    }

    /// The manager's switch: when check-ins come, on or off, and quiet hours.
    private func checkInsCard(_ model: SettingsViewModel) -> some View {
        HStack(spacing: Space.sm) {
            DayDial(
                breakfastMin: model.mealTimes.breakfastMin,
                lunchMin: model.mealTimes.lunchMin,
                dinnerMin: model.mealTimes.dinnerMin,
                quietStartMin: model.quietHours.startMin,
                quietEndMin: model.quietHours.endMin,
                showsHourLabels: false,
                today: DialToday(
                    states: [.breakfast: .upcoming, .lunch: .upcoming, .dinner: .upcoming],
                    nowMin: nil,
                    showsBells: model.enforcementEnabled && !model.checkInsPaused
                )
            ) { EmptyView() }
                .frame(width: 124, height: 124)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: Space.xs) {
                HStack {
                    Text("Check-ins")
                        .font(Typography.data(18, weight: .heavy))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    if model.enforcementEnabled {
                        Toggle("Check-ins", isOn: Binding(
                            get: { !model.checkInsPaused },
                            set: { on in Task { await model.setCheckInsPaused(!on) } }
                        ))
                        .labelsHidden()
                        .tint(Palette.accent)
                        .disabled(model.saving)
                    }
                }
                Text(checkInsDetail(model))
                    .font(Typography.data(13))
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Label("Quiet \(formatMinutes(model.quietHours.startMin))–\(formatMinutes(model.quietHours.endMin))", systemImage: "moon.fill")
                    .font(Typography.data(12, weight: .bold))
                    .foregroundStyle(Palette.inkSoft)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Palette.surfaceSunk, in: Capsule())
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Palette.surface)
                .elevation(.resting)
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.hairline))
        }
    }

    private func checkInsDetail(_ model: SettingsViewModel) -> String {
        if !model.enforcementEnabled { return enforcementNote(model.enforcementDisabledReason) }
        if model.checkInsPaused { return "Paused. Your plan still updates." }
        return "\(CheckInSchedule.graceMin) min after a meal time, if nothing’s logged."
    }

    private func goalSubtitle(_ model: SettingsViewModel) -> String {
        model.goal.hasWeightTarget ? "\(model.goal.title) · \(model.pace.title.lowercased())" : "Hold steady"
    }

    private func mealTimesSubtitle(_ model: SettingsViewModel) -> String {
        [model.mealTimes.breakfastMin, model.mealTimes.lunchMin, model.mealTimes.dinnerMin]
            .map(formatMinutes)
            .joined(separator: " · ")
    }

    private func restrictionsSubtitle(_ model: SettingsViewModel) -> String {
        model.restrictions.isEmpty ? "None" : model.restrictions.joined(separator: ", ")
    }

    private func planTitle(_ model: SettingsViewModel) -> String {
        guard model.goal.hasWeightTarget, let target = model.targetWeightKg else {
            return "Hold steady"
        }
        return "\(model.goal.directionVerb) \(massUnit.formatKg(target, digits: 0))"
    }

    private func planProgress(_ model: SettingsViewModel) -> Double? {
        guard model.goal.hasWeightTarget,
              let start = model.startWeightKg,
              let current = model.currentWeightKg,
              let target = model.targetWeightKg,
              target != start else { return nil }
        return min(max((current - start) / (target - start), 0), 1)
    }
}

private struct YouRow: View {
    let symbol: String
    let title: String
    let value: String?
    var isNew = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 36, height: 36)
                .background(Palette.surfaceSunk, in: Circle())
            Text(title)
                .font(Typography.data(16, weight: .bold))
                .foregroundStyle(Palette.ink)
            if isNew {
                Text("NEW")
                    .font(Typography.data(10, weight: .heavy))
                    .foregroundStyle(Palette.accentDeep)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Palette.accentTint, in: Capsule())
            }
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(Typography.data(14))
                    .foregroundStyle(Palette.inkFaint)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.inkFaint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

struct DestinationRow: View {
    let title: String
    var subtitle: String?

    var body: some View {
        HStack(spacing: Space.sm) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Typography.data(17, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(Typography.data(13))
                        .foregroundStyle(Palette.inkSoft)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.inkFaint)
        }
        .padding(16)
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
}

func formatBusyRange(_ startMin: Int, _ endMin: Int) -> String {
    "\(clock12(startMin))–\(clock12(endMin))"
}

private func clock12(_ minutes: Int) -> String {
    let wrapped = ((minutes % 1440) + 1440) % 1440
    let h = wrapped / 60
    let m = wrapped % 60
    let hour12 = h % 12 == 0 ? 12 : h % 12
    if m == 0 { return "\(hour12)" }
    return "\(hour12):\(String(format: "%02d", m))"
}

func formatMinutes(_ minutes: Int) -> String {
    let h = minutes / 60
    let m = minutes % 60
    var c = DateComponents()
    c.hour = h
    c.minute = m
    let date = Calendar.current.date(from: c) ?? .now
    let f = DateFormatter()
    f.timeStyle = .short
    return f.string(from: date)
}

func enforcementNote(_ reason: String?) -> String {
    switch reason {
    case "EATING_DISORDER_SCREEN":
        return "Quiet tracking is on. A professional can help if eating feels hard."
    case "MEDICAL_SUPERVISION":
        return "Quiet tracking is on. Follow your care team’s plan."
    default:
        return "Check-ins are off."
    }
}

private struct SettingsSkeletonView: View {
    private let wash = Palette.background.opacity(0.28)
    private let washStrong = Palette.background.opacity(0.42)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                plan
                checkIns
                rows
            }
            .padding(Space.gutter)
        }
        .scrollDisabled(true)
        .background(Palette.background.ignoresSafeArea())
        .skeletonLoading()
    }

    private var plan: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack {
                SkeletonBlock(width: 72, height: 10, tint: wash)
                Spacer()
                SkeletonBlock(width: 32, height: 13, tint: wash)
            }
            SkeletonBlock(width: 196, height: 30, radius: 8, tint: washStrong)
            Capsule().fill(wash).frame(height: 18)
            HStack(spacing: Space.md) {
                planMetric(width: 64)
                planMetric(width: 48)
                planMetric(width: 52)
                Spacer(minLength: 0)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.accent, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func planMetric(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SkeletonBlock(width: width, height: 24, radius: 6, tint: washStrong)
            SkeletonBlock(width: width - 8, height: 10, tint: wash)
        }
    }

    private var checkIns: some View {
        HStack(spacing: Space.sm) {
            mutedDial
                .frame(width: 124, height: 124)

            VStack(alignment: .leading, spacing: Space.xs) {
                HStack {
                    SkeletonBlock(width: 92, height: 18)
                    Spacer()
                    Capsule().fill(Palette.surfaceSunk).frame(width: 51, height: 31)
                }
                SkeletonBlock(width: 168, height: 13)
                SkeletonBlock(width: 128, height: 13)
                SkeletonBlock(width: 118, height: 24, radius: Radius.pill)
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Palette.surface)
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.hairline))
        }
    }

    private var mutedDial: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let r = size * 0.33
            let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            ZStack {
                Circle()
                    .stroke(Palette.surfaceSunk, lineWidth: size * 0.076)
                    .frame(width: r * 2, height: r * 2)
                    .position(c)
                ForEach([480, 780, 1140], id: \.self) { minute in
                    let angle = CGFloat(minute) / 1440 * 2 * .pi
                    Circle()
                        .fill(Palette.surface)
                        .overlay(Circle().strokeBorder(Palette.hairline, lineWidth: 1.5))
                        .frame(width: size * 0.13, height: size * 0.13)
                        .position(x: c.x + r * sin(angle), y: c.y - r * cos(angle))
                }
            }
        }
    }

    private var rows: some View {
        VStack(spacing: 0) {
            youRow(titleWidth: 118, valueWidth: 96)
            divider
            youRow(titleWidth: 92, valueWidth: 128)
            divider
            youRow(titleWidth: 124, valueWidth: 48)
            divider
            youRow(titleWidth: 72, valueWidth: 0)
        }
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Palette.surface)
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.hairline))
        }
    }

    private var divider: some View {
        Divider().overlay(Palette.hairline).padding(.leading, 66)
    }

    private func youRow(titleWidth: CGFloat, valueWidth: CGFloat) -> some View {
        HStack(spacing: 14) {
            Circle().fill(Palette.surfaceSunk).frame(width: 36, height: 36)
            SkeletonBlock(width: titleWidth, height: 16)
            Spacer(minLength: 8)
            if valueWidth > 0 {
                SkeletonBlock(width: valueWidth, height: 14)
            }
            SkeletonBlock(width: 8, height: 12, radius: 3)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#if DEBUG
private struct DevOnboardingPreview: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: OnboardingViewModel?
    @State private var showingSetup = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if showingSetup, let model {
                OnboardingFlow(model: model)
            } else {
                WelcomeView(onStart: { showingSetup = true })
            }

            Button("Close preview") { dismiss() }
                .font(Typography.data(13, weight: .medium))
                .foregroundStyle(Palette.inkSoft)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.trailing, Space.gutter)
                .padding(.top, 6)
        }
        .onAppear {
            if model == nil {
                model = .previewed(at: .goal, onComplete: { dismiss() })
            }
        }
    }
}

private struct DevMealConfirmPreview: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = LogMealViewModel.samplePhotoConfirm
    @Namespace private var ns

    var body: some View {
        PhotoParseConfirm(
            model: model,
            namespace: ns,
            imageID: "dev-confirm-image",
            cardID: "dev-confirm-card",
            onReject: { dismiss() },
            onKeep: { dismiss() }
        )
    }
}

/// The full-screen check-in (§5.3/§5.4) over a dimmed Home, same staging as
/// `-uiStub prescription` — reachable from Settings so it doesn't need a real
/// check-in to be pending.
private struct DevCheckInPreview: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            HomeContent(model: .previewed(.loaded(.sampleUnder)))
                .disabled(true)
                .overlay { Palette.scrim.ignoresSafeArea().allowsHitTesting(false) }

            if let checkIn = HomeResponse.sampleUnder.activeCheckIn {
                PrescriptionView(
                    checkIn: checkIn,
                    headline: TodayCopy.headline(TodayMoment.resolve(.sampleUnder)),
                    whyNow: TodayCopy.whyNow(.sampleUnder),
                    onDismiss: { dismiss() },
                    onResolved: { dismiss() },
                    onAlreadyAte: { dismiss() }
                )
            }
        }
    }
}

/// Opens a real tier-3 conversation against the signed-in account — reachable
/// from Settings so it doesn't need three consecutive misses.
private struct DevConversationPreview: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var env
    @State private var checkInID: String?
    @State private var error: String?

    var body: some View {
        Group {
            if let checkInID {
                ConversationView(
                    checkInID: checkInID,
                    onDismiss: { dismiss() },
                    onResolved: { dismiss() }
                )
            } else if let error {
                VStack(spacing: 14) {
                    Text(error)
                        .font(Typography.data(15))
                        .foregroundStyle(Palette.inkSoft)
                        .multilineTextAlignment(.center)
                    ActionButton(title: "Try again", kind: .secondary) {
                        Task { await start() }
                    }
                    .frame(maxWidth: 200)
                    ActionButton(title: "Close", kind: .secondary) { dismiss() }
                        .frame(maxWidth: 200)
                }
                .padding(28)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.background.ignoresSafeArea())
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Palette.background.ignoresSafeArea())
            }
        }
        .task { await start() }
    }

    private func start() async {
        guard checkInID == nil else { return }
        error = nil
        do {
            let res: StartTalkResponse = try await env.api.post("/api/checkins/start-talk")
            checkInID = res.checkInId
        } catch {
            self.error = UserFacingError.message(for: error, fallback: "Couldn't start the conversation.")
        }
    }
}

#Preview {
    NavigationStack { SettingsView(previewModel: .previewed()) }
        .environment(AppEnvironment.preview())
}

#Preview("Skeleton") {
    SettingsSkeletonView()
}
#endif
