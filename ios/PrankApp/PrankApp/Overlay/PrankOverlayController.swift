import UIKit
import WebKit

/// Полноэкранный прозрачный WKWebView-оверлей с игрой.
final class PrankOverlayController: UIViewController, WKNavigationDelegate {
    private var webView: WKWebView!
    private let bridge = PrankWebBridge()
    private let tilt = TiltSource()
    private var schemeHandler: PrankSchemeHandler!
    private var isShowing = false
    private var pageReady = false

    var onHidden: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        setupWebView()
        bridge.onEvent = { [weak self] event, data in
            self?.handleBridgeEvent(event, data: data)
        }
    }

    private func setupWebView() {
        guard let webRoot = Bundle.main.resourceURL?.appendingPathComponent("Web", isDirectory: true) else {
            assertionFailure("Web bundle missing — run scripts/sync-web-to-ios.sh")
            return
        }

        schemeHandler = PrankSchemeHandler(webRoot: webRoot)

        let userContent = WKUserContentController()
        userContent.add(bridge, name: PrankWebBridge.handlerName)

        let config = WKWebViewConfiguration()
        config.userContentController = userContent
        config.setURLSchemeHandler(schemeHandler, forURLScheme: PrankSchemeHandler.scheme)
        config.allowsInlineMediaPlayback = true
        if #available(iOS 14.0, *) {
            config.defaultWebpagePreferences.allowsContentJavaScript = true
        }

        let wv = WKWebView(frame: view.bounds, configuration: config)
        wv.navigationDelegate = self
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.backgroundColor = .clear
        wv.scrollView.isScrollEnabled = false
        wv.scrollView.bounces = false
        wv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // Клики сквозь canvas (pointer-events: none), но WebView нужен для JS
        wv.isUserInteractionEnabled = false
        view.addSubview(wv)
        webView = wv

        let url = URL(string: "\(PrankSchemeHandler.scheme)://overlay/index.html")!
        wv.load(URLRequest(url: url))
    }

    func showGame() {
        guard !isShowing else { return }
        isShowing = true
        view.isHidden = false
        view.alpha = 1

        tilt.onTilt = { [weak self] x, y in
            self?.pushTilt(x: x, y: y)
        }
        tilt.start()

        let js = """
        (async function() {
          if (!window.PrankBridge) throw new Error('PrankBridge missing');
          await window.PrankBridge.init({ version: '1', enabled: true, trigger: { on: 'shake', payload_id: 'cats_yarn' } });
          await window.PrankBridge.show({ version: '1', id: 'cats_yarn', native_tilt: true });
        })();
        """
        runWhenReady(js)
    }

    func hideGame(reason: String = "manual") {
        guard isShowing else { return }
        isShowing = false
        tilt.stop()
        webView.evaluateJavaScript("window.PrankBridge && window.PrankBridge.hide('cats_yarn');", completionHandler: nil)
        UIView.animate(withDuration: 0.25, animations: {
            self.view.alpha = 0
        }, completion: { _ in
            self.view.isHidden = true
            self.onHidden?()
        })
    }

    private func pushTilt(x: Double, y: Double) {
        guard isShowing else { return }
        // y инвертируем: pitch вперёд → клубки вниз по экрану
        let js = String(format: "window.PrankBridge && window.PrankBridge.setTilt(%.4f, %.4f);", x, y)
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func runWhenReady(_ js: String) {
        if pageReady {
            webView.evaluateJavaScript(js) { _, error in
                if let error { print("[PrankOverlay] JS error: \(error)") }
            }
            return
        }
        // Страница ещё грузится — повторим после didFinish
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.runWhenReady(js)
        }
    }

    private func handleBridgeEvent(_ event: String, data: [String: Any]?) {
        print("[PrankOverlay] event=\(event) data=\(String(describing: data))")
        switch event {
        case "action":
            if let action = data?["action"] as? String, action == "game_won" {
                // Даём доиграть танец (~1.6s) — web уже шлёт после dance-complete
                hideGame(reason: "timeout")
            }
        case "error":
            hideGame(reason: "manual")
        default:
            break
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageReady = true
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("[PrankOverlay] navigation failed: \(error)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("[PrankOverlay] provisional failed: \(error)")
    }

    deinit {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: PrankWebBridge.handlerName)
        tilt.stop()
    }
}
