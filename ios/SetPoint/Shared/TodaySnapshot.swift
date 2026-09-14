import Foundation

enum AppGroup {
    static let id = "group.com.setpoint.app"
    static let snapshotKey = "todaySnapshot"
    static let tokenKey = "sessionToken"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: id) ?? .standard
    }

    static func writeToken(_ token: String?) {
        if let token, !token.isEmpty {
            defaults.set(token, forKey: tokenKey)
        } else {
            defaults.removeObject(forKey: tokenKey)
        }
    }

    static func readToken() -> String? {
        defaults.string(forKey: tokenKey)
    }
}

struct TodaySnapshot: Codable, Equatable {
    var remainingKcal: Int
    var targetKcal: Int
    var consumedKcal: Int
    var nextCheckIn: String?
    var nextSlot: String?
    var savedMeals: [Saved]

    struct Saved: Codable, Equatable, Identifiable {
        var id: String
        var name: String
        var kcal: Int
    }

    static let empty = TodaySnapshot(
        remainingKcal: 0,
        targetKcal: 0,
        consumedKcal: 0,
        nextCheckIn: nil,
        nextSlot: nil,
        savedMeals: []
    )

    static func load() -> TodaySnapshot {
        guard let data = AppGroup.defaults.data(forKey: AppGroup.snapshotKey),
              let snap = try? JSONDecoder().decode(TodaySnapshot.self, from: data)
        else { return .empty }
        return snap
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            AppGroup.defaults.set(data, forKey: AppGroup.snapshotKey)
        }
    }
}
