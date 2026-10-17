import UIKit

/// Короткая нативная анимация на случай, если игра не запустилась: пользователь потряс телефон
/// и увидел ответ, а не пустоту. Работает без WebView — ведь как раз он и не смог.
///
/// Кадры приложение передаёт само (из ресурсов сборки или CDN-кэша), например танец котика
/// из того же атласа, что использует JS-рендер (`web/assets/atlas.json`, ключ `catDance`).
public struct PrankFallbackAnimation: @unchecked Sendable {
    public var frames: [UIImage]
    /// Длительность одного кадра. В JS-рендере: 4 кадра за 1600 мс.
    public var frameDuration: TimeInterval = 0.4
    /// Сколько показывать целиком, 2–4 с.
    public var totalDuration: TimeInterval = 3.2 {
        didSet { totalDuration = min(4, max(2, totalDuration)) }
    }
    /// Высота котика на экране в точках.
    public var height: CGFloat = 150
    /// Насколько ниже центра экрана — доля высоты экрана.
    public var belowCenter: CGFloat = 0.12

    public init(frames: [UIImage]) {
        self.frames = frames
    }

    /// Нарезает кадры из листа спрайтов. `rects` — в пикселях исходной картинки, как в atlas.json.
    public static func spriteSheet(_ sheet: UIImage, rects: [CGRect]) -> PrankFallbackAnimation? {
        guard let cgImage = sheet.cgImage else { return nil }
        let frames = rects.compactMap { rect -> UIImage? in
            guard let cropped = cgImage.cropping(to: rect.integral) else { return nil }
            return UIImage(cgImage: cropped, scale: sheet.scale, orientation: .up)
        }
        return frames.isEmpty ? nil : PrankFallbackAnimation(frames: frames)
    }

    /// Читает `atlas.json` в формате JS-рендера и берёт анимацию по ключу (по умолчанию `catDance`).
    /// Картинка ищется рядом с атласом. Любая ошибка — `nil`, без падений.
    public static func atlas(at atlasURL: URL, key: String = "catDance") -> PrankFallbackAnimation? {
        guard let data = try? Data(contentsOf: atlasURL),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let entry = root[key] as? [String: Any],
              let imageName = entry["image"] as? String,
              !imageName.contains("/"),
              let rawFrames = entry["frames"] as? [[String: Any]],
              let sheet = UIImage(contentsOfFile: atlasURL.deletingLastPathComponent().appendingPathComponent(imageName).path)
        else { return nil }

        let rects = rawFrames.compactMap { frame -> CGRect? in
            guard let x = frame["x"] as? Double, let y = frame["y"] as? Double,
                  let width = frame["width"] as? Double, let height = frame["height"] as? Double,
                  width > 0, height > 0 else { return nil }
            return CGRect(x: x, y: y, width: width, height: height)
        }
        guard var animation = spriteSheet(sheet, rects: rects) else { return nil }
        if let durationMs = entry["durationMs"] as? Double, durationMs > 0 {
            animation.frameDuration = durationMs / 1000 / Double(animation.frames.count)
        }
        return animation
    }
}

/// Показывает `PrankFallbackAnimation` в отдельном окне поверх приложения.
/// Как и сам прикол: касания не забирает, первое касание убирает анимацию.
@MainActor
final class PrankFallbackPresenter {

    var onFinish: (() -> Void)?

    private let animation: PrankFallbackAnimation
    private var window: PrankOverlayWindow?
    private var hideTimer: Timer?
    private var isClosing = false

    init(animation: PrankFallbackAnimation) {
        self.animation = animation
    }

    func start(in scene: UIWindowScene) {
        guard let first = animation.frames.first else {
            finish()
            return
        }
        let root = PrankOverlayViewController()
        let bounds = scene.coordinateSpace.bounds
        // Размер корня задаём заранее: иначе autoresizing при вставке в окно утащит картинку за экран.
        root.view.frame = bounds
        let aspect = first.size.width / max(first.size.height, 1)
        let size = CGSize(width: animation.height * aspect, height: animation.height)

        let imageView = UIImageView(frame: CGRect(origin: .zero, size: size))
        imageView.contentMode = .scaleAspectFit
        imageView.animationImages = animation.frames
        imageView.animationDuration = animation.frameDuration * Double(animation.frames.count)
        imageView.animationRepeatCount = 0
        imageView.center = CGPoint(x: bounds.midX, y: bounds.midY + bounds.height * animation.belowCenter)
        imageView.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin, .flexibleBottomMargin]
        imageView.isAccessibilityElement = false
        root.view.addSubview(imageView)

        let window = PrankOverlayWindow(windowScene: scene)
        window.rootViewController = root
        window.alpha = 0
        window.onTouch = { [weak self] _ in self?.close() }
        window.isHidden = false
        self.window = window

        imageView.startAnimating()
        // Мягкое появление — без резких анимаций и «скримеров».
        imageView.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            window.alpha = 1
            imageView.transform = .identity
        }
        hideTimer = Timer.scheduledTimer(withTimeInterval: animation.totalDuration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    func close() {
        guard !isClosing else { return }
        isClosing = true
        hideTimer?.invalidate()
        hideTimer = nil
        guard let window else {
            finish()
            return
        }
        window.onTouch = nil
        UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .curveEaseIn]) {
            window.alpha = 0
        } completion: { _ in
            MainActor.assumeIsolated { self.finish() }
        }
    }

    private func finish() {
        window?.isHidden = true
        window = nil
        onFinish?()
        onFinish = nil
    }
}
