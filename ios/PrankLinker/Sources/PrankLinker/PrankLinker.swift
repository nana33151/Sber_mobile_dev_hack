import UIKit

/// Точка входа для приложения: связывает СберKids с JS-приколом.
///
/// ```swift
/// let linker = PrankLinker(content: FallbackContentProvider(primary: cms, fallback: bundled))
/// linker.delegate = self
/// linker.attach(to: windowScene)
/// await linker.reloadConfig()
/// // из UIWindow приложения: override motionEnded → linker.handleShakeMotion(motion)
/// // при переходе на оплату: linker.screenAllowsPranks = false
/// ```
///
/// Гарантии для приложения:
/// - касание экрана сразу закрывает прикол и проходит в интерфейс под ним;
/// - битый конфиг, битый payload, падение или зависание страницы не роняют приложение —
///   оверлей убирается, приложение получает `.failed`;
/// - на запрещённых экранах (`screenAllowsPranks = false`) прикол не показывается,
///   а уже показанный закрывается.
@MainActor
public final class PrankLinker {

    public struct Options {
        /// Пауза после закрытия, прежде чем прикол можно вызвать снова.
        public var cooldown: TimeInterval = 2
        /// Столько сбоев подряд — и приколы выключаются до перезапуска приложения.
        public var maxConsecutiveFailures = 3
        /// Ловить тряску акселерометром, а не только системным `motionShake`.
        public var detectsShakeWithAccelerometer = true
        /// Лёгкая вибрация на `VIBRATION_EVENT`.
        public var hapticsEnabled = true
        /// Закрывать прикол касанием. Выключается только в демо, чтобы управлять наклоном с экрана.
        public var dismissesOnTouch = true
        /// Касания, которые не закрывают прикол (точка в координатах окна). Только для демо:
        /// например, джойстик наклона в симуляторе. В продукте не задаётся.
        public var ignoresTouch: (@MainActor (CGPoint) -> Bool)?

        public init() {}
    }

    public weak var delegate: PrankLinkerDelegate?

    /// Источник наклона. По умолчанию CoreMotion, в симуляторе — `ManualTiltSource`.
    public let tiltSource: any PrankTiltSource

    public private(set) var config: PrankConfig?
    public var isShowing: Bool { presenter != nil }

    /// Приложение выставляет при каждом переходе. Экраны оплаты, переводов, реквизитов и лимитов — `false`.
    public var screenAllowsPranks = true {
        didSet {
            if !screenAllowsPranks { hide() }
            scheduleDelayTrigger()
            updateShakeDetector()
        }
    }

    private let content: any PrankContentProvider
    public var options: Options
    private weak var scene: UIWindowScene?
    private var presenter: PrankPresenter?
    private var loadingTask: Task<Void, Never>?
    private var delayTimer: Timer?
    private var breaker: CircuitBreaker
    private var cooldown: Cooldown
    private var hasCompleted = false
    private let shakeDetector = ShakeDetector()
    private let haptics = UIImpactFeedbackGenerator(style: .light)
    private var lastHaptic = Date.distantPast
    private var observers: [NSObjectProtocol] = []

    public init(content: any PrankContentProvider, options: Options = Options(), tiltSource: (any PrankTiltSource)? = nil) {
        self.content = content
        self.options = options
        self.breaker = CircuitBreaker(maxConsecutiveFailures: options.maxConsecutiveFailures)
        self.cooldown = Cooldown(interval: options.cooldown)
        #if targetEnvironment(simulator)
        self.tiltSource = tiltSource ?? ManualTiltSource()
        #else
        self.tiltSource = tiltSource ?? MotionTiltSource()
        #endif
        shakeDetector.onShake = { [weak self] in self?.handleTrigger(.shake) }
        observeApplication()
    }

    // MARK: Настройка

    /// Сцена, поверх которой показывать прикол.
    public func attach(to scene: UIWindowScene) {
        self.scene = scene
        updateShakeDetector()
    }

