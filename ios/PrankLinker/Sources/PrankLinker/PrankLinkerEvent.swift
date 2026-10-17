import Foundation

/// Почему оверлей закрылся. Первые три значения — из контракта (`hidden.reason`).
public enum PrankHideReason: String, Sendable {
    /// Истёк `duration_ms`.
    case timeout
    /// Пользователь коснулся экрана.
    case dismiss
    /// Закрыло приложение или сама страница (`CLOSE_EVENT`).
    case manual
    /// Закрыто линкером из-за сбоя страницы. В контракте нет — только для приложения.
    case failure
}

/// Ошибка показа. Коды совпадают с контрактом, `crashed` и `hung` — нативные причины `INTERNAL`.
public enum PrankError: Error, Equatable, Sendable {
    case invalidPayload(String)
    case notSupported(String)
    case timeout
    case contentUnavailable(String)
    case webContentCrashed
    case hung
    case internalError(String)

    /// Код из `PrankEngine_Bridge_v1.md`.
    public var code: String {
        switch self {
        case .invalidPayload: "INVALID_PAYLOAD"
        case .notSupported: "NOT_SUPPORTED"
        case .timeout: "TIMEOUT"
        case .contentUnavailable, .webContentCrashed, .hung, .internalError: "INTERNAL"
        }
    }

    public var message: String {
        switch self {
        case .invalidPayload(let reason): "Payload не прошёл схему: \(reason)"
        case .notSupported(let reason): reason
        case .timeout: "Первый кадр не отрисован за 2000 мс"
        case .contentUnavailable(let reason): "Контент недоступен: \(reason)"
        case .webContentCrashed: "Процесс WebView завершился"
        case .hung: "Страница не отвечает"
        case .internalError(let reason): reason
        }
    }
}

/// Почему триггер не привёл к показу.
public enum PrankSkipReason: String, Sendable {
    case disabled = "приколы выключены конфигом"
    case forbiddenScreen = "экран запрещает приколы"
    case cooldown = "пауза после прошлого показа"
    case busy = "прикол уже показывается"
    case wrongTrigger = "конфиг ждёт другой триггер"
    case circuitOpen = "слишком много сбоев, приколы выключены до перезапуска"
    case notConfigured = "конфиг ещё не загружен"
}

/// Всё, что линкер сообщает приложению. Один поток событий — удобно и для логики, и для лога.
public enum PrankLinkerEvent: Sendable, Equatable {
    case configLoaded(PrankConfig)
    case configRejected(String)
    case triggered(PrankConfig.TriggerKind, payloadID: String)
    case skipped(PrankSkipReason)
    case shown(payloadID: String)
    case hidden(payloadID: String, reason: PrankHideReason)
    case action(payloadID: String, action: String)
    /// Показ прерван сбоем — оверлей уже убран.
    case failed(payloadID: String?, PrankError)
    /// Страница сообщила об ошибке или бросила исключение, но продолжает работать.
    case pageError(payloadID: String, code: String, message: String)
    /// Событие канала хакатона: приложение решает, засчитать ли прогресс, показать ли шеринг.
    case finished(payloadID: String)
    case completed(payloadID: String)
    case shareRequested(payloadID: String, text: String?, image: String?)
    /// Игра не запустилась, вместо неё играет нативная анимация (`Options.launchFailureAnimation`).
    case fallbackShown(payloadID: String?)
    case fallbackFinished(payloadID: String?)
    /// Сообщение страницы, которое не удалось разобрать. Показ не прерывает.
    case ignoredMessage(String)
}

@MainActor
public protocol PrankLinkerDelegate: AnyObject {
    func prankLinker(_ linker: PrankLinker, didEmit event: PrankLinkerEvent)
}
