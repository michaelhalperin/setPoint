import SwiftUI

/// The log panel over any tab: the dock rising from the nav's "+", the photo
/// confirm, the barcode scanner and product sheet, the saved-meal editor, and the
/// status toast. Logging stays where you are; the meal lands on Today, which
/// reloads behind it.
struct LogAnywhere: ViewModifier {
    let home: HomeViewModel

    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var logger: LogMealViewModel?
    @FocusState private var focused: Bool
    @Namespace private var photoNamespace
    @State private var showingOrder = false
    /// Today before a known meal was shown as eaten (see HomeScreen).
    @State private var beforeKnownMeal: HomeResponse?

    private static let imageID = "log-anywhere-image"
    private static let cardID = "log-anywhere-card"

    /// Lives on the shared chrome, so opening the panel doesn't redraw the tabs.
    private var open: Bool {
        get { env.chrome.logPanelOpen }
        nonmutating set { env.chrome.logPanelOpen = newValue }
    }

    private var loadedHome: HomeResponse? {
        if case let .loaded(response) = home.phase { return response }
        return nil
    }

    func body(content: Content) -> some View {
        content
            // The panel animates on its own layer; the tabs underneath never relayout.
            .overlay {
                panel
                    .animation(Motion.adaptive(Motion.sheet, reduceMotion: reduceMotion), value: open)
                    .animation(Motion.adaptive(Motion.morph, reduceMotion: reduceMotion), value: logger?.confirmingPhoto == true)
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
                    slotTitle: slotTitle,
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
                    slotTitle: slotTitle,
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
            .fullScreenCover(isPresented: $showingOrder) {
                if let home = loadedHome {
                    NavigationStack {
                        OrderNearbyView(
                            gapKcal: OrderNearbyContext.gap(home),
                            slotTitle: OrderNearbyContext.slotTitle(home)
                        ) {
                            Task { await self.home.load(showSpinner: false) }
                        }
                    }
                }
            }
            .sheet(item: editorBinding) { draft in
                SavedMealEditorView(
                    draft: draft,
                    saving: logger?.editorSaving ?? false,
                    error: logger?.editorError,
                    onSave: { await logger?.saveEditor($0) ?? false }
                )
            }
            .onChange(of: env.chrome.logPanelOpen) { _, isOpen in
                // Opens like Today's: every way to log showing, the field not focused.
                if isOpen { show(focus: false) } else { focused = false }
            }
            .onChange(of: logger?.phase) { _, phase in
                if let phase { handle(phase) }
            }
    }

    @ViewBuilder
    private var panel: some View {
        ZStack(alignment: .bottom) {
            if open {
                Palette.scrim
                    .ignoresSafeArea()
                    .onTapGesture(perform: close)
                    .transition(.opacity)
                    .accessibilityLabel("Close")
                    .accessibilityAddTraits(.isButton)
            }
            if let logger {
                if open {
                    LogDock(
                        logger: logger,
                        focused: $focused,
                        estimateKcal: estimateKcal,
                        currentSlot: currentSlot,
                        photoNamespace: photoNamespace,
                        photoGeometryID: Self.imageID,
                        onClose: close,
                        onSubmit: { Task { await logger.submit() } },
                        onOrder: env.flags.isOn(.orderNearby) ? {
                            close()
                            showingOrder = true
                        } : nil
                    )
                    // Its background runs under the home indicator, so sliding by its own
                    // height would leave that strip showing until the spring settles.
                    .transition(.offset(y: 900))
                    .zIndex(1)
                } else {
                    // Above the floating nav.
                    LogStatusToast(
                        logger: logger,
                        onRetry: { show(focus: false) },
                        onDelete: {
                            logger.clearAfterSuccess()
                        }
                    )
                        .padding(.bottom, 96)
                        .frame(maxWidth: .infinity)
                }
            }
            if let logger, logger.confirmingPhoto {
                PhotoParseConfirm(
                    model: logger,
                    namespace: photoNamespace,
                    imageID: Self.imageID,
                    cardID: Self.cardID,
                    countsFor: loadedHome?.day?.slots.first { $0.slotState == .now }?.meal
                ) {
                    Task { await keepPhotoLog() }
                }
                .zIndex(2)
            }
        }
    }

    // MARK: Open and close

    private func show(focus: Bool) {
        if logger == nil {
            logger = LogMealViewModel(api: env.api, onMealChanged: { env.changes.mealsChanged() })
        }
        if !open { open = true }
        if focus {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focused = true }
        }
        Task {
            await logger?.loadRecents(today: loadedHome?.meals ?? [])
            await logger?.loadSavedMeals()
        }
    }

    private func close() {
        focused = false
        logger?.backdate = nil
        open = false
    }

    private func handle(_ phase: LogMealViewModel.Phase) {
        switch phase {
        case .parsing:
            focused = false
            open = false
            if let meal = logger?.pendingKnownMeal {
                let slot = currentSlot
                beforeKnownMeal = home.applyNow { $0.inserting(meal, into: slot) }
            }
        case .queued:
            focused = false
            open = false
        case .failed:
            if logger?.pendingKnownMeal != nil {
                if let before = beforeKnownMeal { home.restore(before) }
                beforeKnownMeal = nil
                logger?.dropFailedKnown()
                Haptics.nudge()
                env.chrome.reportFailure(retry: { Task { await logger?.retryKnown() } })
                return
            }
            show(focus: false)
        case let .logged(logged):
            focused = false
            open = false
            Haptics.landed()
            if logged.fromPhoto { return }
            if let before = beforeKnownMeal { home.restore(before) }
            beforeKnownMeal = nil
            env.chrome.noteLogged(mealID: logged.mealId, kcal: logged.kcal, title: logged.summary)
            logger?.clearAfterSuccess()
            Task { await home.load(showSpinner: false) }
        case .compose:
            break
        }
    }

    private func keepPhotoLog() async {
        guard case .logged = logger?.phase else { return }
        logger?.endConfirm()
        await home.load(showSpinner: false)
        guard case .logged = logger?.phase else { return }
        logger?.clearAfterSuccess()
    }

    // MARK: Context from Today

    private var estimateKcal: Int? {
        guard let home = loadedHome, home.ledger.targetKcal > 0 else { return nil }
        let meals = 3 + (home.appetite?.extraSlots.count ?? 0)
        let share = Double(home.ledger.targetKcal) / Double(meals)
        return max(200, Int((share / 50).rounded()) * 50)
    }

    private var currentSlot: MealSlot {
        let minute = loadedHome?.day?.nowMin ?? TodayLayout.minuteOfDay(from: .now)
        return TodayLayout.slot(forMinute: minute, times: loadedHome?.resolvedMealTimes ?? .standard)
    }

    private var slotTitle: String {
        if let backdate = logger?.backdate { return backdate.slot.title }
        return loadedHome?.day?.slots.first { $0.slotState == .now }?.meal.title ?? "Now"
    }

    // MARK: Bindings

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
}
