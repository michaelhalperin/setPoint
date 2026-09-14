import Foundation
import HealthKit
import Observation

/// What Apple Health knows about the body, for prefilling onboarding.
struct HealthProfile: Equatable {
    var heightCm: Double?
    var weightKg: Double?
    var birthDate: Date?
    var sex: Sex?
}

/// Reads HRV + resting heart rate, computes the deviation from personal baseline
/// on-device, and sends only the z-scores to `POST /api/biosignals` (plan §2, §4).
@MainActor
@Observable
final class HealthKitManager {
    static let shared = HealthKitManager()
    private static let lastSyncKey = "com.setpoint.app.health.lastSyncAt"

    var api: APIClient?
    private(set) var connected = false
    private(set) var lastSyncAt: Date?

    private let store = HKHealthStore()
    private let hrvType = HKQuantityType(.heartRateVariabilitySDNN)
    private let rhrType = HKQuantityType(.restingHeartRate)
    private let bodyMassType = HKQuantityType(.bodyMass)
    private let heightType = HKQuantityType(.height)
    private let hrvUnit = HKUnit.secondUnit(with: .milli)
    private let rhrUnit = HKUnit(from: "count/min")
    private let kgUnit = HKUnit.gramUnit(with: .kilo)

    private init() {
        lastSyncAt = UserDefaults.standard.object(forKey: Self.lastSyncKey) as? Date
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        [hrvType, rhrType, bodyMassType, heightType,
         HKCharacteristicType(.dateOfBirth), HKCharacteristicType(.biologicalSex)]
    }

    /// Prompts for read access. HealthKit never reveals whether *read* was
    /// granted, so we treat "the sheet was shown without error" as connected and
    /// let a later empty query be the real signal.
    @discardableResult
    func connect() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
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

    /// Whether Health actually holds recent HRV data — the real test of "a
    /// compatible device is connected" (§1). Used at onboarding to decide Smart
    /// vs Basic mode rather than trusting a toggle.
    func hasRecentSignal(days: Int = 21) async -> Bool {
        guard isAvailable else { return false }
        let hrv = await samples(hrvType, unit: hrvUnit, days: days)
        return !hrv.isEmpty
    }

    /// Height, weight, birth date and sex as far as Health knows them — the
    /// onboarding "Fill from Apple Health" shortcut. Missing or implausible
    /// values stay nil.
    func readProfile() async -> HealthProfile {
        guard isAvailable else { return HealthProfile() }
        async let height = latest(heightType, unit: .meterUnit(with: .centi))
        async let weight = latest(bodyMassType, unit: kgUnit)
        let (heightCm, weightKg) = await (height, weight)

        var profile = HealthProfile()
        if let heightCm, (120 ... 230).contains(heightCm) { profile.heightCm = heightCm.rounded() }
        if let weightKg, (35 ... 250).contains(weightKg) { profile.weightKg = (weightKg * 10).rounded() / 10 }
        if let components = try? store.dateOfBirthComponents(),
           let date = Calendar.current.date(from: components) {
            profile.birthDate = date
        }
        switch (try? store.biologicalSex())?.biologicalSex {
        case .male: profile.sex = .male
        case .female: profile.sex = .female
        default: break
        }
        return profile
    }

    /// Fetch → compute → upload. Safe to call often; no-ops without access.
    func sync() async {
        guard isAvailable, let api else { return }

        async let hrv = samples(hrvType, unit: hrvUnit, days: 30)
        async let rhr = samples(rhrType, unit: rhrUnit, days: 30)
        let (hrvSamples, rhrSamples) = await (hrv, rhr)
        defer { recordSync() }

        let now = Date()
        guard let hrvZ = BiosignalStats.zScore(hrvSamples, now: now) else { return }
        let rhrZ = BiosignalStats.zScore(rhrSamples, now: now)

        struct Body: Encodable {
            let hrvDeviation: Double
            let rhrDeviation: Double?
            let source = "healthkit"
        }
        try? await api.post("/api/biosignals", Body(hrvDeviation: hrvZ, rhrDeviation: rhrZ))

        await syncWeight()
    }

    private func recordSync() {
        lastSyncAt = Date()
        UserDefaults.standard.set(lastSyncAt, forKey: Self.lastSyncKey)
    }

    /// Push the latest body-mass sample to the weight log (M16). Idempotent —
    /// the backend upserts on (user, measuredAt), so re-sending is harmless.
    private func syncWeight() async {
        guard isAvailable, let api else { return }
        let recent = await samples(bodyMassType, unit: kgUnit, days: 14)
        guard let latest = recent.last, latest.value >= 25, latest.value <= 400 else { return }
        try? await api.post(
            "/api/weight",
            WeightLogRequest(
                weightKg: (latest.value * 10).rounded() / 10,
                measuredAt: ISO8601DateFormatter().string(from: latest.date),
                source: "healthkit"
            )
        )
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

    private func latest(_ type: HKQuantityType, unit: HKUnit) async -> Double? {
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, results, _ in
                let value = (results?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
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
