import UIKit
import WebKit

/// Один показ прикола: окно, WebView, таймауты, сторож зависаний и передача наклона.
///
/// Всё, что может пойти не так на странице, заканчивается вызовом `onFinish` с причиной —
/// никаких исключений наружу. Процесс WebKit отдельный, поэтому падение или зависание JS
/// приложение не роняет: линкер просто убирает оверлей.
@MainActor
final class PrankPresenter: NSObject {

    enum Outcome: Equatable {
        case hidden(PrankHideReason)
        case failed(PrankError)
    }

    struct Timing {
        /// Контракт: `show()` резолвится за 2000 мс, иначе TIMEOUT.
        var showTimeout: TimeInterval = 2.0
        var fadeIn: TimeInterval = 0.25
        var fadeOut: TimeInterval = 0.2
        var pingInterval: TimeInterval = 1.0
        /// Столько страница может не отвечать на пинг, прежде чем её закроют как зависшую.
        var hangTimeout: TimeInterval = 3.0
    }

    let content: PrankContent
    var payloadID: String { content.payload.id }

    var onShown: (() -> Void)?
    var onMessage: ((Any) -> Void)?
    var onFinish: ((Outcome) -> Void)?

    private let config: PrankConfig
    private let timing: Timing
    private let tiltSource: any PrankTiltSource
    private var window: PrankOverlayWindow?
    private var webView: WKWebView?
    private var schemeHandler: PrankSchemeHandler?

    private enum State { case idle, loading, showing, closing, finished }
    private var state: State = .idle

    private var showDeadline: Timer?
    private var durationTimer: Timer?
    private var pingTimer: Timer?
    private var lastPong = Date()
    private var tiltLink: CADisplayLink?
    private var tiltInFlight = false
    private var lastSentTilt: PrankTilt?

    private let shouldDismiss: (CGPoint) -> Bool

    init(
        content: PrankContent,
        config: PrankConfig,
        tiltSource: any PrankTiltSource,
        timing: Timing = Timing(),
        shouldDismiss: @escaping (CGPoint) -> Bool = { _ in true }
    ) {
        self.shouldDismiss = shouldDismiss
        self.content = content
        self.config = config
        self.tiltSource = tiltSource
        self.timing = timing
    }

    // MARK: Жизненный цикл

