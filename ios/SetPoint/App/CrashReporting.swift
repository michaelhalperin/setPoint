import Foundation
import Sentry

/// Crash and error reporting. Sentry is off until a DSN is set in the
/// `SENTRY_DSN` build setting (project.yml), so local and preview builds send
/// nothing there. A small local marker still lets the next launch tell our
/// own analytics so crashes show up on the owner dashboard.
///
/// Privacy (§4): crashes and errors only — no screenshots, no view hierarchy,
/// no default PII, no performance tracing.
enum CrashReporting {
    static var defaults: UserDefaults = .standard
    private static let markerKey = "com.setpoint.app.pendingCrash"

    struct Marker: Equatable {
        var kind: String
        var name: String
    }

    static func start(bundle: Bundle = .main) {
        installExceptionHandler()
        guard let dsn = dsn(in: bundle) else { return }
        SentrySDK.start { options in
            options.dsn = dsn
            #if DEBUG
            options.environment = "debug"
            #else
            options.environment = "production"
            #endif
            options.sendDefaultPii = false
            options.attachScreenshot = false
            options.attachViewHierarchy = false
            options.tracesSampleRate = 0
        }
        if SentrySDK.crashedLastRun {
            remember(Marker(kind: "fatal", name: "sentry"))
        }
    }

    /// Sends a pending crash from the previous launch, then clears it.
    static func flush(api: APIClient) {
        guard let marker = consumePending() else { return }
        Analytics.send(.appCrashed, props: ["kind": marker.kind, "name": marker.name], api: api)
    }

    static func remember(_ marker: Marker) {
        let kind = sanitize(marker.kind)
        let name = sanitize(marker.name)
        guard !kind.isEmpty, !name.isEmpty else { return }
        defaults.set("\(kind):\(name)", forKey: markerKey)
    }

    static func pendingMarker() -> Marker? {
        guard let raw = defaults.string(forKey: markerKey), !raw.isEmpty else { return nil }
        let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
        if parts.count == 2 {
            return Marker(kind: sanitize(parts[0]), name: sanitize(parts[1]))
        }
        return Marker(kind: "fatal", name: sanitize(raw))
    }

    static func consumePending() -> Marker? {
        let marker = pendingMarker()
        if marker != nil { defaults.removeObject(forKey: markerKey) }
        return marker
    }

    /// The DSN from Info.plist, or nil when the build setting is empty.
    static func dsn(in bundle: Bundle) -> String? {
        guard let raw = bundle.object(forInfoDictionaryKey: "SentryDSN") as? String else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasPrefix("https://") else { return nil }
        return value
    }

    /// Letters, digits, dots, underscores, hyphens — the analytics alphabet.
    static func sanitize(_ value: String) -> String {
        let kept = value.unicodeScalars.map { ch -> Character in
            CharacterSet.alphanumerics.contains(ch) || ch == "." || ch == "_" || ch == "-"
                ? Character(ch)
                : "_"
        }
        return String(kept.prefix(40))
    }

    private static func installExceptionHandler() {
        previousUncaughtExceptionHandler = NSGetUncaughtExceptionHandler()
        NSSetUncaughtExceptionHandler(setpointUncaughtException)
    }
}

private var previousUncaughtExceptionHandler: NSUncaughtExceptionHandler?

private func setpointUncaughtException(_ exception: NSException) {
    CrashReporting.remember(CrashReporting.Marker(kind: "exception", name: exception.name.rawValue))
    previousUncaughtExceptionHandler?(exception)
}
