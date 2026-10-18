import UIKit

/// Один показ прикола — неважно, чем он нарисован: WebView (`PrankPresenter`) или нативно (`NativeGameSession`).
@MainActor
protocol PrankSession: AnyObject {
    var onShown: (() -> Void)? { get set }
    /// Сообщение от игры в формате канала страницы (`{ event, data }`, `{ type }`).
    var onMessage: ((Any) -> Void)? { get set }
    var onFinish: ((PrankPresenter.Outcome) -> Void)? { get set }

    func start(in scene: UIWindowScene)
    func close(_ reason: PrankHideReason)
    func setBackgroundBlur(_ enabled: Bool, animated: Bool)
    func failLaunchIfLoading(_ error: PrankError)
}

extension PrankPresenter: PrankSession {}

/// Нативная игра поверх приложения: то же окно-оверлей, что у WebView, но без WebKit.
/// Запуск занимает миллисекунды: атлас уже на диске (кеш или сборка), картинки декодируются сразу.
@MainActor
final class NativeGameSession: PrankSession {

    var onShown: (() -> Void)?
    var onMessage: ((Any) -> Void)?
    var onFinish: ((PrankPresenter.Outcome) -> Void)?

    private let content: PrankContent
    private let atlasURL: URL
    private let tiltSource: any PrankTiltSource
    private let shouldDismiss: (CGPoint) -> Bool
    private var window: PrankOverlayWindow?
    private var gameView: CatGameView?
    private let blurView = UIVisualEffectView(effect: nil)
    private var blursBackground = false
    private var durationTimer: Timer?

    private enum State { case idle, loading, showing, closing, finished }
    private var state: State = .idle

    init(
        content: PrankContent,
        atlasURL: URL,
        tiltSource: any PrankTiltSource,
        shouldDismiss: @escaping (CGPoint) -> Bool
    ) {
        self.content = content
        self.atlasURL = atlasURL
        self.tiltSource = tiltSource
        self.shouldDismiss = shouldDismiss
    }

    func start(in scene: UIWindowScene) {
        guard state == .idle else { return }
        state = .loading

        guard let atlas = PrankAtlas.load(atlasURL: atlasURL) else {
            finish(.failed(.contentUnavailable("Атлас не загрузился: \(atlasURL.lastPathComponent)")))
            return
        }

        let root = PrankOverlayViewController()
        root.view.frame = scene.coordinateSpace.bounds
        blurView.frame = root.view.bounds
        blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        blurView.isUserInteractionEnabled = false
        applyBlur(animated: false)
        root.view.addSubview(blurView)

        let gameView = CatGameView(atlas: atlas, tiltSource: tiltSource)
        gameView.frame = root.view.bounds
        gameView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        gameView.onAction = { [weak self] action in
            // Тот же формат, что у JS-игры: линкер обрабатывает его одинаково (вибрация, «пройдено»).
            self?.onMessage?(["event": "action", "data": ["action": action]])
        }
        gameView.onVictoryStarted = { [weak self] in
            // `duration_ms` ограничивает игру, но не должен обрывать уже начавшийся финал.
            self?.durationTimer?.invalidate()
            self?.durationTimer = nil
        }
        root.view.addSubview(gameView)
        self.gameView = gameView

        let window = PrankOverlayWindow(windowScene: scene)
        window.rootViewController = root
        window.alpha = 0
        window.onTouch = { [weak self] point in
            guard let self, self.content.payload.dismissible, self.shouldDismiss(point) else { return }
            self.close(.dismiss)
        }
        window.isHidden = false
        self.window = window

        gameView.start()
        state = .showing
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            window.alpha = 1
        }
        let duration = TimeInterval(content.payload.durationMs) / 1000
        durationTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.close(.timeout) }
        }
        onShown?()
    }

    func close(_ reason: PrankHideReason) {
        finish(.hidden(reason))
    }

    func setBackgroundBlur(_ enabled: Bool, animated: Bool) {
        blursBackground = enabled
        applyBlur(animated: animated)
    }

    func failLaunchIfLoading(_ error: PrankError) {
        guard state == .loading else { return }
        finish(.failed(error))
    }

    private func applyBlur(animated: Bool) {
        let effect = blursBackground ? UIBlurEffect(style: .systemUltraThinMaterial) : nil
        guard animated else {
            blurView.effect = effect
            return
        }
        UIView.animate(withDuration: 0.3, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut]) {
            self.blurView.effect = effect
        }
    }

    private func finish(_ outcome: PrankPresenter.Outcome) {
        guard state != .closing, state != .finished else { return }
        let wasVisible = state == .showing
        state = .closing
        durationTimer?.invalidate()
        durationTimer = nil
        gameView?.stop()
        onFinish?(outcome)
        onFinish = nil

        guard wasVisible, let window else {
            teardown()
            return
        }
        UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
            window.alpha = 0
        } completion: { _ in
            MainActor.assumeIsolated { self.teardown() }
        }
    }

    private func teardown() {
        guard state != .finished else { return }
        state = .finished
        gameView?.removeFromSuperview()
        gameView = nil
        window?.onTouch = nil
        window?.isHidden = true
        window = nil
    }
}
