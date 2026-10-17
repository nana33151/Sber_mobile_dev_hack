import Foundation

/// PrankConfig из `contract/config_schema.json`.
public struct PrankConfig: Equatable, Sendable {

    public enum TriggerKind: String, Sendable, CaseIterable {
        case tap, shake, delay, manual
    }

    public struct Trigger: Equatable, Sendable {
        public let on: TriggerKind
        public let payloadID: String
        public let delayMs: Int?

        public init(on: TriggerKind, payloadID: String, delayMs: Int? = nil) {
            self.on = on
            self.payloadID = payloadID
            self.delayMs = delayMs
        }
    }

    public static let supportedVersion = "1"

    /// Конфиг, который ничего не показывает. Используется, когда настоящий конфиг пустой или битый.
    public static let disabled = PrankConfig(enabled: false, trigger: nil)

    public let enabled: Bool
    public let trigger: Trigger?

    public init(enabled: Bool = true, trigger: Trigger?) {
        self.enabled = enabled
        self.trigger = trigger
    }

    /// Разбирает JSON по схеме. Любое несоответствие схеме — ошибка, а не падение.
    public static func decode(_ data: Data) throws(ContractError) -> PrankConfig {
        let object = try JSONObject.parse(data)
        try object.requireOnlyKeys(["version", "enabled", "trigger"])
        guard object["version"] as? String == supportedVersion else {
            throw .invalid("version должен быть \"\(supportedVersion)\"")
        }
        let enabled = try object.optionalBool("enabled") ?? true

        var trigger: Trigger?
        if let raw = object["trigger"] {
            guard let triggerObject = raw as? [String: Any] else {
                throw .invalid("trigger должен быть объектом")
            }
            try triggerObject.requireOnlyKeys(["on", "payload_id", "delay_ms"])
            guard let kindRaw = triggerObject["on"] as? String, let kind = TriggerKind(rawValue: kindRaw) else {
                throw .invalid("trigger.on должен быть одним из \(TriggerKind.allCases.map(\.rawValue))")
            }
            guard let payloadID = triggerObject["payload_id"] as? String, !payloadID.isEmpty else {
                throw .invalid("trigger.payload_id обязателен")
            }
            let delayMs = try triggerObject.optionalInt("delay_ms")
            if let delayMs, !(0...60_000).contains(delayMs) {
                throw .invalid("trigger.delay_ms вне диапазона 0…60000")
            }
            trigger = Trigger(on: kind, payloadID: payloadID, delayMs: delayMs)
        }
        return PrankConfig(enabled: enabled, trigger: trigger)
    }
}
