import SwiftUI

struct HomeContent: View {
    @Bindable var model: HomeViewModel
    var deepLinkCheckInID: Binding<String?> = .constant(nil)
    var previewLogger: LogMealViewModel? = nil
    var startComposerExpanded = false
    var previewNow: Date? = nil

    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var logger: LogMealViewModel?
    @State private var showingCheckIn = false
    @State private var selectedMeal: MealSummary?
    @State private var composerExpanded: Bool
    @FocusState private var composerFocused: Bool
    @Namespace private var checkInNamespace
    @Namespace private var photoLogNamespace

    init(
        model: HomeViewModel,
        deepLinkCheckInID: Binding<String?> = .constant(nil),
        previewLogger: LogMealViewModel? = nil,
        startComposerExpanded: Bool = false,
        previewNow: Date? = nil
    ) {
        self.model = model
        self.deepLinkCheckInID = deepLinkCheckInID
        self.previewLogger = previewLogger
        self.startComposerExpanded = startComposerExpanded
        self.previewNow = previewNow
        _logger = State(initialValue: previewLogger)
        _composerExpanded = State(initialValue: startComposerExpanded)
    }

    private static let checkInGeometryID = "active-check-in"
    private static let photoImageID = "photo-log-image"
    private static let photoCardID = "photo-log-card"

    private var activeCheckIn: HomeResponse.ActiveCheckIn? {
        if case let .loaded(home) = model.phase { return home.activeCheckIn }
        return nil
    }

    private var now: Date { previewNow ?? Date() }

    /// Minutes from now until the user's next meal anchor (tomorrow's breakfast
    /// once the day's anchors have passed). Feeds the "after my next meal" snooze.
    private func minutesUntilNextMeal() -> Int {
        let times: MealTimesPayload
        if case let .loaded(home) = model.phase { times = home.resolvedMealTimes } else { times = .standard }
        let cal = Calendar.current
        let nowMin = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        let anchors = [times.breakfastMin, times.lunchMin, times.dinnerMin].sorted()
        if let next = anchors.first(where: { $0 > nowMin + 20 }) {
            return next - nowMin
        }
        return (1440 - nowMin) + anchors[0]
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            homeLayer
                .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: isLoaded)
                .overlay {
                    Palette.scrim
                        .ignoresSafeArea()
                        .opacity(showingCheckIn ? 1 : 0)
                        .allowsHitTesting(false)
                }
                .animation(Motion.adaptive(Motion.morph, reduceMotion: reduceMotion), value: showingCheckIn)

            if showingCheckIn, let checkIn = activeCheckIn {
                Group {
                    if checkIn.tier >= 3 {
                        ConversationView(
                            checkInID: checkIn.id,
                            onDismiss: { withAnimation(springForCheckIn) { showingCheckIn = false } },
                            onResolved: {
                                withAnimation(springForCheckIn) { showingCheckIn = false }
                                Task { await model.load(showSpinner: false) }
                            }
                        )
                    } else {
                        PrescriptionView(
                            checkIn: checkIn,
                            nextMealMinutes: minutesUntilNextMeal(),
                            namespace: checkInNamespace,
                            geometryID: Self.checkInGeometryID,
                            onDismiss: { withAnimation(springForCheckIn) { showingCheckIn = false } },
                            onResolved: {
                                withAnimation(springForCheckIn) { showingCheckIn = false }
                                Task { await model.load(showSpinner: false) }
                            },
                            onLogSomethingElse: {
                                withAnimation(springForCheckIn) {
                                    showingCheckIn = false
                                    composerExpanded = true
                                }
                                DispatchQueue.main.async { composerFocused = true }
                            }
                        )
                    }
                }
                .transition(.opacity)
                .zIndex(2)
            }

