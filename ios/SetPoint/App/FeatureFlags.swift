import Foundation
import Observation

/// Which features are on for this user, from GET /api/flags. Each flag has the
/// same default here as on the server, so a launch with no signal behaves; the
/// last answer is kept for the next launch.
@MainActor
@Observable
final class FeatureFlags {
    enum Flag: String, CaseIterable {
        case orderNearby = "order_nearby"

        var defaultValue: Bool {
            switch self {
            case .orderNearby: return true
            }
        }
    }

    private struct Response: Decodable { let flags: [String: Bool] }

    private static let storeKey = "com.setpoint.app.featureFlags.v1"
    private var values: [String: Bool]

    init() {
        values = UserDefaults.standard.dictionary(forKey: Self.storeKey) as? [String: Bool] ?? [:]
    }

    func isOn(_ flag: Flag) -> Bool {
        values[flag.rawValue] ?? flag.defaultValue
    }

    func refresh(using api: APIClient) async {
        guard let response: Response = try? await api.get("/api/flags") else { return }
        values = response.flags
        UserDefaults.standard.set(response.flags, forKey: Self.storeKey)
    }

    /// Signing out forgets the last user's flags; the next account loads its own.
    nonisolated static func clearStored() {
        UserDefaults.standard.removeObject(forKey: storeKey)
    }
}
