import WebKit

/// Принимает события от `webkit.messageHandlers.prankBridge` (JSON: { event, data }).
final class PrankWebBridge: NSObject, WKScriptMessageHandler {
    var onEvent: ((String, [String: Any]?) -> Void)?

    static let handlerName = "prankBridge"

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == Self.handlerName else { return }

        let payload: [String: Any]?
        if let text = message.body as? String,
           let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            payload = json
        } else if let dict = message.body as? [String: Any] {
            payload = dict
        } else {
            payload = nil
        }

        let event = payload?["event"] as? String ?? "unknown"
        let data = payload?["data"] as? [String: Any]
        onEvent?(event, data)
    }
}
