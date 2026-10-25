import XCTest
@testable import SetPoint

/// The photo screen's X: closing while it reads drops whatever it logs; closing a
/// read result removes the logged meal.
@MainActor
final class PhotoLogCloseTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private func makeVM() -> LogMealViewModel {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let api = APIClient(baseURL: URL(string: "https://api.test")!, session: URLSession(configuration: config), tokenProvider: { "token" })
        return LogMealViewModel(api: api)
    }

    private static let photo: Data = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40)).pngData { ctx in
        UIColor.orange.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
    }

    private static let logged = Data("""
    {"meal":{"id":"m_photo","kcal":640,"proteinG":41,"source":"PHOTO"},"parsed":null,"resolvedCheckInId":null}
    """.utf8)

    private func stub(postDelay: TimeInterval = 0, requests: LockedBox<[String]>) {
        StubURLProtocol.handler = { request in
            let line = "\(request.httpMethod ?? "") \(request.url?.path ?? "")"
            requests.set(requests.get() + [line])
            if request.httpMethod == "POST" {
                if postDelay > 0 { Thread.sleep(forTimeInterval: postDelay) }
                return (200, ["Content-Type": "application/json"], Self.logged)
            }
            return (200, ["Content-Type": "application/json"], Data("{\"deleted\":true}".utf8))
        }
    }

    func testClosingWhileReadingDropsTheMealItStillLogs() async throws {
        let requests = LockedBox<[String]>([])
        stub(postDelay: 0.4, requests: requests)
        let vm = makeVM()
        vm.attach(Self.photo)

        let submit = Task { await vm.submit() }
        while vm.phase != .parsing { await Task.yield() }
        XCTAssertTrue(vm.confirmingPhoto)

        vm.cancelPhotoLog()
        XCTAssertFalse(vm.confirmingPhoto)
        XCTAssertEqual(vm.phase, .compose)

        await submit.value
        XCTAssertEqual(requests.get().last, "DELETE /api/meals/m_photo")
        XCTAssertEqual(vm.phase, .compose, "a cancelled read never shows up as logged")
    }

    func testClosingAReadResultRemovesTheMeal() async {
        let requests = LockedBox<[String]>([])
        stub(requests: requests)
        let vm = makeVM()
        vm.attach(Self.photo)
        await vm.submit()
        guard case .logged = vm.phase else { return XCTFail("expected the photo to be logged") }

        await vm.discardPhotoLog()

        XCTAssertEqual(requests.get().last, "DELETE /api/meals/m_photo")
        XCTAssertEqual(vm.phase, .compose)
        XCTAssertFalse(vm.confirmingPhoto)
        XCTAssertNil(vm.photo, "a discarded photo doesn't come back into the composer")
    }
}
