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
    /// Today before a known meal (a usual, a repeat) was shown as eaten — put back
    /// if the server refuses it, or swapped for the real meal when it lands.
    @State private var beforeKnownMeal: HomeResponse?
    @State private var logger: LogMealViewModel?
    @State private var showingCheckIn = false
    @State private var selectedMeal: MealSummary?
    @State private var choosingSnooze = false
    @State private var showingPaywall = false
    @State private var topUpBusy = false
    @State private var logOpen = false
    @State private var showingDay = false
    @State private var showingOrder = false
    @State private var showingNutrition = false
    @State private var reloading = false
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
                            onDismiss: laterTalk,
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
        .navigationDestination(isPresented: $showingDay) {
            if let home = loadedHome {
                TodayDayView(
                    home: home,
                    pending: pendingMeal,
                    date: now,
                    onOpenMeal: { meal in selectedMeal = meal },
                    onLogMissed: { slot in
                        showingDay = false
                        logMissed(slot)
                    },
                    onLog: {
                        showingDay = false
                        openLog()
                    }
                )
            }
        }
        .fullScreenCover(isPresented: $showingOrder) {
            if let home = loadedHome {
                NavigationStack {
                    OrderNearbyView(
                        gapKcal: OrderNearbyContext.gap(home),
                        slotTitle: OrderNearbyContext.slotTitle(home)
                    ) {
                        Task { await model.load(showSpinner: false) }
                    }
                }
            }
        }
        .sheet(item: $selectedMeal) { meal in
            MealDetailSheet(
                meal: meal,
                onRemove: { deleteMeal(meal) },
                onSaveAsMeal: {
                    logger?.openEditor(from: meal)
                    selectedMeal = nil
                },
                onFixed: { Task { await model.load(showSpinner: false) } }
            )
        }
        .fullScreenCover(isPresented: scannerPresented, onDismiss: { logger?.scannerDismissed() }) {
            BarcodeScannerView(
                status: logger?.scanStatus ?? .scanning,
                onCode: { code in
                    Task { await logger?.handleScannedCode(code) }
                },
                onRescan: { logger?.rescan() },
                onType: { logger?.typeInsteadOfScanning() },
                onLabelPhoto: { data in Task { await logger?.readLabel(data) } },
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
        .sheet(item: catalogBinding) { pick in
            CatalogFoodSheet(
                pick: Binding(
                    get: { logger?.catalogPick ?? pick },
                    set: { logger?.catalogPick = $0 }
                ),
                slotTitle: logSlotTitle,
                logging: {
                    if case .parsing = logger?.phase { return true }
                    return false
                }(),
                onLog: { Task { await logger?.logCatalog() } },
                onSave: { logger?.openEditorToSaveCatalog() },
                onClose: { logger?.catalogPick = nil }
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
        .sheet(isPresented: $showingNutrition) {
            NutritionAssistantView()
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(Palette.background)
        }
        .sheet(isPresented: $showingPaywall) {
            if env.flags.isOn(.paywall) {
                PaywallView()
                    .presentationDetents([.large])
            }
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
            if previewLogger == nil {
                await logger?.loadSavedMeals()
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
            logger?.openCamera()
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
            RetryState(message: message, retry: { Task { await model.load() } }, onLog: { openLog() })
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
                        busy: false,
                        error: nil,
                        onOpen: openCheckIn,
                        onAteThis: ateThis,
                        onAlreadyAte: alreadyAte,
                        onSnooze: { choosingSnooze = true },
                        onLater: laterTalk,
                        onOrder: orderAction
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
                        TodayHero(
                            home: home,
                            moment: moment,
                            date: now,
                            picks: picks(for: home, moment: moment),
                            loggingPickID: loggingPickID,
                            onAppetiteChanged: { await model.load(showSpinner: false) },
                            onOpenDay: { showingDay = true },
                            onPick: logPick,
                            onLog: { openLog() },
                            onOpenCheckIn: openCheckIn,
                            onOrder: orderAction,
                            onAskNutrition: env.flags.isOn(.nutritionChat) ? { showingNutrition = true } : nil
                        )
                    }
                    .padding(.horizontal, Space.gutter)
                    .transition(.opacity)
                }

                VStack(alignment: .leading, spacing: Space.lg) {
                    if !moment.takesOver, let topUp = home.topUp, topUpDismissed != TopUpDismissal.key(for: topUp, now: now) {
                        TopUpCard(
                            topUp: topUp,
                            busy: topUpBusy,
                            onAdd: { addTopUp(topUp) },
                            onDismiss: { topUpDismissed = TopUpDismissal.key(for: topUp, now: now) }
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    if moment.takesOver {
                        MealLog(
                            home: home,
                            pending: pendingMeal,
                            landingNamespace: photoLogNamespace,
                            landingCardID: photoLandingCardID,
                            onOpenMeal: { meal in selectedMeal = meal },
                            onLogMissed: logMissed
                        )
                        .appearIn(2)
                    }
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
        .scrollDismissesKeyboard(.interactively)
        .pullToReload({ await model.load(showSpinner: false) }, covering: $reloading)
        .reloadCover(reloading) { HomeSkeletonView() }
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
                        onClose: closeLog,
                        onSubmit: { Task { await logger.submit() } },
                        onOrder: env.flags.isOn(.orderNearby) ? {
                            closeLog()
                            openOrder()
                        } : nil
                    )
                    .transition(.move(edge: .bottom))
                } else {
                    LogStatusToast(
                        logger: logger,
                        onRetry: { openLog() },
                        onDelete: {
                            logger.clearAfterSuccess()
                        }
                    )
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: Order nearby

    /// Deleting is instant: the sheet closes and the meal leaves Today now. If the
    /// server says no, it comes back with "Didn't save · Try again".
    private func deleteMeal(_ meal: MealSummary) {
        Task {
            do {
                try await model.removeMeal(id: meal.id)
            } catch APIError.unauthorized {
                return
            } catch {
                Haptics.nudge()
                env.chrome.reportFailure(retry: { deleteMeal(meal) })
            }
        }
    }

    /// Order nearby, when its flag is on for this user.
    private var orderAction: (() -> Void)? {
        env.flags.isOn(.orderNearby) ? openOrder : nil
    }

    private func openOrder() {
        Haptics.nudge()
        showingOrder = true
    }

    // MARK: Picks

    /// The "Pick one" rows on Today's next card.
    private func picks(for home: HomeResponse, moment: TodayMoment) -> [SavedMeal] {
        let target = home.appetite?.nextPlate?.kcal ?? home.day?.pace?.next?.suggestedKcal
        return TodayPicks.resolve(saved: logger?.savedMeals ?? [], moment: moment, targetKcal: target)
    }

    private var loggingPickID: String? {
        guard let logger, case .parsing = logger.phase else { return nil }
        return logger.savedMeals.first { $0.name == logger.submittedPrompt }?.id
    }

    private func logPick(_ meal: SavedMeal) {
        Haptics.nudge()
        Task { await logger?.logSaved(meal) }
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
        guard let checkIn = activeCheckIn else { return }
        answerCheckIn(retry: coverRefuel) {
            try await CheckInActions.cover(checkInID: checkIn.id, api: env.api)
        }
    }

    /// Check-in answers are instant: the check-in leaves Today now and the request
    /// goes out behind it. If the server says no, it comes back with "Didn't save ·
    /// Try again". `change` adds anything else that should show at once.
    private func answerCheckIn(
        retry: @escaping () -> Void,
        change: (HomeResponse) -> HomeResponse = { $0 },
        then: @escaping () async -> Void = {},
        send: @escaping () async throws -> Void
    ) {
        let before = model.applyNow { change($0.closingCheckIn) }
        closeCheckIn()
        Task {
            do {
                try await send()
                await then()
                await model.load(showSpinner: false)
            } catch APIError.unauthorized {
                return
            } catch {
                if let before { model.restore(before) }
                Haptics.nudge()
                env.chrome.reportFailure(retry: retry)
            }
        }
    }

    /// After "I already ate": open the dock at the meal's time so logging it is one step.
    private func offerQuickLog(for checkIn: HomeResponse.ActiveCheckIn) {
        if let slot = checkIn.slot.flatMap(MealSlot.init(rawValue:)) {
            let times = loadedHome?.resolvedMealTimes ?? .standard
            let at = slot == .breakfast ? times.breakfastMin : slot == .lunch ? times.lunchMin : times.dinnerMin
            logger?.backdate = .init(slot: slot, at: TodayLayout.today(atMin: at, now: now))
        }
        openLog()
    }

    private func alreadyAte() {
        guard let checkIn = activeCheckIn else { return }
        answerCheckIn(retry: alreadyAte) {
            try await CheckInActions.alreadyAte(checkInID: checkIn.id, api: env.api)
        }
        offerQuickLog(for: checkIn)
    }

    /// Close the tier-3 talk without changing the plan. Today comes back.
    private func laterTalk() {
        guard let checkIn = activeCheckIn else {
            closeCheckIn()
            return
        }
        model.ignoreCheckIn(checkIn.id)
        closeCheckIn()
        Task { try? await CheckInActions.alreadyAte(checkInID: checkIn.id, api: env.api) }
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
        guard let checkIn = activeCheckIn, let prescription = checkIn.prescription else { return }
        Haptics.landed()
        // The plate shows on Today now; the reload swaps in the real meal.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plate = MealSummary(
            id: "pending-\(prescription.id)",
            loggedAt: formatter.string(from: Date()),
            kcal: prescription.totalKcal,
            proteinG: prescription.totalProteinG,
            carbsG: 0,
            fatG: 0,
            source: "PRESCRIPTION",
            summary: prescription.items.map(\.name).joined(separator: ", "),
            photoUrl: nil,
            notes: nil,
            items: nil,
            parseConfidence: nil
        )
        let slot = checkIn.slot.flatMap(MealSlot.init(rawValue:))
            ?? TodayLayout.slot(forMinute: loadedHome?.day?.nowMin ?? TodayLayout.minuteOfDay(from: now), times: loadedHome?.resolvedMealTimes ?? .standard)
        answerCheckIn(
            retry: ateThis,
            change: { $0.inserting(plate, into: slot) },
            then: { env.changes.mealsChanged() }
        ) {
            try await CheckInActions.eat(prescriptionID: prescription.id, api: env.api)
        }
    }

    private func snooze(minutes: Int) {
        guard let checkIn = activeCheckIn else { return }
        answerCheckIn(retry: { snooze(minutes: minutes) }) {
            try await CheckInActions.snooze(checkInID: checkIn.id, minutes: minutes, api: env.api)
        }
    }

    private func handleLoggerPhase(_ phase: LogMealViewModel.Phase) {

        switch phase {
        case .parsing:
            composerFocused = false
            withAnimation(Motion.adaptive(Motion.sheet, reduceMotion: reduceMotion)) { logOpen = false }
            if let meal = logger?.pendingKnownMeal {
                let slot = pendingSlot
                beforeKnownMeal = model.applyNow { $0.inserting(meal, into: slot) }
            }
        case .failed:
            if logger?.pendingKnownMeal != nil {
                if let before = beforeKnownMeal { model.restore(before) }
                beforeKnownMeal = nil
                logger?.dropFailedKnown()
                Haptics.nudge()
                env.chrome.reportFailure(retry: { Task { await logger?.retryKnown() } })
                return
            }
            openLog()
        case .queued:
            composerFocused = false
            withAnimation(Motion.adaptive(Motion.sheet, reduceMotion: reduceMotion)) { logOpen = false }
        case let .logged(logged):
            composerFocused = false
            withAnimation(Motion.adaptive(Motion.sheet, reduceMotion: reduceMotion)) { logOpen = false }
            Haptics.landed()
            if logged.fromPhoto { return }
            // Swap the shown-early copy for the real meal in the same frame.
            if let before = beforeKnownMeal { model.restore(before) }
            beforeKnownMeal = nil
            landLoggedMeal()
            env.chrome.noteLogged(mealID: logged.mealId, kcal: logged.kcal, title: logged.summary)
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

    private var catalogBinding: Binding<LogMealViewModel.CatalogPick?> {
        Binding(get: { logger?.catalogPick }, set: { logger?.catalogPick = $0 })
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
            // A known meal is already on Today as eaten.
            if logger?.pendingKnownMeal != nil { return nil }
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

/// Today couldn't load: an unlit orb in a broken ring, and what still works
/// without a connection.
private struct RetryState: View {
    let message: String
    let retry: () -> Void
    var onLog: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [60, 22]))
                        .rotationEffect(.degrees(-90))
                    FuelOrb(size: 160, dimmed: true, glow: 0)
                    Image(systemName: "icloud.slash")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(Palette.hazeSoft)
                        .frame(width: 46, height: 46)
                        .background(Circle().fill(Palette.sheet))
                        .overlay(Circle().strokeBorder(Palette.hazeSoft.opacity(0.4)))
                        .shadow(color: Palette.haze.opacity(0.35), radius: 10)
                        .offset(x: 62, y: 62)
                }
                .frame(width: 240, height: 240)
                .frame(maxWidth: .infinity)
                .padding(.top, 30)
                .accessibilityHidden(true)

                Text("No connection")
                    .font(Typography.mono(11))
                    .tracking(1.3)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.inkFaint)
                    .frame(maxWidth: .infinity)

                Headline("Couldn’t load today.", tail: "You can still log.", size: 38)

                Text(message)
                    .font(Typography.data(13, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)

                HStack(spacing: 8) {
                    tile("Log a meal", "Saved here, sent later")
                    tile("Check-ins", "Run on this phone")
                    tile("Your plan", "From last time")
                }
                .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 4) {
                    ActionButton(title: "Try again", action: retry)
                    if let onLog {
                        Button("Log something anyway", action: onLog)
                            .font(Typography.data(14, weight: .regular))
                            .foregroundStyle(Palette.inkSoft)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, 120)
        }
        .background(alignment: .top) {
            AmbientGlow(tone: .haze, strength: 0.4).offset(y: -40).ignoresSafeArea()
        }
    }

    private func tile(_ title: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(Palette.positive)
                .frame(width: 18, height: 18)
                .background(Palette.positive.opacity(0.14), in: Circle())
            Text(title)
                .font(Typography.data(13, weight: .regular))
                .foregroundStyle(Palette.ink)
            Text(note)
                .font(Typography.data(11, weight: .regular))
                .foregroundStyle(Palette.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glass(radius: 18, fill: Color.white.opacity(0.035))
        .accessibilityElement(children: .combine)
    }
}

/// Today while it loads: the day and date (the phone knows those), a dim orb
/// warming up inside a turning amber arc, and the meal dots pulsing.
struct HomeSkeletonView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Space.md) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Date.now.formatted(.dateTime.weekday(.wide)))
                        .font(Typography.data(20, weight: .regular))
                        .foregroundStyle(Palette.ink)
                    Text("\(Date.now.formatted(.dateTime.day().month(.abbreviated))) · warming up")
                        .font(Typography.mono(11))
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(Palette.inkFaint)
                }
                Spacer()
            }
            ZStack {
                Circle().stroke(Color.white.opacity(0.07), lineWidth: 4)
                TimelineView(.animation(paused: reduceMotion)) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    Circle()
                        .trim(from: 0, to: 0.15)
                        .stroke(Palette.amber, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .shadow(color: Palette.amber.opacity(0.7), radius: 8)
                        .rotationEffect(.degrees(reduceMotion ? -90 : t.truncatingRemainder(dividingBy: 2.4) / 2.4 * 360))
                }
                FuelOrb(size: 180, glow: 0.2)
                    .opacity(0.32)
                VStack(spacing: 10) {
                    SkeletonBlock(width: 110, height: 38, radius: 12)
                    Text("of your day")
                        .font(Typography.mono(11))
                        .foregroundStyle(Color(hex: 0xFDE6CF).opacity(0.7))
                }
            }
            .frame(width: 240, height: 240)
            .padding(.top, Space.xs)
            HStack(spacing: 8) {
                Circle().fill(Palette.amber).frame(width: 6, height: 6)
                Text("Pulling in today’s plan")
                    .font(Typography.mono(11))
                    .tracking(1.1)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.inkFaint)
            }
            VStack(alignment: .leading, spacing: 12) {
                SkeletonBlock(width: 150, height: 10)
                SkeletonBlock(width: 220, height: 22, radius: 8)
                SkeletonBlock(height: 50, radius: 16)
                SkeletonBlock(height: 50, radius: 16).opacity(0.6)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(radius: 26)
            .shimmering()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.xs)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(alignment: .top) {
            AmbientGlow(tone: .ember, strength: 0.5).offset(y: -40).ignoresSafeArea()
        }
        .background(Palette.background.ignoresSafeArea())
        .accessibilityElement()
        .accessibilityLabel("Loading today")
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
