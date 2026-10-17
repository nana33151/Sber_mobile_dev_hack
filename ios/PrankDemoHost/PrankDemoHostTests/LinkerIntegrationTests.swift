import PrankLinker
import UIKit
import XCTest

/// Прогоняет настоящий линкер с настоящим WKWebView внутри демо-приложения:
/// мок-игра и все сценарии сбоев из `Pranks/`. Главное, что проверяем, — приложение
/// не падает, оверлей убирается, а приложение получает понятное событие.
/// Как в приложении: `cats_yarn` — игра из `web/src`, статика из `web/assets`.
private struct GameContentProvider: PrankContentProvider {
    let root: URL
    let web: URL

    func loadConfig() async throws -> Data {
        try await DirectoryContentProvider(root: root).loadConfig()
    }

    func loadContent(payloadID: String) async throws -> PrankContent {
        let content = try await DirectoryContentProvider(root: root).loadContent(payloadID: payloadID)
        guard payloadID == "cats_yarn" else { return content }
        return PrankContent(payload: content.payload, source: .directory(web), entry: "src/index.html", publicDirectory: "assets")
    }
}

@MainActor
final class LinkerIntegrationTests: XCTestCase {

    private final class Recorder: PrankLinkerDelegate {
        var events: [PrankLinkerEvent] = []
        func prankLinker(_ linker: PrankLinker, didEmit event: PrankLinkerEvent) {
            events.append(event)
        }
    }

    private var linker: PrankLinker!
    private var recorder: Recorder!

    override func setUp() async throws {
        let root = try XCTUnwrap(Bundle.main.url(forResource: "Pranks", withExtension: nil))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        var options = PrankLinker.Options()
        options.cooldown = 0
        options.maxConsecutiveFailures = 100
        let web = try XCTUnwrap(Bundle.main.url(forResource: "web", withExtension: nil))
        linker = PrankLinker(content: GameContentProvider(root: root, web: web), options: options, tiltSource: ManualTiltSource())
        recorder = Recorder()
        linker.delegate = recorder
        linker.attach(to: scene)
        await linker.reloadConfig()
    }

    override func tearDown() async throws {
        linker.hide()
        try await Task.sleep(nanoseconds: 400_000_000)
        linker = nil
    }