            if let logger, logger.confirmingPhoto {
                PhotoParseConfirm(
                    model: logger,
                    namespace: photoLogNamespace,
                    imageID: Self.photoImageID,
                    cardID: Self.photoCardID
                ) {
                    Task { await keepPhotoLog() }
                }
                .zIndex(3)
            }
        }
        .animation(Motion.adaptive(Motion.morph, reduceMotion: reduceMotion), value: logger?.confirmingPhoto == true)
        .sheet(item: $selectedMeal) { meal in
            MealDetailSheet(meal: meal) {
                try await model.removeMeal(id: meal.id)
            }
        }
        .toolbar(showingCheckIn || logger?.confirmingPhoto == true ? .hidden : .visible, for: .tabBar)
        .task {
            if logger == nil {
                logger = previewLogger ?? LogMealViewModel(
                    api: env.api,
                    onMealChanged: { env.changes.mealsChanged() }
                )
            }
            if startComposerExpanded {
                composerFocused = true
            }
        }
        .onChange(of: deepLinkCheckInID.wrappedValue) { _, id in
            guard id != nil else { return }
            Task { await openDeepLinkedCheckIn() }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, isLoaded else { return }
            Task {
                await env.push.syncAuthorizationStatus()
                await model.load(showSpinner: false)
            }
        }
        .task { await env.push.syncAuthorizationStatus() }
    }

    private func handleLoggerPhase(_ phase: LogMealViewModel.Phase) {
        switch phase {
        case .parsing:
            composerFocused = false
        case .failed:
            composerExpanded = true
            composerFocused = true
        case let .logged(logged):
            composerExpanded = false
            composerFocused = false
            Haptics.landed()
            if logged.fromPhoto { return }
            Task {
                await model.load(showSpinner: false)
                guard case .logged = logger?.phase else { return }
                logger?.clearAfterSuccess()
            }
        case .compose:
            break
        }
    }

    private func keepPhotoLog() async {
        guard case .logged = logger?.phase else { return }
        withAnimation(springForCheckIn) {
            logger?.endConfirm()
        }
        await model.load(showSpinner: false)
        guard case .logged = logger?.phase else { return }
        logger?.clearAfterSuccess()
    }

    private func openCheckIn() {
        Haptics.nudge()
        composerFocused = false
        composerExpanded = false
        withAnimation(springForCheckIn) { showingCheckIn = true }
    }

    private func openDeepLinkedCheckIn() async {
        let target = deepLinkCheckInID.wrappedValue
        await model.load(showSpinner: false)
        if let target, activeCheckIn?.id == target {
            openCheckIn()
        }
        deepLinkCheckInID.wrappedValue = nil
    }

    private var isLoaded: Bool {
        if case .loaded = model.phase { return true }
        return false
    }

    private var springForCheckIn: Animation {
        Motion.adaptive(Motion.morph, reduceMotion: reduceMotion)
    }

    private var photoLandingCardID: String? {
        guard logger?.confirmingPhoto != true else { return nil }
        if case let .logged(logged) = logger?.phase, logged.fromPhoto {
            return Self.photoCardID
        }
        return nil
    }

    @ViewBuilder
    private var homeLayer: some View {
        switch model.phase {
        case .loading:
            HomeSkeletonView()
        case let .failed(message):
            RetryState(message: message) { Task { await model.load() } }
        case .needsOnboarding:
            HomeSkeletonView() // onboarding is presented by MainTabView
        case let .loaded(home):
            loaded(home)
        }
    }

    @ViewBuilder
    private func loaded(_ home: HomeResponse) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Today")
                        .font(Typography.display(34))
                        .foregroundStyle(Palette.ink)
                    Text(now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        .font(Typography.data(13, weight: .medium))
                        .foregroundStyle(Palette.inkFaint)
                }
                .appearIn(0)

                if home.enforcementEnabled, env.push.authorizationStatus == .denied {
                    NotificationsOffBanner()
                        .appearIn(1)
                }

                TodayNowSurface(
                    home: home,
                    checkIn: showingCheckIn ? nil : home.activeCheckIn,
                    namespace: checkInNamespace,
                    geometryID: Self.checkInGeometryID,
                    onOpenCheckIn: openCheckIn
                )
                    .appearIn(1)

                if let logger {
                    actionDock(home: home, logger: logger)
                        .onChange(of: logger.phase) { _, phase in
                            handleLoggerPhase(phase)
                        }
                        .appearIn(2)
                }

                TodayDayFeed(
                    meals: visibleMeals(home.meals),
                    pending: pendingMeal,
                    currentSlot: DaySlot.assigning(now, times: home.resolvedMealTimes),
                    currentClock: DaySlot.assigning(now, times: home.resolvedMealTimes).clock(in: home.resolvedMealTimes),
                    mealTimes: home.resolvedMealTimes,
                    landingNamespace: photoLogNamespace,
                    landingCardID: photoLandingCardID,
                    onOpenMeal: { selectedMeal = $0 }
                )
                .appearIn(3)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.md)
            .padding(.bottom, Space.xl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await model.load(showSpinner: false) }
    }

    @ViewBuilder
    private func actionDock(home: HomeResponse, logger: LogMealViewModel) -> some View {
        switch logger.phase {
        case .parsing:
            TodayLogStatus(
                title: logger.submittedPrompt.isEmpty ? "Working it out…" : logger.submittedPrompt,
                detail: "Updating today.",
                working: true
            )

        case let .logged(logged):
            if !logger.confirmingPhoto {
                TodayLogStatus(
                    title: logged.summary ?? "Meal logged",
                    detail: logged.resolvedCheckIn
                        ? "\(logged.kcal) kcal · resolved"
                        : "\(logged.kcal) kcal",
                    working: false
                )
            }

        case .failed:
            composerSurface(logger)

        case .compose:
            if composerExpanded {
                composerSurface(logger)
            } else if home.activeCheckIn != nil {
                ActionButton(
                    title: (home.activeCheckIn?.tier ?? 0) >= 3 ? "Let’s talk" : "Check-in"
                ) {
                    openCheckIn()
                }
            } else if home.ledger.mealsToday == 0 {
                composerSurface(logger)
            } else {
                Button {
                    openComposer()
                } label: {
                    HStack(spacing: Space.sm) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(home.framing.primaryCta == "log_meal" ? Color.white : Palette.inkSoft)
                            .frame(width: 34, height: 34)
                            .background(
                                home.framing.primaryCta == "log_meal" ? Palette.accent : Palette.surfaceSunk,
                                in: Circle()
                            )
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Log meal")
                                .font(Typography.data(16, weight: .semibold))
                                .foregroundStyle(Palette.ink)
                            Text(home.framing.primaryCta == "log_meal"
                                 ? "Update today."
                                 : "Add another.")
                                .font(Typography.data(12))
                                .foregroundStyle(Palette.inkFaint)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .fill(home.framing.primaryCta == "log_meal" ? Palette.accentTint : Palette.surface)
                            .elevation(.resting)
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                    .strokeBorder(home.framing.primaryCta == "log_meal"
                                                  ? Palette.accent.opacity(0.3)
                                                  : Palette.hairline)
                            )
                    }
                }
                .buttonStyle(PressableCard())
            }
        }
    }

    private func composerSurface(_ logger: LogMealViewModel) -> some View {
        Card(tint: Palette.surfaceRaised, elevation: .floating, padding: 14) {
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack {
                    Text("What you ate")
                        .font(Typography.voice(18))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    if composerExpanded {
                        Button {
                            composerFocused = false
                            withAnimation(Motion.settle) { composerExpanded = false }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Palette.inkFaint)
                                .frame(width: 28, height: 28)
                                .background(Palette.surfaceSunk, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close meal logger")
                    }
                }

                SearchComposer(
                    model: logger,
                    focused: $composerFocused,
                    onSubmit: { Task { await logger.submit() } },
                    photoNamespace: photoLogNamespace,
                    photoGeometryID: Self.photoImageID
                )
            }
        }
    }

    private func openComposer() {
        withAnimation(Motion.settle) { composerExpanded = true }
        DispatchQueue.main.async { composerFocused = true }
    }

    private func visibleMeals(_ meals: [MealSummary]) -> [MealSummary] {
        guard case let .logged(logged) = logger?.phase else { return meals }
        return meals.filter { $0.id != logged.mealId }
    }

    private var pendingMeal: DayTimeline.Pending? {
        if logger?.confirmingPhoto == true { return nil }
        switch logger?.phase {
        case .parsing:
            let title = logger?.submittedPrompt ?? ""
            return .parsing(title: title.isEmpty ? "Estimating…" : title)
        case let .logged(logged):
            return .logged(title: logged.summary ?? "Logged", kcal: logged.kcal)
        default:
            return nil
        }
    }
}

