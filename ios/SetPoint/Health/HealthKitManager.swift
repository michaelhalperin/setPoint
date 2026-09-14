import Foundation
import HealthKit
import Observation
import UIKit

/// What Apple Health knows about the body, for prefilling onboarding.
struct HealthProfile: Equatable {
    var heightCm: Double?
    var weightKg: Double?
    var birthDate: Date?
    var sex: Sex?
}

/// Honest HealthKit read-auth state. HealthKit never reveals whether *read*
/// access was granted — only whether the permission sheet has been shown.
enum HealthState: Equatable {
    case unavailable       // HKHealthStore.isHealthDataAvailable() == false (e.g. some iPads)
    case notConnected      // permission sheet never shown (statusForAuthorizationRequest == .shouldRequest)
    case connected         // sheet shown (.unnecessary) — access may still be off for some types
}

enum HealthMode: String {
    case basic = "BASIC"
    case smart = "SMART"
}

/// Reads HRV + resting heart rate, computes the deviation from personal baseline
/// on-device, and sends only the z-scores to `POST /api/biosignals` (plan §2, §4).
@MainActor
@Observable
final class HealthKitManager {
    static let shared = HealthKitManager()

    static let lastSyncKey = "com.setpoint.app.health.lastSyncAt"
    static let bodyMassAnchorKey = "com.setpoint.app.health.anchor.bodyMass"
    static let lastModeKey = "com.setpoint.app.health.lastMode"
    static let writePrefsKey = HealthWritePreferences.defaultsKey

    var api: APIClient?
    private(set) var state: HealthState
    private(set) var hasHeartData = false
    private(set) var lastSyncAt: Date?
    private(set) var connecting = false
    private(set) var lastError: String?
    var writePreferences = HealthWritePreferences()
    private(set) var todayWrittenKcal = 0
    var connected: Bool { state == .connected }

    private let source: HealthDataSource
    private let defaults: UserDefaults
    private let tokenStore: TokenStore
    private let clock: () -> Date

    private let hrvType = HKQuantityType(.heartRateVariabilitySDNN)
    private let rhrType = HKQuantityType(.restingHeartRate)
    private let bodyMassType = HKQuantityType(.bodyMass)
    private let heightType = HKQuantityType(.height)
    private let hrvUnit = HKUnit.secondUnit(with: .milli)
    private let rhrUnit = HKUnit(from: "count/min")
    private let kgUnit = HKUnit.gramUnit(with: .kilo)

    private var observersStarted = false
    private var lastKnownMode: String?

    init(
        source: HealthDataSource = HKHealthStoreSource(),
        defaults: UserDefaults = .standard,
        tokenStore: TokenStore = SessionTokenStore(),
        now: @escaping () -> Date = Date.init
    ) {
        self.source = source
        self.defaults = defaults
        self.tokenStore = tokenStore
        self.clock = now
        self.lastSyncAt = defaults.object(forKey: Self.lastSyncKey) as? Date
        self.lastKnownMode = defaults.string(forKey: Self.lastModeKey)
        if let data = defaults.data(forKey: Self.writePrefsKey),
           let prefs = try? JSONDecoder().decode(HealthWritePreferences.self, from: data) {
            self.writePreferences = prefs
        }
        self.state = source.isAvailable ? .notConnected : .unavailable
        refreshTodayWritten()
    }

    var isAvailable: Bool { source.isAvailable }

    /// Settings hero / row copy. Never claims data is flowing when it isn't.
    var statusLine: String {
        switch state {
        case .unavailable, .notConnected:
            return "Not connected"
        case .connected:
            if !hasHeartData { return "Connected · no heart data yet" }
            if let lastSyncAt {
                return "Connected · last sync \(Self.timeOnly(lastSyncAt))"
            }
            return "Connected"
        }
    }

    private var readTypes: Set<HKObjectType> {
        [hrvType, rhrType, bodyMassType, heightType,
         HKCharacteristicType(.dateOfBirth), HKCharacteristicType(.biologicalSex),
         HKObjectType.workoutType()]
    }

