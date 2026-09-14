import Foundation
import Security

/// The session token in the Keychain, shared with the widget extension and App Intents
/// through the app group. Never stored in plain `UserDefaults`, shared or not.
enum SharedKeychain {
    private static let service = "com.setpoint.app"
    private static let account = "session-token"

    private static var itemQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static var sharedQuery: [String: Any] {
        var query = itemQuery
        query[kSecAttrAccessGroup as String] = AppGroup.id
        return query
    }

    static func readToken() -> String? {
        if let shared = copy(sharedQuery) { return shared }
        // Tokens saved before sharing live in the app's own access group: move them.
        guard let legacy = copy(itemQuery) else { return nil }
        SecItemDelete(itemQuery as CFDictionary)
        if !writeToken(legacy) {
            // The shared group isn't available (unsigned build) — put it back where it was.
            add(itemQuery, token: legacy)
        }
        return legacy
    }

    /// Returns false when the Keychain isn't usable (e.g. an unsigned simulator build).
    @discardableResult
    static func writeToken(_ token: String) -> Bool {
        let data = Data(token.utf8)
        let status = SecItemUpdate(sharedQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            return add(sharedQuery, token: token) == errSecSuccess
        }
        return status == errSecSuccess
    }

    static func clear() {
        // No access group → removes the shared item and any legacy copy.
        SecItemDelete(itemQuery as CFDictionary)
    }

    private static func copy(_ base: [String: Any]) -> String? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    private static func add(_ base: [String: Any], token: String) -> OSStatus {
        var query = base
        query[kSecValueData as String] = Data(token.utf8)
        // Intents can run while the phone is locked after first unlock.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(query as CFDictionary, nil)
    }
}