    /// Загружает конфиг. Ошибка не бросается: прикол просто выключается до следующей загрузки.
    public func reloadConfig() async {
        let loaded: PrankConfig
        do {
            loaded = try PrankConfig.decode(try await content.loadConfig())
        } catch let error as ContractError {
            reject("Конфиг не прошёл схему: \(error.message)")
            return
        } catch {
            reject("Конфиг не загрузился: \(error.localizedDescription)")
            return
        }
        apply(loaded)
    }

    /// Применить уже полученный конфиг (например, из общего ответа CMS).
    public func apply(_ config: PrankConfig) {
        self.config = config
        emit(.configLoaded(config))
        if !config.enabled { hide() }
        scheduleDelayTrigger()
        updateShakeDetector()
    }

    private func reject(_ reason: String) {
        config = .disabled
        emit(.configRejected(reason))
        hide()
        updateShakeDetector()
    }

    // MARK: Триггеры

    /// Вызывать из `motionEnded(_:with:)` окна приложения. В симуляторе — Device → Shake.
    public func handleShakeMotion(_ motion: UIEvent.EventSubtype) {
        guard motion == .motionShake else { return }
        handleTrigger(.shake)
    }

    /// Вызывать на касание элемента, к которому привязан прикол (триггер `tap`).
    public func handleTap() {
        handleTrigger(.tap)
    }

    /// Показать прикол из конфига вне зависимости от вида триггера (триггер `manual`, кнопка в демо).
    public func trigger() {
        guard let payloadID = config?.trigger?.payloadID else {
            emit(.skipped(.notConfigured))
            return
        }
        show(payloadID: payloadID, via: .manual)
    }

    /// Показать конкретный прикол — для демо и отладки.
    public func show(payloadID: String) {
        show(payloadID: payloadID, via: .manual)
    }

    /// Закрыть прикол, если он показывается.
    public func hide() {
        loadingTask?.cancel()
        loadingTask = nil
        presenter?.close(.manual)
    }

    private func handleTrigger(_ kind: PrankConfig.TriggerKind) {
        guard let config, let trigger = config.trigger else {
            emit(.skipped(.notConfigured))
            return
        }
        guard trigger.on == kind else {
            emit(.skipped(.wrongTrigger))
            return
        }
        show(payloadID: trigger.payloadID, via: kind)
    }

    private func show(payloadID: String, via kind: PrankConfig.TriggerKind) {
        if let reason = skipReason() {
            emit(.skipped(reason))
            return
        }
        emit(.triggered(kind, payloadID: payloadID))
        let content = self.content
        loadingTask = Task { [weak self] in
            let result: Result<PrankContent, PrankError>
            do {
                result = .success(try await content.loadContent(payloadID: payloadID))
            } catch let error as ContractError {
                result = .failure(.invalidPayload(error.message))
            } catch {
                result = .failure(.contentUnavailable(error.localizedDescription))
            }
            guard !Task.isCancelled else { return }
            self?.loadingTask = nil
            self?.present(result, payloadID: payloadID)
        }
    }

    private func skipReason() -> PrankSkipReason? {
        guard let config else { return .notConfigured }
        if !config.enabled { return .disabled }
        if breaker.isOpen { return .circuitOpen }
        if !screenAllowsPranks { return .forbiddenScreen }
        if presenter != nil || loadingTask != nil { return .busy }
        if cooldown.isActive() { return .cooldown }
        return nil
    }

    // MARK: Показ

