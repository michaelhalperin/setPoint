import Foundation

enum AppGroup {
    static let id = "group.com.setpoint.app"
    static let snapshotKey = "todaySnapshot"
    private static let legacyTokenKey = "sessionToken"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: id) ?? .standard
    }

    /// The session token now lives only in the Keychain (`SharedKeychain`).
    static func removeLegacyPlaintextToken() {
        defaults.removeObject(forKey: legacyTokenKey)
    }
}

struct TodaySnapshot: Codable, Equatable {
    var remainingKcal: Int
    var targetKcal: Int
    var consumedKcal: Int
    var nextCheckIn: String?
    var nextSlot: String?
    var savedMeals: [Saved]
    /// The local day (yyyy-MM-dd) these numbers are for. Nil in snapshots saved before it existed.
    var day: String? = nil

    struct Saved: Codable, Equatable, Identifiable {
        var id: String
        var name: String
        var kcal: Int
        /// breakfast / lunch / dinner, when the user tagged it.
        var suggestSlot: String? = nil
    }

    static let empty = TodaySnapshot(
        remainingKcal: 0,
        targetKcal: 0,
        consumedKcal: 0,
        nextCheckIn: nil,
        nextSlot: nil,
        savedMeals: []
    )

    /// Today's snapshot. One left over from an earlier day keeps the target and saved meals
    /// but nothing eaten and no check-in — yesterday's "kcal left" is never shown as today's.
    static func load(now: Date = .now) -> TodaySnapshot {
        guard let data = AppGroup.defaults.data(forKey: AppGroup.snapshotKey),
              var snap = try? JSONDecoder().decode(TodaySnapshot.self, from: data)
        else { return .empty }
        let today = dayKey(for: now)
        if snap.day != today {
            snap.consumedKcal = 0
            snap.remainingKcal = snap.targetKcal
            snap.nextCheckIn = nil
            snap.nextSlot = nil
            snap.day = today
        }
        return snap
    }

    static func dayKey(for date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            AppGroup.defaults.set(data, forKey: AppGroup.snapshotKey)
        }
    }
}
