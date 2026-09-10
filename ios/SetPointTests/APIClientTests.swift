import XCTest
@testable import SetPoint

/// Session renewal (M-fix): the backend returns a fresh token in
/// `x-session-token` once the current one is a week old; the client hands it on.
final class APIClientTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private func client(onRefresh: @escaping @Sendable (String) -> Void) -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return APIClient(
            baseURL: URL(string: "https://api.test")!,
            session: URLSession(configuration: config),
            tokenProvider: { "old-token" },
            onTokenRefresh: onRefresh
        )
    }

    func testRenewedSessionTokenIsHandedOn() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer old-token")
            return (200, ["x-session-token": "fresh-token", "Content-Type": "application/json"], Data("{}".utf8))
        }
        let received = LockedBox<String?>(nil)
        try await client { received.set($0) }.post("/api/ping")
        XCTAssertEqual(received.get(), "fresh-token")
    }

    func testNoRenewalWithoutTheHeader() async throws {
        StubURLProtocol.handler = { _ in (200, ["Content-Type": "application/json"], Data("{}".utf8)) }
        let received = LockedBox<String?>(nil)
        try await client { received.set($0) }.post("/api/ping")
        XCTAssertNil(received.get())
    }

    func testFailedResponsesNeverRenew() async {
        StubURLProtocol.handler = { _ in (500, ["x-session-token": "fresh-token"], Data("{}".utf8)) }
        let received = LockedBox<String?>(nil)
        do {
            try await client { received.set($0) }.post("/api/ping")
            XCTFail("expected an HTTP error")
        } catch {}
        XCTAssertNil(received.get())
    }
}

final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, [String: String], Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, headers, data) = handler(request)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) { self.value = value }

    func set(_ newValue: Value) { lock.withLock { value = newValue } }
    func get() -> Value { lock.withLock { value } }
}
