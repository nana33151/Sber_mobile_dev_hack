import PrankLinker
import SwiftUI
import UIKit

/// Связывает демо-интерфейс с линкером: лог событий, тосты, шеринг.
/// В СберKids на этом месте — существующие реакции приложения.
@MainActor
final class DemoController: ObservableObject, PrankLinkerDelegate {

    struct LogEntry: Identifiable {
        let id = UUID()
        let time = Date()
        let text: String
        let isProblem: Bool
    }

    let linker: PrankLinker
    /// Наклон с клавиатуры и джойстика — только в симуляторе. На телефоне работает CoreMotion.
    let manualTilt: ManualTiltSource?

    @Published private(set) var log: [LogEntry] = []
    @Published private(set) var toast: String?
    @Published var dismissesOnTouch = true {
        didSet { linker.options.dismissesOnTouch = dismissesOnTouch }
    }

    var presenterProvider: (() -> UIViewController?)?

    static let payloadIDs = ["cats_yarn", "crash_throw", "crash_hang", "crash_slow", "crash_escape", "crash_error", "crash_invalid"]

    init() {
        let root = Bundle.main.url(forResource: "Pranks", withExtension: nil) ?? Bundle.main.bundleURL
        #if targetEnvironment(simulator)
        let manual = ManualTiltSource()
        manualTilt = manual
        linker = PrankLinker(content: DirectoryContentProvider(root: root), tiltSource: manual)
        #else
        manualTilt = nil
        linker = PrankLinker(content: DirectoryContentProvider(root: root))
        #endif
        linker.delegate = self
        // Демо-режим для жюри: `-prankDemo YES` в схеме — прикол не закрывается касанием,
        // чтобы наклоном можно было управлять джойстиком на экране.
        if UserDefaults.standard.bool(forKey: "prankDemo") {
            dismissesOnTouch = false
            linker.options.dismissesOnTouch = false
        }
    }

    var isSimulator: Bool { manualTilt != nil }

    func clearLog() {
        log.removeAll()
    }

    // MARK: PrankLinkerDelegate

    func prankLinker(_ linker: PrankLinker, didEmit event: PrankLinkerEvent) {
        switch event {
        case .configLoaded(let config):
            append("Конфиг: \(config.enabled ? "включён" : "выключен"), триггер \(config.trigger.map { "\($0.on.rawValue) → \($0.payloadID)" } ?? "нет")")
        case .configRejected(let reason):
            append("Конфиг отклонён: \(reason)", problem: true)
        case .triggered(let kind, let payloadID):
            append("Триггер \(kind.rawValue) → \(payloadID)")
        case .skipped(let reason):
            append("Пропуск: \(reason.rawValue)")
        case .shown(let payloadID):
            append("Показан \(payloadID)")
        case .hidden(let payloadID, let reason):
            append("Скрыт \(payloadID): \(reason.rawValue)")
        case .action(let payloadID, let action):
            append("Действие \(payloadID): \(action)")
        case .failed(let payloadID, let error):
            append("Сбой \(payloadID ?? "—"): \(error.code) · \(error.message)", problem: true)
            show(toast: "Прикол не удался — приложение работает дальше")
        case .pageError(let payloadID, let code, let message):
            append("Ошибка страницы \(payloadID): \(code) · \(message)", problem: true)
        case .finished(let payloadID):
            append("FINISH \(payloadID)")
        case .completed(let payloadID):
            append("COMPLETED \(payloadID)")
            show(toast: "Котики довольны!")
        case .shareRequested(_, let text, let image):
            append("Поделиться: \(text ?? "") \(image == nil ? "" : "+ картинка")")
            share(text: text, image: image)
        case .ignoredMessage(let reason):
            append("Сообщение проигнорировано: \(reason)", problem: true)
        }
    }

    private func append(_ text: String, problem: Bool = false) {
        log.insert(LogEntry(text: text, isProblem: problem), at: 0)
        if log.count > 200 { log.removeLast() }
    }

    private func show(toast text: String) {
        toast = text
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if toast == text { toast = nil }
        }
    }

    private func share(text: String?, image: String?) {
        var items: [Any] = []
        if let text { items.append(text) }
        if let image, let comma = image.firstIndex(of: ","), image.hasPrefix("data:"),
           let data = Data(base64Encoded: String(image[image.index(after: comma)...])),
           let picture = UIImage(data: data) {
            items.append(picture)
        }
        guard !items.isEmpty, let presenter = presenterProvider?() else { return }
        presenter.present(UIActivityViewController(activityItems: items, applicationActivities: nil), animated: true)
    }
}
