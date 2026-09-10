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
        let body = LogMealRequest(
            text: prompt.isEmpty ? nil : prompt,
            image: snapshotPhoto.map { .init(data: $0.base64, mediaType: $0.mediaType) }
        )
        let fromPhoto = snapshotPhoto != nil
        heldText = text
        submittedPhoto = snapshotPhoto
        confirmingPhoto = fromPhoto
        submittedPrompt = prompt.isEmpty ? (fromPhoto ? "From your photo" : "Working it out…") : prompt
        text = ""
        photo = nil
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
    }

    /// After a kept log, wipe the composer so the next meal starts blank.
    func clearAfterSuccess() {
        text = ""
        photo = nil
        heldText = ""
        submittedPhoto = nil
        submittedPrompt = ""
        confirmingPhoto = false
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
