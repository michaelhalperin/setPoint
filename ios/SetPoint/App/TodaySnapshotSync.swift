import Foundation
import WidgetKit

enum TodaySnapshotSync {
    static func write(home: HomeResponse, saved: [SavedMeal]? = nil) {
        var snap = TodaySnapshot.load()
        snap.day = TodaySnapshot.dayKey(for: .now)
        snap.remainingKcal = home.ledger.remainingKcal
        snap.targetKcal = home.ledger.targetKcal
        snap.consumedKcal = home.ledger.consumedKcal
        if let next = home.nextCheckIn {
            snap.nextSlot = next.slot
            snap.nextCheckIn = Self.clock(next.dueMin)
        } else {
            snap.nextSlot = nil
            snap.nextCheckIn = nil
        }
        if let saved {
            snap.savedMeals = Self.snapshotMeals(saved)
        }
        snap.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func writeSaved(_ saved: [SavedMeal]) {
        var snap = TodaySnapshot.load()
        snap.savedMeals = Self.snapshotMeals(saved)
        snap.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Widgets show the first two; Siri picks by meal from the rest.
    private static func snapshotMeals(_ saved: [SavedMeal]) -> [TodaySnapshot.Saved] {
        saved.prefix(12).map {
            TodaySnapshot.Saved(id: $0.id, name: $0.name, kcal: $0.kcal, suggestSlot: $0.suggestSlot)
        }
    }

    private static func clock(_ minutes: Int) -> String {
        let wrapped = ((minutes % 1440) + 1440) % 1440
        var c = DateComponents()
        c.hour = wrapped / 60
        c.minute = wrapped % 60
        let date = Calendar.current.date(from: c) ?? .now
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: date)
    }
}