    private var shareTypes: Set<HKSampleType> {
        [
            HKQuantityType(.dietaryEnergyConsumed),
            HKQuantityType(.dietaryProtein),
            HKQuantityType(.dietaryCarbohydrates),
            HKQuantityType(.dietaryFatTotal),
            bodyMassType,
        ]
    }

    func persistWritePreferences() {
        if let data = try? JSONEncoder().encode(writePreferences) {
            defaults.set(data, forKey: Self.writePrefsKey)
        }
        Task { await pushWritePreferences() }
    }

    func applyServerWritePreferences(_ prefs: HealthWritePreferences) {
        writePreferences = prefs
        if let data = try? JSONEncoder().encode(prefs) {
            defaults.set(data, forKey: Self.writePrefsKey)
        }
    }

    func writeMeal(_ meal: MealSummary) async {
        guard isAvailable, state == .connected, writePreferences.writesNutrition else { return }
        let date = MealFormat.parse(meal.loggedAt) ?? clock()
        do {
            try await source.saveFood(
                DietaryWrite(
                    mealId: meal.id,
                    kcal: Double(meal.kcal),
                    proteinG: meal.proteinG,
                    carbsG: meal.carbsG,
                    fatG: meal.fatG,
                    date: date
                ),
                types: writePreferences
            )
            rememberWritten(mealId: meal.id, kcal: meal.kcal, at: date)
        } catch {
            lastError = UserFacingError.message(for: error, fallback: "Couldn't write this meal to Health.")
        }
    }

    func deleteMealFromHealth(id: String) async {
        guard isAvailable, state == .connected else { return }
        try? await source.deleteFood(mealId: id)
        forgetWritten(mealId: id)
    }

    func writeWeighIn(kg: Double) async {
        guard isAvailable, state == .connected, writePreferences.bodyMass else { return }
        try? await source.saveBodyMass(kg: kg, at: clock(), mealId: "weight-\(UUID().uuidString)")
    }

    private static let writtenMealsKey = "com.setpoint.app.health.writtenMeals"

    private struct WrittenMealRecord: Codable {
        var kcal: Int
        var at: TimeInterval
    }

    private func loadWritten() -> [String: WrittenMealRecord] {
        guard let data = defaults.data(forKey: Self.writtenMealsKey),
              let map = try? JSONDecoder().decode([String: WrittenMealRecord].self, from: data)
        else { return [:] }
        return map
    }

    private func saveWritten(_ map: [String: WrittenMealRecord]) {
        if let data = try? JSONEncoder().encode(map) {
            defaults.set(data, forKey: Self.writtenMealsKey)
        }
    }

    private func rememberWritten(mealId: String, kcal: Int, at date: Date) {
        var map = loadWritten()
        map[mealId] = WrittenMealRecord(kcal: kcal, at: date.timeIntervalSince1970)
        saveWritten(map)
        refreshTodayWritten()
    }

    private func forgetWritten(mealId: String) {
        var map = loadWritten()
        map.removeValue(forKey: mealId)
        saveWritten(map)
        refreshTodayWritten()
    }

    func refreshTodayWritten() {
        let start = Calendar.current.startOfDay(for: clock())
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let lo = start.timeIntervalSince1970
        let hi = end.timeIntervalSince1970
        todayWrittenKcal = loadWritten().values
            .filter { $0.at >= lo && $0.at < hi }
            .reduce(0) { $0 + $1.kcal }
    }

    private func pushWritePreferences() async {
        guard let api else { return }
        try? await api.patch(
            "/api/settings",
            SettingsPatch(healthWrite: writePreferences.settingsPayload)
        )
    }

    /// Prompts for read access, then refreshes honest state, starts observers,
    /// and forces a sync. Errors leave `state` unchanged.
    @discardableResult
    func connect() async -> HealthState {
        guard isAvailable else { return state }
        connecting = true
        lastError = nil
        defer { connecting = false }
        do {
            try await source.requestAuthorization(toShare: shareTypes, read: readTypes)
        } catch {
            lastError = Self.message(forConnect: error)
            return state
        }
        await refreshState()
        await startBackgroundObservers()
        await sync(force: true)
        if hasHeartData { await setMode(.smart) }
        return state
    }

