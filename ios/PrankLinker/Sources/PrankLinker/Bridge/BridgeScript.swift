import WebKit

/// JS-часть линкера. Встраивается до загрузки страницы прикола.
///
/// Страница → приложение: `window.postMessage(...)` и необработанные ошибки JS.
/// Приложение → страница: `window.__prankNative.*`, через него линкер вызывает
/// `window.PrankBridge.init/show/hide` из контракта и передаёт наклон телефона.
enum BridgeScript {

    static let handlerName = "prankLinker"
    /// Канал, которым шлёт события сама игра: `webkit.messageHandlers.prankBridge.postMessage(json)`.
    static let gameHandlerName = "prankBridge"

    /// Прозрачный оверлей: фон страницы и всё, кроме canvas (например, заглушка «экран приложения»
    /// для превью в браузере), не рисуем — под игрой должно быть видно приложение.
    @MainActor static var transparentOverlayStyle: WKUserScript {
        WKUserScript(source: """
        (function () {
          var style = document.createElement('style');
          style.textContent = 'html, body { background: transparent !important; } ' +
            'body > :not(canvas):not(script):not(style) { display: none !important; }';
          (document.head || document.documentElement).appendChild(style);
        })();
        """, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }

    @MainActor static var userScript: WKUserScript {
        WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    }

    /// Вызывается через `callAsyncJavaScript`: аргументы приходят как переменные `config`, `payload`.
    static let callInit = "return await window.__prankNative.init(config);"
    static let callShow = "return await window.__prankNative.show(payload);"
    static let callHide = "window.__prankNative.hide(payloadID, reason); return true;"
    static let ping = "window.__prankNative ? 1 : 0"

    static func tilt(x: Double, y: Double) -> String {
        "window.__prankNative&&window.__prankNative.tilt(\(x.jsNumber),\(y.jsNumber))"
    }

    private static let source = """
    (function () {
      if (window.__prankNative) { return; }
      var handler = window.webkit.messageHandlers.\(handlerName);
      function send(body) {
        try { handler.postMessage(body); }
        catch (e) { try { handler.postMessage(JSON.stringify(body)); } catch (_) {} }
      }
      window.addEventListener('message', function (event) {
        if (event.source === window) { send(event.data); }
      });
      window.addEventListener('error', function (event) {
        var target = event.target;
        if (target && target !== window && (target.src || target.href)) {
          // Не загрузился ресурс страницы: скрипт, модуль, картинка, стиль.
          send({ event: 'error', code: 'RESOURCE', message: 'Не загрузился ' + (target.src || target.href) });
          return;
        }
        send({ event: 'error', code: 'INTERNAL', message: String(event.message || 'Script error') });
      }, true);
      var originalConsoleError = console.error;
      console.error = function () {
        try {
          var text = Array.prototype.map.call(arguments, function (item) {
            return item && item.message ? item.message : String(item);
          }).join(' ');
          send({ event: 'error', code: 'CONSOLE', message: text });
        } catch (_) {}
        return originalConsoleError.apply(console, arguments);
      };
      window.addEventListener('unhandledrejection', function (event) {
        var reason = event.reason;
        send({ event: 'error', code: 'INTERNAL', message: String((reason && reason.message) || reason || 'Unhandled rejection') });
      });
      window.open = function () { return null; };

      function nextFrame() {
        return new Promise(function (resolve) {
          requestAnimationFrame(function () { requestAnimationFrame(resolve); });
        });
      }
      function bridge() { return window.PrankBridge; }
      // Модули (<script type="module">) могут выполниться позже, чем приложение позовёт init:
      // ждём объявления PrankBridge, но не дольше таймаута показа.
      function waitForBridge(timeoutMs) {
        return new Promise(function (resolve) {
          if (bridge()) { resolve(bridge()); return; }
          var started = Date.now();
          var timer = setInterval(function () {
            if (bridge() || Date.now() - started > timeoutMs) {
              clearInterval(timer);
              resolve(bridge());
            }
          }, 25);
        });
      }

      window.PrankTilt = { x: 0, y: 0 };
      window.__prankNative = {
        init: async function (config) {
          var b = await waitForBridge(1500);
          if (!b) {
            var scripts = Array.prototype.map.call(document.scripts, function (item) {
              return (item.type || 'classic') + ':' + (item.src || 'inline');
            }).join(', ');
            send({ event: 'error', code: 'NO_BRIDGE', message: 'window.PrankBridge не объявлен при init. ' + location.href + ' скрипты: ' + scripts });
          }
          if (b && typeof b.init === 'function') { await b.init(config); }
          return true;
        },
        show: async function (payload) {
          var b = await waitForBridge(200);
          if (b && typeof b.show === 'function') { await b.show(payload); }
          else { await nextFrame(); }
          return true;
        },
        hide: function (payloadID, reason) {
          var b = bridge();
          try { if (b && typeof b.hide === 'function') { b.hide(payloadID || undefined); } } catch (_) {}
          try { window.dispatchEvent(new CustomEvent('prank:hide', { detail: { reason: reason } })); } catch (_) {}
        },
        // Наклон: x вправо, y вниз, в долях g (-1…1). Нативная сторона шлёт ~60 раз в секунду.
        // Дублируем стандартным `deviceorientation` (gamma/beta в градусах): игры, написанные под браузер,
        // работают без изменений, а системный запрос разрешения на датчики не нужен.
        tilt: function (x, y) {
          window.PrankTilt.x = x; window.PrankTilt.y = y;
          window.dispatchEvent(new CustomEvent('prank:tilt', { detail: { x: x, y: y } }));
          var gamma = Math.asin(Math.max(-1, Math.min(1, x))) * 180 / Math.PI;
          var beta = Math.asin(Math.max(-1, Math.min(1, y))) * 180 / Math.PI;
          var orientation;
          try {
            orientation = new DeviceOrientationEvent('deviceorientation', { alpha: 0, beta: beta, gamma: gamma, absolute: false });
          } catch (_) {
            orientation = new Event('deviceorientation');
            Object.defineProperty(orientation, 'alpha', { value: 0 });
            Object.defineProperty(orientation, 'beta', { value: beta });
            Object.defineProperty(orientation, 'gamma', { value: gamma });
          }
          window.dispatchEvent(orientation);
        }
      };
    })();
    """
}

private extension Double {
    /// `evaluateJavaScript` не переварит `nan` или `inf`.
    var jsNumber: String {
        isFinite ? String(format: "%.4f", self) : "0"
    }
}

/// Не даёт `WKUserContentController` удерживать линкер.
final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var delegate: WKScriptMessageHandler?

    init(_ delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(controller, didReceive: message)
    }
}