    func start(in scene: UIWindowScene) {
        guard state == .idle else { return }
        state = .loading

        let payload = content.payload
        let handler = PrankSchemeHandler(content: {
            switch content.source {
            case .inline: .payload(payload)
            case .directory(let url): .directory(url)
            }
        }())
        schemeHandler = handler

        let configuration = WKWebViewConfiguration()
        // Как в продукте: каждый показ с нуля, ничего не сохраняется между запусками.
        configuration.websiteDataStore = .nonPersistent()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.setURLSchemeHandler(handler, forURLScheme: PrankSchemeHandler.scheme)
        configuration.userContentController.addUserScript(BridgeScript.userScript)
        configuration.userContentController.add(WeakScriptMessageHandler(self), name: BridgeScript.handlerName)

        let webView = WKWebView(frame: scene.coordinateSpace.bounds, configuration: configuration)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isOpaque = payload.background == .opaque
        webView.backgroundColor = payload.background == .opaque ? .systemBackground : .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        // Касания обрабатывает окно оверлея: страница их не получает.
        webView.isUserInteractionEnabled = false
        #if DEBUG
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        #endif
        self.webView = webView

        let root = PrankOverlayViewController()
        root.dimColor = payload.background == .dim ? UIColor.black.withAlphaComponent(0.3) : .clear
        root.view.addSubview(webView)
        webView.frame = root.view.bounds

        let window = PrankOverlayWindow(windowScene: scene)
        window.rootViewController = root
        window.alpha = 0
        window.onTouch = { [weak self] point in
            guard let self, self.content.payload.dismissible, self.shouldDismiss(point) else { return }
            self.close(.dismiss)
        }
        window.isHidden = false
        self.window = window

        showDeadline = Timer.scheduledTimer(withTimeInterval: timing.showTimeout, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.fail(.timeout) }
        }
        let entry = content.source == .inline ? PrankSchemeHandler.entryURL : PrankSchemeHandler.entryURL(for: content.entry)
        webView.load(URLRequest(url: entry))
    }

    /// Закрыть показ. Повторные вызовы безопасны.
    func close(_ reason: PrankHideReason) {
        finish(.hidden(reason))
    }

    private func fail(_ error: PrankError) {
        finish(.failed(error))
    }

    private func finish(_ outcome: Outcome) {
        guard state != .closing, state != .finished else { return }
        let wasVisible = state == .showing
        state = .closing
        stopTimers()

        if let webView, case .hidden(let reason) = outcome {
            webView.callAsyncJavaScript(
                BridgeScript.callHide,
                arguments: ["payloadID": payloadID, "reason": reason.rawValue],
                in: nil, in: .page, completionHandler: nil
            )
        }
        onFinish?(outcome)
        onFinish = nil

        let teardown = { [weak self] in self?.teardown() }
        if wasVisible, let window {
            UIView.animate(withDuration: timing.fadeOut, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
                window.alpha = 0
            } completion: { _ in
                MainActor.assumeIsolated { teardown() }
            }
        } else {
            teardown()
        }
    }

    private func teardown() {
        guard state != .finished else { return }
        state = .finished
        if let webView {
            webView.stopLoading()
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
            webView.configuration.userContentController.removeScriptMessageHandler(forName: BridgeScript.handlerName)
            webView.removeFromSuperview()
        }
        webView = nil
        schemeHandler = nil
        window?.onTouch = nil
        window?.isHidden = true
        window = nil
    }

    // MARK: Показ

    private func pageDidLoad() {
        guard state == .loading, let webView else { return }
        let configJSON: [String: Any] = {
            var result: [String: Any] = ["version": PrankConfig.supportedVersion, "enabled": config.enabled]
            if let trigger = config.trigger {
                var triggerJSON: [String: Any] = ["on": trigger.on.rawValue, "payload_id": trigger.payloadID]
                triggerJSON["delay_ms"] = trigger.delayMs
                result["trigger"] = triggerJSON
            }
            return result
        }()

        webView.callAsyncJavaScript(BridgeScript.callInit, arguments: ["config": configJSON], in: nil, in: .page) { [weak self] result in
            MainActor.assumeIsolated {
                guard let self, self.state == .loading else { return }
                if case .failure(let error) = result {
                    self.fail(.internalError("PrankBridge.init: \(error.localizedDescription)"))
                    return
                }
                self.callShow()
            }
        }
    }

    private func callShow() {
        guard let webView else { return }
        webView.callAsyncJavaScript(
            BridgeScript.callShow, arguments: ["payload": content.payload.metadataJSON], in: nil, in: .page
        ) { [weak self] result in
            MainActor.assumeIsolated {
                guard let self, self.state == .loading else { return }
                switch result {
                case .success: self.didShow()
                case .failure(let error): self.fail(Self.showError(from: error))
                }
            }
        }
    }

    private func didShow() {
        state = .showing
        showDeadline?.invalidate()
        showDeadline = nil
        UIView.animate(withDuration: timing.fadeIn, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            self.window?.alpha = 1
        }
        let duration = TimeInterval(content.payload.durationMs) / 1000
        durationTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.close(.timeout) }
        }
        startWatchdog()
        startTilt()
        onShown?()
    }

    /// `show()` на странице реджектится `{ code, message }` — переводим в ошибки контракта.
    private static func showError(from error: Error) -> PrankError {
        let text = (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String ?? error.localizedDescription
        if text.contains("INVALID_PAYLOAD") { return .invalidPayload(text) }
        if text.contains("NOT_SUPPORTED") { return .notSupported(text) }
        if text.contains("TIMEOUT") { return .timeout }
        return .internalError("PrankBridge.show: \(text)")
    }

    // MARK: Сторож зависаний

    private func startWatchdog() {
        lastPong = Date()
        pingTimer = Timer.scheduledTimer(withTimeInterval: timing.pingInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.ping() }
        }
    }

    private func ping() {
        guard state == .showing, let webView else { return }
        if Date().timeIntervalSince(lastPong) > timing.hangTimeout {
            fail(.hung)
            return
        }
        webView.evaluateJavaScript(BridgeScript.ping) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.lastPong = Date() }
        }
    }

    // MARK: Наклон

    private func startTilt() {
        tiltSource.start()
        let link = CADisplayLink(target: DisplayLinkProxy(self), selector: #selector(DisplayLinkProxy.tick))
        if #available(iOS 15.0, *) {
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        }
        link.add(to: .main, forMode: .common)
        tiltLink = link
    }

    fileprivate func sendTilt() {
        guard state == .showing, let webView, !tiltInFlight else { return }
        let tilt = tiltSource.current
        guard tilt != lastSentTilt else { return }
        lastSentTilt = tilt
        tiltInFlight = true
        webView.evaluateJavaScript(BridgeScript.tilt(x: tilt.x, y: tilt.y)) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.tiltInFlight = false }
        }
    }

    private func stopTimers() {
        showDeadline?.invalidate()
        durationTimer?.invalidate()
        pingTimer?.invalidate()
        tiltLink?.invalidate()
        showDeadline = nil
        durationTimer = nil
        pingTimer = nil
        tiltLink = nil
        tiltSource.stop()
    }
}

// MARK: - WebKit

extension PrankPresenter: WKScriptMessageHandler {
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == BridgeScript.handlerName, state == .loading || state == .showing else { return }
        onMessage?(message.body)
    }
}

extension PrankPresenter: WKNavigationDelegate, WKUIDelegate {

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        // Только своя схема: никаких переходов наружу, ссылок и сторонних ресурсов в главном фрейме.
        let scheme = navigationAction.request.url?.scheme?.lowercased()
        decisionHandler(scheme == PrankSchemeHandler.scheme || scheme == "about" ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageDidLoad()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail(.contentUnavailable(error.localizedDescription))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        fail(.contentUnavailable(error.localizedDescription))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        fail(.webContentCrashed)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        nil
    }

    // Алерты и диалоги со страницы прикола не показываем: они блокировали бы ввод.
    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor () -> Void
    ) {
        completionHandler()
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor (Bool) -> Void
    ) {
        completionHandler(false)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor (String?) -> Void
    ) {
        completionHandler(nil)
    }
}

/// `CADisplayLink` держит свою цель сильно — прокси разрывает цикл.
private final class DisplayLinkProxy: NSObject {
    private weak var presenter: PrankPresenter?

    init(_ presenter: PrankPresenter) {
        self.presenter = presenter
    }

    @MainActor @objc func tick() {
        presenter?.sendTilt()
    }
}