    /// Recompute `state` from `statusForAuthorizationRequest`, then `hasHeartData`
    /// via a cheap HRV query. Call at launch and whenever the app becomes active.
    func refreshState() async {
        guard isAvailable else {
            state = .unavailable
            return
        }
        let status = await source.requestStatus(toShare: shareTypes, read: readTypes)
        state = status == .unnecessary ? .connected : .notConnected
        do {
            let to = clock()
            let from = Calendar.current.date(byAdding: .day, value: -21, to: to) ?? to
            let hrv = try await source.samples(type: hrvType, unit: hrvUnit, from: from, to: to)
            hasHeartData = !hrv.isEmpty
        } catch {
            if isLockedDevice(error) { return }
            hasHeartData = false
        }
    }

    /// Whether Health actually holds recent HRV data — the real test of "a
    /// compatible device is connected" (§1). Used at onboarding to decide Smart
    /// vs Basic mode rather than trusting a toggle.
    func hasRecentSignal(days: Int = 21) async -> Bool {
        guard isAvailable else {
            hasHeartData = false
            return false
        }
        do {
            let to = clock()
            let from = Calendar.current.date(byAdding: .day, value: -days, to: to) ?? to
            let hrv = try await source.samples(type: hrvType, unit: hrvUnit, from: from, to: to)
            hasHeartData = !hrv.isEmpty
            return hasHeartData
        } catch {
            return hasHeartData
        }
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
        if let date = try? source.dateOfBirth() {
            profile.birthDate = date
        }
        switch try? source.biologicalSex() {
        case .male: profile.sex = .male
        case .female: profile.sex = .female
        default: break
        }
        return profile
    }

    /// Fetch → compute → upload. Safe to call often; no-ops without access.
    func sync(force: Bool = false) async {
        guard isAvailable, state == .connected, api != nil, tokenStore.read() != nil else { return }
        if !force, let lastSyncAt, clock().timeIntervalSince(lastSyncAt) < 15 * 60 { return }

        let now = clock()
        do {
            async let hrv = source.samples(type: hrvType, unit: hrvUnit, from: daysAgo(30, from: now), to: now)
            async let rhr = source.samples(type: rhrType, unit: rhrUnit, from: daysAgo(30, from: now), to: now)
            let (hrvSamples, rhrSamples) = try await (hrv, rhr)

            let cutoff21 = daysAgo(21, from: now)
            hasHeartData = hrvSamples.contains { $0.date >= cutoff21 }

            if let hrvZ = BiosignalStats.zScore(hrvSamples, now: now) {
                let rhrZ = BiosignalStats.zScore(rhrSamples, now: now)
                struct Body: Encodable {
                    let hrvDeviation: Double
                    let rhrDeviation: Double?
                    let source = "healthkit"
                }
                try? await api?.post("/api/biosignals", Body(hrvDeviation: hrvZ, rhrDeviation: rhrZ))
            }

            try await syncWeight(now: now)
            await uploadWorkouts(now: now)

            lastSyncAt = now
            defaults.set(lastSyncAt, forKey: Self.lastSyncKey)

            if hasHeartData {
                await setMode(.smart)
            } else {
                await setMode(.basic)
            }
        } catch {
            if isLockedDevice(error) { return }
        }
    }

