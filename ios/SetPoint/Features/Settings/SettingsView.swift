import SwiftUI

/// You tab — identity header plus destination rows (Airbnb profile, not a Form dump).
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var model: SettingsViewModel?
    @AppStorage(MassUnit.storageKey) private var massUnit = MassUnit.localeDefault
    @AppStorage("you.seen.calendar") private var seenCalendar = false
    @AppStorage("you.seen.appetite") private var seenAppetite = false
    #if DEBUG
    @State private var showingDevOnboarding = false
    @State private var showingDevMealConfirm = false
    @State private var showingDevCheckInToday = false
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
            // For the Calendar row's "3 moved".
            if !env.calendar.isPreview, env.subscription.entitled {
                env.calendar.refreshAuthorization()
                await env.calendar.refreshStatus()
                if env.calendar.connected { await env.calendar.refreshWeek() }
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
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Headline("You", size: 36)
                    Spacer(minLength: 8)
                    NavigationLink { GoalSettingsView(model: model) } label: {
                        Text("Edit plan")
                            .font(Typography.data(13, weight: .regular))
                            .foregroundStyle(Palette.ink)
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .glassCapsule(fill: Color.white.opacity(0.06), stroke: Color.white.opacity(0.10))
                    }
                    .buttonStyle(PressableCard())
                }
                .appearIn(0)

                goalCard(model)
                    .appearIn(0)

                checkInsSection(model)
                    .appearIn(1)

                setupGrid(model)
                    .appearIn(2)

                proCard
                    .appearIn(3)

                NavigationLink { AccountSettingsView(model: model) } label: {
                    HStack {
                        Text("Account & data")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x52525B))
                    }
                    .font(Typography.data(14, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
                    .padding(.horizontal, 18)
                    .frame(height: 48)
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.08)))
                    .contentShape(Capsule())
                }
                .buttonStyle(PressableCard())
                .appearIn(4)

                if let error = model.error {
                    Text(error)
                        .font(Typography.data(13, weight: .regular))
                        .foregroundStyle(Palette.danger)
                        .padding(Space.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glass(radius: Radius.sm, fill: Palette.danger.opacity(0.08))
                }

                #if DEBUG
                developerTools
                #endif
            }
            .padding(Space.gutter)
            .padding(.bottom, 90)
        }
        .background(alignment: .top) { AmbientGlow(tone: .mixed, strength: 0.6).offset(y: -140).ignoresSafeArea() }
        .background(Palette.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        #if DEBUG
        .fullScreenCover(isPresented: $showingDevOnboarding) {
            DevOnboardingPreview()
        }
        .fullScreenCover(isPresented: $showingDevMealConfirm) {
            DevMealConfirmPreview()
        }
        .fullScreenCover(isPresented: $showingDevCheckInToday) {
            DevCheckInTodayPreview()
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
                showingDevCheckInToday = true
            } label: {
                DestinationRow(title: "Check-in · Today", subtitle: "Real check-in on Today")
            }
            .buttonStyle(PressableCard())
            .appearIn(8)

            Button {
                showingDevCheckIn = true
            } label: {
                DestinationRow(title: "Check-in · Sheet", subtitle: "Starts a real check-in")
            }
            .buttonStyle(PressableCard())
            .appearIn(9)

            Button {
                showingDevConversation = true
            } label: {
                DestinationRow(title: "Let’s talk", subtitle: "Starts a real conversation")
            }
            .buttonStyle(PressableCard())
            .appearIn(10)
        }
    }
    #endif

    private var healthRowValue: String {
        switch env.health.state {
        case .connected:
            return env.health.hasHeartData ? "Connected" : "No heart data yet"
        case .notConnected, .unavailable:
            return "Not connected"
        }
    }

    /// The goal as a picture: weight now inside a ring that fills toward the target.
    private func goalCard(_ model: SettingsViewModel) -> some View {
        let progress = model.goal.hasWeightTarget ? (planProgress(model) ?? 0.04) : 1
        return NavigationLink {
            GoalSettingsView(model: model)
        } label: {
            HStack(spacing: 18) {
                ZStack {
                    OrbRing(progress: max(0.04, progress))
                    FuelOrb(size: 80, glow: 0.4)
                    VStack(spacing: 0) {
                        Text(model.currentWeightKg.map { massUnit.number($0, digits: 1 ... 1) } ?? "—")
                            .font(Typography.data(22, weight: .light))
                            .tracking(-0.6)
                        Text("\(massUnit.abbreviation.uppercased()) NOW")
                            .font(Typography.mono(9))
                            .foregroundStyle(Color(hex: 0xFDE6CF))
                    }
                    .foregroundStyle(Palette.ink)
                    .shadow(color: .black.opacity(0.6), radius: 6, y: 2)
                }
                .frame(width: 112, height: 112)

                VStack(alignment: .leading, spacing: 6) {
                    Text(goalLabel(model, progress: progress)).sectionLabelStyle(Palette.amber)
                    Text(goalTitle(model))
                        .font(Typography.display(26))
                        .tracking(-0.8)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Text(goalLines(model))
                        .font(Typography.mono(11))
                        .foregroundStyle(Palette.inkSoft)
                        .lineSpacing(3)
                        .textCase(.uppercase)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(LinearGradient(colors: [Palette.ember.opacity(0.12), Color.white.opacity(0.02)], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color(hex: 0xFF8A50, opacity: 0.30)))
        }
        .buttonStyle(PressableCard())
        .accessibilityLabel("\(goalTitle(model)). \(goalLines(model)). Edit plan")
    }

    private func goalLabel(_ model: SettingsViewModel, progress: Double) -> String {
        guard model.goal.hasWeightTarget else { return "Maintaining" }
        let verb = model.goal == .bulk ? "Gaining" : "Cutting"
        return "\(verb) · \(Int((progress * 100).rounded()))% there"
    }

    private func goalTitle(_ model: SettingsViewModel) -> String {
        guard model.goal.hasWeightTarget, let target = model.targetWeightKg else {
            if let current = model.currentWeightKg { return "Holding at \(massUnit.formatKg(current))" }
            return "Hold steady"
        }
        return "To \(massUnit.formatKg(target, digits: 0))"
    }

    private func goalLines(_ model: SettingsViewModel) -> String {
        let first = "\(model.kcalTarget.formatted()) kcal a day"
        let second: String
        if model.goal.hasWeightTarget {
            second = model.honestDurationWeeks.map { "\(model.pace.title) · ~\($0) weeks left" } ?? model.pace.title
        } else {
            second = "No end date"
        }
        return first + "\n" + second
    }

    /// On or paused, drawn as the three meal check-ins a day — or a quiet line.
    private func checkInsSection(_ model: SettingsViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("How I check in").sectionLabelStyle()
                Spacer()
                Text("Quiet \(formatMinutes(model.quietHours.startMin))–\(formatMinutes(model.quietHours.endMin))")
                    .font(Typography.mono(10))
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.inkFaint)
            }
            .padding(.horizontal, 4)

            if model.enforcementEnabled {
                HStack(spacing: 8) {
                    checkInTile(title: "On", caption: "After each meal time", dots: 3, selected: !model.checkInsPaused) {
                        Task { await model.setCheckInsPaused(false) }
                    }
                    checkInTile(title: "Paused", caption: "Plan still updates", dots: 0, selected: model.checkInsPaused) {
                        Task { await model.setCheckInsPaused(true) }
                    }
                }
                .disabled(model.saving)
            }

            Text(checkInsDetail(model))
                .font(Typography.data(13, weight: .regular))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    private func checkInTile(title: String, caption: String, dots: Int, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    if dots == 0 {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(selected ? Palette.onBone : Palette.inkFaint)
                    }
                    ForEach(0..<dots, id: \.self) { _ in
                        Circle()
                            .fill(selected ? Palette.ember : Color.white.opacity(0.25))
                            .frame(width: 6, height: 6)
                            .shadow(color: Palette.ember.opacity(selected ? 0.8 : 0), radius: 3)
                    }
                }
                .frame(height: 14)
                Text(title)
                    .font(Typography.data(15, weight: .medium))
                Text(caption.uppercased())
                    .font(Typography.mono(10))
                    .opacity(0.7)
            }
            .foregroundStyle(selected ? Palette.onBone : Palette.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(selected ? Palette.ink : Color.white.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(selected ? Palette.ink : Color.white.opacity(0.08))
            )
        }
        .buttonStyle(PressableCard())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Each setting as a tile with a small picture of its current value.
    private func setupGrid(_ model: SettingsViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your setup").sectionLabelStyle().padding(.horizontal, 4)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                NavigationLink { RhythmSettingsView(model: model) } label: {
                    SetupTile(title: "Meal times", value: mealTimesSubtitle(model)) {
                        HStack(alignment: .center, spacing: 6) {
                            ForEach([model.mealTimes.breakfastMin, model.mealTimes.lunchMin, model.mealTimes.dinnerMin], id: \.self) { minute in
                                Circle().fill(Palette.amber).frame(width: 8, height: 8)
                                    .shadow(color: Palette.amber.opacity(0.6), radius: 3)
                                    .offset(y: CGFloat(abs(minute - 780)) / 60 - 3)
                            }
                        }
                    }
                }
                NavigationLink {
                    AppetiteSettingsView().onAppear { seenAppetite = true }
                } label: {
                    SetupTile(title: "Appetite", value: appetiteValue(model), isNew: !seenAppetite) {
                        HStack(spacing: 5) {
                            Circle().strokeBorder(Palette.amber, lineWidth: 1.5).frame(width: 9, height: 9)
                            Circle().fill(Color.white.opacity(0.3)).frame(width: 12, height: 12)
                            FuelOrb(size: 18, breathing: false, glow: 0.3)
                        }
                    }
                }
                NavigationLink { FoodsSettingsView(model: model) } label: {
                    SetupTile(title: "Foods I avoid", value: restrictionsSubtitle(model)) {
                        HStack(spacing: 5) {
                            FuelOrb(size: 18, breathing: false, glow: 0.3)
                            Image(systemName: "nosign")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Palette.danger)
                        }
                    }
                }
                NavigationLink {
                    if env.subscription.entitled {
                        CalendarSettingsView().onAppear { seenCalendar = true }
                    } else {
                        PaywallView()
                    }
                } label: {
                    SetupTile(
                        title: "Calendar",
                        value: env.subscription.entitled ? env.calendar.youRowValue : "Pro",
                        valueColor: env.subscription.entitled ? Palette.inkSoft : Palette.hazeSoft,
                        isNew: !seenCalendar
                    ) {
                        HStack(spacing: 5) {
                            let picked = env.calendar.selectedChoices.prefix(4)
                            if picked.isEmpty {
                                ForEach([0x818CF8, 0xFFB86B, 0x86EFAC] as [UInt32], id: \.self) { hex in
                                    RoundedRectangle(cornerRadius: 4).fill(Color(hex: hex)).frame(width: 12, height: 12).opacity(0.25)
                                }
                            } else {
                                ForEach(Array(picked)) { choice in
                                    RoundedRectangle(cornerRadius: 4).fill(Color(hex: choice.colorHex)).frame(width: 12, height: 12)
                                }
                            }
                        }
                    }
                }
                if env.health.isAvailable {
                    NavigationLink { HealthSettingsView() } label: {
                        SetupTile(title: "Apple Health", value: healthRowValue, valueColor: env.health.connected ? Palette.positive : Palette.inkSoft) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color(hex: 0xFF3B5C))
                                .frame(width: 22, height: 22)
                                .background(Palette.ink, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                    }
                }
                Button {
                    massUnit = massUnit == .kg ? .lb : .kg
                } label: {
                    SetupTile(title: "Units", value: massUnit.title, showsChevron: false) {
                        HStack(spacing: 4) {
                            ForEach(MassUnit.allCases, id: \.self) { unit in
                                Text(unit.abbreviation)
                                    .font(Typography.mono(10))
                                    .foregroundStyle(unit == massUnit ? Palette.onBone : Palette.inkFaint)
                                    .padding(.horizontal, 6)
                                    .frame(height: 18)
                                    .background(unit == massUnit ? Palette.ink : Color.white.opacity(0.06), in: Capsule())
                            }
                        }
                    }
                }
            }
            .buttonStyle(PressableCard())
        }
    }

    private func appetiteValue(_ model: SettingsViewModel) -> String {
        switch model.mode {
        case "SMALL_FREQUENT": return "Smaller plates"
        case "DRINKABLE": return "Drinkable first"
        case "ASK_DAILY": return "Ask each morning"
        default: return "Normal plates"
        }
    }

    private var proCard: some View {
        NavigationLink { PaywallView() } label: {
            HStack(spacing: 14) {
                FuelOrb(size: 38, breathing: false, glow: 0.5, haze: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("SetPoint Pro")
                        .font(Typography.data(15, weight: .medium))
                        .foregroundStyle(Palette.ink)
                    Text(env.subscription.entitled ? "Active · training and calendar on" : "Training refuels and calendar planning")
                        .font(Typography.data(12, weight: .regular))
                        .foregroundStyle(Palette.hazeSoft)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.hazeSoft)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LinearGradient(colors: [Palette.haze.opacity(0.16), Palette.haze.opacity(0.03)], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.hazeSoft.opacity(0.35)))
        }
        .buttonStyle(PressableCard())
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

/// A tile on You: a small picture of the setting, its name and current value.
private struct SetupTile<Mark: View>: View {
    let title: String
    let value: String
    var valueColor: Color = Palette.inkSoft
    var isNew = false
    var showsChevron = true
    @ViewBuilder var mark: Mark

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                mark.frame(height: 22)
                Spacer(minLength: 0)
                if isNew {
                    Text("NEW")
                        .font(Typography.mono(9, weight: .medium))
                        .foregroundStyle(Palette.onEmber)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Palette.amber, in: Capsule())
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.data(15, weight: .regular))
                    .foregroundStyle(Palette.ink)
                Text(value)
                    .font(Typography.data(12, weight: .regular))
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .glass(radius: 22)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
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
        .glass(radius: Radius.lg)
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
    private let wash = Color.white.opacity(0.06)
    private let washStrong = Color.white.opacity(0.1)

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
        .glass(radius: 28)
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
                model = .previewed(at: .about, onComplete: { dismiss() })
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

/// Today with a real check-in takeover — creates one if none is open.
private struct DevCheckInTodayPreview: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var env
    @State private var model: HomeViewModel?
    @State private var error: String?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let model {
                    HomeContent(model: model)
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

            Button("Close preview") { dismiss() }
                .font(Typography.data(13, weight: .medium))
                .foregroundStyle(Palette.inkSoft)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.trailing, Space.gutter)
                .padding(.top, 6)
        }
        .task { await start() }
    }

    private func start() async {
        guard model == nil else { return }
        error = nil
        do {
            let _: StartTalkResponse = try await env.api.post("/api/checkins/start-check-in")
            let vm = HomeViewModel(
                api: env.api,
                onUnauthorized: { env.auth.handleUnauthorized() },
                onMealChanged: { env.changes.mealsChanged() }
            )
            await vm.load()
            model = vm
        } catch {
            self.error = UserFacingError.message(for: error, fallback: "Couldn't start a check-in.")
        }
    }
}

