import AppIntents
import Foundation
import WidgetKit

enum WidgetAPI {
    static var baseURL: URL {
        if let override = ProcessInfo.processInfo.environment["SETPOINT_API_BASE_URL"],
           let url = URL(string: override) {
            return url
        }
        #if targetEnvironment(simulator)
        return URL(string: "http://localhost:3000")!
        #else
        return URL(string: "https://set-point-backend.vercel.app")!
        #endif
    }
}

struct SavedMealEntity: AppEntity, Identifiable, Hashable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Saved meal"
    static var defaultQuery = SavedMealQuery()

    var id: String
    var name: String
    var kcal: Int

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(kcal) kcal")
    }
}

struct SavedMealQuery: EntityQuery {
    func entities(for identifiers: [SavedMealEntity.ID]) async throws -> [SavedMealEntity] {
        TodaySnapshot.load().savedMeals
            .filter { identifiers.contains($0.id) }
            .map { SavedMealEntity(id: $0.id, name: $0.name, kcal: $0.kcal) }
    }

    func suggestedEntities() async throws -> [SavedMealEntity] {
        TodaySnapshot.load().savedMeals.map { SavedMealEntity(id: $0.id, name: $0.name, kcal: $0.kcal) }
    }
}

enum UsualMealSlot: String, AppEnum {
    case breakfast, lunch, dinner

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Meal"
    static var caseDisplayRepresentations: [UsualMealSlot: DisplayRepresentation] = [
        .breakfast: "breakfast",
        .lunch: "lunch",
        .dinner: "dinner",
    ]
}

struct LogSavedMealIntent: AppIntent {
    static var title: LocalizedStringResource = "Log my usual meal"
    static var description = IntentDescription("Logs one of your saved SetPoint meals.")
    static var openAppWhenRun = false

    @Parameter(title: "Meal")
    var meal: SavedMealEntity?

    @Parameter(title: "Which meal")
    var slot: UsualMealSlot?

    init() {}

    init(meal: SavedMealEntity) {
        self.meal = meal
    }

    init(mealId: String, mealName: String, kcal: Int) {
        self.meal = SavedMealEntity(id: mealId, name: mealName, kcal: kcal)
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let saved = TodaySnapshot.load().savedMeals
        let chosen: SavedMealEntity?
        if let meal {
            chosen = meal
        } else if let slot {
            // "Log my usual breakfast" logs the meal tagged breakfast — never some other plate.
            chosen = saved.first { $0.suggestSlot == slot.rawValue }
                .map { SavedMealEntity(id: $0.id, name: $0.name, kcal: $0.kcal) }
            if chosen == nil {
                throw IntentError.message("No usual \(slot.rawValue) saved yet. Tag one in SetPoint.")
            }
        } else {
            chosen = saved.first.map { SavedMealEntity(id: $0.id, name: $0.name, kcal: $0.kcal) }
        }
        guard let chosen else {
            throw IntentError.message("Save a usual meal in SetPoint first.")
        }
        guard let token = SharedKeychain.readToken() else {
            throw IntentError.message("Open SetPoint to sign in first.")
        }
        var request = URLRequest(url: WidgetAPI.baseURL.appendingPathComponent("api/meals"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode([
            "savedMealId": chosen.id,
            "clientId": UUID().uuidString,
        ])
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw IntentError.message("Couldn't log that meal.")
        }
        var snap = TodaySnapshot.load()
        snap.remainingKcal = max(0, snap.remainingKcal - chosen.kcal)
        snap.consumedKcal += chosen.kcal
        snap.save()
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "Logged · \(chosen.name) · \(chosen.kcal) kcal")
    }
}

struct KcalLeftIntent: AppIntent {
    static var title: LocalizedStringResource = "Calories left today"
    static var description = IntentDescription("How many calories are left on today's SetPoint target.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let left = max(0, TodaySnapshot.load().remainingKcal)
        return .result(dialog: "\(left) kcal left today")
    }
}

struct SetPointShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: KcalLeftIntent(),
            phrases: [
                "How many calories left in \(.applicationName)",
                "What's left today in \(.applicationName)",
            ],
            shortTitle: "Calories left",
            systemImageName: "flame"
        )
        AppShortcut(
            intent: LogSavedMealIntent(),
            phrases: [
                "Log my usual \(\.$slot) in \(.applicationName)",
                "Log my usual meal in \(.applicationName)",
            ],
            shortTitle: "Log usual meal",
            systemImageName: "fork.knife"
        )
    }
}

private enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case message(String)
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case let .message(text): return "\(text)"
        }
    }
}
