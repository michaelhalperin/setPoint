import Foundation

/// Copy a person can see. Server, framework, and system strings never pass through.
enum UserFacingError {
    static var generic: String { L10n( "That didn’t work. Try again.") }
    static var unreachable: String { L10n( "No connection. Check your signal and try again.") }
    static var session: String { L10n( "Session expired. Sign in.") }

    static func message(for error: Error, fallback: String = generic) -> String {
        if let api = error as? APIError {
            switch api {
            case .unauthorized:
                return session
            case let .http(status, _):
                return http(status, fallback: fallback)
            case .decoding:
                return fallback
            case .transport:
                return unreachable
            }
        }
        if error is URLError { return unreachable }
        return fallback
    }

    static func http(_ status: Int, fallback: String = generic) -> String {
        switch status {
        case 429:
            return L10n( "Too many tries. Wait.")
        case 500 ... 599:
            return L10n( "The server had a problem. Try again in a bit.")
        default:
            return fallback
        }
    }
}
