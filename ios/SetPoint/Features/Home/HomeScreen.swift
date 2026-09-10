import SwiftUI

/// Today (§5.2), rebuilt around one question: am I on pace today, and what do I
/// do next? The manager's line, the day (what's left, protein, the day track,
/// pace), one Next card, and the meal log under each meal time. Logging lives in
/// `LogDock`, pinned above the tab bar so it's in the same place in every state.
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
    }

    private static let checkInGeometryID = "active-check-in"
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
                    } else {
                        PrescriptionView(
                            checkIn: checkIn,
                            nextMealMinutes: minutesUntilNextMeal(),
                            namespace: checkInNamespace,
                            geometryID: Self.checkInGeometryID,
                            onDismiss: closeCheckIn,
                            onResolved: {
                                closeCheckIn()
                                Task { await model.load(showSpinner: false) }
                            },
                            onLogSomethingElse: {
                                closeCheckIn()
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
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                if home.enforcementEnabled, env.push.authorizationStatus == .denied {
                    NotificationsOffBanner()
                        .appearIn(0)
                }

                VStack(alignment: .leading, spacing: Space.md) {
                    TodayHeader(date: now, note: home.managerNote)
                        .appearIn(0)

                    DayPanel(home: home)
                        .appearIn(1)

                    if TodayNext.resolve(home) != .quiet {
                        NextCard(
                            home: home,
                            showsCheckIn: !showingCheckIn,
                            namespace: checkInNamespace,
                            geometryID: Self.checkInGeometryID,
                            busy: checkInBusy,
                            error: checkInError,
                            onOpenCheckIn: openCheckIn,
                            onAteThis: ateThis,
                            onSomethingElse: focusDock,
                            onSnooze: { choosingSnooze = true },
                            onLog: focusDock
                        )
                        .appearIn(2)
                    }
                }

                MealLog(
                    home: home,
                    pending: pendingMeal,
                    landingNamespace: photoLogNamespace,
                    landingCardID: photoLandingCardID,
                    onOpenMeal: { selectedMeal = $0 },
                    onLogMissed: logMissed
                )
                .appearIn(3)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.sm)
            .padding(.bottom, Space.lg)
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

    private func focusDock() {
        composerFocused = true
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
