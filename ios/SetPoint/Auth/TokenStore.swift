import Foundation
import OSLog

protocol TokenStore: Sendable {
    func read() -> String?
    func write(_ token: String)
    func clear()
}

private let log = Logger(subsystem: "com.setpoint.app", category: "auth")

/// Stores the session JWT in the shared Keychain (see `SharedKeychain`), falling back to
/// `UserDefaults` when the Keychain isn't usable — which is the normal case for an
/// **unsigned** simulator build (`SecItem*` returns `errSecMissingEntitlement`). A signed
/// build (Xcode with a team, or any real device) uses the Keychain.
final class SessionTokenStore: TokenStore, @unchecked Sendable {
    private let defaultsKey = "com.setpoint.app.session-token"

    init() {
        // An earlier build copied the token into the app group's plain UserDefaults.
        AppGroup.removeLegacyPlaintextToken()
    }

    // MARK: TokenStore

    func read() -> String? {
        if let fromKeychain = SharedKeychain.readToken() { return fromKeychain }
        return UserDefaults.standard.string(forKey: defaultsKey)
    }

    func write(_ token: String) {
        // Verify the write actually stuck; if not, the Keychain isn't available.
        if SharedKeychain.writeToken(token), SharedKeychain.readToken() == token {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        } else {
            log.warning("Keychain unavailable (unsigned build?) — storing session token in UserDefaults")
            UserDefaults.standard.set(token, forKey: defaultsKey)
        }
    }

    func clear() {
        SharedKeychain.clear()
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}

/// In-memory store for previews and tests.
final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?

    init(token: String? = nil) { self.token = token }

    func read() -> String? { lock.withLock { token } }
    func write(_ token: String) { lock.withLock { self.token = token } }
    func clear() { lock.withLock { token = nil } }
}
