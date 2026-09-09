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
