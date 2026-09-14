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
        let body = LogMealRequest(
            text: prompt.isEmpty ? nil : prompt,
            image: snapshotPhoto.map { .init(data: $0.base64, mediaType: $0.mediaType) },
            loggedAt: snapshotBackdate.map { ISO8601DateFormatter().string(from: $0.at) }
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
                    resolvedCheckIn: res.resolvedCheckInId != nil
                )
            )
            onMealChanged()
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
                    resolvedCheckIn: res.resolvedCheckInId != nil
                )
            )
            onMealChanged()
        } catch {
            backdate = snapshotBackdate
            submittedSlot = nil
            submittedLoggedAt = nil
            phase = .failed(UserFacingError.message(for: error, fallback: "Couldn't log. Try again."))
        }
    }

    func undo() async {
        guard case let .logged(logged) = phase, !removing else { return }
        removing = true
        actionError = nil
        defer { removing = false }
        do {
            try await api.delete("/api/meals/\(logged.mealId)")
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
                    resolvedCheckIn: logged.resolvedCheckIn
                )
            )
            onMealChanged()
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
            source: logged.fromPhoto ? "PHOTO" : "TEXT",
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
            resolvedCheckIn: true
        )
    )
    #endif
}
