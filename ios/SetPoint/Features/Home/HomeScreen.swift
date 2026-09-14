import SwiftUI

/// Today (§5.2): the day dial as hero — what's logged, what's due, and when the
/// next check-in comes — or, when a check-in fires, a terracotta takeover with the
/// meal to eat. Calories and protein sit in a strip below, then the meal log.
/// Logging lives in `LogDock`, pinned above the tab bar in every state.
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
    @State private var choosingSnooze = false
    @State private var checkInBusy = false
    @State private var checkInError: String?
    @FocusState private var composerFocused: Bool
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
    }

    private static let photoImageID = "photo-log-image"
    private static let photoCardID = "photo-log-card"

    private var loadedHome: HomeResponse? {
        if case let .loaded(home) = model.phase { return home }
        return nil
    }

    private var activeCheckIn: HomeResponse.ActiveCheckIn? { loadedHome?.activeCheckIn }

    private var now: Date { previewNow ?? Date() }

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
                            onDismiss: closeCheckIn,
                            onResolved: {
                                closeCheckIn()
                                Task { await model.load(showSpinner: false) }
                            }
                        )
                        .transition(.opacity)
                    } else if let home = loadedHome {
                        PrescriptionView(
                            checkIn: checkIn,
                            headline: TodayCopy.headline(TodayMoment.resolve(home)),
                            whyNow: TodayCopy.whyNow(home, now: now),
                            nextMealMinutes: minutesUntilNextMeal(),
                            onDismiss: closeCheckIn,
                            onResolved: {
                                closeCheckIn()
                                Task { await model.load(showSpinner: false) }
                            },
                            onAlreadyAte: {
                                closeCheckIn()
                                offerQuickLog(for: checkIn)
                            }
                        )
                        .transition(.move(edge: .bottom))
                    }
                }
                .zIndex(2)
            }

            if let logger, logger.confirmingPhoto {
                PhotoParseConfirm(
                    model: logger,
                    namespace: photoLogNamespace,
                    imageID: Self.photoImageID,
                    cardID: Self.photoCardID,
                    countsFor: loadedHome?.day?.slots.first { $0.slotState == .now }?.meal
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
        .confirmationDialog("Snooze this check-in", isPresented: $choosingSnooze, titleVisibility: .visible) {
            ForEach(CheckInActions.snoozeChoices(nextMealMinutes: minutesUntilNextMeal())) { choice in
                Button(choice.title) { snooze(minutes: choice.minutes) }
            }
            Button("Cancel", role: .cancel) {}
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

            await env.push.syncAuthorizationStatus()
        }
        .onChange(of: composerFocused) { _, isFocused in
            guard isFocused, let meals = loadedHome?.meals else { return }
            Task { await logger?.loadRecents(today: meals) }
        }
        .onChange(of: logger?.phase) { _, phase in
            if let phase { handleLoggerPhase(phase) }
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
    }

    // MARK: Layers

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

    private func loaded(_ home: HomeResponse) -> some View {
        let moment = TodayMoment.resolve(home)
        return ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                if moment.takesOver, let checkIn = home.activeCheckIn {
                    CheckInTakeover(
                        home: home,
                        checkIn: checkIn,
                        moment: moment,
                        busy: checkInBusy,
                        error: checkInError,
                        onOpen: openCheckIn,
                        onAteThis: ateThis,
                        onAlreadyAte: alreadyAte,
                        onSnooze: { choosingSnooze = true }
                    )
                    .transition(.opacity)
                } else {
                    VStack(alignment: .leading, spacing: Space.md) {
                        if home.enforcementEnabled, env.push.authorizationStatus == .denied {
                            NotificationsOffBanner()
                        }
                        TodayHero(home: home, moment: moment, date: now)
                    }
                    .padding(.horizontal, Space.gutter)
                    .padding(.top, Space.sm)
                    .transition(.opacity)
                }

                VStack(alignment: .leading, spacing: Space.lg) {
                    FuelStrip(home: home, moment: moment)
                        .appearIn(1)

                    MealLog(
                        home: home,
                        pending: pendingMeal,
                        landingNamespace: photoLogNamespace,
                        landingCardID: photoLandingCardID,
                        onOpenMeal: { selectedMeal = $0 },
                        onLogMissed: logMissed
                    )
                    .appearIn(2)
                }
                .padding(.horizontal, Space.gutter)
            }
            .padding(.bottom, Space.lg)
            .animation(Motion.adaptive(Motion.morph, reduceMotion: reduceMotion), value: moment.takesOver)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await model.load(showSpinner: false) }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let logger {
                LogDock(
                    logger: logger,
                    focused: $composerFocused,
                    photoNamespace: photoLogNamespace,
                    photoGeometryID: Self.photoImageID
                ) {
                    Task { await logger.submit() }
                }
            }
        }
    }

    // MARK: Actions

    private func openCheckIn() {
        Haptics.nudge()
        composerFocused = false
        withAnimation(springForCheckIn) { showingCheckIn = true }
    }

    private func closeCheckIn() {
        withAnimation(springForCheckIn) { showingCheckIn = false }
    }

    /// After "I already ate": open the dock at the meal's time so logging it is one step.
    private func offerQuickLog(for checkIn: HomeResponse.ActiveCheckIn) {
        Task { await model.load(showSpinner: false) }
        if let slot = checkIn.slot.flatMap(MealSlot.init(rawValue:)) {
            let times = loadedHome?.resolvedMealTimes ?? .standard
            let at = slot == .breakfast ? times.breakfastMin : slot == .lunch ? times.lunchMin : times.dinnerMin
            logger?.backdate = .init(slot: slot, at: TodayLayout.today(atMin: at, now: now))
        }
        DispatchQueue.main.async { composerFocused = true }
    }

    private func alreadyAte() {
        guard let checkIn = activeCheckIn, !checkInBusy else { return }
        checkInBusy = true
        checkInError = nil
        Task {
            do {
                try await CheckInActions.alreadyAte(checkInID: checkIn.id, api: env.api)
                offerQuickLog(for: checkIn)
            } catch {
                checkInError = UserFacingError.message(for: error, fallback: "Couldn't close that. Try again.")
            }
            checkInBusy = false
        }
    }

    private func logMissed(_ slot: HomeResponse.Day.Slot) {
        logger?.backdate = .init(slot: slot.meal, at: TodayLayout.today(atMin: slot.atMin, now: now))
        composerFocused = true
    }

    private func ateThis() {
        guard let prescription = activeCheckIn?.prescription, !checkInBusy else { return }
        checkInBusy = true
        checkInError = nil
        Task {
            do {
                try await CheckInActions.eat(prescriptionID: prescription.id, api: env.api)
                Haptics.landed()
                env.changes.mealsChanged()
                await model.load(showSpinner: false)
            } catch {
                checkInError = UserFacingError.message(for: error, fallback: "Couldn't log that. Try again.")
            }
            checkInBusy = false
        }
    }

    private func snooze(minutes: Int) {
        guard let checkIn = activeCheckIn, !checkInBusy else { return }
        checkInBusy = true
        checkInError = nil
        Task {
            do {
                try await CheckInActions.snooze(checkInID: checkIn.id, minutes: minutes, api: env.api)
                await model.load(showSpinner: false)
            } catch {
                checkInError = UserFacingError.message(for: error, fallback: "Couldn't snooze. Try again.")
            }
            checkInBusy = false
        }
    }

    private func handleLoggerPhase(_ phase: LogMealViewModel.Phase) {

        switch phase {
        case .parsing:
            composerFocused = false
        case .failed:
            composerFocused = true
        case let .logged(logged):
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

    private func openDeepLinkedCheckIn() async {
        let target = deepLinkCheckInID.wrappedValue
        await model.load(showSpinner: false)
        if let target, activeCheckIn?.id == target {
            openCheckIn()
        }
        deepLinkCheckInID.wrappedValue = nil
    }

    // MARK: Derived

    private var isLoaded: Bool { loadedHome != nil }

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

    private var pendingMeal: TodayPending? {
        if logger?.confirmingPhoto == true { return nil }
        switch logger?.phase {
        case .parsing:
            let title = logger?.submittedPrompt ?? ""
            return .parsing(title: title.isEmpty ? "Estimating…" : title)
        case let .logged(logged):
            // Once Home reloads, the real meal is in the log — don't show it twice.
            if loadedHome?.meals.contains(where: { $0.id == logged.mealId }) == true { return nil }
            return .logged(title: logged.summary ?? "Logged", kcal: logged.kcal)
        default:
            return nil
        }
    }

    /// Minutes until the next meal time — the "after my next meal" snooze.
    private func minutesUntilNextMeal() -> Int {
        if let day = loadedHome?.day, let next = day.pace?.next, next.atMin > day.nowMin {
            return next.atMin - day.nowMin
        }
        let times = loadedHome?.resolvedMealTimes ?? .standard
        let calendar = Calendar.current
        let nowMin = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        let anchors = [times.breakfastMin, times.lunchMin, times.dinnerMin].sorted()
        if let next = anchors.first(where: { $0 > nowMin + 20 }) {
            return next - nowMin
        }
        return (1440 - nowMin) + anchors[0]
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
            VStack(alignment: .leading, spacing: Space.md) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    SkeletonBlock(width: 150, height: 13)
                    SkeletonBlock(height: 22, radius: 8)
                    SkeletonBlock(width: 220, height: 22, radius: 8)
                }

                SkeletonCard(height: 196) {
                    VStack(alignment: .leading, spacing: Space.md) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 8) {
                                SkeletonBlock(width: 150, height: 40, radius: 10)
                                SkeletonBlock(width: 120, height: 12)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 6) {
                                SkeletonBlock(width: 56, height: 10)
                                SkeletonBlock(width: 70, height: 20)
                                SkeletonBlock(width: 84, height: 5, radius: 3)
                            }
                        }
                        SkeletonBlock(height: 6, radius: 3)
                        SkeletonBlock(width: 200, height: 12)
                    }
                }

                SkeletonCard(height: 76) {
                    HStack(spacing: Space.sm) {
                        SkeletonBlock(width: 40, height: 40, radius: 20)
                        VStack(alignment: .leading, spacing: 6) {
                            SkeletonBlock(width: 60, height: 10)
                            SkeletonBlock(width: 170, height: 16)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Space.xs) {
                    SkeletonBlock(width: 120, height: 11)
                    SkeletonCard(height: 64) {
                        SkeletonBlock(width: 180, height: 16)
                    }
                }
                .padding(.top, Space.sm)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.sm)
        }
        .background(Palette.background.ignoresSafeArea())
        .scrollDisabled(true)
        .skeletonLoading()
    }
}

#if DEBUG
#Preview("Check-in") {
    HomeContent(model: .previewed(.loaded(.sampleUnder)))
        .environment(AppEnvironment.preview())
}

#Preview("On pace") {
    HomeContent(model: .previewed(.loaded(.sampleOnPace)))
        .environment(AppEnvironment.preview())
}

#Preview("Missed breakfast") {
    HomeContent(model: .previewed(.loaded(.sampleMissed)))
        .environment(AppEnvironment.preview())
}

#Preview("Over") {
    HomeContent(model: .previewed(.loaded(.sampleOver)))
        .environment(AppEnvironment.preview())
}

#Preview("Quiet mode") {
    HomeContent(model: .previewed(.loaded(.sampleQuiet)))
        .environment(AppEnvironment.preview())
}

#Preview("Logging") {
    HomeContent(model: .previewed(.loaded(.sampleOnPace)), previewLogger: .sampleParsing)
        .environment(AppEnvironment.preview())
}
#endif
