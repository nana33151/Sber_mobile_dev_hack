import CoreMotion
import Foundation

/// Наклон телефона в долях g: `x` — вправо, `y` — вниз по экрану, оба в диапазоне −1…1.
public struct PrankTilt: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public static let zero = PrankTilt(x: 0, y: 0)

    public init(x: Double, y: Double) {
        self.x = max(-1, min(1, x))
        self.y = max(-1, min(1, y))
    }
}

/// Откуда берётся наклон. Страница сама датчики не читает: в WKWebView для этого нужен
/// `DeviceMotionEvent.requestPermission()` по жесту пользователя, а касание закрывает прикол.
@MainActor
public protocol PrankTiltSource: AnyObject {
    var current: PrankTilt { get }
    func start()
    func stop()
}

/// Наклон из CoreMotion. Разрешений не требует. Датчик работает только пока виден прикол.
@MainActor
public final class MotionTiltSource: PrankTiltSource {

    public private(set) var current: PrankTilt = .zero

    private let manager = CMMotionManager()
    private let smoothing: Double

    /// - Parameter smoothing: доля нового значения в фильтре (0…1). Меньше — плавнее.
    public init(smoothing: Double = 0.35) {
        self.smoothing = smoothing
    }

    public var isAvailable: Bool { manager.isDeviceMotionAvailable }

    public func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        current = .zero
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            MainActor.assumeIsolated {
                self?.update(gravity: motion.gravity)
            }
        }
    }

    public func stop() {
        manager.stopDeviceMotionUpdates()
    }

    private func update(gravity: CMAcceleration) {
        // Гравитация в осях устройства: y направлен вверх по экрану, поэтому для экрана инвертируем.
        let target = PrankTilt(x: gravity.x, y: -gravity.y)
        current = PrankTilt(
            x: current.x + (target.x - current.x) * smoothing,
            y: current.y + (target.y - current.y) * smoothing
        )
    }
}

/// Наклон, который задают руками: клавиатура Mac в симуляторе, джойстик в демо, тесты.
@MainActor
public final class ManualTiltSource: PrankTiltSource {
    public var current: PrankTilt = .zero

    public init() {}

    public func set(_ tilt: PrankTilt) {
        current = tilt
    }

    public func start() {}
    public func stop() {}
}
