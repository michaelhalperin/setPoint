import Foundation
import HealthKit
import Observation

/// Reads HRV + resting heart rate, computes the deviation from personal baseline
/// on-device, and sends only the z-scores to `POST /api/biosignals` (plan §2, §4).
@MainActor
@Observable
final class HealthKitManager {
    static let shared = HealthKitManager()

    var api: APIClient?
    private(set) var connected = false

    private let store = HKHealthStore()
    private let hrvType = HKQuantityType(.heartRateVariabilitySDNN)
    private let rhrType = HKQuantityType(.restingHeartRate)
    private let hrvUnit = HKUnit.secondUnit(with: .milli)
    private let rhrUnit = HKUnit(from: "count/min")

    private init() {}

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Prompts for read access. HealthKit never reveals whether *read* was
    /// granted, so we treat "the sheet was shown without error" as connected and
    /// let a later empty query be the real signal.
    @discardableResult
    func connect() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: [hrvType, rhrType])
            connected = true
            enableBackgroundDelivery()
            await sync()
            return true
        } catch {
            return false
        }
    }

    func refreshConnectionState() {
        connected = isAvailable
            && store.authorizationStatus(for: hrvType) != .notDetermined
    }

    /// Fetch → compute → upload. Safe to call often; no-ops without access.
    func sync() async {
        guard isAvailable, let api else { return }

        async let hrv = samples(hrvType, unit: hrvUnit, days: 30)
        async let rhr = samples(rhrType, unit: rhrUnit, days: 30)
        let (hrvSamples, rhrSamples) = await (hrv, rhr)

        let now = Date()
        guard let hrvZ = BiosignalStats.zScore(hrvSamples, now: now) else { return }
        let rhrZ = BiosignalStats.zScore(rhrSamples, now: now)

        struct Body: Encodable {
            let hrvDeviation: Double
            let rhrDeviation: Double?
            let source = "healthkit"
        }
        try? await api.post("/api/biosignals", Body(hrvDeviation: hrvZ, rhrDeviation: rhrZ))
    }

    // MARK: HealthKit plumbing

    private func enableBackgroundDelivery() {
        for type in [hrvType, rhrType] {
            store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, _ in
                Task { await self?.sync(); completion() }
            }
            store.execute(query)
        }
    }

    private func samples(_ type: HKQuantityType, unit: HKUnit, days: Int) async -> [BiosignalSample] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, results, _ in
                let samples = (results as? [HKQuantitySample] ?? []).map {
                    BiosignalSample(value: $0.quantity.doubleValue(for: unit), date: $0.endDate)
                }
                continuation.resume(returning: samples)
            }
            store.execute(query)
        }
    }
}
