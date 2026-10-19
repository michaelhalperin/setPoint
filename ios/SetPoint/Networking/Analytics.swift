import Foundation

/// The two events only the app can see. Everything else (meals, check-ins, days)
/// is recorded by the server where it happens. Fire and forget: analytics never
/// gets in the way.
enum Analytics {
    enum Event: String {
        case appOpened = "app_opened"
        case woltOpened = "wolt_opened"
    }

    private struct Body: Encodable {
        let name: String
        let props: [String: String]?
    }

    static func send(_ event: Event, props: [String: String]? = nil, api: APIClient) {
        Task {
            try? await api.post("/api/events", Body(name: event.rawValue, props: props))
        }
    }
}
