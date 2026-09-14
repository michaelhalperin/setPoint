import HealthKit
import XCTest
@testable import SetPoint

@MainActor
final class HealthKitManagerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var fake: FakeHealthDataSource!
    private var tokens: InMemoryTokenStore!
    private var captured: LockedBox<[CapturedRequest]>!
    private var now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        super.setUp()
        suiteName = "HealthKitManagerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        fake = FakeHealthDataSource()
        tokens = InMemoryTokenStore(token: "tok")
        captured = LockedBox([])
        let box = captured!
        StubURLProtocol.handler = { request in
            box.set(box.get() + [CapturedRequest(request)])
            return (200, ["Content-Type": "application/json"], Data("{}".utf8))
        }
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeManager() -> HealthKitManager {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let tokens = tokens!
        let api = APIClient(
            baseURL: URL(string: "https://api.test")!,
            session: URLSession(configuration: config),
            tokenProvider: { tokens.read() }
        )
        let manager = HealthKitManager(
            source: fake,
            defaults: defaults,
            tokenStore: tokens,
            now: { [weak self] in self?.now ?? Date() }
        )
        manager.api = api
        return manager
    }

    private var posts: [CapturedRequest] { captured.get() }
    private func posts(_ path: String) -> [CapturedRequest] {
        posts.filter { $0.path == path }
    }

    // MARK: State

    func testStateIsNotConnectedBeforeAuthAndConnectedAfter() async {
        let manager = makeManager()
        XCTAssertEqual(manager.state, .notConnected)
        XCTAssertFalse(manager.connected)

        let state = await manager.connect()
        XCTAssertEqual(state, .connected)
        XCTAssertTrue(manager.connected)
        XCTAssertFalse(manager.hasHeartData)
        XCTAssertTrue(manager.statusLine.contains("no heart data yet"))
    }

    func testConnectFailureLeavesStateUnchanged() async {
        fake.authorizationError = NSError(domain: "test", code: 1)
        let manager = makeManager()
        let state = await manager.connect()
        XCTAssertEqual(state, .notConnected)
        XCTAssertEqual(manager.state, .notConnected)
        XCTAssertEqual(manager.lastError, "Couldn't open the Health permission sheet.")
    }

    // MARK: Sync gates

    func testSyncIsSkippedWhenNotConnected() async {
        let manager = makeManager()
        await manager.sync(force: true)
        XCTAssertTrue(posts.isEmpty)
        XCTAssertNil(manager.lastSyncAt)
    }

    func testSyncIsSkippedWhenSignedOut() async {
        fake.authStatus = .unnecessary
        tokens.clear()
        let manager = makeManager()
        await manager.refreshState()
        await manager.sync(force: true)
        XCTAssertTrue(posts.isEmpty)
    }

    func testSyncIsThrottledWithin15MinutesAndRunsWhenForced() async {
        fake.authStatus = .unnecessary
        fake.addSamples(hrvForZScore(), for: .heartRateVariabilitySDNN)
        let manager = makeManager()
        await manager.refreshState()
        await manager.sync(force: true)
        let afterFirst = posts.count
        XCTAssertGreaterThan(afterFirst, 0)

        await manager.sync()
        XCTAssertEqual(posts.count, afterFirst)

        await manager.sync(force: true)
        XCTAssertGreaterThan(posts.count, afterFirst)
    }

    func testLockedDeviceLeavesLastSyncAtUnchanged() async {
        let previous = now.addingTimeInterval(-3_600)
        defaults.set(previous, forKey: HealthKitManager.lastSyncKey)
        fake.authStatus = .unnecessary
        fake.samplesError = NSError(
            domain: HKErrorDomain,
            code: HKError.Code.errorDatabaseInaccessible.rawValue
        )
        let manager = makeManager()
        XCTAssertEqual(manager.lastSyncAt, previous)
        await manager.refreshState()
        await manager.sync(force: true)
        XCTAssertEqual(manager.lastSyncAt, previous)
        XCTAssertTrue(posts.isEmpty)
    }

    // MARK: Biosignals

    func testBiosignalsPostOnlyWhenZScoreExistsAndBodyHasNoRawSamples() async {
        fake.authStatus = .unnecessary
        fake.addSamples(
            [BiosignalSample(value: 50, date: now.addingTimeInterval(-3_600))],
            for: .heartRateVariabilitySDNN
        )
        let manager = makeManager()
        await manager.refreshState()
        await manager.sync(force: true)
        XCTAssertTrue(posts("/api/biosignals").isEmpty)
        XCTAssertTrue(manager.hasHeartData)

        fake.addSamples(hrvForZScore(), for: .heartRateVariabilitySDNN)
        fake.addSamples(rhrForZScore(), for: .restingHeartRate)
        await manager.sync(force: true)

        let bios = posts("/api/biosignals")
        XCTAssertEqual(bios.count, 1)
        let json = bios[0].json
        XCTAssertTrue(Set(json.keys).isSubset(of: ["hrvDeviation", "rhrDeviation", "source"]))
        XCTAssertNotNil((json["hrvDeviation"] as? NSNumber)?.doubleValue)
        XCTAssertEqual(json["source"] as? String, "healthkit")
        XCTAssertNil(json["samples"])
        XCTAssertNil(json["value"])
        XCTAssertNil(json["sdnn"])
    }

    // MARK: Weight

    func testWeightUploadsInRangeAnchoredSamplesOnceAndSkipsOutOfRange() async {
        fake.authStatus = .unnecessary
        fake.addWeight(20, at: now.addingTimeInterval(-60))
        fake.addWeight(80.4, at: now.addingTimeInterval(-120))
        fake.addWeight(500, at: now.addingTimeInterval(-180))
        fake.addWeight(82, at: now.addingTimeInterval(-20 * 24 * 3_600)) // older than 14 days
        let manager = makeManager()
        await manager.refreshState()
        await manager.sync(force: true)

        let weights = posts("/api/weight")
        XCTAssertEqual(weights.count, 1)
        XCTAssertEqual((weights[0].json["weightKg"] as? NSNumber)?.doubleValue, 80.4)
        XCTAssertEqual(weights[0].json["source"] as? String, "healthkit")
        XCTAssertNotNil(weights[0].json["measuredAt"])
        XCTAssertNotNil(defaults.data(forKey: HealthKitManager.bodyMassAnchorKey))

        await manager.sync(force: true)
        XCTAssertEqual(posts("/api/weight").count, 1)

        fake.addWeight(81, at: now)
        await manager.sync(force: true)
        XCTAssertEqual(posts("/api/weight").count, 2)
        XCTAssertEqual((posts("/api/weight").last?.json["weightKg"] as? NSNumber)?.doubleValue, 81)
    }

    func testWeightAnchorAdvancesOnlyAfterSuccessfulUpload() async {
        fake.authStatus = .unnecessary
        fake.addWeight(78, at: now)
        let fail = LockedBox(true)
        let box = captured!
        StubURLProtocol.handler = { request in
            box.set(box.get() + [CapturedRequest(request)])
            if request.url?.path == "/api/weight", fail.get() {
                return (500, ["Content-Type": "application/json"], Data("{}".utf8))
            }
            return (200, ["Content-Type": "application/json"], Data("{}".utf8))
        }
        let previous = now.addingTimeInterval(-3_600)
        defaults.set(previous, forKey: HealthKitManager.lastSyncKey)
        let manager = makeManager()
        await manager.refreshState()
        await manager.sync(force: true)

        XCTAssertNil(defaults.data(forKey: HealthKitManager.bodyMassAnchorKey))
        XCTAssertEqual(manager.lastSyncAt, previous)
        XCTAssertEqual(posts("/api/weight").count, 1)

        fail.set(false)
        await manager.sync(force: true)
        XCTAssertNotNil(defaults.data(forKey: HealthKitManager.bodyMassAnchorKey))
        XCTAssertEqual(manager.lastSyncAt, now)
        XCTAssertEqual(posts("/api/weight").count, 2)
    }

    // MARK: Mode

    func testModePatchIsSentOnceWhenHeartDataFirstAppears() async {
        fake.authStatus = .unnecessary
        let manager = makeManager()
        await manager.refreshState()
        await manager.sync(force: true)
        XCTAssertEqual(posts("/api/settings").map { $0.json["mode"] as? String }, ["BASIC"])

        fake.addSamples(hrvForZScore(), for: .heartRateVariabilitySDNN)
        await manager.sync(force: true)
        XCTAssertEqual(
            posts("/api/settings").compactMap { $0.json["mode"] as? String },
            ["BASIC", "SMART"]
        )

        await manager.sync(force: true)
        XCTAssertEqual(
            posts("/api/settings").compactMap { $0.json["mode"] as? String },
            ["BASIC", "SMART"]
        )
    }

    // MARK: Fixtures

    private func hrvForZScore() -> [BiosignalSample] {
        var samples = (1 ... 10).map { i in
            BiosignalSample(value: 50, date: now.addingTimeInterval(-24 * 3600 * Double(i)))
        }
        samples.append(BiosignalSample(value: 40, date: now.addingTimeInterval(-3600)))
        return samples
    }

    private func rhrForZScore() -> [BiosignalSample] {
        var samples = (1 ... 10).map { i in
            BiosignalSample(value: 60, date: now.addingTimeInterval(-24 * 3600 * Double(i)))
        }
        samples.append(BiosignalSample(value: 62, date: now.addingTimeInterval(-3600)))
        return samples
    }

    func testWritesAFoodCorrelationAndOverwritesOnEdit() async {
        let manager = makeManager()
        _ = await manager.connect()
        XCTAssertTrue(fake.lastShare.contains(HKQuantityType(.dietaryEnergyConsumed)))
        if let food = HKObjectType.correlationType(forIdentifier: .food) {
            XCTAssertFalse(fake.lastShare.contains(food))
        }
        let loggedAt = iso(now)
        let meal = MealSummary.sample(id: "m1", kcal: 520, protein: 32, source: "TEXT", summary: "Oats", loggedAt: loggedAt)
        await manager.writeMeal(meal)
        XCTAssertEqual(fake.foods["m1"]?.kcal, 520)
        XCTAssertEqual(fake.foodVersions["m1"], 1)

        let edited = MealSummary.sample(id: "m1", kcal: 610, protein: 35, source: "TEXT", summary: "Oats", loggedAt: loggedAt)
        await manager.writeMeal(edited)
        XCTAssertEqual(fake.foods["m1"]?.kcal, 610)
        XCTAssertEqual(fake.foodVersions["m1"], 2)
        XCTAssertEqual(manager.todayWrittenKcal, 610)
    }

    func testDeleteRemovesTheWrittenMeal() async {
        let manager = makeManager()
        _ = await manager.connect()
        await manager.writeMeal(MealSummary.sample(id: "m2", kcal: 400, protein: 20, source: "TEXT", summary: "Toast", loggedAt: iso(now)))
        await manager.deleteMealFromHealth(id: "m2")
        XCTAssertNil(fake.foods["m2"])
        XCTAssertEqual(manager.todayWrittenKcal, 0)
    }

    func testWriteIsSkippedWhenNutritionTogglesAreOff() async {
        let manager = makeManager()
        _ = await manager.connect()
        manager.writePreferences = HealthWritePreferences(energy: false, protein: false, carbs: false, fat: false, bodyMass: false)
        await manager.writeMeal(MealSummary.sample(id: "m3", kcal: 400, protein: 20, source: "TEXT", summary: "Toast", loggedAt: iso(now)))
        XCTAssertTrue(fake.foods.isEmpty)
    }

    private func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

