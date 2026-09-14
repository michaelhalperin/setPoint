import Observation
import UIKit
import UserNotifications

@MainActor
@Observable
final class PushManager {
    static let shared = PushManager()

    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    /// Set when a notification / Live Activity is tapped; MainTabView observes it
    /// to deep-link to the check-in.
    var pendingCheckInID: String?

    /// Injected by AppEnvironment.
    var api: APIClient?

    private var deviceTokenHex: String?
    private var liveActivityStartTokenHex: String?

    /// Use `shared` in the app; internal so tests can build an isolated one.
    init() {}

    /// The check-in notification's buttons. Both need the phone unlocked — they
    /// call the API with the signed-in session.
    static let checkInCategory = "CHECK_IN"
    static let headsUpCategory = "HEADS_UP"
    static let refuelCategory = "REFUEL"
    static let ateThisAction = "ATE_THIS"
    static let snoozeHourAction = "SNOOZE_HOUR"
    static let remindAction = "REMIND_ME"
    static let afterBlockAction = "AFTER_BLOCK"
    static let coverDinnerAction = "COVER_DINNER"

    func registerCategories() {
        let ate = UNNotificationAction(identifier: Self.ateThisAction, title: "I ate this", options: [.authenticationRequired])
        let snooze = UNNotificationAction(identifier: Self.snoozeHourAction, title: "In 1 hour", options: [.authenticationRequired])
        let remind = UNNotificationAction(identifier: Self.remindAction, title: "Remind me", options: [.authenticationRequired])
        let after = UNNotificationAction(identifier: Self.afterBlockAction, title: "After this block", options: [.authenticationRequired])
        let hadThis = UNNotificationAction(identifier: Self.ateThisAction, title: "I had this", options: [.authenticationRequired])
        let coverDinner = UNNotificationAction(identifier: Self.coverDinnerAction, title: "Dinner covers it", options: [.authenticationRequired])
        let meal = UNNotificationCategory(identifier: Self.checkInCategory, actions: [ate, snooze], intentIdentifiers: [])
        let headsUp = UNNotificationCategory(identifier: Self.headsUpCategory, actions: [remind, after], intentIdentifiers: [])
        let refuel = UNNotificationCategory(identifier: Self.refuelCategory, actions: [hadThis, coverDinner], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([meal, headsUp, refuel])
    }

    /// Answer a check-in straight from its notification. Falls back to opening it
    /// when there's nothing to log or the call fails.
    func handleAction(_ action: String, checkInID: String, prescriptionID: String?) async {
        guard let api else { return openCheckIn(checkInID) }
        do {
            switch action {
            case Self.ateThisAction:
                guard let prescriptionID else { return openCheckIn(checkInID) }
                try await CheckInActions.eat(prescriptionID: prescriptionID, api: api)
            case Self.snoozeHourAction:
                try await CheckInActions.snooze(checkInID: checkInID, minutes: 60, api: api)
            case Self.remindAction:
                try await CheckInActions.snooze(checkInID: checkInID, minutes: 45, api: api)
            case Self.afterBlockAction:
                try await CheckInActions.snooze(checkInID: checkInID, minutes: 180, api: api)
            case Self.coverDinnerAction:
                try await CheckInActions.cover(checkInID: checkInID, api: api)
            default:
                openCheckIn(checkInID)
            }
        } catch {
            openCheckIn(checkInID)
        }
    }

    func syncAuthorizationStatus() async {
        authorizationStatus = await UNUserNotificationCenter.current()
            .notificationSettings().authorizationStatus
    }

    /// Ask for permission; on grant, register for remote notifications.
    @discardableResult
    func requestAuthorization() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await syncAuthorizationStatus()
        if granted { UIApplication.shared.registerForRemoteNotifications() }
        return granted
    }

    /// If we already have permission, make sure APNs has our token.
    func registerIfAuthorized() async {
        await syncAuthorizationStatus()
        if authorizationStatus == .authorized || authorizationStatus == .provisional {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func setDeviceToken(_ data: Data) {
        let hex = data.map { String(format: "%02x", $0) }.joined()
        guard hex != deviceTokenHex else { return }
        deviceTokenHex = hex
        Task { await uploadToken(hex, kind: "alert") }
    }

    func setLiveActivityStartToken(_ hex: String) {
        liveActivityStartTokenHex = hex
        Task { await uploadToken(hex, kind: "live_activity_start") }
    }

    func openCheckIn(_ id: String) {
        pendingCheckInID = id
    }

    /// Detaches this device from the account being signed out of, so its
    /// check-ins stop arriving here. Authenticates with that account's token
    /// explicitly — the stored session is already gone — and never reports a
    /// 401, so a stale session can't set off another sign-out.
    func unregister(sessionToken: String, baseURL: URL = APIConfig.baseURL, session: URLSession = .shared) async {
        let tokens = [deviceTokenHex, liveActivityStartTokenHex].compactMap { $0 }
        // Forget them so the next sign-in uploads them for the new account.
        deviceTokenHex = nil
        liveActivityStartTokenHex = nil
        guard !tokens.isEmpty else { return }
        let client = APIClient(baseURL: baseURL, session: session, tokenProvider: { sessionToken })
        for token in tokens {
            try? await client.delete("/api/push-tokens/\(token)")
        }
    }

    private func uploadToken(_ token: String, kind: String) async {
        struct Body: Encodable {
            let token: String
            let kind: String
            #if DEBUG
            let environment = "sandbox"
            #else
            let environment = "production"
            #endif
        }
        try? await api?.post("/api/push-tokens", Body(token: token, kind: kind))
    }
}
