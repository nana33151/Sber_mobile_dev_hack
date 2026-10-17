import Foundation
import PrankLinker

/// Приколы из папки `Pranks/` в сборке + переключатель «сломать загрузку игры»,
/// чтобы на демо показать цепочку: тряска → игра не загрузилась → нативная анимация.
final class DemoContentProvider: PrankContentProvider, @unchecked Sendable {

    struct SimulatedLoadFailure: LocalizedError {
        var errorDescription: String? { "Имитация: игра не загрузилась (нет сети)" }
    }

    private let base: DirectoryContentProvider
    /// Общая папка `web/` из репозитория, лежит в сборке целиком.
    private let webRoot = Bundle.main.url(forResource: "web", withExtension: nil)
    /// Игра с котиками из `web/` (main): исходники как есть, статика — из `web/assets` (как Vite publicDir).
    private let gameEntries = ["cats_yarn": "src/index.html"]
    private let lock = NSLock()
    private var _failsLoading = false

    init(root: URL) {
        base = DirectoryContentProvider(root: root)
    }

    var failsLoading: Bool {
        get { lock.withLock { _failsLoading } }
        set { lock.withLock { _failsLoading = newValue } }
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
        if let entry = gameEntries[payloadID], let webRoot {
            return PrankContent(payload: content.payload, source: .directory(webRoot), entry: entry, publicDirectory: "assets")
        }
        return content
    }
}
