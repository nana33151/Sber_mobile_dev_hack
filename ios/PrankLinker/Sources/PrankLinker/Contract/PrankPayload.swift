import Foundation

/// PrankPayload из `contract/payload_schema.json`: один оверлей-прикол.
public struct PrankPayload: Equatable, Sendable {

    public enum Background: String, Sendable {
        case transparent, dim, opaque
    }

    public let id: String
    public let title: String?
    public let html: String
    public let css: String?
    public let js: String?
    /// Уже декодированные из base64 вложения. В HTML доступны как `assets/<key>`.
    public let assets: [String: Data]
    public let durationMs: Int
    public let dismissible: Bool
    public let background: Background

    public init(
        id: String,
        title: String? = nil,
        html: String,
        css: String? = nil,
        js: String? = nil,
        assets: [String: Data] = [:],
        durationMs: Int = 5000,
        dismissible: Bool = true,
        background: Background = .opaque
    ) {
        self.id = id
        self.title = title
        self.html = html
        self.css = css
        self.js = js
        self.assets = assets
        self.durationMs = durationMs
        self.dismissible = dismissible
        self.background = background
    }

    /// Метаданные без тяжёлых полей — их получает `PrankBridge.show()` на странице.
    var metadataJSON: [String: Any] {
        var result: [String: Any] = [
            "version": PrankConfig.supportedVersion,
            "id": id,
            "duration_ms": durationMs,
            "dismissible": dismissible,
            "background": background.rawValue
        ]
        result["title"] = title
        return result
    }

    private static let allowedKeys: Set<String> = [
        "version", "id", "title", "html", "css", "js", "assets", "duration_ms", "dismissible", "background"
    ]

    /// Разбирает и валидирует payload по схеме.
    public static func decode(_ data: Data) throws(ContractError) -> PrankPayload {
        let object = try JSONObject.parse(data)
        try object.requireOnlyKeys(allowedKeys)
        guard object["version"] as? String == PrankConfig.supportedVersion else {
            throw .invalid("version должен быть \"\(PrankConfig.supportedVersion)\"")
        }
        guard let id = try object.optionalString("id"), isValidID(id) else {
            throw .invalid("id не соответствует ^[a-z0-9][a-z0-9_-]{0,63}$")
        }
        guard let html = try object.optionalString("html") else {
            throw .invalid("html обязателен")
        }
        let title = try object.optionalString("title")
        let css = try object.optionalString("css")
        let js = try object.optionalString("js")
        try check(title, max: 120, name: "title")
        try check(html, max: 200_000, name: "html")
        try check(css, max: 50_000, name: "css")
        try check(js, max: 50_000, name: "js")

        var assets: [String: Data] = [:]
        if let raw = object["assets"] {
            guard let encoded = raw as? [String: Any] else { throw .invalid("assets должен быть объектом") }
            guard encoded.count <= 20 else { throw .invalid("assets: больше 20 вложений") }
            for (key, value) in encoded {
                guard isSafeAssetKey(key) else { throw .invalid("assets: недопустимое имя «\(key)»") }
                // Контракт: standard alphabet, с padding, без префикса "data:".
                guard let string = value as? String, !string.hasPrefix("data:"),
                      let data = Data(base64Encoded: string) else {
                    throw .invalid("assets.\(key): невалидный base64")
                }
                assets[key] = data
            }
        }

        let durationMs = try object.optionalInt("duration_ms") ?? 5000
        guard (500...60_000).contains(durationMs) else { throw .invalid("duration_ms вне диапазона 500…60000") }
        let dismissible = try object.optionalBool("dismissible") ?? true
        let background: Background
        if let rawBackground = try object.optionalString("background") {
            guard let parsed = Background(rawValue: rawBackground) else {
                throw .invalid("background должен быть transparent, dim или opaque")
            }
            background = parsed
        } else {
            background = .opaque
        }

        return PrankPayload(
            id: id, title: title, html: html, css: css, js: js, assets: assets,
            durationMs: durationMs, dismissible: dismissible, background: background
        )
    }

    private static func check(_ value: String?, max: Int, name: String) throws(ContractError) {
        if let value, value.count > max {
            throw .invalid("\(name) длиннее \(max) символов")
        }
    }

    /// `^[a-z0-9][a-z0-9_-]{0,63}$` без Regex: он появился только в iOS 16.
    static func isValidID(_ id: String) -> Bool {
        let scalars = Array(id.unicodeScalars)
        guard (1...64).contains(scalars.count) else { return false }
        func isAlnum(_ s: Unicode.Scalar) -> Bool { ("a"..."z").contains(s) || ("0"..."9").contains(s) }
        return isAlnum(scalars[0]) && scalars.dropFirst().allSatisfy { isAlnum($0) || $0 == "_" || $0 == "-" }
    }

    /// Имя вложения становится путём `assets/<key>`, поэтому без выходов из папки.
    static func isSafeAssetKey(_ key: String) -> Bool {
        !key.isEmpty && key.count <= 128 && !key.contains("/") && !key.contains("\\") && key != "." && key != ".."
    }
}
