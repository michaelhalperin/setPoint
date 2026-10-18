import SwiftUI

/// Today: the fuel orb as hero — how much of the day's food is in, what's next,
/// and the day's plates — or, when a check-in fires, the check-in itself with the
/// plate to eat. Calories and protein sit in a strip below, then the meal log.
/// Logging rises from the nav's "+" as `LogDock`.
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
    @State private var showingPaywall = false
    @State private var checkInBusy = false
    @State private var checkInError: String?
    @State private var topUpBusy = false
    @State private var logOpen = false
    @AppStorage("topUpDismissed") private var topUpDismissed = ""
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
                    } else if let home = loadedHome, checkIn.kind == "REFUEL" {
                        RefuelSheet(
                            checkIn: checkIn,
                            dinnerMin: home.resolvedMealTimes.dinnerMin,
                            remainingSeconds: refuelSecondsLeft(home: home),
                            onHadThis: ateThis,
                            onCoveredByDinner: coverRefuel,
                            onDismiss: closeCheckIn
                        )
                        .transition(.move(edge: .bottom))
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
                            },
                            suggestSmallerDefault: home.appetite?.suggestSmallerDefault == true,
                            appetiteLevel: home.appetite?.level
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
        .animation(Motion.adaptive(Motion.sheet, reduceMotion: reduceMotion), value: logOpen)
        .sheet(item: $selectedMeal) { meal in
            MealDetailSheet(
                meal: meal,
                onRemove: {
                    try await model.removeMeal(id: meal.id)
                },
                onSaveAsMeal: {
                    logger?.openEditor(from: meal)
                    selectedMeal = nil
                }
            )
        }
        .fullScreenCover(isPresented: scannerPresented) {
            BarcodeScannerView(
                onCode: { code in
                    Task { await logger?.handleScannedCode(code) }
                },
                onCancel: {
                    logger?.showScanner = false
                    logger?.mode = .type
                }
            )
        }
        .sheet(item: productBinding) { product in
            BarcodeProductSheet(
                product: Binding(
                    get: { logger?.product ?? product },
                    set: { logger?.product = $0 }
                ),
                slotTitle: logSlotTitle,
                logging: {
                    if case .parsing = logger?.phase { return true }
                    return false
                }(),
                onLog: { Task { await logger?.logBarcode() } },
                onSave: { logger?.openEditorToSaveProduct() },
                onClose: {
                    logger?.product = nil
                    logger?.mode = .type
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: editorBinding) { draft in
            SavedMealEditorView(
                draft: draft,
                saving: logger?.editorSaving ?? false,
                error: logger?.editorError,
                onSave: { await logger?.saveEditor($0) ?? false }
            )
        }
        .sheet(isPresented: $choosingSnooze) {
            let choices = CheckInActions.snoozeChoices(nextMealMinutes: minutesUntilNextMeal())
            SnoozeSheet(choices: choices) { minutes in
                snooze(minutes: minutes)
            }
            .presentationDetents([.height(SnoozeSheet.height(for: choices.count))])
            .presentationDragIndicator(.visible)
            .presentationBackground(Palette.sheet)
            .presentationCornerRadius(32)
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
                .presentationDetents([.large])
        }
        .onChange(of: hidesNav, initial: true) { _, hidden in
            env.chrome.navHidden = hidden
        }
        .onChange(of: env.chrome.logRequest) { _, _ in
            openLog()
        }
        .task {
            if logger == nil {
                logger = previewLogger ?? LogMealViewModel(
                    api: env.api,
                    onMealChanged: { env.changes.mealsChanged() }
                )
            }
            if startComposerExpanded {
                openLog(focus: true)
            }

            await env.push.syncAuthorizationStatus()
        }
        .onChange(of: logOpen) { _, open in
            guard open, let meals = loadedHome?.meals else { return }
            Task {
                await logger?.loadRecents(today: meals)
                if previewLogger == nil {
                    await logger?.loadSavedMeals()
                }
            }
        }
        .onChange(of: logger?.phase) { _, phase in
            if let phase { handleLoggerPhase(phase) }
        }
        .onChange(of: deepLinkCheckInID.wrappedValue) { _, id in
            guard id != nil else { return }
            Task { await openDeepLinkedCheckIn() }
        }
        .onChange(of: env.changes.pendingLogPhoto) { _, pending in
            guard pending else { return }
            env.changes.pendingLogPhoto = false
            openLog()
            logger?.mode = .photo
            logger?.showPhotoPicker = true
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, isLoaded else { return }
            Task {
                await env.push.syncAuthorizationStatus()
                await env.calendar.uploadBusy()
                await env.health.uploadWorkouts()
                await model.load(showSpinner: false)
            }
        }
        .onChange(of: activeCheckIn?.id) { _, id in
            if activeCheckIn?.kind == "REFUEL" {
                showingCheckIn = true
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
                if moment.takesOver, let checkIn = home.activeCheckIn, checkIn.kind != "REFUEL" {
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
                        if let since = model.staleSince {
                            StaleBanner(since: since) { Task { await model.load(showSpinner: false) } }
                        }
                        if home.enforcementEnabled, env.push.authorizationStatus == .denied {
                            NotificationsOffBanner()
                        }
                        TodayHero(home: home, moment: moment, date: now) {
                            Task { await model.load(showSpinner: false) }
                        }
                    }
                    .padding(.horizontal, Space.gutter)
                    .padding(.top, Space.xs)
                    .transition(.opacity)
                }

                VStack(alignment: .leading, spacing: Space.lg) {
                    if !moment.takesOver {
                        if AppetiteTodayVisibility.resolve(home: home) != .ask {
                            AppetiteTodayLine(home: home) {
                                Task { await model.load(showSpinner: false) }
                            }
                            .appearIn(0)
                        }

                        if let topUp = home.topUp, topUpDismissed != TopUpDismissal.key(for: topUp, now: now) {
                            TopUpCard(
                                topUp: topUp,
                                busy: topUpBusy,
                                onAdd: { addTopUp(topUp) },
                                onDismiss: { topUpDismissed = TopUpDismissal.key(for: topUp, now: now) }
                            )
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }

                    FuelStrip(home: home, moment: moment)
                        .appearIn(1)

                    MealLog(
                        home: home,
                        pending: pendingMeal,
                        landingNamespace: photoLogNamespace,
                        landingCardID: photoLandingCardID,
                        onOpenMeal: { meal in
                            selectedMeal = meal
                        },
                        onLogMissed: logMissed
                    )
                    .appearIn(2)
                }
                .padding(.horizontal, Space.gutter)
            }
            .padding(.bottom, Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .top) {
                if !moment.takesOver {
                    AmbientGlow(tone: moment == .quiet ? .quiet : .mixed)
                        .offset(y: 20)
                }
            }
            .animation(Motion.adaptive(Motion.morph, reduceMotion: reduceMotion), value: moment.takesOver)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await model.load(showSpinner: false) }
        .overlay {
            if logOpen {
                Palette.scrim
                    .ignoresSafeArea()
                    .onTapGesture(perform: closeLog)
                    .transition(.opacity)
                    .accessibilityLabel("Close")
                    .accessibilityAddTraits(.isButton)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let logger {
                if logOpen {
                    LogDock(
                        logger: logger,
                        focused: $composerFocused,
                        estimateKcal: estimateKcal(for: home),
                        currentSlot: TodayLayout.slot(forMinute: home.day?.nowMin ?? TodayLayout.minuteOfDay(from: now), times: home.resolvedMealTimes),
                        photoNamespace: photoLogNamespace,
                        photoGeometryID: Self.photoImageID,
                        onClose: closeLog
                    ) {
                        Task { await logger.submit() }
                    }
                    .transition(.move(edge: .bottom))
                } else {
                    LogStatusToast(logger: logger)
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: Actions

    private func openLog(focus: Bool = false) {
        guard !showingCheckIn else { return }
        withAnimation(Motion.adaptive(Motion.sheet, reduceMotion: reduceMotion)) { logOpen = true }
        if focus {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { composerFocused = true }
        }
    }

    private func closeLog() {
        composerFocused = false
        logger?.backdate = nil
        withAnimation(Motion.adaptive(Motion.sheet, reduceMotion: reduceMotion)) { logOpen = false }
    }

    private var hidesNav: Bool {
        showingCheckIn || logOpen || logger?.confirmingPhoto == true
    }

    private func openCheckIn() {
        Haptics.nudge()
        composerFocused = false
        logOpen = false
        withAnimation(springForCheckIn) { showingCheckIn = true }
    }

    private func closeCheckIn() {
        withAnimation(springForCheckIn) { showingCheckIn = false }
    }

    private func refuelSecondsLeft(home: HomeResponse) -> Int {
        guard let until = home.training?.refuelUntilMin else { return 45 * 60 }
        let left = until - (home.day?.nowMin ?? 0)
        return max(0, left * 60)
    }

    private func coverRefuel() {
        guard let checkIn = activeCheckIn, !checkInBusy else { return }
        checkInBusy = true
        checkInError = nil
        Task {
            do {
                try await CheckInActions.cover(checkInID: checkIn.id, api: env.api)
                closeCheckIn()
                await model.load(showSpinner: false)
            } catch {
                checkInError = UserFacingError.message(for: error, fallback: "Couldn't close that. Try again.")
            }
            checkInBusy = false
        }
    }

    /// After "I already ate": open the dock at the meal's time so logging it is one step.
    private func offerQuickLog(for checkIn: HomeResponse.ActiveCheckIn) {
        Task { await model.load(showSpinner: false) }
        if let slot = checkIn.slot.flatMap(MealSlot.init(rawValue:)) {
            let times = loadedHome?.resolvedMealTimes ?? .standard
            let at = slot == .breakfast ? times.breakfastMin : slot == .lunch ? times.lunchMin : times.dinnerMin
            logger?.backdate = .init(slot: slot, at: TodayLayout.today(atMin: at, now: now))
        }
        openLog()
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

    private func addTopUp(_ topUp: HomeResponse.TopUp) {
        guard let logger, !topUpBusy else { return }
        topUpBusy = true
        Task {
            await logger.logMacros(
                summary: topUp.logText,
                kcal: topUp.totalKcal,
                proteinG: topUp.totalProteinG,
                carbsG: topUp.totalCarbsG,
                fatG: topUp.totalFatG
            )
            topUpBusy = false
        }
    }

    /// A usual-size meal for "About a normal lunch": the day's target split
    /// across the meals the user eats.
    private func estimateKcal(for home: HomeResponse) -> Int? {
        guard home.ledger.targetKcal > 0 else { return nil }
        let meals = 3 + (home.appetite?.extraSlots.count ?? 0)
        let share = Double(home.ledger.targetKcal) / Double(meals)
        return max(200, Int((share / 50).rounded()) * 50)
    }

    private func logMissed(_ slot: HomeResponse.Day.Slot) {
        logger?.backdate = .init(slot: slot.meal, at: TodayLayout.today(atMin: slot.atMin, now: now))
        openLog()
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
            withAnimation(Motion.adaptive(Motion.sheet, reduceMotion: reduceMotion)) { logOpen = false }
        case .failed:
            openLog(focus: true)
        case .queued:
            composerFocused = false
            withAnimation(Motion.adaptive(Motion.sheet, reduceMotion: reduceMotion)) { logOpen = false }
        case let .logged(logged):
            composerFocused = false
            withAnimation(Motion.adaptive(Motion.sheet, reduceMotion: reduceMotion)) { logOpen = false }
            Haptics.landed()
            if logged.fromPhoto { return }
            landLoggedMeal()
            logger?.clearAfterSuccess()
            Task { await model.load(showSpinner: false) }
        case .compose:
            break
        }
    }

    /// Place the just-logged meal under its slot immediately, so Today doesn't
    /// show it in the wrong section until Home reloads.
    private func landLoggedMeal() {
        guard let logger, let meal = logger.pendingMealSummary() else { return }
        model.applyLoggedMeal(meal, slot: pendingSlot)
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

    private var scannerPresented: Binding<Bool> {
        Binding(
            get: { logger?.showScanner == true },
            set: { on in
                logger?.showScanner = on
                if !on { logger?.mode = .type }
            }
        )
    }

    private var productBinding: Binding<LogMealViewModel.BarcodeProduct?> {
        Binding(get: { logger?.product }, set: { logger?.product = $0 })
    }

    private var editorBinding: Binding<SavedMealDraft?> {
        Binding(get: { logger?.editor }, set: { logger?.editor = $0 })
    }

    private var logSlotTitle: String {
        if let backdate = logger?.backdate { return backdate.slot.title }
        return loadedHome?.day?.slots.first { $0.slotState == .now }?.meal.title ?? "Now"
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

    private var pendingMeal: TodayPending? {
        if logger?.confirmingPhoto == true { return nil }
        let slot = pendingSlot
        switch logger?.phase {
        case .parsing:
            let title = logger?.submittedPrompt ?? ""
            return .parsing(title: title.isEmpty ? "Estimating…" : title, slot: slot)
        case let .logged(logged):
            // Once Home has the real meal — from the optimistic insert or a
            // reload — don't show it twice.
            if loadedHome?.meals.contains(where: { $0.id == logged.mealId }) == true { return nil }
            return .logged(title: logged.summary ?? "Logged", kcal: logged.kcal, slot: slot)
        default:
            return nil
        }
    }

    /// Where an in-flight log belongs: an explicit backdate (Add breakfast),
    /// else the slot closest to the time it was logged, matching the backend.
    private var pendingSlot: MealSlot {
        if let slot = logger?.submittedSlot { return slot }
        let times = loadedHome?.resolvedMealTimes ?? .standard
        let minute: Int
        if let at = logger?.submittedLoggedAt {
            minute = TodayLayout.minuteOfDay(from: at)
        } else {
            minute = loadedHome?.day?.nowMin ?? TodayLayout.minuteOfDay(from: now)
        }
        return TodayLayout.slot(forMinute: minute, times: times)
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
        VStack(spacing: Space.md) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    SkeletonBlock(width: 110, height: 20, radius: 6)
                    SkeletonBlock(width: 60, height: 10)
                }
                Spacer()
            }
            ZStack {
                Circle().stroke(Palette.idleRing, lineWidth: 4)
                Circle().fill(Palette.surfaceSunk).padding(30)
                VStack(spacing: 8) {
                    SkeletonBlock(width: 96, height: 40, radius: 10)
                    SkeletonBlock(width: 80, height: 10)
                }
            }
            .frame(width: 240, height: 240)
            .padding(.top, Space.xs)
            SkeletonBlock(width: 170, height: 34, radius: 17)
            SkeletonCard(height: 150) {
                VStack(alignment: .leading, spacing: 12) {
                    SkeletonBlock(width: 140, height: 10)
                    SkeletonBlock(width: 220, height: 26, radius: 8)
                    SkeletonBlock(width: 180, height: 14)
                }
            }
            .padding(.top, Space.xs)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.xs)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.background.ignoresSafeArea())
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

#Preview("Skeleton") {
    HomeSkeletonView()
}
#endif
