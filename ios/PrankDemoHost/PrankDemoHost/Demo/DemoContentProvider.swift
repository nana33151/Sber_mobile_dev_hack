import Foundation
import PrankLinker

/// Приколы из папки `Pranks/` в сборке + переключатели для демо:
/// нативная игра или WebView, и «сломать загрузку игры» (тряска → сбой → котик-заглушка).
final class DemoContentProvider: PrankContentProvider, @unchecked Sendable {

    struct SimulatedLoadFailure: LocalizedError {
        var errorDescription: String? { "Имитация: игра не загрузилась (нет сети)" }
    }

    /// CDN с ассетами из `main`. Поменяли картинку или атлас в репозитории — приложение
    /// подхватит их без пересборки (сначала в фоне докачает и атомарно заменит кеш).
    static let testCDN = URL(string: "https://cdn.statically.io/gh/nana33151/Sber_mobile_dev_hack@main/web/assets/")!

    /// Кеш ассетов нативной игры; запасной вариант — `web/assets` внутри сборки.
    let assetCache: PrankAssetCache
    /// Откуда взялись ассеты последнего показа — для лога демо.
    var onAssetsResolved: (@Sendable (PrankAssetCache.Origin) -> Void)?

    private let base: DirectoryContentProvider
    /// Игра из `web/` (только `src` и `assets`, кладутся в сборку скриптом).
    private let webRoot = Bundle.main.url(forResource: "web", withExtension: nil)
    private let gameIDs: Set<String> = ["cats_yarn"]
    private let lock = NSLock()
    private var _failsLoading = false
    private var _usesNativeGame = true

    init(root: URL) {
        base = DirectoryContentProvider(root: root)
        let bundledAssets = Bundle.main.bundleURL.appendingPathComponent("web/assets", isDirectory: true)
        assetCache = PrankAssetCache(remoteBase: Self.testCDN, bundledDirectory: bundledAssets)
    }

    var failsLoading: Bool {
        get { lock.withLock { _failsLoading } }
        set { lock.withLock { _failsLoading = newValue } }
    }

    /// Нативная игра на Swift (по умолчанию) или JS-игра в WebView.
    var usesNativeGame: Bool {
        get { lock.withLock { _usesNativeGame } }
        set { lock.withLock { _usesNativeGame = newValue } }
    }

    func loadConfig() async throws -> Data {
        try await base.loadConfig()
    }

    func loadContent(payloadID: String) async throws -> PrankContent {
        if failsLoading {
            // Похоже на настоящую сеть: немного ждём и падаем.
            try await Task.sleep(nanoseconds: 400_000_000)
            throw SimulatedLoadFailure()
        }
        let content = try await base.loadContent(payloadID: payloadID)
        guard gameIDs.contains(payloadID) else { return content }

        if usesNativeGame {
            let resolved = await assetCache.resolve()
            onAssetsResolved?(resolved.origin)
            return PrankContent(payload: content.payload, source: .native(atlas: resolved.atlasURL))
        }
        guard let webRoot else { return content }
        return PrankContent(payload: content.payload, source: .directory(webRoot), entry: "src/index.html", publicDirectory: "assets")
    }
}
