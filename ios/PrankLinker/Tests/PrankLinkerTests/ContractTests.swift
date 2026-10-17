import XCTest
@testable import PrankLinker

final class PrankConfigTests: XCTestCase {

    func testDecodesExampleConfig() throws {
        let json = #"{"version":"1","enabled":true,"trigger":{"on":"shake","payload_id":"cats_yarn","delay_ms":0}}"#
        let config = try PrankConfig.decode(Data(json.utf8))
        XCTAssertEqual(config, PrankConfig(enabled: true, trigger: .init(on: .shake, payloadID: "cats_yarn", delayMs: 0)))
    }

    func testEnabledDefaultsToTrue() throws {
        XCTAssertTrue(try PrankConfig.decode(Data(#"{"version":"1"}"#.utf8)).enabled)
    }

    func testRejectsBrokenConfigsWithoutCrashing() {
        let broken = [
            "",
            "null",
            "[]",
            #"{"enabled":true}"#,
            #"{"version":"2"}"#,
            #"{"version":"1","extra":1}"#,
            #"{"version":"1","enabled":1}"#,
            #"{"version":"1","trigger":{"on":"swipe","payload_id":"a"}}"#,
            #"{"version":"1","trigger":{"on":"shake"}}"#,
            #"{"version":"1","trigger":{"on":"delay","payload_id":"a","delay_ms":60001}}"#,
            #"{"version":"1","trigger":{"on":"delay","payload_id":"a","delay_ms":1.5}}"#
        ]
        for json in broken {
            XCTAssertThrowsError(try PrankConfig.decode(Data(json.utf8)), json)
        }
    }
}

final class PrankPayloadTests: XCTestCase {

    func testDecodesPayloadWithAssets() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let json = """
        {"version":"1","id":"cats_yarn","html":"<html></html>","assets":{"cat":"\(png.base64EncodedString())"},
         "duration_ms":30000,"dismissible":true,"background":"transparent"}
        """
        let payload = try PrankPayload.decode(Data(json.utf8))
        XCTAssertEqual(payload.id, "cats_yarn")
        XCTAssertEqual(payload.assets["cat"], png)
        XCTAssertEqual(payload.durationMs, 30000)
        XCTAssertEqual(payload.background, .transparent)
    }

    func testDefaultsMatchSchema() throws {
        let payload = try PrankPayload.decode(Data(#"{"version":"1","id":"a","html":""}"#.utf8))
        XCTAssertEqual(payload.durationMs, 5000)
        XCTAssertTrue(payload.dismissible)
        XCTAssertEqual(payload.background, .opaque)
    }

    func testRejectsInvalidPayloads() {
        let broken = [
            #"{"version":"1","id":"Bad","html":""}"#,
            #"{"version":"1","id":"_a","html":""}"#,
            #"{"version":"1","id":"a"}"#,
            #"{"version":"1","id":"a","html":"","duration_ms":100}"#,
            #"{"version":"1","id":"a","html":"","background":"blur"}"#,
            #"{"version":"1","id":"a","html":"","assets":{"x":"data:image/png;base64,AAAA"}}"#,
            #"{"version":"1","id":"a","html":"","assets":{"../x":"AAAA"}}"#,
            #"{"version":"1","id":"a","html":"","script":"x"}"#
        ]
        for json in broken {
            XCTAssertThrowsError(try PrankPayload.decode(Data(json.utf8)), json)
        }
    }

    func testIDPattern() {
        XCTAssertTrue(PrankPayload.isValidID("cats_yarn-2"))
        XCTAssertTrue(PrankPayload.isValidID(String(repeating: "a", count: 64)))
        XCTAssertFalse(PrankPayload.isValidID(String(repeating: "a", count: 65)))
        XCTAssertFalse(PrankPayload.isValidID(""))
        XCTAssertFalse(PrankPayload.isValidID("кот"))
    }
}

final class PageMessageTests: XCTestCase {

    func testParsesBridgeEvents() {
        XCTAssertEqual(try PageMessage.parse(["event": "action", "payload_id": "a", "action": "pet"]).get(),
                       .action(payloadID: "a", action: "pet"))
        XCTAssertEqual(try PageMessage.parse(["event": "error", "code": "INTERNAL", "message": "x"]).get(),
                       .error(code: "INTERNAL", message: "x"))
        XCTAssertEqual(try PageMessage.parse(["event": "hidden"]).get(), .hidden(payloadID: nil))
    }

    func testParsesHackathonChannelInAllShapes() {
        XCTAssertEqual(try PageMessage.parse(["type": "CLOSE_EVENT"]).get(), .close)
        XCTAssertEqual(try PageMessage.parse(#"{"type":"COMPLETED_EVENT"}"#).get(), .completed)
        XCTAssertEqual(try PageMessage.parse(["type": "SHARING_EVENT", "params": ["text": "Котики!"]]).get(),
                       .sharing(text: "Котики!", image: nil))
        XCTAssertEqual(try PageMessage.parse(["data": ["type": "VIBRATION_EVENT"]]).get(), .vibration)
    }

    func testParsesGameMessageWithDataObject() {
        // Формат игры из web/src/prank.js: JSON-строка `{ event, data }`.
        let body = #"{"event":"action","data":{"action":"cat_caught","catId":"cat-1"}}"#
        XCTAssertEqual(try PageMessage.parse(body).get(), .action(payloadID: nil, action: "cat_caught"))
    }

    func testReportsInvalidMessages() {
        XCTAssertEqual(PageMessage.parse(42), .failure(.notAnObject))
        XCTAssertEqual(PageMessage.parse(["type": "PAY_EVENT"]), .failure(.unknown("PAY_EVENT")))
        XCTAssertEqual(PageMessage.parse(["type": "SHARING_EVENT"]), .failure(.missingField("text|image")))
        XCTAssertEqual(PageMessage.parse(["event": "action"]), .failure(.missingField("action")))
        XCTAssertEqual(PageMessage.parse([String: Any]()), .failure(.missingField("type")))
    }
}

final class SchemeHandlerTests: XCTestCase {

    func testInjectsCSSAndJS() {
        let payload = PrankPayload(id: "a", html: "<html><head></head><body><p>x</p></body></html>", css: "p{}", js: "go()")
        let page = PrankSchemeHandler.page(for: payload)
        XCTAssertEqual(page, "<html><head><style>p{}</style></head><body><p>x</p><script>go()</script></body></html>")
    }

    func testInjectsIntoFragmentWithoutTags() {
        let page = PrankSchemeHandler.page(for: PrankPayload(id: "a", html: "<p>x</p>", css: "p{}", js: "go()"))
        XCTAssertEqual(page, "<style>p{}</style><p>x</p><script>go()</script>")
    }

    func testPublicDirectoryFallbackLikeVite() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("src"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("assets"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: root.appendingPathComponent("assets/atlas.json"))
        defer { try? FileManager.default.removeItem(at: root) }

        let content = PrankContent(
            payload: PrankPayload(id: "game", html: ""),
            source: .directory(root),
            entry: "src/index.html",
            publicDirectory: "assets"
        )
        XCTAssertEqual(content.entry, "src/index.html")
        XCTAssertEqual(content.publicDirectory, "assets")
        XCTAssertEqual(PrankContent(payload: content.payload, entry: "../x.html").entry, "index.html")
        XCTAssertNil(PrankContent(payload: content.payload, publicDirectory: "../etc").publicDirectory)
    }

    func testSniffsMimeTypeOfExtensionlessAssets() {
        XCTAssertEqual(PrankSchemeHandler.mimeType(forPath: "cat", data: Data([0x89, 0x50, 0x4E, 0x47])), "image/png")
        XCTAssertEqual(PrankSchemeHandler.mimeType(forPath: "atlas.json", data: Data()), "application/json")
        XCTAssertEqual(PrankSchemeHandler.mimeType(forPath: "blob", data: Data([1, 2])), "application/octet-stream")
    }
}

final class SafetyTests: XCTestCase {

    func testCircuitBreakerOpensAfterConsecutiveFailures() {
        var breaker = CircuitBreaker(maxConsecutiveFailures: 3)
        breaker.recordFailure()
        breaker.recordFailure()
        breaker.recordSuccess()
        breaker.recordFailure()
        breaker.recordFailure()
        XCTAssertFalse(breaker.isOpen)
        breaker.recordFailure()
        XCTAssertTrue(breaker.isOpen)
    }

    func testCooldown() {
        var cooldown = Cooldown(interval: 2)
        let start = Date()
        XCTAssertFalse(cooldown.isActive(now: start))
        cooldown.start(now: start)
        XCTAssertTrue(cooldown.isActive(now: start.addingTimeInterval(1.9)))
        XCTAssertFalse(cooldown.isActive(now: start.addingTimeInterval(2.1)))
    }

    func testTiltIsClamped() {
        XCTAssertEqual(PrankTilt(x: 3, y: -3), PrankTilt(x: 1, y: -1))
    }
}

final class DirectoryContentProviderTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("game"), withIntermediateDirectories: true)
        try Data(#"{"version":"1","id":"inline","html":"<p>hi</p>"}"#.utf8).write(to: root.appendingPathComponent("inline.json"))
        try Data(#"{"version":"1","id":"game","duration_ms":60000,"background":"transparent"}"#.utf8)
            .write(to: root.appendingPathComponent("game/payload.json"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testLoadsInlineAndDirectoryContent() async throws {
        let provider = DirectoryContentProvider(root: root)
        let inline = try await provider.loadContent(payloadID: "inline")
        XCTAssertEqual(inline.source, .inline)
        XCTAssertEqual(inline.payload.html, "<p>hi</p>")

        let game = try await provider.loadContent(payloadID: "game")
        XCTAssertEqual(game.source, .directory(root.appendingPathComponent("game", isDirectory: true)))
        XCTAssertEqual(game.payload.durationMs, 60000)
    }

    func testRejectsPathTraversal() async {
        let provider = DirectoryContentProvider(root: root)
        do {
            _ = try await provider.loadContent(payloadID: "../etc")
            XCTFail("должно было упасть")
        } catch {}
    }

    func testFallbackUsedWhenPrimaryConfigIsBroken() async throws {
        struct Broken: PrankContentProvider {
            func loadConfig() async throws -> Data { Data("{".utf8) }
            func loadContent(payloadID: String) async throws -> PrankContent { throw URLError(.notConnectedToInternet) }
        }
        try Data(#"{"version":"1","trigger":{"on":"shake","payload_id":"inline"}}"#.utf8).write(to: root.appendingPathComponent("config.json"))
        let provider = FallbackContentProvider(primary: Broken(), fallback: DirectoryContentProvider(root: root))
        let config = try PrankConfig.decode(try await provider.loadConfig())
        XCTAssertEqual(config.trigger?.payloadID, "inline")
        let content = try await provider.loadContent(payloadID: "inline")
        XCTAssertEqual(content.payload.id, "inline")
    }
}