/// Full-screen check-in sheet against the signed-in account — creates a real
/// meal check-in if none is open.
private struct DevCheckInPreview: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var env
    @State private var home: HomeResponse?
    @State private var error: String?

    var body: some View {
        Group {
            if let home, let checkIn = home.activeCheckIn, checkIn.tier < 3 {
                ZStack {
                    HomeContent(model: .previewed(.loaded(home)))
                        .disabled(true)
                        .overlay { Palette.scrim.ignoresSafeArea().allowsHitTesting(false) }

                    PrescriptionView(
                        checkIn: checkIn,
                        headline: TodayCopy.headline(TodayMoment.resolve(home)),
                        whyNow: TodayCopy.whyNow(home),
                        nextMealMinutes: minutesUntilNextMeal(home),
                        onDismiss: { dismiss() },
                        onResolved: { dismiss() },
                        onAlreadyAte: { dismiss() },
                        suggestSmallerDefault: home.appetite?.suggestSmallerDefault == true,
                        appetiteLevel: home.appetite?.level
                    )
                }
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
        guard home == nil else { return }
        error = nil
        do {
            let _: StartTalkResponse = try await env.api.post("/api/checkins/start-check-in")
            let loaded: HomeResponse = try await env.api.get("/api/home")
            guard let checkIn = loaded.activeCheckIn, checkIn.tier < 3 else {
                self.error = "Couldn't open a meal check-in."
                return
            }
            home = loaded
        } catch {
            self.error = UserFacingError.message(for: error, fallback: "Couldn't start a check-in.")
        }
    }

    private func minutesUntilNextMeal(_ home: HomeResponse) -> Int? {
        let times = home.resolvedMealTimes
        let now = Calendar.current.dateComponents([.hour, .minute], from: .now)
        let nowMin = (now.hour ?? 0) * 60 + (now.minute ?? 0)
        let candidates = [times.breakfastMin, times.lunchMin, times.dinnerMin]
            .map { $0 > nowMin ? $0 - nowMin : $0 + 1440 - nowMin }
            .filter { $0 > 0 }
        return candidates.min()
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