private struct RetryState: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text(message)
                .font(Typography.data(15))
                .foregroundStyle(Palette.inkSoft)
                .multilineTextAlignment(.center)
            ActionButton(title: "Try again", kind: .secondary, action: retry)
                .frame(maxWidth: 200)
        }
        .padding(28)
    }
}

struct HomeSkeletonView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    SkeletonBlock(width: 108, height: 36, radius: 10)
                    SkeletonBlock(width: 184, height: 13)
                }

                SkeletonCard(height: 188) {
                    VStack(alignment: .leading, spacing: Space.md) {
                        HStack {
                            SkeletonBlock(width: 82, height: 12)
                            Spacer()
                            SkeletonBlock(width: 64, height: 25, radius: Radius.pill)
                        }
                        SkeletonBlock(width: 170, height: 27, radius: 9)
                        SkeletonBlock(width: 246, height: 14)
                        Spacer()
                        HStack(spacing: Space.xs) {
                            SkeletonBlock(height: 9, radius: Radius.pill)
                            SkeletonBlock(height: 9, radius: Radius.pill)
                            SkeletonBlock(height: 9, radius: Radius.pill)
                        }
                    }
                }

                SkeletonCard(height: 64) {
                    HStack(spacing: Space.sm) {
                        SkeletonBlock(width: 36, height: 36, radius: 18)
                        VStack(alignment: .leading, spacing: 6) {
                            SkeletonBlock(width: 112, height: 15)
                            SkeletonBlock(width: 190, height: 11)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Space.sm) {
                    SkeletonBlock(width: 86, height: 13)
                    ForEach(0..<3, id: \.self) { index in
                        HStack(spacing: Space.sm) {
                            SkeletonBlock(width: 44, height: 44, radius: 14)
                            VStack(alignment: .leading, spacing: 6) {
                                SkeletonBlock(width: index == 1 ? 126 : 154, height: 14)
                                SkeletonBlock(width: 88, height: 11)
                            }
                            Spacer()
                            SkeletonBlock(width: 48, height: 14)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.md)
            .padding(.bottom, Space.xl)
        }
        .background(Palette.background.ignoresSafeArea())
        .scrollDisabled(true)
        .skeletonLoading()
    }
}

#if DEBUG
#Preview("Loaded — under target") {
    HomeContent(model: .previewed(.loaded(.sampleUnder)))
        .environment(AppEnvironment.preview())
}

#Preview("Loaded — over target") {
    HomeContent(model: .previewed(.loaded(.sampleOver)))
        .environment(AppEnvironment.preview())
}

#Preview("Empty") {
    HomeContent(model: .previewed(.loaded(.sampleEmpty)))
        .environment(AppEnvironment.preview())
}

#Preview("Composer expanded") {
    HomeContent(model: .previewed(.loaded(.sampleEmpty)), startComposerExpanded: true)
        .environment(AppEnvironment.preview())
}

#Preview("Parsing") {
    HomeContent(
        model: .previewed(.loaded(.sampleEmpty)),
        previewLogger: .sampleParsing,
        previewNow: Calendar.current.date(bySettingHour: 13, minute: 0, second: 0, of: Date())
    )
    .environment(AppEnvironment.preview())
}
#endif
