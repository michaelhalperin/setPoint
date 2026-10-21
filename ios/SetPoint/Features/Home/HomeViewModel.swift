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
    /// A background refresh failed while Today was already showing: keep the
    /// last good data on screen and say when it's from, instead of wiping it.
    private(set) var staleSince: Date?
    private var loadedAt: Date?
    /// Debug previews show sample data and never touch the network.
    private var isPreview = false
    private static let ignoredCheckInKey = "com.setpoint.app.ignoredCheckInID"

    private let api: APIClient
    private let onUnauthorized: @MainActor () -> Void
    private let onMealChanged: @MainActor () -> Void

    init(
        api: APIClient,
        onUnauthorized: @escaping @MainActor () -> Void,
        onMealChanged: @escaping @MainActor () -> Void = {}
    ) {
        self.api = api
        self.onUnauthorized = onUnauthorized
        self.onMealChanged = onMealChanged
    }

    func load(showSpinner: Bool = true) async {
        if isPreview { return }
        if showSpinner { phase = .loading }
        do {
            await OfflineMealQueue.flush(using: api)
            let home = withoutIgnoredCheckIn(try await api.get("/api/home"))
            phase = .loaded(home)
            loadedAt = Date()
            staleSince = nil
            LiveActivityController.shared.sync(activeCheckIn: home.activeCheckIn)
            TodaySnapshotSync.write(home: home)
            await HealthKitManager.shared.reconcileToday(home.meals)
        } catch APIError.unauthorized {
            onUnauthorized()
        } catch let APIError.http(status, _) where status == 409 {
            phase = .needsOnboarding
        } catch {
            if !showSpinner, case .loaded = phase {
                staleSince = loadedAt ?? Date()
            } else {
                phase = .failed(message(for: error))
            }
        }
    }

    /// Deletes a meal. It leaves Today at once; if the server says no, it comes back.
    func removeMeal(id: String) async throws {
        let before = applyNow { $0.removing(id) }
        do {
            try await api.delete("/api/meals/\(id)")
            onMealChanged()
            await load(showSpinner: false)
            await HealthKitManager.shared.deleteMealFromHealth(id: id)
        } catch APIError.unauthorized {
            onUnauthorized()
            throw APIError.unauthorized
        } catch {
            if let before { restore(before) }
            throw error
        }
    }

    /// Shows a change on Today before the server confirms it. Returns what was
    /// there, to put back with `restore` if the request fails.
    @discardableResult
    func applyNow(_ change: (HomeResponse) -> HomeResponse) -> HomeResponse? {
        guard case let .loaded(home) = phase else { return nil }
        let updated = change(home)
        phase = .loaded(updated)
        TodaySnapshotSync.write(home: updated)
        return home
    }

    func restore(_ home: HomeResponse) {
        phase = .loaded(withoutIgnoredCheckIn(home))
        TodaySnapshotSync.write(home: home)
    }

    func ignoreCheckIn(_ id: String) {
        UserDefaults.standard.set(id, forKey: Self.ignoredCheckInKey)
        _ = applyNow { home in
            guard home.activeCheckIn?.id == id else { return home }
            return home.closingCheckIn
        }
    }

    func applyLoggedMeal(_ meal: MealSummary, slot: MealSlot) {
        guard case let .loaded(home) = phase else { return }
        let updated = home.inserting(meal, into: slot)
        phase = .loaded(updated)
        TodaySnapshotSync.write(home: updated)
    }

    private func withoutIgnoredCheckIn(_ home: HomeResponse) -> HomeResponse {
        let ignored = UserDefaults.standard.string(forKey: Self.ignoredCheckInKey)
        guard let ignored, home.activeCheckIn?.id == ignored else { return home }
        return home.closingCheckIn
    }

    private func message(for error: Error) -> String {
        UserFacingError.message(for: error, fallback: L10n( "Couldn’t load today."))
    }

    #if DEBUG
    static func previewedStale(_ home: HomeResponse) -> HomeViewModel {
        let vm = previewed(.loaded(home))
        vm.staleSince = Calendar.current.date(byAdding: .minute, value: -48, to: .now)
        return vm
    }

    static func previewed(_ phase: Phase) -> HomeViewModel {
        let env = AppEnvironment.preview()
        let vm = HomeViewModel(api: env.api, onUnauthorized: {})
        vm.phase = phase
        vm.isPreview = true
        return vm
    }
    #endif
}
