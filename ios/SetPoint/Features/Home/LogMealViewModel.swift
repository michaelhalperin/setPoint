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
    private(set) var removing = false
    private(set) var savingCorrection = false
    /// What the user sent — kept for the timeline skeleton after the field clears.
    private(set) var submittedPrompt = ""
    /// Photo logs wait here until the user confirms the parse.
    private(set) var confirmingPhoto = false
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
            case .type: return "Type"
            case .scan: return "Scan"
            case .photo: return "Photo"
            }
        }
    }
    var mode: Mode = .type
    var showScanner = false
    var showPhotoPicker = false
    var product: BarcodeProduct?
    var editor: SavedMealDraft?

    struct BarcodeProduct: Equatable, Identifiable {
        var id: String { food.code }
        let food: BarcodeFood
        var servings: Double
    }

    private let api: APIClient
    private let onMealChanged: @MainActor () -> Void
    private var heldText = ""

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

    func removePhoto() {
        photo = nil
    }

    func submit() async {
        guard canSubmit else { return }
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
        heldText = text
        submittedPhoto = snapshotPhoto
        confirmingPhoto = fromPhoto
        submittedPrompt = prompt.isEmpty ? (fromPhoto ? "From your photo" : "Working it out…") : prompt
        submittedSlot = snapshotBackdate?.slot
        submittedLoggedAt = snapshotBackdate?.at ?? Date()
        text = ""
        photo = nil
        backdate = nil
        phase = .parsing
        do {
            let res: LogMealResponse = try await api.post("/api/meals", body)
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
        } catch let error where snapshotPhoto == nil && !prompt.isEmpty && OfflineMealQueue.isOffline(error) {
            OfflineMealQueue.enqueue(.init(id: clientId, text: prompt, loggedAt: eatenAt))
            heldText = ""
            submittedSlot = nil
            submittedLoggedAt = nil
            phase = .queued("No connection. Saved on this phone — it sends when you’re back online.")
        } catch {
            text = heldText
            photo = submittedPhoto
            submittedPhoto = nil
            confirmingPhoto = false
            backdate = snapshotBackdate
            submittedSlot = nil
            submittedLoggedAt = nil
            phase = .failed(UserFacingError.message(for: error, fallback: "Couldn't log. Try again."))
        }
    }

    /// Load recent meals from today and yesterday for the "Again?" chips.
    func loadRecents(today: [MealSummary], now: Date = .now) async {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        let older: MealsListResponse? = try? await api.get("/api/meals", query: ["date": formatter.string(from: yesterday)])
        recents = Self.distinctRecents(today + (older?.meals ?? []))
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
        guard phase != .parsing else { return }
        let snapshotBackdate = backdate
        submittedPrompt = meal.summary ?? "Logged"
        submittedSlot = snapshotBackdate?.slot
        submittedLoggedAt = snapshotBackdate?.at ?? Date()
        backdate = nil
        phase = .parsing
        do {
            let res: LogMealResponse = try await api.post(
                "/api/meals",
                LogMealRequest(
                    text: meal.summary,
                    macros: .init(kcal: meal.kcal, proteinG: meal.proteinG, carbsG: meal.carbsG, fatG: meal.fatG),
                    loggedAt: snapshotBackdate.map { ISO8601DateFormatter().string(from: $0.at) }
                )
            )
            phase = .logged(
                Logged(
                    mealId: res.meal.id,
                    kcal: res.meal.kcal,
                    proteinG: res.meal.proteinG,
                    summary: meal.summary,
                    notes: nil,
                    confidence: nil,
                    items: [],
                    fromPhoto: false,
                    resolvedCheckIn: res.resolvedCheckInId != nil,
                    source: meal.source
                )
            )
            onMealChanged()
            await writeLoggedMealToHealth()
        } catch {
            backdate = snapshotBackdate
            submittedSlot = nil
            submittedLoggedAt = nil
            phase = .failed(UserFacingError.message(for: error, fallback: "Couldn't log. Try again."))
        }
    }

    func loadSavedMeals(now: Date = .now) async {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let res: SavedMealsResponse? = try? await api.get("/api/saved-meals", query: ["now": formatter.string(from: now)])
        savedMeals = res?.meals ?? []
    }

    /// One-tap log of a named plate — no parse, no AI quota.
    func logSaved(_ meal: SavedMeal) async {
        guard phase != .parsing else { return }
        let snapshotBackdate = backdate
        submittedPrompt = meal.name
        submittedSlot = snapshotBackdate?.slot
        submittedLoggedAt = snapshotBackdate?.at ?? Date()
        backdate = nil
        phase = .parsing
        do {
            let res: LogMealResponse = try await api.post(
                "/api/meals",
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
            phase = .failed(UserFacingError.message(for: error, fallback: "Couldn't log. Try again."))
        }
    }

    func openScanner() {
        mode = .scan
        showScanner = true
    }

    func handleScannedCode(_ code: String) async {
        showScanner = false
        do {
            let res: BarcodeFoodResponse = try await api.get("/api/foods/barcode/\(code)")
            product = BarcodeProduct(food: res.food, servings: 1)
            actionError = nil
        } catch let error as APIError {
            if case let .http(status, _) = error, status == 404 {
                mode = .type
                actionError = "Not in the database. Type it instead."
            } else {
                actionError = UserFacingError.message(for: error, fallback: "Couldn't look that up. Type it instead.")
                mode = .type
            }
        } catch {
            actionError = UserFacingError.message(for: error, fallback: "Couldn't look that up. Type it instead.")
            mode = .type
        }
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
            let res: LogMealResponse = try await api.post(
                "/api/meals",
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
                            quantity: servings == 1 ? "1 serving" : "\(servings.formatted()) servings",
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
            phase = .failed(UserFacingError.message(for: error, fallback: "Couldn't log. Try again."))
        }
    }

    func openEditor(from meal: MealSummary) {
        editor = SavedMealDraft(from: meal)
    }

    func openEditor(from meal: SavedMeal) {
        editor = SavedMealDraft(from: meal)
    }

    func openEditorToSaveProduct() {
        guard let product else { return }
        editor = SavedMealDraft(from: product)
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
            editorError = UserFacingError.message(for: error, fallback: "Couldn't save. Try again.")
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
            actionError = UserFacingError.message(for: error, fallback: "Couldn't remove. Try again.")
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
            actionError = UserFacingError.message(for: error, fallback: "Couldn't save. Try again.")
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

    func reset() {
        phase = .compose
        actionError = nil
        submittedSlot = nil
        submittedLoggedAt = nil
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
