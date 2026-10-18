import Foundation

/// Что показать: payload из контракта и откуда брать файлы страницы.
public struct PrankContent: Sendable, Equatable {

    public enum Source: Sendable, Equatable {
        /// Страница целиком в payload: `html`, `css`, `js`, `assets`.
        case inline
        /// Папка с игрой на диске (например, скачанная с CDN и закэшированная).
        /// Входная точка — `index.html`, ссылки между файлами относительные.
        case directory(URL)
        /// Нативная игра на Swift, без WebView. URL — `atlas.json` на диске (кеш или сборка).
        case native(atlas: URL)
    }

    public let payload: PrankPayload
    public let source: Source
    /// Стартовая страница внутри папки игры, относительный путь. Для `.inline` всегда `index.html`.
    /// Позволяет взять общую папку `web/` и открыть в ней нужную страницу, не копируя файлы.
    public let entry: String
    /// Папка статики, как `publicDir` у Vite: если файла нет рядом со стартовой страницей,
    /// он ищется здесь. Так игра из `web/` запускается из исходников, без сборки.
    public let publicDirectory: String?

    public init(payload: PrankPayload, source: Source = .inline, entry: String = "index.html", publicDirectory: String? = nil) {
        self.payload = payload
        self.source = source
        self.entry = Self.isSafeEntry(entry) ? entry : "index.html"
        self.publicDirectory = publicDirectory.flatMap { Self.isSafeEntry($0) ? $0 : nil }
    }

    /// Только относительный путь внутри папки: без `..`, без схемы и абсолютных путей.
    static func isSafeEntry(_ entry: String) -> Bool {
        !entry.isEmpty && !entry.hasPrefix("/") && !entry.contains(":") && !entry.contains("\\")
            && !entry.split(separator: "/").contains("..")
    }
}

/// Источник конфига и приколов. Реализует приложение: CMS по ключу, CDN, ресурсы сборки.
public protocol PrankContentProvider: Sendable {
    /// JSON PrankConfig — например, ответ CMS по именованному ключу.
    func loadConfig() async throws -> Data
    /// Прикол по `payload_id` из конфига.
    func loadContent(payloadID: String) async throws -> PrankContent
}

/// Сначала основной источник, при любой ошибке — запасной (обычно ресурсы внутри сборки).
/// Так пустой или битый конфиг в CMS не ломает приложение и не выключает прикол.
public struct FallbackContentProvider: PrankContentProvider {
    private let primary: any PrankContentProvider
    private let fallback: any PrankContentProvider

    public init(primary: any PrankContentProvider, fallback: any PrankContentProvider) {
        self.primary = primary
        self.fallback = fallback
    }

    public func loadConfig() async throws -> Data {
        if let data = try? await primary.loadConfig(), (try? PrankConfig.decode(data)) != nil {
            return data
        }
        return try await fallback.loadConfig()
    }

    public func loadContent(payloadID: String) async throws -> PrankContent {
        if let content = try? await primary.loadContent(payloadID: payloadID) {
            return content
        }
        return try await fallback.loadContent(payloadID: payloadID)
    }
}

/// Приколы из папки внутри сборки или на диске.
///
/// Раскладка: `config.json` и по папке на каждый прикол:
/// `<payload_id>.json` — payload целиком, или `<payload_id>/` — игра файлами
/// (`index.html` + `payload.json` с полями контракта без `html`).
public struct DirectoryContentProvider: PrankContentProvider {
    private let root: URL

    public init(root: URL) {
        self.root = root
    }

    public func loadConfig() async throws -> Data {
        try Data(contentsOf: root.appendingPathComponent("config.json"))
    }

    public func loadContent(payloadID: String) async throws -> PrankContent {
        guard PrankPayload.isValidID(payloadID) else {
            throw ContractError.invalid("Недопустимый payload_id «\(payloadID)»")
        }
        let file = root.appendingPathComponent("\(payloadID).json")
        if let data = try? Data(contentsOf: file) {
            return PrankContent(payload: try PrankPayload.decode(data))
        }

        let folder = root.appendingPathComponent(payloadID, isDirectory: true)
        let metadata = try Data(contentsOf: folder.appendingPathComponent("payload.json"))
        guard var object = (try? JSONSerialization.jsonObject(with: metadata)) as? [String: Any] else {
            throw ContractError.notJSONObject
        }
        // html живёт в index.html рядом; схеме он всё равно нужен, подставляем заглушку.
        object["html"] = object["html"] ?? ""
        let payload = try PrankPayload.decode(try JSONSerialization.data(withJSONObject: object))
        guard payload.id == payloadID else {
            throw ContractError.invalid("id в payload.json не совпадает с папкой «\(payloadID)»")
        }
        return PrankContent(payload: payload, source: .directory(folder))
    }
}
