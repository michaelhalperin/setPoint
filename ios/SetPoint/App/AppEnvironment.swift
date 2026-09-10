import Foundation
import Observation

/// Lightweight DI container handed down through the SwiftUI environment.
@MainActor
@Observable
final class AppEnvironment {
    let auth: AuthStore
    let api: APIClient
    let push = PushManager.shared
    let health = HealthKitManager.shared
    let changes = AppDataChanges()

    init(tokenStore: TokenStore = SessionTokenStore()) {
        self.auth = AuthStore(tokenStore: tokenStore)
        self.api = APIClient(
            tokenProvider: { tokenStore.read() },
            onTokenRefresh: { renewed in
                // Only replace a live session — never resurrect one after sign-out.
                guard tokenStore.read() != nil else { return }
                tokenStore.write(renewed)
            }
        )
        push.api = api
        health.api = api
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

    func mealsChanged() {
        mealRevision &+= 1
    }
}