private struct CapturedRequest {
    let path: String
    let method: String
    let json: [String: Any]

    init(_ request: URLRequest) {
        path = request.url?.path ?? ""
        method = request.httpMethod ?? ""
        json = HealthKitTestsJSON.json(from: request)
    }
}

private enum HealthKitTestsJSON {
    static func json(from request: URLRequest) -> [String: Any] {
        let data = body(from: request)
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    static func body(from request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1_024)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: 1_024)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

final class FakeHealthDataSource: HealthDataSource, @unchecked Sendable {
    var available = true
    var authStatus: HKAuthorizationRequestStatus = .shouldRequest
    var authorizationError: Error?
    var samplesError: Error?
    var anchoredError: Error?
    var samplesByType: [String: [BiosignalSample]] = [:]
    var birthDate: Date?
    var sex: HKBiologicalSex = .notSet
    private var nextWeightId = 0
    private var weights: [(id: Int, sample: BiosignalSample)] = []

    func addSamples(_ samples: [BiosignalSample], for type: HKQuantityTypeIdentifier) {
        let id = HKQuantityType(type).identifier
        samplesByType[id, default: []].append(contentsOf: samples)
    }

    func addWeight(_ value: Double, at date: Date) {
        nextWeightId += 1
        weights.append((nextWeightId, BiosignalSample(value: value, date: date)))
    }

