import Foundation

/// Ошибка разбора конфига или payload. Никогда не приводит к падению — только к отказу показа.
public enum ContractError: Error, Equatable, Sendable {
    case notJSONObject
    case invalid(String)

    public var message: String {
        switch self {
        case .notJSONObject: "Ожидался JSON-объект"
        case .invalid(let reason): reason
        }
    }
}

/// Ручная проверка по JSON-схеме: `additionalProperties: false`, типы и диапазоны.
/// Codable здесь не подходит — он молча пропускает лишние ключи и путает Bool с числами.
enum JSONObject {
    static func parse(_ data: Data) throws(ContractError) -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw .notJSONObject
        }
        return object
    }
}

extension Dictionary where Key == String, Value == Any {

    func requireOnlyKeys(_ allowed: Set<String>) throws(ContractError) {
        let unknown = Set(keys).subtracting(allowed)
        if !unknown.isEmpty {
            throw .invalid("Неизвестные поля: \(unknown.sorted().joined(separator: ", "))")
        }
    }

    func optionalString(_ key: String) throws(ContractError) -> String? {
        guard let value = self[key] else { return nil }
        guard let string = value as? String else { throw .invalid("\(key) должен быть строкой") }
        return string
    }

    func optionalBool(_ key: String) throws(ContractError) -> Bool? {
        guard let value = self[key] else { return nil }
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
            throw .invalid("\(key) должен быть boolean")
        }
        return number.boolValue
    }

    func optionalInt(_ key: String) throws(ContractError) -> Int? {
        guard let value = self[key] else { return nil }
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue == number.doubleValue.rounded() else {
            throw .invalid("\(key) должен быть целым числом")
        }
        return number.intValue
    }
}
