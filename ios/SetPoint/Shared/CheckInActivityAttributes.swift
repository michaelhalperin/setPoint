import ActivityKit
import Foundation

/// Shared between the app and the widget extension.
struct CheckInActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// The manager's-voice line.
        var title: String
        /// The prescription's directive, e.g. "2× Hard-boiled eggs + Banana". Empty if none.
        var detail: String
        /// `setpoint://check-in/<id>`
        var deepLink: String
        /// What the check-in is for, e.g. "Lunch" or "Refuel". Nil from older builds.
        var label: String? = nil
        /// The suggested plate's kcal.
        var kcal: Int? = nil
        /// A post-training refuel rather than a meal.
        var isRefuel: Bool? = nil
        /// Today so far and today's target, for the thin progress line.
        var dayKcal: Int? = nil
        var dayTarget: Int? = nil
    }

    var checkInId: String
}
