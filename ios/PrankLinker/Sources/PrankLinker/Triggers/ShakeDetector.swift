import CoreMotion
import UIKit

/// Распознаёт тряску по акселерометру: несколько резких рывков за короткое время.
/// Дополняет системный `motionShake`, который приходит только в key window приложения
/// и только когда первый респондер его не перехватил.
@MainActor
final class ShakeDetector {

    struct Tuning {
        /// Порог рывка в g (без гравитации).
        var threshold: Double = 1.8
        /// Сколько рывков нужно…
        var requiredPeaks = 3
        /// …за это время.
        var window: TimeInterval = 0.8
    }

    var onShake: (() -> Void)?

    private let manager = CMMotionManager()
    private let tuning: Tuning
    private var peaks: [TimeInterval] = []
    private var wasAbove = false

    init(tuning: Tuning = Tuning()) {
        self.tuning = tuning
    }

    var isRunning: Bool { manager.isDeviceMotionActive }

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            MainActor.assumeIsolated {
                self?.process(motion.userAcceleration, at: motion.timestamp)
            }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        peaks.removeAll()
        wasAbove = false
    }

    private func process(_ acceleration: CMAcceleration, at time: TimeInterval) {
        let magnitude = (acceleration.x * acceleration.x + acceleration.y * acceleration.y + acceleration.z * acceleration.z).squareRoot()
        let isAbove = magnitude > tuning.threshold
        defer { wasAbove = isAbove }
        guard isAbove, !wasAbove else { return }

        peaks.append(time)
        peaks.removeAll { time - $0 > tuning.window }
        if peaks.count >= tuning.requiredPeaks {
            peaks.removeAll()
            onShake?()
        }
    }
}
