import Foundation

/// The events only the app can see: opening it, crashes, failed logs that never
/// reached the server, opening Wolt, and which screens people open. Everything
/// else (meals, check-ins, days) is recorded by the server where it happens.
/// Fire and forget: analytics never gets in the way. Previews (-uiStub) send nothing.
enum Analytics {
    enum Event: String {
        case appOpened = "app_opened"
        case appCrashed = "app_crashed"
        case woltOpened = "wolt_opened"
        case screenViewed = "screen_viewed"
        case mealLogFailed = "meal_log_failed"
        case mealQueuedOffline = "meal_queued_offline"
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

    /// Short codes only — matches the server's analytics prop alphabet.
    static func failReason(_ error: Error) -> String {
        guard let api = error as? APIError else { return "unknown" }
        switch api {
        case .unauthorized:
            return "unauthorized"
        case let .http(status, _):
            if status == 400 { return "bad_request" }
            if status == 409 { return "conflict" }
            if status == 429 { return "quota" }
            if status == 503 { return "parse" }
            if (500 ..< 600).contains(status) { return "server" }
            return "http_\(status)"
        case .decoding:
            return "decoding"
        case let .transport(underlying):
            guard let urlError = underlying as? URLError else { return "transport" }
            switch urlError.code {
            case .timedOut: return "timeout"
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
                 .cannotFindHost, .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff,
                 .callIsActive, .secureConnectionFailed:
                return "offline"
            default:
                return "transport"
            }
        }
    }

    static func mealSource(_ request: LogMealRequest) -> String {
        if request.image != nil { return "PHOTO" }
        if request.savedMealId != nil { return "SAVED" }
        if request.barcode != nil { return "BARCODE" }
        if request.catalogId != nil { return "CATALOG" }
        if request.prescriptionId != nil { return "PRESCRIPTION" }
        if request.macros != nil { return "MANUAL" }
        return "TEXT"
    }

    /// Failures the server never saw (the request didn't land). HTTP errors are
    /// recorded on the backend.
    static func isClientSideFailure(_ error: Error) -> Bool {
        guard let api = error as? APIError else { return true }
        switch api {
        case .http, .unauthorized: return false
        case .decoding, .transport: return true
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

