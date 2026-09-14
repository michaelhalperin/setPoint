import XCTest
@testable import SetPoint

final class OfflineMealQueueTests: XCTestCase {
    private func store() -> UserDefaults {
        let name = "offline-meals-\(UUID().uuidString)"
        let store = UserDefaults(suiteName: name)!
        store.removePersistentDomain(forName: name)
        return store
    }

    func testOnlyConnectionFailuresCountAsOffline() {
        XCTAssertTrue(OfflineMealQueue.isOffline(APIError.transport(URLError(.notConnectedToInternet))))
        XCTAssertTrue(OfflineMealQueue.isOffline(APIError.transport(URLError(.timedOut))))
        XCTAssertFalse(OfflineMealQueue.isOffline(APIError.http(status: 500, message: nil)))
        XCTAssertFalse(OfflineMealQueue.isOffline(APIError.http(status: 400, message: "bad")))
        XCTAssertFalse(OfflineMealQueue.isOffline(APIError.unauthorized))
        XCTAssertFalse(OfflineMealQueue.isOffline(APIError.transport(URLError(.badURL))))
    }

    func testRetryKeepsWhenTheMealWasEatenAndItsClientId() throws {
        let eaten = Date(timeIntervalSince1970: 1_789_000_000)
        let item = OfflineMealQueue.Item(id: "3F2504E0-4F89-11D3-9A0C-0305E82C3301", text: "oats", loggedAt: eaten)
        let body = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(OfflineMealQueue.request(for: item))
        ) as? [String: Any]
        XCTAssertEqual(body?["clientId"] as? String, item.id)
        XCTAssertEqual(body?["loggedAt"] as? String, ISO8601DateFormatter().string(from: eaten))
        XCTAssertEqual(body?["text"] as? String, "oats")
    }

    func testEnqueueReplacesTheSameAttempt() {
        let store = store()
        let item = OfflineMealQueue.Item(id: "a", text: "eggs", loggedAt: .now)
        OfflineMealQueue.enqueue(item, in: store)
        OfflineMealQueue.enqueue(item, in: store)
        XCTAssertEqual(OfflineMealQueue.all(in: store), [item])
        OfflineMealQueue.clear(in: store)
        XCTAssertTrue(OfflineMealQueue.all(in: store).isEmpty)
    }

    func testFlushDropsRejectedMealsAndKeepsTheRestOnServerTrouble() async {
        let store = store()
        let now = Date()
        let rejected = OfflineMealQueue.Item(id: "1", text: "first", loggedAt: now.addingTimeInterval(-300))
        let serverDown = OfflineMealQueue.Item(id: "2", text: "second", loggedAt: now.addingTimeInterval(-200))
        let waiting = OfflineMealQueue.Item(id: "3", text: "third", loggedAt: now.addingTimeInterval(-100))
        [waiting, rejected, serverDown].forEach { OfflineMealQueue.enqueue($0, in: store) }

        let calls = LockedBox(0)
        StubURLProtocol.handler = { _ in
            calls.set(calls.get() + 1)
            return (calls.get() == 1 ? 400 : 503, ["Content-Type": "application/json"], Data("{}".utf8))
        }
        defer { StubURLProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let api = APIClient(
            baseURL: URL(string: "https://api.test")!,
            session: URLSession(configuration: config),
            tokenProvider: { "token" }
        )

        let delivered = await OfflineMealQueue.flush(using: api, store: store)

        XCTAssertEqual(delivered, 0)
        XCTAssertEqual(calls.get(), 2, "stops at the first server error")
        XCTAssertEqual(Set(OfflineMealQueue.all(in: store).map(\.id)), ["2", "3"], "rejected meal dropped, the rest kept")
    }
}
