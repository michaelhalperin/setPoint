import Foundation
import HealthKit

struct HealthWorkoutSample: Sendable, Equatable {
    let id: String
    let start: Date
    let durationMin: Int
    let activeKcal: Int?
    let kind: String
}

/// Completion for an `HKObserverQuery`. Always call it (use `defer`).
typealias HealthObserverHandler = (@escaping () -> Void) -> Void

/// Every HealthKit call `HealthKitManager` needs. Production uses
/// `HKHealthStoreSource`; tests inject a fake.
protocol HealthDataSource: Sendable {
    var isAvailable: Bool { get }

    func requestAuthorization(toShare: Set<HKSampleType>, read: Set<HKObjectType>) async throws
    /// Wraps `HKHealthStore.statusForAuthorizationRequest`.
    func requestStatus(toShare: Set<HKSampleType>, read: Set<HKObjectType>) async -> HKAuthorizationRequestStatus

    func samples(type: HKQuantityType, unit: HKUnit, from: Date, to: Date) async throws -> [BiosignalSample]
    func latestSample(type: HKQuantityType, unit: HKUnit) async throws -> BiosignalSample?

    func dateOfBirth() throws -> Date?
    func biologicalSex() throws -> HKBiologicalSex

    func enableBackgroundDelivery(type: HKQuantityType, frequency: HKUpdateFrequency) async throws
    func startObserver(type: HKQuantityType, handler: @escaping HealthObserverHandler)

    /// One-shot anchored read. `anchor` is `NSKeyedArchiver` data for an
    /// `HKQueryAnchor` (nil on first run). `since` limits the first run.
    func anchoredSamples(
        type: HKQuantityType,
        unit: HKUnit,
        anchor: Data?,
        since: Date?
    ) async throws -> (samples: [BiosignalSample], newAnchor: Data)

    func saveFood(_ write: DietaryWrite, types: HealthWritePreferences) async throws
    func deleteFood(mealId: String) async throws
    func saveBodyMass(kg: Double, at date: Date, mealId: String) async throws

    func workouts(from: Date, to: Date) async throws -> [HealthWorkoutSample]
    func enableBackgroundDelivery(sampleType: HKSampleType, frequency: HKUpdateFrequency) async throws
    func startObserver(sampleType: HKSampleType, handler: @escaping HealthObserverHandler)
}

/// Real HealthKit. Completion handlers run off the main thread; the manager
/// hops back to `@MainActor` before touching observable state.
final class HKHealthStoreSource: HealthDataSource, @unchecked Sendable {
    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization(toShare: Set<HKSampleType>, read: Set<HKObjectType>) async throws {
        try await store.requestAuthorization(toShare: toShare, read: read)
    }

    func requestStatus(toShare: Set<HKSampleType>, read: Set<HKObjectType>) async -> HKAuthorizationRequestStatus {
        (try? await store.statusForAuthorizationRequest(toShare: toShare, read: read)) ?? .unknown
    }

