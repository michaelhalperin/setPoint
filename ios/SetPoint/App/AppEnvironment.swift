import Foundation
import Observation
import WidgetKit

/// Lightweight DI container handed down through the SwiftUI environment.
@MainActor
@Observable
final class AppEnvironment {
    let auth: AuthStore
    let api: APIClient
    let push = PushManager.shared
    let health = HealthKitManager.shared
    let calendar = CalendarManager.shared
    let changes = AppDataChanges()
    let subscription = SubscriptionStore()

    init(tokenStore: TokenStore = SessionTokenStore()) {
        let auth = AuthStore(tokenStore: tokenStore)
        self.auth = auth
        self.api = APIClient(
            tokenProvider: { tokenStore.read() },
            onTokenRefresh: { renewed in
                guard tokenStore.read() != nil else { return }
                tokenStore.write(renewed)
            },
            onUnauthorized: {
                Task { @MainActor in auth.handleUnauthorized() }
            }
        )
        push.api = api
        health.api = api
        calendar.api = api
    }

    static func preview() -> AppEnvironment {
        AppEnvironment(tokenStore: InMemoryTokenStore(token: "preview-token"))
    }
}

/// Lightweight cross-feature invalidation. Screens still own their data and
/// loading states; this only tells them when a shared server-backed ledger has
/// changed underneath them.
@MainActor
@Observable
final class AppDataChanges {
    private(set) var mealRevision = 0

    var pendingLogPhoto = false

    func mealsChanged() {
        mealRevision &+= 1
        WidgetCenter.shared.reloadAllTimelines()
    }

    func openLogPhoto() {
        pendingLogPhoto = true
    }
}
