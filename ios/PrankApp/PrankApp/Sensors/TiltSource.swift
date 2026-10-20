import CoreMotion
import Foundation

/// Наклон телефона для управления клубками. Страница сама датчики не читает:
/// в WKWebView DeviceOrientation требует жест пользователя.
final class TiltSource {
    private let manager = CMMotionManager()
    private var baseline: (pitch: Double, roll: Double)?
    /// Нормализованный наклон −1…1 (x = влево/вправо, y = вперёд/назад).
    var onTilt: ((Double, Double) -> Void)?

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        baseline = nil
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let attitude = motion?.attitude else { return }
            let pitch = attitude.pitch
            let roll = attitude.roll

            if self.baseline == nil {
                self.baseline = (pitch, roll)
                self.onTilt?(0, 0)
                return
            }

            let base = self.baseline!
            // ~45° → полный наклон
            let x = (roll - base.roll) / (Double.pi / 4)
            let y = (pitch - base.pitch) / (Double.pi / 4)
            self.onTilt?(
                max(-1, min(1, x)),
                max(-1, min(1, y))
            )
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        baseline = nil
    }

    func recalibrate() {
        baseline = nil
    }
}
