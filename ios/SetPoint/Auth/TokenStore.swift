import Foundation
import Security

protocol TokenStore: Sendable {
    func read() -> String?
    func write(_ token: String)
    func clear()
}

/// Session JWT in the Keychain. `kSecAttrAccessibleAfterFirstUnlock` so a
/// server-driven check-in can still authenticate a background fetch.
final class KeychainTokenStore: TokenStore, @unchecked Sendable {
    private let service = "com.setpoint.app"
    private let account = "session-token"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8)
        else { return nil }
        return token
    }

    func write(_ token: String) {
        let data = Data(token.utf8)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            SecItemAdd(baseQuery.merging(attributes) { $1 } as CFDictionary, nil)
        }
    }

    func clear() {
        SecItemDelete(baseQuery as CFDictionary)
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
