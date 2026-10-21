import SwiftUI

/// You tab — identity header plus destination rows (Airbnb profile, not a Form dump).
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var model: SettingsViewModel?
    @AppStorage(MassUnit.storageKey) private var massUnit = MassUnit.localeDefault
    @AppStorage("you.seen.calendar") private var seenCalendar = false
    @AppStorage("you.seen.appetite") private var seenAppetite = false
    @State private var reloading = false
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
                SettingsSkeletonView(showPro: env.flags.isOn(.paywall))
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
            if !env.calendar.isPreview {
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
            SettingsSkeletonView(showPro: env.flags.isOn(.paywall))
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
                HStack(spacing: 12) {
                    NavigationLink { AccountSettingsView(model: model) } label: {
                        identityChip(model)
                    }
                    .buttonStyle(PressableCard())
                    Spacer(minLength: 0)
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

                if env.flags.isOn(.paywall) {
                    proCard
                        .appearIn(3)
                }

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
        .pullToReload({ await model.load(showSpinner: false) }, covering: $reloading)
        .reloadCover(reloading) { SettingsSkeletonView(showPro: env.flags.isOn(.paywall)) }
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
            return env.health.hasHeartData ? L10n( "Connected") : L10n( "No heart data yet")
        case .notConnected, .unavailable:
            return L10n( "Not connected")
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
                        Text(L10n("\(massUnit.abbreviation) NOW"))
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
        guard model.goal.hasWeightTarget else { return L10n( "Maintaining") }
        let percent = Int((progress * 100).rounded())
        return model.goal == .bulk
            ? L10n( "Gaining · \(percent)% there")
            : L10n( "Cutting · \(percent)% there")
    }

    private func goalTitle(_ model: SettingsViewModel) -> String {
        guard model.goal.hasWeightTarget, let target = model.targetWeightKg else {
            if let current = model.currentWeightKg { return L10n( "Holding at \(massUnit.formatKg(current))") }
            return L10n( "Hold steady")
        }
        return L10n( "To \(massUnit.formatKg(target, digits: 0))")
    }

    private func goalLines(_ model: SettingsViewModel) -> String {
        let first = L10n( "\(model.kcalTarget.formatted()) kcal a day")
        let second: String
        if model.goal.hasWeightTarget {
            second = model.honestDurationWeeks.map { L10n( "\(model.pace.title) · ~\($0) weeks left") } ?? model.pace.title
        } else {
            second = L10n( "No end date")
        }
        return first + "\n" + second
    }

    /// On or paused — one card: the day's three meal check-ins, and a sliding switch.
    private func checkInsSection(_ model: SettingsViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("How I check in").sectionLabelStyle()
                Spacer()
                Text(L10n("Quiet \(formatMinutes(model.quietHours.startMin))–\(formatMinutes(model.quietHours.endMin))"))
                    .font(Typography.mono(10))
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.inkFaint)
            }
            .padding(.horizontal, 4)

            if model.enforcementEnabled {
                CheckInModeSwitch(
                    paused: model.checkInsPaused,
                    mealMinutes: [
                        model.mealTimes.breakfastMin,
                        model.mealTimes.lunchMin,
                        model.mealTimes.dinnerMin,
                    ],
                    busy: model.saving
                ) { paused in
                    Task { await model.setCheckInsPaused(paused) }
                }
            }

            if model.enforcementEnabled && !model.checkInsPaused {
                Text(checkInsDetail(model))
                    .font(Typography.data(13, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .hintCopy()
            } else {
                Text(checkInsDetail(model))
                    .font(Typography.data(13, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }

    /// Each setting as a tile with a small picture of its current value.
    private func setupGrid(_ model: SettingsViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your setup").sectionLabelStyle().padding(.horizontal, 4)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                NavigationLink { RhythmSettingsView(model: model) } label: {
                    SetupTile(
                        title: "Meal times",
                        badge: model.hasWeekendMealOverrides ? "Weekends" : nil
                    ) {
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
                    SetupTile(title: "Foods I avoid") {
                        HStack(spacing: 5) {
                            FuelOrb(size: 18, breathing: false, glow: 0.3)
                            Image(systemName: "nosign")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Palette.danger)
                        }
                    }
                }
                if env.flags.isOn(.nutritionChat), model.enforcementDisabledReason == nil {
                    NavigationLink { NutritionAssistantView() } label: {
                        SetupTile(title: "Nutrition assistant", value: L10n("AI")) {
                            HStack(spacing: 5) {
                                FuelOrb(size: 18, breathing: false, glow: 0.3)
                                Circle().fill(Palette.ember).frame(width: 8, height: 8)
                                    .shadow(color: Palette.ember.opacity(0.55), radius: 3)
                            }
                        }
                    }
                }
                NavigationLink { SavedMealsSettingsView() } label: {
                    SetupTile(title: "My meals") {
                        HStack(spacing: 5) {
                            Circle().fill(Palette.amber).frame(width: 8, height: 8)
                                .shadow(color: Palette.amber.opacity(0.6), radius: 3)
                            Circle().fill(Palette.ember).frame(width: 10, height: 10)
                                .shadow(color: Palette.ember.opacity(0.55), radius: 3)
                            Circle().strokeBorder(Palette.amber, lineWidth: 1.5).frame(width: 9, height: 9)
                        }
                    }
                }
                NavigationLink {
                    CalendarSettingsView().onAppear { seenCalendar = true }
                } label: {
                    SetupTile(
                        title: "Calendar",
                        value: env.calendar.youRowValue,
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
            }
            .buttonStyle(PressableCard())
        }
    }

    private func identityChip(_ model: SettingsViewModel) -> some View {
        ZStack {
            FuelOrb(size: 36, breathing: false, glow: 0.45)
            Text(identityInitial(model))
                .font(Typography.data(15, weight: .medium))
                .foregroundStyle(Palette.onBone)
        }
        .frame(width: 44, height: 44)
        .accessibilityLabel(identityAccessibilityLabel(model))
    }

    private func identityName(_ model: SettingsViewModel) -> String {
        let name = model.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? L10n( "You") : name
    }

    private func identityAccessibilityLabel(_ model: SettingsViewModel) -> String {
        if let email = model.visibleEmail {
            return "\(identityName(model)), \(email). Opens your details"
        }
        return "\(identityName(model)). Opens your details"
    }

    private func identityInitial(_ model: SettingsViewModel) -> String {
        let name = model.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = name.first { return String(first).uppercased() }
        if let first = model.visibleEmail?.first { return String(first).uppercased() }
        return "Y"
    }

    private func appetiteValue(_ model: SettingsViewModel) -> String {
        switch model.mode {
        case "SMALL_FREQUENT": return L10n( "Smaller plates")
        case "DRINKABLE": return L10n( "Drinkable first")
        case "ASK_DAILY": return L10n( "Ask each morning")
        default: return L10n( "Normal plates")
        }
    }

    private var proCard: some View {
        NavigationLink { PaywallView() } label: {
            HStack(spacing: 14) {
                FuelOrb(size: 38, breathing: false, glow: 0.5, haze: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("SetPoint")
                        .font(Typography.data(15, weight: .medium))
                        .foregroundStyle(Palette.ink)
                    Text(LocalizedStringKey(env.subscription.entitled ? "Active" : "The whole product — one deal"))
                        .font(Typography.data(12, weight: .regular))
                        .foregroundStyle(Palette.hazeSoft)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.forward")
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
        if model.checkInsPaused { return L10n( "Paused. Your plan still updates.") }
        return L10n( "\(CheckInSchedule.graceMin) min after a meal time, if nothing’s logged.")
    }

    private func goalSubtitle(_ model: SettingsViewModel) -> String {
        model.goal.hasWeightTarget ? "\(model.goal.title) · \(model.pace.title.lowercased())" : L10n( "Hold steady")
    }

    private func planTitle(_ model: SettingsViewModel) -> String {
        guard model.goal.hasWeightTarget, let target = model.targetWeightKg else {
            return L10n( "Hold steady")
        }
        return L10n( "\(model.goal.directionVerb) \(massUnit.formatKg(target, digits: 0))")
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
    var value: String? = nil
    var valueColor: Color = Palette.inkSoft
    var isNew = false
    /// Quiet status chip (e.g. "Weekends") — muted vs the amber NEW badge.
    var badge: String? = nil
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
                } else if let badge {
                    Text(LocalizedStringKey(badge))
                        .font(Typography.mono(9, weight: .medium))
                        .foregroundStyle(Palette.inkFaint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.08), in: Capsule())
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                    .font(Typography.data(15, weight: .regular))
                    .foregroundStyle(Palette.ink)
                if let value {
                    Text(LocalizedStringKey(value))
                        .font(Typography.data(12, weight: .regular))
                        .foregroundStyle(valueColor)
                        .lineLimit(1)
                }
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
                Text(LocalizedStringKey(title))
                    .font(Typography.data(17, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                if let subtitle {
                    Text(LocalizedStringKey(subtitle))
                        .font(Typography.data(13))
                        .foregroundStyle(Palette.inkSoft)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.forward")
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
    f.locale = AppLanguage.current.locale
    f.timeStyle = .short
    return f.string(from: date)
}

func enforcementNote(_ reason: String?) -> String {
    switch reason {
    case "EATING_DISORDER_SCREEN":
        return L10n( "Quiet tracking is on. A professional can help if eating feels hard.")
    case "MEDICAL_SUPERVISION":
        return L10n( "Quiet tracking is on. Follow your care team’s plan.")
    default:
        return L10n( "Check-ins are off.")
    }
}

/// How check-ins run: the day's three meal moments as a lit ribbon, with a
/// sliding On / Paused switch underneath.
private struct CheckInModeSwitch: View {
    let paused: Bool
    let mealMinutes: [Int]
    var busy = false
    let onChange: (Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var segmentNS

    private var listening: Bool { !paused }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            dayRibbon
            modeSwitch
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(radius: 24, fill: Color.white.opacity(0.035))
        .opacity(busy ? 0.55 : 1)
        .disabled(busy)
        .animation(Motion.adaptive(Motion.settle, reduceMotion: reduceMotion), value: paused)
        .accessibilityElement(children: .contain)
    }

    /// Three meal check-ins on a day line — ember when listening, a quiet hush when paused.
    private var dayRibbon: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(LocalizedStringKey(listening ? "Listening" : "Quiet"))
                    .font(Typography.data(15, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.opacity)
                Spacer(minLength: 8)
                Text(LocalizedStringKey(listening ? "After each meal" : "Plan still updates"))
                    .font(Typography.data(12, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
                    .contentTransition(.opacity)
            }

            GeometryReader { geo in
                let width = geo.size.width
                let ys: CGFloat = 11
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(listening ? Palette.ember.opacity(0.22) : Color.white.opacity(0.06))
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                        .offset(y: ys - 1)

                    if listening {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Palette.ember.opacity(0.15), Palette.ember.opacity(0.55), Palette.ember.opacity(0.15)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(height: 2)
                            .frame(maxWidth: .infinity)
                            .offset(y: ys - 1)
                    }

                    HStack(spacing: 0) {
                        ForEach(Array(mealMinutes.enumerated()), id: \.offset) { index, minute in
                            mealNode(minute: minute)
                            if index < mealMinutes.count - 1 { Spacer(minLength: 0) }
                        }
                    }
                    .frame(width: width)
                }
            }
            .frame(height: 36)
        }
        .accessibilityHidden(true)
    }

    private func mealNode(minute: Int) -> some View {
        VStack(spacing: 6) {
            ZStack {
                if listening {
                    Circle()
                        .fill(Palette.ember.opacity(0.28))
                        .frame(width: 18, height: 18)
                        .blur(radius: reduceMotion ? 0 : 2)
                }
                Circle()
                    .fill(listening ? Palette.ember : Color.white.opacity(0.06))
                    .frame(width: listening ? 9 : 8, height: listening ? 9 : 8)
                    .overlay {
                        if !listening {
                            Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 1.2)
                        }
                    }
                    .shadow(color: Palette.ember.opacity(listening ? 0.7 : 0), radius: listening ? 5 : 0)
            }
            .frame(width: 18, height: 18)

            Text(formatMinutes(minute))
                .font(Typography.mono(9))
                .foregroundStyle(listening ? Palette.inkSoft : Palette.inkFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var modeSwitch: some View {
        HStack(spacing: 0) {
            modeOption(title: "On", selected: listening) {
                guard paused else { return }
                Haptics.select()
                onChange(false)
            }
            modeOption(title: "Paused", selected: paused) {
                guard !paused else { return }
                Haptics.select()
                onChange(true)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07))
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Check-ins")
    }

    private func modeOption(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(LocalizedStringKey(title))
                .font(Typography.data(14, weight: selected ? .medium : .regular))
                .foregroundStyle(selected ? Palette.onBone : Palette.inkSoft)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Palette.ink)
                            .matchedGeometryEffect(id: "checkInMode", in: segmentNS)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Matches the loaded You layout: Edit plan, goal orb card, check-in switch, setup grid.
private struct SettingsSkeletonView: View {
    var showPro = false
    private let wash = Color.white.opacity(0.06)
    private let washStrong = Color.white.opacity(0.1)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Circle().fill(washStrong).frame(width: 36, height: 36)
                    Spacer(minLength: 0)
                    Capsule().fill(washStrong).frame(width: 88, height: 36)
                }

                goalCard
                checkIns
                setupGrid
                if showPro { proCard }
            }
            .padding(Space.gutter)
        }
        .scrollDisabled(true)
        .background(Palette.background.ignoresSafeArea())
        .skeletonLoading()
    }

    private var goalCard: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(washStrong, lineWidth: 8)
                    .frame(width: 112, height: 112)
                Circle()
                    .fill(wash)
                    .frame(width: 80, height: 80)
                VStack(spacing: 4) {
                    SkeletonBlock(width: 44, height: 20, radius: 6, tint: washStrong)
                    SkeletonBlock(width: 36, height: 8, tint: wash)
                }
            }
            .frame(width: 112, height: 112)

            VStack(alignment: .leading, spacing: 8) {
                SkeletonBlock(width: 96, height: 10, tint: wash)
                SkeletonBlock(width: 120, height: 26, radius: 8, tint: washStrong)
                SkeletonBlock(width: 108, height: 11, tint: wash)
                SkeletonBlock(width: 132, height: 11, tint: wash)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: [Palette.ember.opacity(0.08), Color.white.opacity(0.02)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color(hex: 0xFF8A50, opacity: 0.18)))
    }

    private var checkIns: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SkeletonBlock(width: 108, height: 10, tint: wash)
                Spacer()
                SkeletonBlock(width: 92, height: 10, tint: wash)
            }
            .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    SkeletonBlock(width: 72, height: 15, tint: washStrong)
                    Spacer()
                    SkeletonBlock(width: 96, height: 12, tint: wash)
                }
                ZStack(alignment: .top) {
                    Capsule()
                        .fill(wash)
                        .frame(height: 2)
                        .padding(.horizontal, 18)
                        .padding(.top, 8)
                    HStack {
                        ForEach(0..<3, id: \.self) { _ in
                            VStack(spacing: 6) {
                                Circle()
                                    .strokeBorder(washStrong, lineWidth: 1.5)
                                    .frame(width: 9, height: 9)
                                SkeletonBlock(width: 28, height: 8, tint: wash)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(height: 36)

                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(washStrong)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(wash)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                }
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
            }
            .padding(16)
            .glass(radius: 24, fill: Color.white.opacity(0.035))

            SkeletonBlock(width: 220, height: 12, tint: wash)
                .padding(.horizontal, 4)
        }
    }

    private var setupGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            SkeletonBlock(width: 84, height: 10, tint: wash)
                .padding(.horizontal, 4)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(0..<6, id: \.self) { i in
                    setupTile(markWidth: [48, 40, 36, 44, 28, 56][i])
                }
            }
        }
    }

    private func setupTile(markWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SkeletonBlock(width: markWidth, height: 18, radius: 6, tint: washStrong)
            VStack(alignment: .leading, spacing: 4) {
                SkeletonBlock(width: 72, height: 14, tint: washStrong)
                SkeletonBlock(width: 88, height: 11, tint: wash)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .glass(radius: 22)
    }

    private var proCard: some View {
        HStack(spacing: 14) {
            Circle().fill(Palette.haze.opacity(0.2)).frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 4) {
                SkeletonBlock(width: 96, height: 14, tint: washStrong)
                SkeletonBlock(width: 168, height: 11, tint: wash)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [Palette.haze.opacity(0.12), Palette.haze.opacity(0.02)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.hazeSoft.opacity(0.22)))
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
            self.error = UserFacingError.message(for: error, fallback: L10n( "Couldn't start a check-in."))
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
                self.error = L10n( "Couldn't open a meal check-in.")
                return
            }
            home = loaded
        } catch {
            self.error = UserFacingError.message(for: error, fallback: L10n( "Couldn't start a check-in."))
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
                    onDismiss: { Task { await closeTalk(id: checkInID) } },
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
            self.error = UserFacingError.message(for: error, fallback: L10n( "Couldn't start the conversation."))
        }
    }

    private func closeTalk(id: String) async {
        try? await CheckInActions.alreadyAte(checkInID: id, api: env.api)
        dismiss()
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
