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
                        onOpenMeal: { meal in
                            composerFocused = false
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
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { composerFocused = false })
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
        Task { composerFocused = true }
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
        case .queued:
            composerFocused = false
        case let .logged(logged):
            composerFocused = false
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
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                VStack(alignment: .leading, spacing: Space.md) {
                    dial
                    VStack(alignment: .leading, spacing: 8) {
                        SkeletonBlock(width: 220, height: 34, radius: 8)
                        SkeletonBlock(width: 168, height: 16, radius: 6)
                    }
                }
                .padding(.horizontal, Space.gutter)
                .padding(.top, Space.sm)

                VStack(alignment: .leading, spacing: Space.lg) {
                    fuel
                    meals
                }
                .padding(.horizontal, Space.gutter)
            }
            .padding(.bottom, Space.lg)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDisabled(true)
        .background(Palette.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { dock }
        .skeletonLoading()
    }

    /// Muted stand-in for the day dial: ring, three meal knobs, a number in the middle.
    private var dial: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let r = size * 0.33
            let ringWidth = size * 0.076
            let knob = min(44, max(18, size * 0.13))
            let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

            ZStack {
                Circle()
                    .stroke(Palette.surfaceSunk, lineWidth: ringWidth)
                    .frame(width: r * 2, height: r * 2)
                    .position(c)

                ForEach([480, 780, 1140], id: \.self) { minute in
                    Circle()
                        .fill(Palette.surface)
                        .overlay(Circle().strokeBorder(Palette.hairline, lineWidth: 2))
                        .frame(width: knob, height: knob)
                        .position(dialPoint(minute, radius: r, center: c))
                }

                VStack(spacing: 8) {
                    SkeletonBlock(width: size * 0.28, height: size * 0.11, radius: 10)
                    SkeletonBlock(width: size * 0.2, height: 10)
                }
                .fixedSize()
                .position(c)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 320)
        .frame(maxWidth: .infinity)
    }

    private func dialPoint(_ minute: Int, radius: CGFloat, center: CGPoint) -> CGPoint {
        let angle = CGFloat(minute) / 1440 * 2 * .pi
        return CGPoint(x: center.x + radius * sin(angle), y: center.y - radius * cos(angle))
    }

    private var fuel: some View {
        HStack(spacing: 10) {
            fuelCell(numberWidth: 56, unitWidth: 72)
            fuelCell(numberWidth: 40, unitWidth: 88)
        }
    }

    private func fuelCell(numberWidth: CGFloat, unitWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                SkeletonBlock(width: numberWidth, height: 22, radius: 6)
                SkeletonBlock(width: unitWidth, height: 12)
            }
            Capsule().fill(Palette.surfaceSunk).frame(height: 6)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Palette.surface)
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.hairline))
        }
    }

    private var meals: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            mealSection(labelWidth: 148)
            mealSection(labelWidth: 118)
        }
    }

    private func mealSection(labelWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            SkeletonBlock(width: labelWidth, height: 11)
            mealRow(titleWidth: 152)
        }
    }

    private func mealRow(titleWidth: CGFloat) -> some View {
        HStack(spacing: Space.sm) {
            SkeletonBlock(width: 44, height: 44, radius: 10)
            VStack(alignment: .leading, spacing: 4) {
                SkeletonBlock(width: titleWidth, height: 16)
                SkeletonBlock(width: 64, height: 12)
            }
            Spacer(minLength: 8)
            SkeletonBlock(width: 62, height: 14)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Palette.hairline)
        )
    }

    private var dock: some View {
        HStack(spacing: 8) {
            SkeletonBlock(height: 44, radius: 22)
            Circle()
                .fill(Palette.surfaceSunk)
                .frame(width: 34, height: 34)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.vertical, 10)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Palette.background.opacity(0.84))
                .overlay(alignment: .top) {
                    Rectangle().fill(Palette.hairline).frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        }
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