    private func present(_ result: Result<PrankContent, PrankError>, payloadID: String) {
        let content: PrankContent
        switch result {
        case .success(let loaded): content = loaded
        case .failure(let error):
            recordFailure(payloadID: payloadID, error)
            return
        }
        // За время загрузки пользователь мог уйти на запрещённый экран.
        guard screenAllowsPranks, config?.enabled == true, let scene, scene.activationState == .foregroundActive else {
            emit(.skipped(scene == nil ? .notConfigured : .forbiddenScreen))
            return
        }

        let presenter = PrankPresenter(
            content: content,
            config: config ?? .disabled,
            tiltSource: tiltSource,
            shouldDismiss: { [weak self] point in
                guard let options = self?.options else { return true }
                return options.dismissesOnTouch && !(options.ignoresTouch?(point) ?? false)
            }
        )
        presenter.onShown = { [weak self] in
            self?.breaker.recordSuccess()
            self?.emit(.shown(payloadID: content.payload.id))
        }
        presenter.onMessage = { [weak self] body in
            self?.handle(body, from: content.payload.id)
        }
        presenter.onFinish = { [weak self, weak presenter] outcome in
            guard let self else { return }
            if self.presenter === presenter { self.presenter = nil }
            self.cooldown.start()
            switch outcome {
            case .hidden(let reason):
                self.emit(.hidden(payloadID: content.payload.id, reason: reason))
            case .failed(let error):
                self.recordFailure(payloadID: content.payload.id, error)
            }
        }
        self.presenter = presenter
        hasCompleted = false
        presenter.start(in: scene)
    }

    private func recordFailure(payloadID: String?, _ error: PrankError) {
        breaker.recordFailure()
        cooldown.start()
        emit(.failed(payloadID: payloadID, error))
        updateShakeDetector()
    }

    // MARK: Сообщения страницы

    private func handle(_ body: Any, from payloadID: String) {
        switch PageMessage.parse(body) {
        case .failure(let failure):
            emit(.ignoredMessage(String(describing: failure)))
        case .success(let message):
            switch message {
            case .shown:
                break // показ подтверждает резолв `PrankBridge.show()`
            case .hidden, .close:
                presenter?.close(.manual)
            case .action(_, let action):
                emit(.action(payloadID: payloadID, action: action))
            case .error(let code, let text):
                emit(.pageError(payloadID: payloadID, code: code, message: text))
            case .finish:
                emit(.finished(payloadID: payloadID))
            case .completed:
                // По контракту канала — один раз за показ.
                guard !hasCompleted else {
                    emit(.ignoredMessage("COMPLETED_EVENT повторно"))
                    return
                }
                hasCompleted = true
                emit(.completed(payloadID: payloadID))
            case .vibration:
                vibrate()
            case .sharing(let text, let image):
                emit(.shareRequested(payloadID: payloadID, text: text, image: image))
            }
        }
    }

    private func vibrate() {
        // Не чаще 10 раз в секунду: страница может слать вибрацию на каждый кадр.
        guard options.hapticsEnabled, Date().timeIntervalSince(lastHaptic) > 0.1 else { return }
        lastHaptic = Date()
        haptics.impactOccurred(intensity: 0.6)
    }

    // MARK: Окружение

    private func scheduleDelayTrigger() {
        delayTimer?.invalidate()
        delayTimer = nil
        guard screenAllowsPranks, let trigger = config?.trigger, trigger.on == .delay, config?.enabled == true else { return }
        let delay = TimeInterval(trigger.delayMs ?? 0) / 1000
        delayTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleTrigger(.delay) }
        }
    }

    private func updateShakeDetector() {
        let wantsShake = options.detectsShakeWithAccelerometer
            && scene != nil
            && screenAllowsPranks
            && config?.enabled == true
            && config?.trigger?.on == .shake
            && !breaker.isOpen
        if wantsShake {
            shakeDetector.start()
        } else {
            shakeDetector.stop()
        }
    }

    private func observeApplication() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            UIApplication.willResignActiveNotification,
            UIApplication.didReceiveMemoryWarningNotification
        ]
        for name in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.hide() }
            })
        }
    }

    private func emit(_ event: PrankLinkerEvent) {
        delegate?.prankLinker(self, didEmit: event)
    }
}
