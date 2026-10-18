import UniformTypeIdentifiers
import WebKit

/// Отдаёт страницу прикола по схеме `prank://` без сети и без `file://`.
///
/// `prank://payload/index.html` — `html` из payload с подставленными `css` и `js`,
/// `prank://payload/assets/<key>` — декодированное вложение.
/// Для пакета с диска (игра из CDN-кэша) отдаются файлы его папки по относительным путям.
final class PrankSchemeHandler: NSObject, WKURLSchemeHandler {

    static let scheme = "prank"
    static let entryURL = URL(string: "\(scheme)://payload/index.html")!

    static func entryURL(for entry: String) -> URL {
        let encoded = entry.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "index.html"
        return URL(string: "\(scheme)://payload/\(encoded)") ?? entryURL
    }

    enum Content {
        case payload(PrankPayload)
        /// Папка игры; `entryDirectory` и `publicDirectory` — для поиска статики как у Vite `publicDir`.
        case directory(URL, entryDirectory: String = "", publicDirectory: String? = nil)
    }

    private let content: Content

    init(content: Content) {
        self.content = content
    }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else {
            task.didFailWithError(URLError(.badURL))
            return
        }
        let path = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        guard let (data, mimeType) = resolve(path: path.isEmpty ? "index.html" : path) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": mimeType,
                "Content-Length": String(data.count),
                "Cache-Control": "no-store",
                // ES-модули (<script type="module">) и fetch() на своей схеме WebKit грузит только с CORS.
                "Access-Control-Allow-Origin": "*"
            ]
        )
        task.didReceive(response ?? URLResponse(url: url, mimeType: mimeType, expectedContentLength: data.count, textEncodingName: nil))
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {
        // Ответ отдаётся синхронно, отменять нечего.
    }

    private func resolve(path: String) -> (Data, String)? {
        switch content {
        case .payload(let payload):
            if path == "index.html" {
                return (Data(Self.page(for: payload).utf8), "text/html; charset=utf-8")
            }
            let assetPrefix = "assets/"
            guard path.hasPrefix(assetPrefix) else { return nil }
            let key = String(path.dropFirst(assetPrefix.count))
            guard let data = payload.assets[key] else { return nil }
            return (data, Self.mimeType(forPath: key, data: data))

        case .directory(let root, let entryDirectory, let publicDirectory):
            if let found = Self.read(path, in: root) { return found }
            // Как Vite publicDir: `src/atlas.json` → `assets/atlas.json`.
            guard let publicDirectory else { return nil }
            let prefix = entryDirectory.isEmpty ? "" : entryDirectory + "/"
            guard path.hasPrefix(prefix) else { return nil }
            let rest = String(path.dropFirst(prefix.count))
            // `src/assets/atlas.json` (сборка Vite кладёт статику в `assets/`) → `assets/atlas.json`.
            if rest.hasPrefix(publicDirectory + "/"), let found = Self.read(rest, in: root) { return found }
            return Self.read(publicDirectory + "/" + rest, in: root)
        }
    }

    private static func read(_ path: String, in root: URL) -> (Data, String)? {
        let root = root.standardizedFileURL
        let file = root.appendingPathComponent(path).standardizedFileURL
        // Никаких выходов за пределы папки пакета.
        guard file.path.hasPrefix(root.path + "/"), let data = try? Data(contentsOf: file) else { return nil }
        return (data, mimeType(forPath: file.lastPathComponent, data: data))
    }

    /// Собирает страницу: `css` — в `<head>`, `js` — в конец `<body>`.
    nonisolated static func page(for payload: PrankPayload) -> String {
        var html = payload.html
        if let css = payload.css, !css.isEmpty {
            html = insert("<style>\(css)</style>", before: "</head>", in: html, fallbackAtStart: true)
        }
        if let js = payload.js, !js.isEmpty {
            html = insert("<script>\(js)</script>", before: "</body>", in: html, fallbackAtStart: false)
        }
        return html
    }

    nonisolated private static func insert(_ fragment: String, before tag: String, in html: String, fallbackAtStart: Bool) -> String {
        if let range = html.range(of: tag, options: [.caseInsensitive, .backwards]) {
            var result = html
            result.insert(contentsOf: fragment, at: range.lowerBound)
            return result
        }
        return fallbackAtStart ? fragment + html : html + fragment
    }

    nonisolated static func mimeType(forPath path: String, data: Data) -> String {
        let ext = (path as NSString).pathExtension
        if !ext.isEmpty, let type = UTType(filenameExtension: ext), let mime = type.preferredMIMEType {
            return mime
        }
        // Имя вложения без расширения — определяем по сигнатуре.
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if bytes.starts(with: [0x47, 0x49, 0x46]) { return "image/gif" }
        if bytes.count >= 12, bytes[0...3] == [0x52, 0x49, 0x46, 0x46], bytes[8...11] == [0x57, 0x45, 0x42, 0x50] {
            return "image/webp"
        }
        if bytes.starts(with: [0x49, 0x44, 0x33]) || bytes.starts(with: [0xFF, 0xFB]) { return "audio/mpeg" }
        return "application/octet-stream"
    }
}
