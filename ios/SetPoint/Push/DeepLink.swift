import Foundation

enum DeepLink: Equatable {
    case checkIn(id: String)

    /// Parses `setpoint://check-in/<id>`.
    init?(url: URL) {
        guard url.scheme == "setpoint" else { return nil }
        switch url.host {
        case "check-in":
            guard let id = url.pathComponents.first(where: { $0 != "/" }), !id.isEmpty else { return nil }
            self = .checkIn(id: id)
        default:
            return nil
        }
    }
}
