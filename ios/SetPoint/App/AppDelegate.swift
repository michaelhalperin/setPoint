import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Task { @MainActor in PushManager.shared.registerCategories() }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in PushManager.shared.setDeviceToken(deviceToken) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[push] remote registration failed: \(error.localizedDescription)")
    }

    // Show the banner even when the app is foregrounded.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    // A notification was tapped (deep-link to the check-in) or one of its
    // buttons was pressed ("I ate this" / "In 1 hour" — answered in place).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard let id = info["checkInId"] as? String else { return }
        let prescriptionID = info["prescriptionId"] as? String
        let action = response.actionIdentifier
        if action == UNNotificationDefaultActionIdentifier {
            await MainActor.run { PushManager.shared.openCheckIn(id) }
        } else {
            await PushManager.shared.handleAction(action, checkInID: id, prescriptionID: prescriptionID)
        }
    }
}