    func samples(type: HKQuantityType, unit: HKUnit, from: Date, to: Date) async throws -> [BiosignalSample] {
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)
        return try await querySamples(type: type, unit: unit, predicate: predicate, limit: HKObjectQueryNoLimit, sort: [sort])
    }

    func latestSample(type: HKQuantityType, unit: HKUnit) async throws -> BiosignalSample? {
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return try await querySamples(type: type, unit: unit, predicate: nil, limit: 1, sort: [sort]).first
    }

    func dateOfBirth() throws -> Date? {
        let components = try store.dateOfBirthComponents()
        return Calendar.current.date(from: components)
    }

    func biologicalSex() throws -> HKBiologicalSex {
        try store.biologicalSex().biologicalSex
    }

    func enableBackgroundDelivery(type: HKQuantityType, frequency: HKUpdateFrequency) async throws {
        try await store.enableBackgroundDelivery(for: type, frequency: frequency)
    }

    func startObserver(type: HKQuantityType, handler: @escaping HealthObserverHandler) {
        let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completionHandler, _ in
            handler(completionHandler)
        }
        store.execute(query)
    }

    func anchoredSamples(
        type: HKQuantityType,
        unit: HKUnit,
        anchor: Data?,
        since: Date?
    ) async throws -> (samples: [BiosignalSample], newAnchor: Data) {
        let hkAnchor: HKQueryAnchor? = {
            guard let anchor else { return nil }
            return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: anchor)
        }()
        let predicate = since.map { HKQuery.predicateForSamples(withStart: $0, end: nil) }

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: type,
                predicate: predicate,
                anchor: hkAnchor,
                limit: HKObjectQueryNoLimit
            ) { _, added, _, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let samples = (added as? [HKQuantitySample] ?? []).map {
                    BiosignalSample(value: $0.quantity.doubleValue(for: unit), date: $0.endDate)
                }
                let data: Data
                if let newAnchor,
                   let archived = try? NSKeyedArchiver.archivedData(withRootObject: newAnchor, requiringSecureCoding: true) {
                    data = archived
                } else {
                    data = anchor ?? Data()
                }
                continuation.resume(returning: (samples, data))
            }
            store.execute(query)
        }
    }

    private func querySamples(
        type: HKQuantityType,
        unit: HKUnit,
        predicate: NSPredicate?,
        limit: Int,
        sort: [NSSortDescriptor]
    ) async throws -> [BiosignalSample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: limit,
                sortDescriptors: sort
            ) { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let samples = (results as? [HKQuantitySample] ?? []).map {
                    BiosignalSample(value: $0.quantity.doubleValue(for: unit), date: $0.endDate)
                }
                continuation.resume(returning: samples)
            }
            store.execute(query)
        }
    }

    func saveFood(_ write: DietaryWrite, types: HealthWritePreferences) async throws {
        guard types.writesNutrition, let foodType = HKObjectType.correlationType(forIdentifier: .food) else { return }
        let start = write.date
        let version = nextVersion(for: write.mealId)
        let meta: [String: Any] = [
            HKMetadataKeySyncIdentifier: write.mealId,
            HKMetadataKeySyncVersion: version,
            HKMetadataKeyFoodType: "SetPoint meal",
        ]
        var objects: Set<HKSample> = []
        if types.energy {
            objects.insert(quantitySample(.dietaryEnergyConsumed, value: write.kcal, unit: .kilocalorie(), at: start, meta: meta))
        }
        if types.protein {
            objects.insert(quantitySample(.dietaryProtein, value: write.proteinG, unit: .gram(), at: start, meta: meta))
        }
        if types.carbs {
            objects.insert(quantitySample(.dietaryCarbohydrates, value: write.carbsG, unit: .gram(), at: start, meta: meta))
        }
        if types.fat {
            objects.insert(quantitySample(.dietaryFatTotal, value: write.fatG, unit: .gram(), at: start, meta: meta))
        }
        guard !objects.isEmpty else { return }
        let correlation = HKCorrelation(type: foodType, start: start, end: start, objects: objects, metadata: meta)
        try await store.save(correlation)
    }

    func deleteFood(mealId: String) async throws {
        guard let foodType = HKObjectType.correlationType(forIdentifier: .food) else { return }
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeySyncIdentifier,
            allowedValues: [mealId]
        )
        _ = try await store.deleteObjects(of: foodType, predicate: predicate)
        clearVersion(for: mealId)
    }

    func saveBodyMass(kg: Double, at date: Date, mealId: String) async throws {
        let meta: [String: Any] = [
            HKMetadataKeySyncIdentifier: mealId,
            HKMetadataKeySyncVersion: nextVersion(for: mealId),
        ]
        let sample = quantitySample(.bodyMass, value: kg, unit: .gramUnit(with: .kilo), at: date, meta: meta)
        try await store.save(sample)
    }

    func workouts(from: Date, to: Date) async throws -> [HealthWorkoutSample] {
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let mapped = (results as? [HKWorkout] ?? []).map { workout -> HealthWorkoutSample in
                    let kcal = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie())
                    return HealthWorkoutSample(
                        id: workout.uuid.uuidString,
                        start: workout.startDate,
                        durationMin: max(1, Int((workout.duration / 60).rounded())),
                        activeKcal: kcal.map { Int($0.rounded()) },
                        kind: HealthWorkoutKind.map(workout.workoutActivityType)
                    )
                }
                continuation.resume(returning: mapped)
            }
            store.execute(query)
        }
    }

    func enableBackgroundDelivery(sampleType: HKSampleType, frequency: HKUpdateFrequency) async throws {
        try await store.enableBackgroundDelivery(for: sampleType, frequency: frequency)
    }

    func startObserver(sampleType: HKSampleType, handler: @escaping HealthObserverHandler) {
        let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { _, completionHandler, _ in
            handler(completionHandler)
        }
        store.execute(query)
    }

    private func quantitySample(
        _ id: HKQuantityTypeIdentifier,
        value: Double,
        unit: HKUnit,
        at date: Date,
        meta: [String: Any]
    ) -> HKQuantitySample {
        HKQuantitySample(
            type: HKQuantityType(id),
            quantity: HKQuantity(unit: unit, doubleValue: value),
            start: date,
            end: date,
            metadata: meta
        )
    }

    private func nextVersion(for mealId: String) -> Int {
        var versions = UserDefaults.standard.dictionary(forKey: HealthWritePreferences.versionsKey) as? [String: Int] ?? [:]
        let next = (versions[mealId] ?? 0) + 1
        versions[mealId] = next
        UserDefaults.standard.set(versions, forKey: HealthWritePreferences.versionsKey)
        return next
    }

    private func clearVersion(for mealId: String) {
        var versions = UserDefaults.standard.dictionary(forKey: HealthWritePreferences.versionsKey) as? [String: Int] ?? [:]
        versions.removeValue(forKey: mealId)
        UserDefaults.standard.set(versions, forKey: HealthWritePreferences.versionsKey)
    }
}

enum HealthWorkoutKind {
    static func map(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining:
            return "STRENGTH"
        case .running, .cycling, .swimming, .hiking, .rowing, .elliptical, .walking, .stairClimbing:
            return "CARDIO"
        default:
            return "MIXED"
        }
    }
}
