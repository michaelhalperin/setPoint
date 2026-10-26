import ActivityKit
import Foundation

/// Runs the check-in Live Activity from the app: starts one when a check-in is
/// active, ends it when it's resolved (plan §2, §5a). Server push-to-start is
/// wired via `observePushToStartToken()` but only fires with an APNs key.
@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()
    private init() {}

    private var current: Activity<CheckInActivityAttributes>?
    private var observing = false

    func sync(activeCheckIn: HomeResponse.ActiveCheckIn?, ledger: HomeResponse.Ledger? = nil) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        guard let checkIn = activeCheckIn else {
            end()
            return
        }

        let state = CheckInActivityAttributes.ContentState(
            title: checkIn.message ?? "Time to eat.",
            detail: checkIn.prescription?.summary ?? "",
            deepLink: "setpoint://check-in/\(checkIn.id)",
            label: Self.label(for: checkIn),
            kcal: checkIn.prescription?.totalKcal,
            isRefuel: checkIn.kind == "REFUEL",
            dayKcal: ledger?.consumedKcal,
            dayTarget: ledger?.targetKcal
        )

        if let current, current.attributes.checkInId == checkIn.id {
            Task { await current.update(ActivityContent(state: state, staleDate: nil)) }
        } else {
            end()
            current = try? Activity.request(
                attributes: CheckInActivityAttributes(checkInId: checkIn.id),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: .token
            )
        }
    }

    /// "Lunch", "Refuel"… in the app's language; a plain line when it isn't about one meal.
    static func label(for checkIn: HomeResponse.ActiveCheckIn) -> String {
        if checkIn.kind == "REFUEL" { return L10n("Refuel") }
        switch checkIn.slot {
        case "breakfast": return L10n("Breakfast")
        case "lunch": return L10n("Lunch")
        case "dinner": return L10n("Dinner")
        case .some: return L10n("Snack")
        case nil: return L10n("Time to eat.")
        }
    }

    func end() {
        let activity = current
        current = nil
        Task { await activity?.end(nil, dismissalPolicy: .immediate) }
    }

    /// Uploads a push-to-start token so the server can begin a Live Activity
    /// while the app is closed (iOS 17.2+).
    func observePushToStartToken() {
        guard !observing else { return }
        observing = true
        if #available(iOS 17.2, *) {
            Task {
                for await tokenData in Activity<CheckInActivityAttributes>.pushToStartTokenUpdates {
                    let hex = tokenData.map { String(format: "%02x", $0) }.joined()
                    PushManager.shared.setLiveActivityStartToken(hex)
                }
            }
        }
    }
}
