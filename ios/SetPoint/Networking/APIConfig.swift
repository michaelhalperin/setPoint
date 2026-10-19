import Foundation

enum APIConfig {
    /// The SetPoint backend — the deployed one, simulator included. Override with a
    /// `SETPOINT_API_BASE_URL` launch environment variable (Scheme → Run → Arguments)
    /// to point at a local server such as http://localhost:3000.
    static var baseURL: URL {
        if let override = ProcessInfo.processInfo.environment["SETPOINT_API_BASE_URL"],
           let url = URL(string: override) {
            return url
        }
        return URL(string: "https://set-point-backend.vercel.app")!
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