    var isAvailable: Bool { available }

    func requestAuthorization(toShare: Set<HKSampleType>, read: Set<HKObjectType>) async throws {
        if let authorizationError { throw authorizationError }
        authStatus = .unnecessary
        lastShare = toShare
        lastRead = read
    }

    func requestStatus(toShare: Set<HKSampleType>, read: Set<HKObjectType>) async -> HKAuthorizationRequestStatus {
        authStatus
    }

    var lastShare: Set<HKSampleType> = []
    var lastRead: Set<HKObjectType> = []
    var foods: [String: DietaryWrite] = [:]
    var foodVersions: [String: Int] = [:]
    var bodyMassWrites: [(kg: Double, date: Date, id: String)] = []

    func saveFood(_ write: DietaryWrite, types: HealthWritePreferences) async throws {
        guard types.writesNutrition else { return }
        foodVersions[write.mealId, default: 0] += 1
        foods[write.mealId] = write
    }

    func deleteFood(mealId: String) async throws {
        foods.removeValue(forKey: mealId)
        foodVersions.removeValue(forKey: mealId)
    }

    func saveBodyMass(kg: Double, at date: Date, mealId: String) async throws {
        bodyMassWrites.append((kg, date, mealId))
    }

    func samples(type: HKQuantityType, unit: HKUnit, from: Date, to: Date) async throws -> [BiosignalSample] {
        if let samplesError { throw samplesError }
        return (samplesByType[type.identifier] ?? [])
            .filter { $0.date >= from && $0.date <= to }
            .sorted { $0.date < $1.date }
    }

