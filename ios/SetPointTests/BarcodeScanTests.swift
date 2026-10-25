import XCTest
@testable import SetPoint

/// Scan, confirm and log all happen on the scanner: a hit shows the product card
/// there, a miss offers the label photo or typing, and "Save as my meal" opens
/// its editor over the scanner.
@MainActor
final class BarcodeScanTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private func makeVM() -> LogMealViewModel {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let api = APIClient(
            baseURL: URL(string: "https://api.test")!,
            session: URLSession(configuration: config),
            tokenProvider: { "token" }
        )
        return LogMealViewModel(api: api)
    }

    private static let yogurt = Data("""
    {"food":{"code":"7290000000001","name":"Greek yogurt","brand":"Tara","servingG":150,
    "kcal100g":97,"proteinG100g":9,"carbsG100g":4,"fatG100g":5,"fetchedAt":"2026-10-25T00:00:00.000Z"}}
    """.utf8)

    func testUnknownCodeKeepsScannerOpenWithAWayForward() async {
        StubURLProtocol.handler = { _ in (404, ["Content-Type": "application/json"], Data("{}".utf8)) }
        let vm = makeVM()
        vm.openScanner()

        await vm.handleScannedCode("0000000000000")

        XCTAssertTrue(vm.showScanner)
        XCTAssertEqual(vm.scanStatus, .notFound)
        XCTAssertNil(vm.product)

        vm.rescan()
        XCTAssertEqual(vm.scanStatus, .scanning)
    }

    func testFoundProductIsShownOnTheScanner() async {
        StubURLProtocol.handler = { _ in (200, ["Content-Type": "application/json"], Self.yogurt) }
        let vm = makeVM()
        vm.openScanner()

        await vm.handleScannedCode("7290000000001")

        XCTAssertTrue(vm.showScanner)
        XCTAssertEqual(vm.scanStatus, .found)
        XCTAssertEqual(vm.product?.food.name, "Greek yogurt")

        vm.rescan()
        XCTAssertNil(vm.product)
        XCTAssertEqual(vm.scanStatus, .scanning)
    }

    func testSaveOpensTheEditorRightAwayOverTheScanner() async {
        StubURLProtocol.handler = { _ in (200, ["Content-Type": "application/json"], Self.yogurt) }
        let vm = makeVM()
        vm.openScanner()
        await vm.handleScannedCode("7290000000001")

        vm.saveScannedProduct()

        XCTAssertTrue(vm.showScanner, "the card stays so the product can still be logged")
        XCTAssertNotNil(vm.scannerEditor)
        XCTAssertNil(vm.editor, "the log panel's own editor isn't asked to present under the scanner")

        vm.rescan()
        XCTAssertFalse(vm.scannedProductSaved)
    }

    func testTypeInsteadClosesScannerIntoTyping() {
        let vm = makeVM()
        vm.openScanner()

        vm.typeInsteadOfScanning()
        vm.scannerDismissed()

        XCTAssertFalse(vm.showScanner)
        XCTAssertEqual(vm.mode, .type)
        XCTAssertNil(vm.product)
    }

    private static var labelPhoto: Data {
        UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40)).pngData { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        }
    }

    func testLabelPhotoFillsAMissAndOpensTheProduct() async {
        let requests = LockedBox<[String]>([])
        StubURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            requests.set(requests.get() + ["\(request.httpMethod ?? "") \(path)"])
            if path.hasSuffix("/label") { return (200, ["Content-Type": "application/json"], Self.yogurt) }
            return (404, ["Content-Type": "application/json"], Data("{}".utf8))
        }
        let vm = makeVM()
        vm.openScanner()
        await vm.handleScannedCode("7290000000001")
        XCTAssertEqual(vm.scanStatus, .notFound)

        await vm.readLabel(Self.labelPhoto)

        XCTAssertEqual(requests.get().last, "POST /api/foods/barcode/7290000000001/label")
        XCTAssertTrue(vm.showScanner)
        XCTAssertEqual(vm.scanStatus, .found)
        XCTAssertEqual(vm.product?.food.name, "Greek yogurt")
    }

    func testUnreadableLabelStaysOnTheScanner() async {
        StubURLProtocol.handler = { request in
            let status = (request.url?.path ?? "").hasSuffix("/label") ? 422 : 404
            return (status, ["Content-Type": "application/json"], Data("{}".utf8))
        }
        let vm = makeVM()
        vm.openScanner()
        await vm.handleScannedCode("7290000000001")

        await vm.readLabel(Self.labelPhoto)

        XCTAssertTrue(vm.showScanner)
        guard case .failed = vm.scanStatus else { return XCTFail("expected a failed status, got \(vm.scanStatus)") }
        XCTAssertNil(vm.product)
    }
}
