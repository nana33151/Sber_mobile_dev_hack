import UIKit

/// Окно поверх приложения. Касания не забирает никогда: первое касание сообщает о закрытии
/// и уходит дальше, в интерфейс приложения под оверлеем. Так прикол не блокирует ввод
/// ни на один кадр.
final class PrankOverlayWindow: UIWindow {

    /// Вызывается один раз на каждое новое касание, с точкой в координатах окна.
    var onTouch: ((CGPoint) -> Void)?

    private var lastTouchTimestamp: TimeInterval = -1

    override init(windowScene: UIWindowScene) {
        super.init(windowScene: windowScene)
        windowLevel = .alert - 1
        backgroundColor = .clear
        isOpaque = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) не используется")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // hitTest зовётся несколько раз на одно касание — реагируем один раз.
        if let event, event.type == .touches, event.timestamp != lastTouchTimestamp {
            lastTouchTimestamp = event.timestamp
            onTouch?(point)
        }
        return nil
    }

    // Окно не должно становиться key: иначе клавиатура и фокус приложения уйдут к нему.
    override var canBecomeKey: Bool { false }
}

/// Корневой контроллер оверлея: не влияет на статус-бар и ориентацию приложения.
final class PrankOverlayViewController: UIViewController {

    var dimColor: UIColor = .clear {
        didSet { view.backgroundColor = dimColor }
    }

    override func loadView() {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        self.view = view
    }

    override var prefersStatusBarHidden: Bool {
        presentingAppController?.prefersStatusBarHidden ?? false
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        presentingAppController?.preferredStatusBarStyle ?? .default
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        presentingAppController?.supportedInterfaceOrientations ?? .allButUpsideDown
    }

    private var presentingAppController: UIViewController? {
        view.window?.windowScene?.windows
            .first { $0.isKeyWindow && !($0 is PrankOverlayWindow) }?
            .rootViewController
    }
}
