import Foundation
import OSLog
import Security

protocol TokenStore: Sendable {
    func read() -> String?
    func write(_ token: String)
    func clear()
}

private let log = Logger(subsystem: "com.setpoint.app", category: "auth")

/// Stores the session JWT in the Keychain, falling back to `UserDefaults` when
/// the Keychain isn't usable — which is the normal case for an **unsigned**
/// simulator build (`SecItem*` returns `errSecMissingEntitlement`). A signed
/// build (Xcode with a team, or any real device) uses the Keychain.
final class SessionTokenStore: TokenStore, @unchecked Sendable {
    private let service = "com.setpoint.app"
    private let account = "session-token"
    private let defaultsKey = "com.setpoint.app.session-token"

    // MARK: TokenStore

    func read() -> String? {
        if let fromKeychain = keychainRead() { return fromKeychain }
        return UserDefaults.standard.string(forKey: defaultsKey)
    }

    func write(_ token: String) {
        keychainWrite(token)
        // Verify the write actually stuck; if not, the Keychain isn't available.
        if keychainRead() == token {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        } else {
            log.warning("Keychain unavailable (unsigned build?) — storing session token in UserDefaults")
            UserDefaults.standard.set(token, forKey: defaultsKey)
        }
    }

    func clear() {
        SecItemDelete(baseQuery as CFDictionary)
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    // MARK: Keychain

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func keychainRead() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func keychainWrite(_ token: String) {
        let data = Data(token.utf8)
        let attributes: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus != errSecSuccess {
                log.debug("SecItemAdd failed: \(addStatus)")
            }
        } else if updateStatus != errSecSuccess {
            log.debug("SecItemUpdate failed: \(updateStatus)")
        }
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