    private func waitFor(_ timeout: TimeInterval, _ predicate: (PrankLinkerEvent) -> Bool) async -> PrankLinkerEvent? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let event = recorder.events.first(where: predicate) { return event }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return nil
    }

    private func failure(of event: PrankLinkerEvent?) -> PrankError? {
        if case .failed(_, let error) = event { return error }
        return nil
    }

    func testConfigFromBundleIsLoaded() {
        XCTAssertEqual(linker.config?.trigger, .init(on: .shake, payloadID: "cats_yarn"))
    }

    func testShakeShowsMockGameAndHideReportsManual() async {
        linker.handleShakeMotion(.motionShake)
        let shown = await waitFor(3) { if case .shown("cats_yarn") = $0 { true } else { false } }
        XCTAssertNotNil(shown, "\(recorder.events)")
        XCTAssertTrue(linker.isShowing)
        XCTAssertTrue(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).contains { String(describing: type(of: $0)) == "PrankOverlayWindow" && !$0.isHidden })

        linker.hide()
        let hidden = await waitFor(1) { if case .hidden(_, .manual) = $0 { true } else { false } }
        XCTAssertNotNil(hidden)
        XCTAssertFalse(linker.isShowing)
    }

    func testForbiddenScreenSkipsAndClosesPrank() async {
        linker.show(payloadID: "cats_yarn")
        _ = await waitFor(3) { if case .shown = $0 { true } else { false } }
        linker.screenAllowsPranks = false
        let found1 = await waitFor(1) { if case .hidden = $0 { true } else { false } }
        XCTAssertNotNil(found1)

        linker.handleShakeMotion(.motionShake)
        let found2 = await waitFor(1) { $0 == .skipped(.forbiddenScreen) }
        XCTAssertNotNil(found2)
        linker.screenAllowsPranks = true
    }

    func testExceptionInShowFailsGracefully() async {
        linker.show(payloadID: "crash_throw")
        let error = failure(of: await waitFor(3) { if case .failed = $0 { true } else { false } })
        XCTAssertEqual(error?.code, "INTERNAL")
        XCTAssertFalse(linker.isShowing)
    }

    func testShowThatNeverResolvesTimesOut() async {
        linker.show(payloadID: "crash_slow")
        let error = failure(of: await waitFor(4) { if case .failed = $0 { true } else { false } })
        XCTAssertEqual(error, .timeout)
        XCTAssertFalse(linker.isShowing)
    }

    func testHungPageIsClosedByWatchdog() async {
        linker.show(payloadID: "crash_hang")
        let found3 = await waitFor(3) { if case .shown = $0 { true } else { false } }
        XCTAssertNotNil(found3)
        let error = failure(of: await waitFor(8) { if case .failed = $0 { true } else { false } })
        XCTAssertEqual(error, .hung)
        XCTAssertFalse(linker.isShowing)
    }

    func testInvalidPayloadIsRejected() async {
        linker.show(payloadID: "crash_invalid")
        let error = failure(of: await waitFor(2) { if case .failed = $0 { true } else { false } })
        XCTAssertEqual(error?.code, "INVALID_PAYLOAD")
    }

    func testRuntimeErrorIsReportedButPrankKeepsRunning() async {
        linker.show(payloadID: "crash_error")
        let found4 = await waitFor(3) { if case .pageError = $0 { true } else { false } }
        XCTAssertNotNil(found4)
        XCTAssertTrue(linker.isShowing)
    }

    func testEscapeAttemptsAreBlocked() async throws {
        linker.show(payloadID: "crash_escape")
        let found5 = await waitFor(3) { if case .shown = $0 { true } else { false } }
        XCTAssertNotNil(found5)
        try await Task.sleep(nanoseconds: 1_500_000_000)
        XCTAssertTrue(linker.isShowing, "\(recorder.events)")
        XCTAssertFalse(recorder.events.contains { if case .failed = $0 { true } else { false } })
    }

    func testUnknownPayloadFails() async {
        linker.show(payloadID: "no_such_prank")
        let error = failure(of: await waitFor(2) { if case .failed = $0 { true } else { false } })
        XCTAssertNotNil(error)
    }

    func testLaunchFailurePlaysFallbackAnimationForItsDuration() async throws {
        let atlas = try XCTUnwrap(Bundle.main.url(forResource: "atlas", withExtension: "json", subdirectory: "web/assets"))
        var animation = try XCTUnwrap(PrankFallbackAnimation.atlas(at: atlas))
        XCTAssertEqual(animation.frames.count, 4, "4 кадра танца из web/assets/atlas.json")
        animation.totalDuration = 2
        linker.options.launchFailureAnimation = animation

        let started = Date()
        linker.show(payloadID: "no_such_prank")
        let shown = await waitFor(2) { if case .fallbackShown = $0 { true } else { false } }
        XCTAssertNotNil(shown, "\(recorder.events)")
        XCTAssertTrue(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).contains { String(describing: type(of: $0)) == "PrankOverlayWindow" && !$0.isHidden })

        let finished = await waitFor(4) { if case .fallbackFinished = $0 { true } else { false } }
        XCTAssertNotNil(finished)
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertGreaterThan(elapsed, 1.9)
        XCTAssertLessThan(elapsed, 3.5)
    }

    func testFallbackNotPlayedWhenFailureHappensAfterShow() async {
        let atlas = Bundle.main.url(forResource: "atlas", withExtension: "json", subdirectory: "web/assets")!
        linker.options.launchFailureAnimation = PrankFallbackAnimation.atlas(at: atlas)
        linker.show(payloadID: "crash_hang")
        let failed = await waitFor(8) { if case .failed = $0 { true } else { false } }
        XCTAssertNotNil(failed)
        XCTAssertFalse(recorder.events.contains { if case .fallbackShown = $0 { true } else { false } })
    }

    func testSecondTriggerWhileShowingIsSkipped() async {
        linker.show(payloadID: "cats_yarn")
        linker.show(payloadID: "cats_yarn")
        let found6 = await waitFor(1) { $0 == .skipped(.busy) }
        XCTAssertNotNil(found6)
    }
}
