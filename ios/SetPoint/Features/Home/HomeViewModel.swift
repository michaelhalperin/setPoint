import Foundation
import Observation

@MainActor
@Observable
final class HomeViewModel {
    enum Phase {
        case loading
        case loaded(HomeResponse)
        case needsOnboarding
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    var loggingMeal = false

    private let api: APIClient
    private let onUnauthorized: @MainActor () -> Void

    init(api: APIClient, onUnauthorized: @escaping @MainActor () -> Void) {
        self.api = api
        self.onUnauthorized = onUnauthorized
    }

    func load(showSpinner: Bool = true) async {
        if showSpinner { phase = .loading }
        do {
            let home: HomeResponse = try await api.get("/api/home")
            phase = .loaded(home)
            LiveActivityController.shared.sync(activeCheckIn: home.activeCheckIn)
        } catch APIError.unauthorized {
            onUnauthorized()
        } catch let APIError.http(status, _) where status == 409 {
            phase = .needsOnboarding
        } catch {
            phase = .failed(message(for: error))
        }
    }

    func logMeal(text: String) async {
        loggingMeal = true
        defer { loggingMeal = false }
        do {
            let _: LogMealResponse = try await api.post("/api/meals", LogMealRequest(text: text))
            await load(showSpinner: false)
        } catch APIError.unauthorized {
            onUnauthorized()
        } catch {
            phase = .failed(message(for: error))
        }
    }

    private func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
    }

    #if DEBUG
    static func previewed(_ phase: Phase) -> HomeViewModel {
        let env = AppEnvironment.preview()
        let vm = HomeViewModel(api: env.api, onUnauthorized: {})
        vm.phase = phase
        return vm
    }
    #endif
}
