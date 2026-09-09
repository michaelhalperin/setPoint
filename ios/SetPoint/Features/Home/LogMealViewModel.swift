import Foundation
import Observation

/// Drives the meal logger sheet: compose (text and/or photo) → parsing skeleton
/// → the AI breakdown, with a one-tap undo if the parse looks wrong (§5.5).
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
        let items: [LogMealResponse.Parsed.Item]
        let fromPhoto: Bool
        let resolvedCheckIn: Bool
    }

    private(set) var phase: Phase = .compose
    var text = ""
    var photo: MealPhoto?

    private let api: APIClient

    init(api: APIClient) { self.api = api }

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
        let body = LogMealRequest(
            text: trimmedText.isEmpty ? nil : trimmedText,
            image: photo.map { .init(data: $0.base64, mediaType: $0.mediaType) }
        )
        let fromPhoto = photo != nil
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
                    items: res.parsed?.items ?? [],
                    fromPhoto: fromPhoto,
                    resolvedCheckIn: res.resolvedCheckInId != nil
                )
            )
        } catch {
            phase = .failed(Self.message(error))
        }
    }

    func undo() async {
        guard case let .logged(logged) = phase else { return }
        phase = .parsing
        do {
            try await api.delete("/api/meals/\(logged.mealId)")
            text = ""
            photo = nil
            phase = .compose
        } catch {
            phase = .failed(Self.message(error))
        }
    }

    func reset() {
        phase = .compose
    }

    private static func message(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
    }

    #if DEBUG
    static func previewed(_ phase: Phase) -> LogMealViewModel {
        let vm = LogMealViewModel(api: AppEnvironment.preview().api)
        vm.phase = phase
        return vm
    }

    static let sampleLogged = Phase.logged(
        Logged(
            mealId: "m_preview",
            kcal: 638,
            proteinG: 41,
            summary: "Chicken burrito bowl",
            notes: "Assumed a regular-size bowl with one scoop of rice.",
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
