import Foundation
import Observation

/// Drives the inline meal composer on Today: compose (text and/or photo) →
/// parsing. Text lands in the timeline; a photo waits on a confirmation of the
/// parse before it becomes the meal (§5.5).
@MainActor
@Observable
final class LogMealViewModel {
    enum Phase: Equatable {
        case compose
        case parsing
        case logged(Logged)
        /// No connection: kept on the phone, sent on the next load. Not a meal yet.
        case queued(String)
        case failed(String)
    }

    struct Logged: Equatable {
        let mealId: String
        let kcal: Int
        let proteinG: Double
        let summary: String?
        let notes: String?
        let confidence: Double?
        let items: [LogMealResponse.Parsed.Item]
        let fromPhoto: Bool
        let resolvedCheckIn: Bool
        var source: String = "TEXT"
    }

    private(set) var phase: Phase = .compose
    /// A usual, repeat, top-up or estimate on its way: its numbers are known, so
    /// Today shows it as eaten now instead of "working it out". Cleared once the
    /// screen has handled the result.
    private(set) var pendingKnownMeal: MealSummary?
    /// What to send again from "Didn't save · Try again".
    private enum KnownLog {
        case macros(summary: String, kcal: Int, proteinG: Double?, carbsG: Double?, fatG: Double?, source: String, backdate: Backdate?)
        case saved(SavedMeal, backdate: Backdate?)
        case catalog(CatalogPick, backdate: Backdate?)
    }
    @ObservationIgnored private var lastKnown: KnownLog?
    private(set) var removing = false
    private(set) var savingCorrection = false
    /// What the user sent — kept for the timeline skeleton after the field clears.
    private(set) var submittedPrompt = ""
    /// Photo logs wait here until the user confirms the parse.
    private(set) var confirmingPhoto = false
    /// The log attempt in flight, and one the person closed before it came back —
    /// a meal that attempt still creates is deleted instead of shown.
    private var currentAttempt: UUID?
    private var cancelledAttempt: UUID?
    private(set) var submittedPhoto: MealPhoto?
    var text = ""
    var photo: MealPhoto?
    var actionError: String?

    /// Logging a meal eaten at an earlier meal time (a "nothing logged" slot on
    /// Today): the meal is recorded at that time instead of now.
    struct Backdate: Equatable {
        let slot: MealSlot
        let at: Date
    }
    var backdate: Backdate?

    /// Slot / time of the in-flight log, so Today can place the pending row
    /// (and then the real meal) under the right meal time before Home reloads.
    private(set) var submittedSlot: MealSlot?
    private(set) var submittedLoggedAt: Date?

    /// Recent meals, newest first, one per name — the "Again?" chips.
    private(set) var recents: [MealSummary] = []
    /// Named plates for the My meals carousel.
    private(set) var savedMeals: [SavedMeal] = []
    /// Type · Scan · Photo — Scan presents the camera; Photo opens the picker.
    enum Mode: String, CaseIterable, Identifiable {
        case type, scan, photo
        var id: String { rawValue }
        var title: String {
            switch self {
            case .type: return L10n( "Type")
            case .scan: return L10n( "Scan")
            case .photo: return L10n( "Photo")
            }
        }
    }
    var mode: Mode = .type
    var showScanner = false
    var scanStatus: ScanStatus = .scanning
    var showPhotoPicker = false
    var showCamera = false
    var product: BarcodeProduct?
    /// "Save as my meal" from the scanner, shown over it so it opens at once.
    var scannerEditor: SavedMealDraft?
    /// The product on the scanner has been saved as a meal.
    var scannedProductSaved = false

    /// The code being looked up, kept so a label photo can be filed under it.
    private var lastScannedCode: String?

    enum ScanStatus: Equatable {
        case scanning
        case lookingUp
        case found
        case notFound
        case readingLabel
        case failed(String)
    }
    var catalogPick: CatalogPick?
    var catalogHits: [CatalogFood] = []
    var editor: SavedMealDraft?

    struct BarcodeProduct: Equatable, Identifiable {
        var id: String { food.code }
        let food: BarcodeFood
        var servings: Double
    }

