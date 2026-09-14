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

    private init() {}

    /// The check-in notification's buttons. Both need the phone unlocked — they
    /// call the API with the signed-in session.
    static let checkInCategory = "CHECK_IN"
    static let ateThisAction = "ATE_THIS"
    static let snoozeHourAction = "SNOOZE_HOUR"

    func registerCategories() {
        let ate = UNNotificationAction(identifier: Self.ateThisAction, title: "I ate this", options: [.authenticationRequired])
        let snooze = UNNotificationAction(identifier: Self.snoozeHourAction, title: "In 1 hour", options: [.authenticationRequired])
        let category = UNNotificationCategory(identifier: Self.checkInCategory, actions: [ate, snooze], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
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
        Task { await uploadToken(hex, kind: "live_activity_start") }
    }

    func openCheckIn(_ id: String) {
        pendingCheckInID = id
    }

    func unregisterOnSignOut() async {
        guard let hex = deviceTokenHex else { return }
        try? await api?.delete("/api/push-tokens/\(hex)")
        deviceTokenHex = nil
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
