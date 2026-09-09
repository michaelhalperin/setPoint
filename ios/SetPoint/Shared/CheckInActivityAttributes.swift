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
    }

    var checkInId: String
}
