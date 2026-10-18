import UIKit

/// Спрайты игры из `atlas.json` — того же файла, что использует JS-рендер (`web/assets/atlas.json`).
/// Картинки нарезаются один раз при загрузке, дальше игра работает только с готовыми кадрами.
public struct PrankAtlas: @unchecked Sendable {

    public enum CatState: CaseIterable {
        case ready, oneBall, twoBalls
    }

    public let catStates: [CatState: CGImage]
    public let danceFrames: [CGImage]
    public let danceDurationMs: Double
    public let yarns: [CGImage]

    /// Файлы, которые атлас требует рядом с собой. Нужны кешу, чтобы скачать пакет целиком.
    public static func imageNames(in atlasData: Data) -> [String] {
        guard let root = (try? JSONSerialization.jsonObject(with: atlasData)) as? [String: Any] else { return [] }
        return ["catStates", "catDance", "yarnVariants"].compactMap { key in
            guard let name = (root[key] as? [String: Any])?["image"] as? String, isSafeName(name) else { return nil }
            return name
        }
    }

    /// Загружает атлас и картинки из папки на диске. Любая ошибка — `nil`, без падений.
    public static func load(atlasURL: URL) -> PrankAtlas? {
        guard let data = try? Data(contentsOf: atlasURL),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let folder = atlasURL.deletingLastPathComponent()

        func sheet(_ key: String) -> (entry: [String: Any], image: CGImage)? {
            guard let entry = root[key] as? [String: Any],
                  let name = entry["image"] as? String, isSafeName(name),
                  let image = UIImage(contentsOfFile: folder.appendingPathComponent(name).path)?.cgImage
            else { return nil }
            return (entry, image)
        }

        guard let states = sheet("catStates"), let dance = sheet("catDance"), let yarn = sheet("yarnVariants"),
              let stateFrames = states.entry["frames"] as? [String: Any] else { return nil }

        var catStates: [CatState: CGImage] = [:]
        for (state, key) in [(CatState.ready, "ready"), (.oneBall, "oneBall"), (.twoBalls, "twoBalls")] {
            guard let rect = rect(stateFrames[key]), let image = states.image.cropping(to: rect) else { return nil }
            catStates[state] = image
        }
        let danceFrames = frames(dance.entry["frames"], from: dance.image)
        let yarns = frames(yarn.entry["frames"], from: yarn.image)
        guard !danceFrames.isEmpty, !yarns.isEmpty else { return nil }

        return PrankAtlas(
            catStates: catStates,
            danceFrames: danceFrames,
            danceDurationMs: (dance.entry["durationMs"] as? Double) ?? 1600,
            yarns: yarns
        )
    }

    private static func frames(_ raw: Any?, from image: CGImage) -> [CGImage] {
        (raw as? [Any] ?? []).compactMap { rect($0).flatMap { image.cropping(to: $0) } }
    }

    private static func rect(_ raw: Any?) -> CGRect? {
        guard let frame = raw as? [String: Any],
              let x = frame["x"] as? Double, let y = frame["y"] as? Double,
              let width = frame["width"] as? Double, let height = frame["height"] as? Double,
              width > 0, height > 0 else { return nil }
        return CGRect(x: x, y: y, width: width, height: height).integral
    }

    static func isSafeName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && !name.contains("\\") && name != ".." && name != "."
    }
}
