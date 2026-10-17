import Foundation

/// Сообщение со страницы прикола после разбора.
///
/// Принимаются два словаря:
/// - события PrankEngine Bridge v1: `{ event: "shown" | "hidden" | "action" | "error", ... }`;
/// - события канала хакатона «страница → приложение»: `{ type: "CLOSE_EVENT", ... }` —
///   тот же канал, что у игр в WebView, поэтому реакции приложения переиспользуются.
public enum PageMessage: Equatable, Sendable {
    case shown(payloadID: String?)
    case hidden(payloadID: String?)
    case action(payloadID: String?, action: String)
    case error(code: String, message: String)
    case close
    case finish
    case completed
    case vibration
    case sharing(text: String?, image: String?)

    public enum Failure: Error, Equatable, Sendable {
        case notAnObject
        case unknown(String)
        case missingField(String)
    }

    /// Тело может быть объектом или JSON-строкой; поддерживаются обёртки `params` и `data`,
    /// как в песочнице хакатона.
    public static func parse(_ body: Any) -> Result<PageMessage, Failure> {
        guard var object = dictionary(from: body) else { return .failure(.notAnObject) }
        if let nested = object["data"] as? [String: Any], nested["type"] is String || nested["event"] is String {
            object = nested
        }
        let params = object["params"] as? [String: Any] ?? [:]
        func string(_ key: String) -> String? {
            nonEmpty(object[key]) ?? nonEmpty(params[key])
        }

        if let event = string("event") {
            let payloadID = string("payload_id")
            switch event {
            case "shown": return .success(.shown(payloadID: payloadID))
            case "hidden": return .success(.hidden(payloadID: payloadID))
            case "action":
                guard let action = string("action") else { return .failure(.missingField("action")) }
                return .success(.action(payloadID: payloadID, action: action))
            case "error":
                return .success(.error(code: string("code") ?? "INTERNAL", message: string("message") ?? ""))
            default:
                return .failure(.unknown(event))
            }
        }

        guard let type = string("type") else { return .failure(.missingField("type")) }
        switch type {
        case "CLOSE_EVENT": return .success(.close)
        case "FINISH_EVENT": return .success(.finish)
        case "COMPLETED_EVENT": return .success(.completed)
        case "VIBRATION_EVENT": return .success(.vibration)
        case "SHARING_EVENT":
            let text = string("text")
            let image = string("image")
            guard text != nil || image != nil else { return .failure(.missingField("text|image")) }
            return .success(.sharing(text: text, image: image))
        default:
            return .failure(.unknown(type))
        }
    }

    private static func dictionary(from body: Any) -> [String: Any]? {
        if let dictionary = body as? [String: Any] { return dictionary }
        if let string = body as? String, let data = string.data(using: .utf8) {
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
        return nil
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let string = value as? String, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return string
    }
}
