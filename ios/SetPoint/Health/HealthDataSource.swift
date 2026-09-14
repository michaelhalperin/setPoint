import Foundation
import HealthKit

/// Completion for an `HKObserverQuery`. Always call it (use `defer`).
typealias HealthObserverHandler = (@escaping () -> Void) -> Void

/// Every HealthKit call `HealthKitManager` needs. Production uses
/// `HKHealthStoreSource`; tests inject a fake.
protocol HealthDataSource: Sendable {
    var isAvailable: Bool { get }

    func requestAuthorization(read: Set<HKObjectType>) async throws
    /// Wraps `HKHealthStore.statusForAuthorizationRequest(toShare: [], read:)`.
    func requestStatus(read: Set<HKObjectType>) async -> HKAuthorizationRequestStatus

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
}

/// Real HealthKit. Completion handlers run off the main thread; the manager
/// hops back to `@MainActor` before touching observable state.
final class HKHealthStoreSource: HealthDataSource, @unchecked Sendable {
    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization(read types: Set<HKObjectType>) async throws {
        try await store.requestAuthorization(toShare: [], read: types)
    }

    func requestStatus(read types: Set<HKObjectType>) async -> HKAuthorizationRequestStatus {
        (try? await store.statusForAuthorizationRequest(toShare: [], read: types)) ?? .unknown
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
}
