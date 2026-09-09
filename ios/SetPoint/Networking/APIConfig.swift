import Foundation

enum APIConfig {
    /// The SetPoint backend. Override with a `SETPOINT_API_BASE_URL` launch
    /// environment variable (Scheme → Run → Arguments) when pointing at a
    /// deployed instance.
    static var baseURL: URL {
        if let override = ProcessInfo.processInfo.environment["SETPOINT_API_BASE_URL"],
           let url = URL(string: override) {
            return url
        }
        #if targetEnvironment(simulator)
        return URL(string: "http://localhost:3000")!
        #else
        return URL(string: "https://set-point-backend.vercel.app")!
        #endif
    }

    /// Enables the developer sign-in shortcut (`POST /api/auth/dev`).
    static var allowDevSignIn: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}
