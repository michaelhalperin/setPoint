import Foundation
import Sentry

/// Crash and error reporting (Sentry). Off until a DSN is set in the
/// `SENTRY_DSN` build setting (project.yml), so local and preview builds send
/// nothing.
///
/// Privacy (§4): crashes and errors only — no screenshots, no view hierarchy,
/// no default PII, no performance tracing.
enum CrashReporting {
    static func start(bundle: Bundle = .main) {
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
    }

    /// The DSN from Info.plist, or nil when the build setting is empty.
    static func dsn(in bundle: Bundle) -> String? {
        guard let raw = bundle.object(forInfoDictionaryKey: "SentryDSN") as? String else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasPrefix("https://") else { return nil }
        return value
    }
}