    func latestSample(type: HKQuantityType, unit: HKUnit) async throws -> BiosignalSample? {
        if let samplesError { throw samplesError }
        return (samplesByType[type.identifier] ?? []).max { $0.date < $1.date }
    }

    func dateOfBirth() throws -> Date? { birthDate }
    func biologicalSex() throws -> HKBiologicalSex { sex }

    func enableBackgroundDelivery(type: HKQuantityType, frequency: HKUpdateFrequency) async throws {}

    func startObserver(type: HKQuantityType, handler: @escaping HealthObserverHandler) {}

    func anchoredSamples(
        type: HKQuantityType,
        unit: HKUnit,
        anchor: Data?,
        since: Date?
    ) async throws -> (samples: [BiosignalSample], newAnchor: Data) {
        if let anchoredError { throw anchoredError }
        let afterId = anchor.flatMap { Int(String(data: $0, encoding: .utf8) ?? "") } ?? 0
        var result = weights.filter { $0.id > afterId }.map(\.sample)
        if let since {
            result = result.filter { $0.date >= since }
        }
        let newId = weights.last?.id ?? afterId
        return (result, Data("\(newId)".utf8))
    }

    var workouts: [HealthWorkoutSample] = []

    func workouts(from: Date, to: Date) async throws -> [HealthWorkoutSample] {
        workouts.filter { $0.start >= from && $0.start <= to }
    }

    func enableBackgroundDelivery(sampleType: HKSampleType, frequency: HKUpdateFrequency) async throws {}

    func startObserver(sampleType: HKSampleType, handler: @escaping HealthObserverHandler) {}
}
