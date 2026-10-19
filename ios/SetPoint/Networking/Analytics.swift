import Foundation

/// The events only the app can see: opening it, opening Wolt, and which screens
/// people open. Everything else (meals, check-ins, days) is recorded by the server
/// where it happens. Fire and forget: analytics never gets in the way.
/// Previews (-uiStub) send nothing.
enum Analytics {
    enum Event: String {
        case appOpened = "app_opened"
        case woltOpened = "wolt_opened"
        case screenViewed = "screen_viewed"
    }

    private static let isPreview = ProcessInfo.processInfo.arguments.contains("-uiStub")

    private struct Body: Encodable {
        let name: String
        let props: [String: String]?
    }

    static func send(_ event: Event, props: [String: String]? = nil, api: APIClient) {
        guard !isPreview else { return }
        Task {
            try? await api.post("/api/events", Body(name: event.rawValue, props: props))
        }
    }
}

import SwiftUI

extension Analytics {
    static func screen(_ name: String, api: APIClient) {
        send(.screenViewed, props: ["screen": name], api: api)
    }
}

private struct TrackScreen: ViewModifier {
    let name: String
    @Environment(AppEnvironment.self) private var env

    func body(content: Content) -> some View {
        content.onAppear { Analytics.screen(name, api: env.api) }
    }
}

extension View {
    /// Records a screen view each time this screen appears (sheets, pushed screens).
    /// Tabs are recorded when switched to, since they stay alive behind each other.
    func trackScreen(_ name: String) -> some View {
        modifier(TrackScreen(name: name))
    }
}