    struct CatalogPick: Equatable, Identifiable {
        var id: String { food.id }
        let food: CatalogFood
        var grams: Double
    }

    private let api: APIClient
    private let onMealChanged: @MainActor () -> Void
    private var heldText = ""
    @ObservationIgnored private var catalogSearchTask: Task<Void, Never>?

    init(api: APIClient, onMealChanged: @escaping @MainActor () -> Void = {}) {
        self.api = api
        self.onMealChanged = onMealChanged
    }

    var canSubmit: Bool {
        guard phase != .parsing else { return false }
        return !trimmedText.isEmpty || photo != nil
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func attach(_ data: Data) {
        photo = MealPhoto.make(from: data)
    }

    /// A photo just taken goes straight to being read — taking it was the intent
    /// to log it. Anything already typed goes along as its description.
    func logPhoto(_ data: Data) async {
        attach(data)
        guard photo != nil else { return }
        mode = .type
        await submit()
    }

    func removePhoto() {
        photo = nil
    }

    func submit() async {
        guard canSubmit else { return }
        catalogSearchTask?.cancel()
        catalogHits = []
        let prompt = trimmedText
        let snapshotPhoto = photo
        let snapshotBackdate = backdate
        // One id per attempt: if the request lands but the response is lost,
        // the queued retry returns this meal instead of adding it again.
        let clientId = UUID().uuidString
        let eatenAt = snapshotBackdate?.at ?? Date()
        let body = LogMealRequest(
            text: prompt.isEmpty ? nil : prompt,
            image: snapshotPhoto.map { .init(data: $0.base64, mediaType: $0.mediaType) },
            loggedAt: snapshotBackdate.map { ISO8601DateFormatter().string(from: $0.at) },
            clientId: clientId
        )
        let fromPhoto = snapshotPhoto != nil
        let attempt = UUID()
        currentAttempt = attempt
        heldText = text
        submittedPhoto = snapshotPhoto
        confirmingPhoto = fromPhoto
        submittedPrompt = prompt.isEmpty ? (fromPhoto ? L10n("From your photo") : L10n("Working it out…")) : prompt
        submittedSlot = snapshotBackdate?.slot
        submittedLoggedAt = snapshotBackdate?.at ?? Date()
        text = ""
        photo = nil
        backdate = nil
        phase = .parsing
        do {
            let res: LogMealResponse = try await api.logMeal(body)
            if attempt == cancelledAttempt {
                cancelledAttempt = nil
                try? await api.delete("/api/meals/\(res.meal.id)")
                onMealChanged()
                return
            }
            phase = .logged(
                Logged(
                    mealId: res.meal.id,
                    kcal: res.meal.kcal,
                    proteinG: res.meal.proteinG,
                    summary: res.parsed?.summary,
                    notes: res.parsed?.notes,
                    confidence: res.parsed?.confidence,
                    items: res.parsed?.items ?? [],
                    fromPhoto: fromPhoto,
                    resolvedCheckIn: res.resolvedCheckInId != nil,
                    source: fromPhoto ? "PHOTO" : "TEXT"
                )
            )
            onMealChanged()
            await writeLoggedMealToHealth()
        } catch _ where attempt == cancelledAttempt {
            cancelledAttempt = nil
        } catch let error where snapshotPhoto == nil && !prompt.isEmpty && OfflineMealQueue.isOffline(error) {
            OfflineMealQueue.enqueue(.init(id: clientId, text: prompt, loggedAt: eatenAt))
            Analytics.send(.mealQueuedOffline, props: ["source": "TEXT"], api: api)
            heldText = ""
            submittedSlot = nil
            submittedLoggedAt = nil
            phase = .queued(L10n("No connection. Saved on this phone — it sends when you’re back online."))
        } catch {
            text = heldText
            photo = submittedPhoto
            submittedPhoto = nil
            confirmingPhoto = false
            backdate = snapshotBackdate
            submittedSlot = nil
            submittedLoggedAt = nil
            phase = .failed(UserFacingError.message(for: error, fallback: L10n( "Couldn't log. Try again.")))
        }
    }

    /// How many meals the log sheet's Recent list shows.
    static let recentLimit = 10

    /// Load recent meals for the log sheet: the last two weeks, or today and
    /// yesterday when the backend doesn't have the recent route yet.
    func loadRecents(today: [MealSummary], now: Date = .now) async {
        if let recent: RecentMealsResponse = try? await api.get("/api/meals/recent") {
            recents = Self.distinctRecents(today + recent.meals, limit: Self.recentLimit)
            return
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        let older: MealsListResponse? = try? await api.get("/api/meals", query: ["date": formatter.string(from: yesterday)])
        // Offline: keep the list from last time rather than emptying it.
        guard older != nil || recents.isEmpty else { return }
        recents = Self.distinctRecents(today + (older?.meals ?? []), limit: Self.recentLimit)
    }

    /// Newest first, one per (case-insensitive) name, only meals with a name.
    static func distinctRecents(_ meals: [MealSummary], limit: Int = 6) -> [MealSummary] {
        var seen = Set<String>()
        return meals
            .filter { !($0.summary ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.loggedAt > $1.loggedAt }
            .filter { seen.insert(($0.summary ?? "").lowercased()).inserted }
            .prefix(limit)
            .map { $0 }
    }

    /// Log a recent meal again with its exact numbers — no parse, no AI quota.
    func logAgain(_ meal: MealSummary) async {
        await logMacros(
            summary: meal.summary ?? "Logged",
            kcal: meal.kcal,
            proteinG: meal.proteinG,
            carbsG: meal.carbsG,
            fatG: meal.fatG,
            source: meal.source
        )
    }

    /// "About a normal lunch": a rough, honest estimate for a meal eaten but
    /// not logged — better than nothing, and never AI-parsed.
    func logEstimate(slot: MealSlot, kcal: Int) async {
        await logMacros(summary: L10n("\(slot.title) (rough estimate)"), kcal: kcal, proteinG: nil, carbsG: nil, fatG: nil)
    }

    /// Logs known macros as-is (a repeat, a top-up, an estimate). Never AI-parsed.
    func logMacros(
        summary: String,
        kcal: Int,
        proteinG: Double?,
        carbsG: Double?,
        fatG: Double?,
        source: String = "TEXT"
    ) async {
        guard phase != .parsing else { return }
        let snapshotBackdate = backdate
        submittedPrompt = summary
        submittedSlot = snapshotBackdate?.slot
        submittedLoggedAt = snapshotBackdate?.at ?? Date()
        backdate = nil
        lastKnown = .macros(summary: summary, kcal: kcal, proteinG: proteinG, carbsG: carbsG, fatG: fatG, source: source, backdate: snapshotBackdate)
        pendingKnownMeal = knownMeal(summary: summary, kcal: kcal, proteinG: proteinG ?? 0, carbsG: carbsG ?? 0, fatG: fatG ?? 0, source: source)
        phase = .parsing
        do {
            let res: LogMealResponse = try await api.logMeal(
                LogMealRequest(
                    text: summary,
                    macros: .init(kcal: kcal, proteinG: proteinG, carbsG: carbsG, fatG: fatG),
                    loggedAt: snapshotBackdate.map { ISO8601DateFormatter().string(from: $0.at) },
                    clientId: UUID().uuidString
                )
            )
            phase = .logged(
                Logged(
                    mealId: res.meal.id,
                    kcal: res.meal.kcal,
                    proteinG: res.meal.proteinG,
                    summary: summary,
                    notes: nil,
                    confidence: nil,
                    items: [],
                    fromPhoto: false,
                    resolvedCheckIn: res.resolvedCheckInId != nil,
                    source: source
                )
            )
            onMealChanged()
            await writeLoggedMealToHealth()
        } catch {
            backdate = snapshotBackdate
            submittedSlot = nil
            submittedLoggedAt = nil
            phase = .failed(UserFacingError.message(for: error, fallback: L10n( "Couldn't log. Try again.")))
        }
    }

    func loadSavedMeals(now: Date = .now) async {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let res: SavedMealsResponse? = try? await api.get("/api/saved-meals", query: ["now": formatter.string(from: now)])
        savedMeals = res?.meals ?? []
        TodaySnapshotSync.writeSaved(savedMeals)
    }

    /// One-tap log of a named plate — no parse, no AI quota.
    func logSaved(_ meal: SavedMeal) async {
        guard phase != .parsing else { return }
        let snapshotBackdate = backdate
        submittedPrompt = meal.name
        submittedSlot = snapshotBackdate?.slot
        submittedLoggedAt = snapshotBackdate?.at ?? Date()
        backdate = nil
        lastKnown = .saved(meal, backdate: snapshotBackdate)
        pendingKnownMeal = knownMeal(
            summary: meal.name,
            kcal: meal.kcal,
            proteinG: meal.proteinG,
            carbsG: meal.carbsG,
            fatG: meal.fatG,
            source: "SAVED"
        )
        phase = .parsing
        do {
            let res: LogMealResponse = try await api.logMeal(
                LogMealRequest(
                    savedMealId: meal.id,
                    loggedAt: snapshotBackdate.map { ISO8601DateFormatter().string(from: $0.at) },
                    clientId: UUID().uuidString
                )
            )
            phase = .logged(
                Logged(
                    mealId: res.meal.id,
                    kcal: res.meal.kcal,
                    proteinG: res.meal.proteinG,
                    summary: meal.name,
                    notes: nil,
                    confidence: nil,
                    items: meal.items.map {
                        .init(
                            name: $0.name,
                            quantity: $0.quantity,
                            kcal: $0.kcal,
                            proteinG: $0.proteinG,
                            carbsG: $0.carbsG,
                            fatG: $0.fatG
                        )
                    },
                    fromPhoto: false,
                    resolvedCheckIn: res.resolvedCheckInId != nil,
                    source: "SAVED"
                )
            )
            onMealChanged()
            await writeLoggedMealToHealth()
            await loadSavedMeals()
        } catch {
            backdate = snapshotBackdate
            submittedSlot = nil
            submittedLoggedAt = nil
            phase = .failed(UserFacingError.message(for: error, fallback: L10n( "Couldn't log. Try again.")))
        }
    }

    func onComposerTextChanged() {
        catalogSearchTask?.cancel()
        let q = trimmedText
        guard q.count >= 2 else {
            catalogHits = []
            return
        }
        catalogSearchTask = Task { await searchCatalog(q) }
    }

    func pickCatalog(_ food: CatalogFood) {
        catalogSearchTask?.cancel()
        catalogHits = []
        text = ""
        catalogPick = CatalogPick(food: food, grams: food.defaultGrams)
    }

    func logCatalog() async {
        guard let pick = catalogPick, phase != .parsing else { return }
        let snapshotBackdate = backdate
        let food = pick.food
        let grams = pick.grams
        let portion = food.portion(grams: grams)
        submittedPrompt = food.name
        submittedSlot = snapshotBackdate?.slot
        submittedLoggedAt = snapshotBackdate?.at ?? Date()
        backdate = nil
        catalogPick = nil
        lastKnown = .catalog(CatalogPick(food: food, grams: grams), backdate: snapshotBackdate)
        pendingKnownMeal = knownMeal(
            summary: food.name,
            kcal: portion.kcal,
            proteinG: portion.proteinG,
            carbsG: portion.carbsG,
            fatG: portion.fatG,
            source: "CATALOG"
        )
        phase = .parsing
        do {
            let res: LogMealResponse = try await api.logMeal(
                LogMealRequest(
                    catalogId: food.id,
                    grams: grams,
                    loggedAt: snapshotBackdate.map { ISO8601DateFormatter().string(from: $0.at) },
                    clientId: UUID().uuidString
                )
            )
            phase = .logged(
                Logged(
                    mealId: res.meal.id,
                    kcal: res.meal.kcal,
                    proteinG: res.meal.proteinG,
                    summary: food.name,
                    notes: food.servingDesc,
                    confidence: nil,
                    items: [
                        .init(
                            name: food.name,
                            quantity: L10n("\(Int(portion.grams.rounded())) g"),
                            kcal: portion.kcal,
                            proteinG: portion.proteinG,
                            carbsG: portion.carbsG,
                            fatG: portion.fatG
                        )
                    ],
                    fromPhoto: false,
                    resolvedCheckIn: res.resolvedCheckInId != nil,
                    source: "CATALOG"
                )
            )
            onMealChanged()
            await writeLoggedMealToHealth()
        } catch {
            backdate = snapshotBackdate
            submittedSlot = nil
            submittedLoggedAt = nil
            catalogPick = CatalogPick(food: food, grams: grams)
            phase = .failed(UserFacingError.message(for: error, fallback: L10n( "Couldn't log. Try again.")))
        }
    }

    private func searchCatalog(_ q: String) async {
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        do {
            let res: CatalogSearchResponse = try await api.get("/api/foods/search", query: ["q": q])
            guard !Task.isCancelled, trimmedText == q else { return }
            catalogHits = res.foods
        } catch {
            guard !Task.isCancelled, trimmedText == q else { return }
            catalogHits = []
        }
    }

    func openScanner() {
        mode = .scan
        product = nil
        scannedProductSaved = false
        scanStatus = .scanning
        showScanner = true
    }

    /// Scan, confirm and log all happen on the scanner: a hit shows the product
    /// card over the paused camera, a miss offers the label photo or typing.
    func handleScannedCode(_ code: String) async {
        guard scanStatus == .scanning else { return }
        lastScannedCode = code
        scanStatus = .lookingUp
        do {
            let res: BarcodeFoodResponse = try await api.get("/api/foods/barcode/\(code)")
            product = BarcodeProduct(food: res.food, servings: 1)
            actionError = nil
            scanStatus = .found
        } catch let error as APIError {
            if case let .http(status, _) = error, status == 404 {
                scanStatus = .notFound
            } else {
                scanStatus = .failed(UserFacingError.message(for: error, fallback: L10n( "Couldn't look that up.")))
            }
        } catch {
            scanStatus = .failed(UserFacingError.message(for: error, fallback: L10n( "Couldn't look that up.")))
        }
    }

    func rescan() {
        product = nil
        scannedProductSaved = false
        scanStatus = .scanning
    }

    /// Closes the scanner onto the log panel, which shows the meal landing.
    func logScannedProduct() async {
        guard product != nil else { return }
        showScanner = false
        await logBarcode()
    }

    func saveScannedProduct() {
        guard let product else { return }
        editorError = nil
        scannerEditor = SavedMealDraft(from: product)
    }

    func saveScannerEditor(_ draft: SavedMealDraft) async -> Bool {
        let saved = await saveEditor(draft)
        if saved { scannedProductSaved = true }
        return saved
    }

    /// Reads the pack's nutrition label and files it under the scanned code, so
    /// the next scan of this product — by anyone — finds it straight away.
    func readLabel(_ data: Data) async {
        guard let code = lastScannedCode, scanStatus != .readingLabel else { return }
        guard let photo = MealPhoto.make(from: data) else {
            scanStatus = .failed(L10n("Couldn’t read that label. Get the numbers in focus and try again."))
            return
        }
        scanStatus = .readingLabel
        do {
            let res: BarcodeFoodResponse = try await api.post(
                "/api/foods/barcode/\(code)/label",
                BarcodeLabelRequest(image: .init(data: photo.base64, mediaType: photo.mediaType))
            )
            product = BarcodeProduct(food: res.food, servings: 1)
            actionError = nil
            scanStatus = .found
        } catch let error as APIError {
            if case let .http(status, _) = error, status == 422 {
                scanStatus = .failed(L10n("Couldn’t read that label. Get the numbers in focus and try again."))
            } else {
                scanStatus = .failed(UserFacingError.message(for: error, fallback: L10n("Couldn’t read that label.")))
            }
        } catch {
            scanStatus = .failed(UserFacingError.message(for: error, fallback: L10n("Couldn’t read that label.")))
        }
    }

    func typeInsteadOfScanning() {
        showScanner = false
        mode = .type
    }

    /// Runs once the full-screen scanner has finished closing — a sheet asked for
    /// while it is still animating away never appears.
    func scannerDismissed() {
        scanStatus = .scanning
        if phase != .parsing { product = nil }
        scannerEditor = nil
        if mode == .scan { mode = .type }
    }

    /// Camera when the device has one, the library otherwise (simulator).
    func openCamera() {
        mode = .photo
        if CameraCapture.isAvailable {
            showCamera = true
        } else {
            showPhotoPicker = true
        }
    }

    func openPhotoLibrary() {
        mode = .photo
        showPhotoPicker = true
    }

    func logBarcode() async {
        guard let product, phase != .parsing else { return }
        let snapshotBackdate = backdate
        let food = product.food
        let servings = product.servings
        let portion = food.portion(servings: servings)
        submittedPrompt = food.name
        submittedSlot = snapshotBackdate?.slot
        submittedLoggedAt = snapshotBackdate?.at ?? Date()
        backdate = nil
        self.product = nil
        phase = .parsing
        do {
            let res: LogMealResponse = try await api.logMeal(
                LogMealRequest(
                    barcode: food.code,
                    servings: servings,
                    loggedAt: snapshotBackdate.map { ISO8601DateFormatter().string(from: $0.at) },
                    clientId: UUID().uuidString
                )
            )
            phase = .logged(
                Logged(
                    mealId: res.meal.id,
                    kcal: res.meal.kcal,
                    proteinG: res.meal.proteinG,
                    summary: food.name,
                    notes: food.brand,
                    confidence: nil,
                    items: [
                        .init(
                            name: food.name,
                            quantity: servings == 1 ? L10n("1 serving") : L10n("\(servings.formatted()) servings"),
                            kcal: portion.kcal,
                            proteinG: portion.proteinG,
                            carbsG: portion.carbsG,
                            fatG: portion.fatG
                        )
                    ],
                    fromPhoto: false,
                    resolvedCheckIn: res.resolvedCheckInId != nil,
                    source: "BARCODE"
                )
            )
            onMealChanged()
            await writeLoggedMealToHealth()
        } catch {
            backdate = snapshotBackdate
            submittedSlot = nil
            submittedLoggedAt = nil
            self.product = BarcodeProduct(food: food, servings: servings)
            phase = .failed(UserFacingError.message(for: error, fallback: L10n( "Couldn't log. Try again.")))
        }
    }

    func openEditor(from meal: MealSummary) {
        editor = SavedMealDraft(from: meal)
    }

    func openEditor(from meal: SavedMeal) {
        editor = SavedMealDraft(from: meal)
    }

    func openEditorToSaveCatalog() {
        guard let catalogPick else { return }
        editor = SavedMealDraft(from: catalogPick)
    }

    var editorSaving = false
    var editorError: String?

    func saveEditor(_ draft: SavedMealDraft) async -> Bool {
        guard let write = draft.write, !editorSaving else { return false }
        editorSaving = true
        editorError = nil
        defer { editorSaving = false }
        do {
            if let id = draft.existingId {
                let _: SavedMealResponse = try await api.patch("/api/saved-meals/\(id)", write)
            } else {
                let _: SavedMealResponse = try await api.post("/api/saved-meals", write)
            }
            await loadSavedMeals()
            return true
        } catch {
            editorError = UserFacingError.message(for: error, fallback: L10n( "Couldn't save. Try again."))
            return false
        }
    }

    func undo() async {
        guard case let .logged(logged) = phase, !removing else { return }
        removing = true
        actionError = nil
        defer { removing = false }
        do {
            try await api.delete("/api/meals/\(logged.mealId)")
            await HealthKitManager.shared.deleteMealFromHealth(id: logged.mealId)
            text = heldText
            photo = submittedPhoto
            confirmingPhoto = false
            submittedPhoto = nil
            submittedPrompt = ""
            submittedSlot = nil
            submittedLoggedAt = nil
            phase = .compose
            onMealChanged()
        } catch {
            actionError = UserFacingError.message(for: error, fallback: L10n( "Couldn't remove. Try again."))
        }
    }

    func correct(summary: String, items: [MealCorrectionRequest.Item]) async -> Bool {
        guard case let .logged(logged) = phase, !savingCorrection else { return false }
        savingCorrection = true
        actionError = nil
        defer { savingCorrection = false }

        do {
            let response: MealCorrectionResponse = try await api.patch(
                "/api/meals/\(logged.mealId)",
                MealCorrectionRequest(summary: summary, items: items)
            )
            let meal = response.meal
            phase = .logged(
                Logged(
                    mealId: meal.id,
                    kcal: meal.kcal,
                    proteinG: meal.proteinG,
                    summary: meal.summary,
                    notes: meal.notes,
                    confidence: meal.parseConfidence,
                    items: (meal.items ?? []).map {
                        .init(
                            name: $0.name,
                            quantity: $0.quantity,
                            kcal: $0.kcal,
                            proteinG: $0.proteinG,
                            carbsG: $0.carbsG,
                            fatG: $0.fatG
                        )
                    },
                    fromPhoto: logged.fromPhoto,
                    resolvedCheckIn: logged.resolvedCheckIn,
                    source: logged.source
                )
            )
            onMealChanged()
            await writeLoggedMealToHealth()
            return true
        } catch {
            actionError = UserFacingError.message(for: error, fallback: L10n( "Couldn't save. Try again."))
            return false
        }
    }

    /// Photo parse accepted — the meal stays, composer goes back to rest.
    func keepLogged() {
        guard case .logged = phase else { return }
        confirmingPhoto = false
        clearAfterSuccess()
    }

    /// Drop the confirm overlay but keep the logged meal so it can morph into the timeline.
    func endConfirm() {
        confirmingPhoto = false
    }

    /// X while the photo is still being read: close, and drop whatever it logs.
    func cancelPhotoLog() {
        guard confirmingPhoto, phase == .parsing else { return }
        cancelledAttempt = currentAttempt
        clearAfterSuccess()
    }

    /// X on a read photo: the meal was logged, so remove it and start clean.
    func discardPhotoLog() async {
        guard confirmingPhoto, case .logged = phase else { return }
        await undo()
        guard phase == .compose else { return }
        text = ""
        photo = nil
        heldText = ""
    }

    func reset() {
        phase = .compose
        actionError = nil
        submittedSlot = nil
        submittedLoggedAt = nil
        pendingKnownMeal = nil
        catalogHits = []
        catalogSearchTask?.cancel()
    }

    /// A known meal the server refused: the screen has put Today back and offers
    /// "Try again", so the panel doesn't reopen on an error.
    func dropFailedKnown() {
        backdate = nil
        submittedPrompt = ""
        reset()
    }

    /// "Try again" for a known meal: sends it again, at the same time it was meant for.
    func retryKnown() async {
        switch lastKnown {
        case let .macros(summary, kcal, proteinG, carbsG, fatG, source, snapshot):
            backdate = snapshot
            await logMacros(summary: summary, kcal: kcal, proteinG: proteinG, carbsG: carbsG, fatG: fatG, source: source)
        case let .saved(meal, snapshot):
            backdate = snapshot
            await logSaved(meal)
        case let .catalog(pick, snapshot):
            backdate = snapshot
            catalogPick = pick
            await logCatalog()
        case nil:
            break
        }
    }

    private func knownMeal(summary: String, kcal: Int, proteinG: Double, carbsG: Double, fatG: Double, source: String) -> MealSummary {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return MealSummary(
            id: "pending-\(UUID().uuidString)",
            loggedAt: formatter.string(from: submittedLoggedAt ?? Date()),
            kcal: kcal,
            proteinG: proteinG,
            carbsG: carbsG,
            fatG: fatG,
            source: source,
            summary: summary,
            photoUrl: nil,
            notes: nil,
            items: nil,
            parseConfidence: nil
        )
    }

    private func writeLoggedMealToHealth() async {
        if let meal = pendingMealSummary() {
            await HealthKitManager.shared.writeMeal(meal)
        }
    }

    /// Enough of a meal card to drop into Today before Home reloads.
    func pendingMealSummary() -> MealSummary? {
        guard case let .logged(logged) = phase else { return nil }
        let at = submittedLoggedAt ?? Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return MealSummary(
            id: logged.mealId,
            loggedAt: formatter.string(from: at),
            kcal: logged.kcal,
            proteinG: logged.proteinG,
            carbsG: logged.items.reduce(0) { $0 + $1.carbsG },
            fatG: logged.items.reduce(0) { $0 + $1.fatG },
            source: logged.source,
            summary: logged.summary,
            photoUrl: nil,
            notes: logged.notes,
            items: logged.items.map {
                .init(
                    name: $0.name,
                    quantity: $0.quantity,
                    kcal: $0.kcal,
                    proteinG: $0.proteinG,
                    carbsG: $0.carbsG,
                    fatG: $0.fatG
                )
            },
            parseConfidence: logged.confidence
        )
    }

    /// After a kept log, wipe the composer so the next meal starts blank.
    func clearAfterSuccess() {
        text = ""
        photo = nil
        heldText = ""
        submittedPhoto = nil
        submittedPrompt = ""
        confirmingPhoto = false
        backdate = nil
        submittedSlot = nil
        submittedLoggedAt = nil
        phase = .compose
        actionError = nil
        removing = false
        pendingKnownMeal = nil
    }

    #if DEBUG
    static func previewed(
        _ phase: Phase,
        text: String = "",
        submittedPrompt: String = "",
        confirmingPhoto: Bool = false
    ) -> LogMealViewModel {
        let vm = LogMealViewModel(api: AppEnvironment.preview().api)
        vm.phase = phase
        vm.text = text
        vm.submittedPrompt = submittedPrompt
        vm.confirmingPhoto = confirmingPhoto
        return vm
    }

    static let sampleParsing = previewed(
        .parsing,
        submittedPrompt: "chicken burrito bowl, large"
    )

    static var samplePhotoParsing: LogMealViewModel {
        let vm = previewed(
            .parsing,
            submittedPrompt: "From your photo",
            confirmingPhoto: true
        )
        vm.submittedPhoto = .demoPlate
        return vm
    }

    static var samplePhotoConfirm: LogMealViewModel {
        let vm = previewed(
            sampleLogged,
            submittedPrompt: "From your photo",
            confirmingPhoto: true
        )
        vm.submittedPhoto = .demoPlate
        return vm
    }

    static let sampleLogged = Phase.logged(
        Logged(
            mealId: "m_preview",
            kcal: 638,
            proteinG: 41,
            summary: "Chicken burrito bowl",
            notes: "Assumed a regular-size bowl with one scoop of rice.",
            confidence: 0.78,
            items: [
                .init(name: "Grilled chicken", quantity: "1 serving", kcal: 280, proteinG: 32, carbsG: 2, fatG: 9),
                .init(name: "Cilantro-lime rice", quantity: "1 cup", kcal: 208, proteinG: 4, carbsG: 44, fatG: 3),
                .init(name: "Black beans", quantity: "1 scoop", kcal: 150, proteinG: 5, carbsG: 22, fatG: 2),
            ],
            fromPhoto: true,
            resolvedCheckIn: true,
            source: "PHOTO"
        )
    )

    static var sampleQuickLog: LogMealViewModel {
        let vm = previewed(.compose)
        vm.savedMeals = SavedMeal.samples
        vm.recents = [
            .sample(id: "r1", kcal: 420, protein: 18, source: "SAVED", summary: "Usual oats"),
            .sample(id: "r2", kcal: 150, protein: 14, source: "BARCODE", summary: "Greek yogurt"),
            .sample(id: "r3", kcal: 640, protein: 42, source: "PHOTO", summary: "Chicken burrito bowl"),
            .sample(id: "r4", kcal: 310, protein: 12, source: "TEXT", summary: "Peanut butter toast"),
            .sample(id: "r5", kcal: 520, protein: 30, source: "CATALOG", summary: "Pasta with tomato sauce"),
        ]
        return vm
    }

    static var sampleScanProduct: LogMealViewModel {
        let vm = previewed(.compose)
        vm.mode = .scan
        vm.product = BarcodeProduct(food: .sampleYogurt, servings: 1)
        return vm
    }
    #endif
}