    /// Idempotent. HealthKit relaunches the app for background delivery, so
    /// observers must be registered on every launch, not only right after connect.
    func startBackgroundObservers() async {
        guard !observersStarted, isAvailable, state == .connected else { return }
        observersStarted = true

        try? await source.enableBackgroundDelivery(type: hrvType, frequency: .hourly)
        try? await source.enableBackgroundDelivery(type: rhrType, frequency: .hourly)
        try? await source.enableBackgroundDelivery(type: bodyMassType, frequency: .immediate)
        try? await source.enableBackgroundDelivery(sampleType: .workoutType(), frequency: .hourly)

        let handle: HealthObserverHandler = { [weak self] completion in
            var task = UIBackgroundTaskIdentifier.invalid
            task = UIApplication.shared.beginBackgroundTask(withName: "health-sync") {
                UIApplication.shared.endBackgroundTask(task)
                task = .invalid
            }
            Task { @MainActor in
                defer {
                    completion()
                    if task != .invalid {
                        UIApplication.shared.endBackgroundTask(task)
                        task = .invalid
                    }
                }
                await self?.sync()
            }
        }
        source.startObserver(type: hrvType, handler: handle)
        source.startObserver(type: rhrType, handler: handle)
        source.startObserver(type: bodyMassType, handler: handle)
        source.startObserver(sampleType: .workoutType(), handler: handle)
    }

    /// Sign-out: HealthKit permission is user-level (don't stop observers), but
    /// the weight cursor and last-sync stamp belong to the account.
    func clearAccountSyncState() {
        lastSyncAt = nil
        defaults.removeObject(forKey: Self.lastSyncKey)
        defaults.removeObject(forKey: Self.bodyMassAnchorKey)
    }

    func uploadWorkouts(now: Date = Date()) async {
        guard let api, tokenStore.read() != nil else { return }
        let from = Calendar.current.date(byAdding: .day, value: -2, to: now) ?? now
        do {
            let samples = try await source.workouts(from: from, to: now)
            let payload = WorkoutSyncPayload(
                workouts: samples.map {
                    .init(
                        source: "HEALTHKIT",
                        kind: $0.kind,
                        start: $0.start,
                        durationMin: $0.durationMin,
                        activeKcal: $0.activeKcal,
                        clientId: $0.id
                    )
                }
            )
            try await api.put("/api/workouts", payload)
        } catch {
            if isLockedDevice(error) { return }
        }
    }

    /// `PATCH /api/settings { mode }`. Fire-and-forget; cached so we don't repeat.
    func setMode(_ mode: HealthMode) async {
        guard lastKnownMode != mode.rawValue, let api else { return }
        do {
            try await api.patch("/api/settings", SettingsPatch(mode: mode.rawValue))
            lastKnownMode = mode.rawValue
            defaults.set(mode.rawValue, forKey: Self.lastModeKey)
        } catch {
            // try? equivalent — leave the cache unset so the next sync retries.
        }
    }

    // MARK: Internals

    private func syncWeight(now: Date) async throws {
        guard let api else { return }
        let stored = defaults.data(forKey: Self.bodyMassAnchorKey)
        let since: Date? = stored == nil ? daysAgo(14, from: now) : nil
        let (samples, newAnchor) = try await source.anchoredSamples(
            type: bodyMassType,
            unit: kgUnit,
            anchor: stored,
            since: since
        )
        for sample in samples {
            guard (25 ... 400).contains(sample.value) else { continue }
            try await api.post(
                "/api/weight",
                WeightLogRequest(
                    weightKg: (sample.value * 10).rounded() / 10,
                    measuredAt: ISO8601DateFormatter().string(from: sample.date),
                    source: "healthkit"
                )
            )
        }
        defaults.set(newAnchor, forKey: Self.bodyMassAnchorKey)
    }

    private func latest(_ type: HKQuantityType, unit: HKUnit) async -> Double? {
        (try? await source.latestSample(type: type, unit: unit))?.value
    }

    private func daysAgo(_ days: Int, from date: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: date) ?? date
    }

    private func isLockedDevice(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain == HKErrorDomain && ns.code == HKError.Code.errorDatabaseInaccessible.rawValue
    }

    static func timeOnly(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func message(forConnect error: Error) -> String {
        let ns = error as NSError
        let text = ns.localizedDescription.lowercased()
        if ns.domain == HKErrorDomain, text.contains("entitlement") {
            return "This simulator build isn’t signed for Health. Quit SetPoint and launch with SIGNED=1 ./ios/scripts/run.sh"
        }
        return "Couldn't open the Health permission sheet."
    }
}
