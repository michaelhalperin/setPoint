import XCTest
@testable import SetPoint

/// Sign-out must detach this device from the old account — with the old
/// session's token, since the stored one is cleared first — and a rejected
/// request must not trigger another sign-out.
final class SignOutTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    @MainActor
    func testUnregisterDeletesBothTokensWithTheOldSession() async {
        let requests = LockedBox<[(String, String, String?)]>([])
        StubURLProtocol.handler = { request in
            requests.set(requests.get() + [(
                request.httpMethod ?? "",
                request.url?.path ?? "",
                request.value(forHTTPHeaderField: "Authorization")
            )])
            return (401, [:], Data())
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)

        let push = PushManager()
        push.setDeviceToken(Data([0xAB, 0xCD]))
        push.setLiveActivityStartToken("ff00")

        await push.unregister(sessionToken: "old-session", baseURL: URL(string: "https://api.test")!, session: session)

        let sent = requests.get()
        XCTAssertEqual(sent.map(\.0), ["DELETE", "DELETE"])
        XCTAssertEqual(Set(sent.map(\.1)), ["/api/push-tokens/abcd", "/api/push-tokens/ff00"])
        XCTAssertEqual(Set(sent.compactMap(\.2)), ["Bearer old-session"])

        // Already detached — nothing more to send.
        await push.unregister(sessionToken: "old-session", baseURL: URL(string: "https://api.test")!, session: session)
        XCTAssertEqual(requests.get().count, 2)
    }
}
