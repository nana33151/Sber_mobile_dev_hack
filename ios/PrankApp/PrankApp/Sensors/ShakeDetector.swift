import CoreMotion
import Foundation

/// Детектор тряски по ускорению. Триггерит показ оверлея.
final class ShakeDetector {
    private let manager = CMMotionManager()
    private let queue = OperationQueue()
    private var lastFire = Date.distantPast
    private let cooldown: TimeInterval
    private let threshold: Double
    var onShake: (() -> Void)?

    init(threshold: Double = 2.7, cooldown: TimeInterval = 1.5) {
        self.threshold = threshold
        self.cooldown = cooldown
        queue.name = "prank.shake"
        queue.maxConcurrentOperationCount = 1
    }

    var isAvailable: Bool { manager.isAccelerometerAvailable }

    func start() {
        guard manager.isAccelerometerAvailable, !manager.isAccelerometerActive else { return }
        manager.accelerometerUpdateInterval = 1.0 / 50.0
        manager.startAccelerometerUpdates(to: queue) { [weak self] data, _ in
            guard let self, let data else { return }
            let a = data.acceleration
            let magnitude = sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
            guard magnitude >= self.threshold else { return }
            let now = Date()
            guard now.timeIntervalSince(self.lastFire) >= self.cooldown else { return }
            self.lastFire = now
            DispatchQueue.main.async { self.onShake?() }
        }
    }

    func stop() {
        manager.stopAccelerometerUpdates()
    }
}
