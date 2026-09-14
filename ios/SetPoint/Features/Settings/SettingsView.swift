import SwiftUI

/// You tab — identity header plus destination rows (Airbnb profile, not a Form dump).
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var model: SettingsViewModel?
    #if DEBUG
    @State private var showingDevOnboarding = false
    @State private var showingDevMealConfirm = false
    @State private var showingDevCheckIn = false
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
            ContentUnavailableView("Load failed", systemImage: "person", description: Text(message))
        case .loaded:
            profile(model)
        }
    }

    @ViewBuilder
    private func profile(_ model: SettingsViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                Text("You")
                    .font(Typography.display(42))
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                    .appearIn(0)

                planCard(model)
                    .appearIn(1)

                checkInsCard(model)
                    .appearIn(2)

                VStack(spacing: 0) {
                    NavigationLink { GoalSettingsView(model: model) } label: {
                        YouRow(symbol: "scope", title: "Goal and pace", value: goalSubtitle(model))
                    }
                    rowDivider
                    NavigationLink { RhythmSettingsView(model: model) } label: {
                        YouRow(symbol: "clock", title: "Meal times", value: mealTimesSubtitle(model))
                    }
                    rowDivider
                    NavigationLink { GoalSettingsView(model: model) } label: {
                        YouRow(symbol: "nosign", title: "Foods I avoid", value: restrictionsSubtitle(model))
                    }
                    if env.health.isAvailable {
                        rowDivider
                        NavigationLink { HealthSettingsView() } label: {
                            YouRow(symbol: "heart", title: "Apple Health", value: env.health.connected ? "Connected" : "Not connected")
                        }
                    }
                    rowDivider
                    NavigationLink { AccountSettingsView(model: model) } label: {
                        YouRow(symbol: "person", title: "Account", value: nil)
                    }
                }
                .buttonStyle(.plain)
                .background {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Palette.surface)
                        .elevation(.resting)
                        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.hairline))
                }
                .appearIn(3)

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
        }
    }
    #endif

    private var rowDivider: some View {
        Divider().overlay(Palette.hairline).padding(.leading, 66)
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
                        planMetric(current.formatted(.number.precision(.fractionLength(1))), label: "kg now")
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
        return "\(model.goal.directionVerb) \(Int(target.rounded())) kg"
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
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    SkeletonBlock(width: 72, height: 34, radius: 10)
                    SkeletonBlock(width: 232, height: 15)
                }

                SkeletonCard(height: 154) {
                    VStack(alignment: .leading, spacing: Space.md) {
                        SkeletonBlock(width: 64, height: 10)
                        SkeletonBlock(width: 176, height: 24)
                        SkeletonBlock(height: 5, radius: 3)
                        HStack(spacing: Space.xl) {
                            SkeletonBlock(width: 76, height: 34)
                            SkeletonBlock(width: 64, height: 34)
                        }
                    }
                }

                SkeletonCard(height: 66) {
                    HStack(spacing: Space.sm) {
                        SkeletonBlock(width: 38, height: 38, radius: 19)
                        VStack(alignment: .leading, spacing: 6) {
                            SkeletonBlock(width: 112, height: 13)
                            SkeletonBlock(width: 196, height: 10)
                        }
                    }
                }

                HStack(spacing: Space.sm) {
                    SkeletonCard(height: 122) { SkeletonBlock(width: 84, height: 50) }
                    SkeletonCard(height: 122) { SkeletonBlock(width: 98, height: 50) }
                }

                VStack(spacing: Space.sm) {
                    destinationRow(titleWidth: 72, detailWidth: 94)
                    destinationRow(titleWidth: 82, detailWidth: 0)
                }
            }
            .padding(Space.gutter)
        }
        .background(Palette.background.ignoresSafeArea())
        .scrollDisabled(true)
        .skeletonLoading()
    }

    private func destinationRow(titleWidth: CGFloat, detailWidth: CGFloat) -> some View {
        SkeletonCard(height: 48) {
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    SkeletonBlock(width: titleWidth, height: 15)
                    if detailWidth > 0 {
                        SkeletonBlock(width: detailWidth, height: 11)
                    }
                }
                Spacer()
                SkeletonBlock(width: 8, height: 16, radius: 4)
            }
        }
    }
}

#if DEBUG
private struct DevOnboardingPreview: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: OnboardingViewModel?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let model {
                OnboardingFlow(model: model)
            } else {
                Palette.background.ignoresSafeArea()
            }

            Button("Close preview") { dismiss() }
                .font(Typography.data(13, weight: .medium))
                .foregroundStyle(Palette.inkFaint)
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

#Preview {
    NavigationStack { SettingsView(previewModel: .previewed()) }
        .environment(AppEnvironment.preview())
}
#endif
