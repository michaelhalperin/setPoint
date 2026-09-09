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

    init(tokenStore: TokenStore = SessionTokenStore()) {
        self.auth = AuthStore(tokenStore: tokenStore)
        self.api = APIClient(tokenProvider: { tokenStore.read() })
        push.api = api
        health.api = api
    }

    static func preview() -> AppEnvironment {
        AppEnvironment(tokenStore: InMemoryTokenStore(token: "preview-token"))
    }
}
