import Foundation

/// Кеш ассетов игры: `atlas.json` и картинки, которые он перечисляет.
///
/// Порядок, в котором берётся пакет:
/// 1. кеш на диске (`Caches/PrankAssets/current`) — мгновенно, без сети; свежая версия
///    при этом тихо докачивается в фоне и будет использована при следующем показе;
/// 2. сеть (CDN), если кеша ещё нет — с коротким таймаутом, чтобы не задерживать прикол;
/// 3. ассеты внутри сборки — если сети нет и кеш пуст.
///
/// Пакет кладётся в кеш только целиком и только если атлас реально разбирается и картинки
/// декодируются: битый ответ CDN не сломает игру, останется предыдущая версия.
public actor PrankAssetCache {

    public enum Origin: String, Sendable {
        case cache = "кеш"
        case network = "сеть"
        case bundle = "сборка"
    }

    public struct Resolved: Sendable, Equatable {
        public let atlasURL: URL
        public let origin: Origin
    }

    public static let atlasFileName = "atlas.json"

    private let remoteBase: URL?
    private let bundledDirectory: URL
    private let directory: URL
    private let session: URLSession
    /// Сколько показ ждёт сеть, если кеша ещё нет. Дальше — ассеты из сборки, загрузка идёт в фоне.
    private let showWait: TimeInterval
    /// Таймаут одного запроса фоновой загрузки (медленная мобильная сеть).
    private let requestTimeout: TimeInterval
    /// Одна загрузка на всех: показ, кнопка «обновить» и фон ждут одну и ту же задачу.
    private var downloadTask: Task<URL?, Never>?

    public private(set) var lastOrigin: Origin?
    public private(set) var lastRefresh: Date?

    /// - Parameters:
    ///   - remoteBase: папка ассетов на CDN (с `/` на конце), например `…/web/assets/`. `nil` — только сборка.
    ///   - bundledDirectory: папка с `atlas.json` внутри сборки — запасной вариант.
    ///   - directory: куда складывать кеш. По умолчанию `Caches/PrankAssets`.
    public init(
        remoteBase: URL?,
        bundledDirectory: URL,
        directory: URL? = nil,
        session: URLSession = .shared,
        showWait: TimeInterval = 3,
        requestTimeout: TimeInterval = 30
    ) {
        self.remoteBase = remoteBase
        self.bundledDirectory = bundledDirectory
        self.directory = directory
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("PrankAssets")
        self.session = session
        self.showWait = showWait
        self.requestTimeout = requestTimeout
    }

    private var currentDirectory: URL { directory.appendingPathComponent("current", isDirectory: true) }

    /// Где взять ассеты прямо сейчас.
    public func resolve() async -> Resolved {
        let cachedAtlas = currentDirectory.appendingPathComponent(Self.atlasFileName)
        if FileManager.default.fileExists(atPath: cachedAtlas.path) {
            _ = startDownload() // свежая версия — в фоне, к следующему показу
            return remember(Resolved(atlasURL: cachedAtlas, origin: .cache))
        }
        if remoteBase != nil, await waitForDownload(upTo: showWait) != nil {
            return remember(Resolved(atlasURL: cachedAtlas, origin: .network))
        }
        // Сеть не успела — играем ассетами из сборки, загрузка в кеш продолжается.
        return remember(Resolved(atlasURL: bundledDirectory.appendingPathComponent(Self.atlasFileName), origin: .bundle))
    }

    /// Скачать свежий пакет сейчас (предзагрузка при старте, кнопка в демо).
    @discardableResult
    public func refresh() async -> Bool {
        guard remoteBase != nil else { return false }
        return await startDownload().value != nil
    }

    /// Удалить кеш: следующий показ пойдёт в сеть, а без сети — в сборку.
    public func clear() {
        downloadTask?.cancel()
        downloadTask = nil
        try? FileManager.default.removeItem(at: directory)
        lastOrigin = nil
        lastRefresh = nil
    }

    public var hasCachedPack: Bool {
        FileManager.default.fileExists(atPath: currentDirectory.appendingPathComponent(Self.atlasFileName).path)
    }

    private func remember(_ resolved: Resolved) -> Resolved {
        lastOrigin = resolved.origin
        return resolved
    }

    private func startDownload() -> Task<URL?, Never> {
        if let downloadTask { return downloadTask }
        let task = Task<URL?, Never> { [weak self] in
            let result = try? await self?.download()
            await self?.finishDownload()
            return result
        }
        downloadTask = task
        return task
    }

    private func finishDownload() {
        downloadTask = nil
    }

    /// Ждём загрузку не дольше `seconds`; сама загрузка при этом не отменяется.
    private func waitForDownload(upTo seconds: TimeInterval) async -> URL? {
        let task = startDownload()
        return await withTaskGroup(of: URL?.self) { group in
            group.addTask { await task.value }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// Скачивает пакет во временную папку, проверяет и атомарно подменяет `current`.
    private func download() async throws -> URL {
        guard let remoteBase else { throw URLError(.badURL) }
        let fileManager = FileManager.default
        let staging = directory.appendingPathComponent("staging-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        // Ветка `@main` на CDN — изменяемый адрес. Минутный query не даёт edge-кешу
        // бесконечно держать старого маскота, но и не создаёт новый URL на каждый запрос.
        let revision = String(Int(Date().timeIntervalSince1970 / 60))
        let atlasData = try await fetch(versioned(remoteBase.appendingPathComponent(Self.atlasFileName), revision: revision))
        try atlasData.write(to: staging.appendingPathComponent(Self.atlasFileName))
        let images = PrankAtlas.imageNames(in: atlasData)
        guard !images.isEmpty else { throw URLError(.cannotParseResponse) }
        // Картинки — параллельно: на медленной сети это в разы быстрее.
        try await withThrowingTaskGroup(of: (String, Data).self) { group in
            for name in images {
                group.addTask {
                    let url = self.versioned(remoteBase.appendingPathComponent(name), revision: revision)
                    return (name, try await self.fetch(url))
                }
            }
            for try await (name, data) in group {
                try data.write(to: staging.appendingPathComponent(name))
            }
        }
        // Кладём в кеш только то, что игра реально сможет показать.
        guard PrankAtlas.load(atlasURL: staging.appendingPathComponent(Self.atlasFileName)) != nil else {
            throw URLError(.cannotDecodeContentData)
        }

        let previous = directory.appendingPathComponent("previous", isDirectory: true)
        try? fileManager.removeItem(at: previous)
        if fileManager.fileExists(atPath: currentDirectory.path) {
            try fileManager.moveItem(at: currentDirectory, to: previous)
        }
        try fileManager.moveItem(at: staging, to: currentDirectory)
        try? fileManager.removeItem(at: previous)
        lastRefresh = Date()
        return currentDirectory
    }

    nonisolated private func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: requestTimeout)
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        guard !data.isEmpty else { throw URLError(.zeroByteResource) }
        return data
    }

    /// Query нужен только HTTP(S). `file://` остаётся без него для быстрых unit-тестов.
    nonisolated private func versioned(_ url: URL, revision: String) -> URL {
        guard url.scheme == "http" || url.scheme == "https",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var query = components.queryItems ?? []
        query.removeAll { $0.name == "prank_asset_revision" }
        query.append(URLQueryItem(name: "prank_asset_revision", value: revision))
        components.queryItems = query
        return components.url ?? url
    }
}
