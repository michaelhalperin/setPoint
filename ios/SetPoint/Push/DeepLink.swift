import Foundation

enum DeepLink: Equatable {
    case checkIn(id: String)
    case logPhoto

    /// Parses `setpoint://check-in/<id>` and `setpoint://log/photo`.
    init?(url: URL) {
        guard url.scheme == "setpoint" else { return nil }
        switch url.host {
        case "check-in":
            guard let id = url.pathComponents.first(where: { $0 != "/" }), !id.isEmpty else { return nil }
            self = .checkIn(id: id)
        case "log":
            guard url.pathComponents.contains("photo") else { return nil }
            self = .logPhoto
        default:
            return nil
        }
    }
}
