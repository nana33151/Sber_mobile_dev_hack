import UIKit
import XCTest
@testable import PrankLinker

/// Кеш ассетов: «CDN» — папка на диске (URLSession умеет file://), сборка — другая папка.
final class AssetCacheTests: XCTestCase {

    private var root: URL!
    private var cdn: URL!
    private var bundled: URL!
    private var cacheDir: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        cdn = root.appendingPathComponent("cdn", isDirectory: true)
        bundled = root.appendingPathComponent("bundle", isDirectory: true)
        cacheDir = root.appendingPathComponent("cache", isDirectory: true)
        try writePack(to: cdn)
        try writePack(to: bundled)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// Минимальный атлас в формате web/assets/atlas.json и три картинки 40×20.
    private func writePack(to folder: URL, skip: String? = nil) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let atlas = """
        {"catStates":{"image":"cats.png","frames":{"ready":{"x":0,"y":0,"width":10,"height":20},
         "oneBall":{"x":10,"y":0,"width":10,"height":20},"twoBalls":{"x":20,"y":0,"width":10,"height":20}}},
         "catDance":{"image":"dance.png","durationMs":1600,"frames":[{"x":0,"y":0,"width":20,"height":20},{"x":20,"y":0,"width":20,"height":20}]},
         "yarnVariants":{"image":"yarn.png","frames":[{"x":0,"y":0,"width":20,"height":20}]}}
        """
        try Data(atlas.utf8).write(to: folder.appendingPathComponent("atlas.json"))
        let png = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 20)).pngData { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        }
        for name in ["cats.png", "dance.png", "yarn.png"] where name != skip {
            try png.write(to: folder.appendingPathComponent(name))
        }
    }

    private func makeCache(remote: URL?) -> PrankAssetCache {
        PrankAssetCache(remoteBase: remote, bundledDirectory: bundled, directory: cacheDir, showWait: 5)
    }

    func testAtlasLoadsFramesFromSharedFormat() throws {
        let atlas = try XCTUnwrap(PrankAtlas.load(atlasURL: cdn.appendingPathComponent("atlas.json")))
        XCTAssertEqual(atlas.catStates.count, 3)
        XCTAssertEqual(atlas.danceFrames.count, 2)
        XCTAssertEqual(atlas.yarns.count, 1)
        XCTAssertEqual(atlas.catStates[.oneBall]?.width, 10)
        XCTAssertEqual(PrankAtlas.imageNames(in: try Data(contentsOf: cdn.appendingPathComponent("atlas.json"))),
                       ["cats.png", "dance.png", "yarn.png"])
    }

    func testFirstShowFromNetworkThenFromCache() async {
        let cache = makeCache(remote: cdn)
        let first = await cache.resolve()
        XCTAssertEqual(first.origin, .network)
        XCTAssertNotNil(PrankAtlas.load(atlasURL: first.atlasURL))
        let hasPack = await cache.hasCachedPack
        XCTAssertTrue(hasPack)

        let second = await cache.resolve()
        XCTAssertEqual(second.origin, .cache)
    }

    func testOfflineFallsBackToBundle() async {
        let cache = makeCache(remote: URL(fileURLWithPath: "/nonexistent-cdn/"))
        let resolved = await cache.resolve()
        XCTAssertEqual(resolved.origin, .bundle)
        XCTAssertEqual(resolved.atlasURL, bundled.appendingPathComponent("atlas.json"))
    }

    func testBrokenPackIsNotCached() async throws {
        let broken = root.appendingPathComponent("broken-cdn", isDirectory: true)
        try writePack(to: broken, skip: "yarn.png")
        let cache = makeCache(remote: broken)
        let resolved = await cache.resolve()
        XCTAssertEqual(resolved.origin, .bundle)
        let hasPack = await cache.hasCachedPack
        XCTAssertFalse(hasPack)
    }

    func testClearRemovesPack() async {
        let cache = makeCache(remote: cdn)
        let refreshed = await cache.refresh()
        XCTAssertTrue(refreshed)
        await cache.clear()
        let hasPack = await cache.hasCachedPack
        XCTAssertFalse(hasPack)
    }

    func testWithoutRemoteUsesBundle() async {
        let cache = makeCache(remote: nil)
        let resolved = await cache.resolve()
        XCTAssertEqual(resolved.origin, .bundle)
    }
}
