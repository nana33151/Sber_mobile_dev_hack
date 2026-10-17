import PrankLinker
import UIKit

/// Главное окно приложения. Ровно то, что нужно добавить в UIWindow СберKids:
/// переслать `motionShake` в линкер. Остальное — удобства для демо в симуляторе.
final class DemoHostWindow: UIWindow {

    weak var linker: PrankLinker?
    weak var tilt: ManualTiltSource?

    private var pressedKeys: Set<UIKeyboardHIDUsage> = []

    // В СберKids: единственная строка интеграции в окне.
    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        linker?.handleShakeMotion(motion)
        super.motionEnded(motion, with: event)
    }

    // MARK: Демо: наклон стрелками / WASD с клавиатуры Mac в симуляторе

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let handled = update(presses, pressed: true)
        if !handled { super.pressesBegan(presses, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let handled = update(presses, pressed: false)
        if !handled { super.pressesEnded(presses, with: event) }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let handled = update(presses, pressed: false)
        if !handled { super.pressesCancelled(presses, with: event) }
    }

    private static let tiltKeys: Set<UIKeyboardHIDUsage> = [
        .keyboardUpArrow, .keyboardDownArrow, .keyboardLeftArrow, .keyboardRightArrow,
        .keyboardW, .keyboardA, .keyboardS, .keyboardD
    ]

    private func update(_ presses: Set<UIPress>, pressed: Bool) -> Bool {
        let codes = presses.compactMap { $0.key?.keyCode }.filter(Self.tiltKeys.contains)
        guard !codes.isEmpty, let tilt else { return false }
        if pressed { pressedKeys.formUnion(codes) } else { pressedKeys.subtract(codes) }

        func any(_ keys: UIKeyboardHIDUsage...) -> Double { keys.contains(where: pressedKeys.contains) ? 1 : 0 }
        let x = any(.keyboardRightArrow, .keyboardD) - any(.keyboardLeftArrow, .keyboardA)
        let y = any(.keyboardDownArrow, .keyboardS) - any(.keyboardUpArrow, .keyboardW)
        tilt.set(PrankTilt(x: x * 0.7, y: y * 0.7))
        return true
    }
}
