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
    let chrome = AppChrome()
    let subscription = SubscriptionStore()
    let flags = FeatureFlags()

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

/// Shell state shared between a tab's content and the floating nav: whether the
/// nav should step aside (a check-in or the log panel is up), and requests to
/// open the log panel from the nav's "+".
@MainActor
@Observable
final class AppChrome {
    var navHidden = false
    private(set) var logRequest = 0
    /// The log panel open over a tab other than Today (see `LogAnywhere`).
    var logPanelOpen = false
    /// A tab asked for from inside a screen (Today's avatar → You).
    private(set) var tabRequest: MainTabView.Tab?

    func requestLog() {
        logRequest &+= 1
    }

    func requestTab(_ tab: MainTabView.Tab) {
        tabRequest = tab
    }

    func clearTabRequest() {
        tabRequest = nil
    }

    /// The meal that just landed, for the "Logged · Fix" toast.
    struct JustLogged: Equatable {
        let mealID: String
        let kcal: Int
        let title: String
        /// Tells two logs of the same meal apart, so each gets its own few seconds.
        let token = UUID()
    }

    private(set) var justLogged: JustLogged?

    func noteLogged(mealID: String, kcal: Int, title: String?) {
        justLogged = JustLogged(mealID: mealID, kcal: kcal, title: title ?? "Logged meal")
    }

    func clearJustLogged() {
        justLogged = nil
    }

    /// An action that showed on screen at once but the server then refused — it
    /// has been put back, and this offers to try again.
    struct ActionFailure: Equatable {
        let id = UUID()
        let message: String
    }

    private(set) var failure: ActionFailure?
    @ObservationIgnored private var retryAction: (() -> Void)?

    func reportFailure(_ message: String = "Didn’t save", retry: (() -> Void)?) {
        retryAction = retry
        failure = ActionFailure(message: message)
    }

    func retryFailure() {
        let retry = retryAction
        clearFailure()
        retry?()
    }

    func clearFailure() {
        failure = nil
        retryAction = nil
    }
}
