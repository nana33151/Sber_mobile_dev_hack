import Foundation

/// Выключает приколы до перезапуска приложения, если страница раз за разом падает.
/// Успешный показ сбрасывает счётчик.
struct CircuitBreaker: Equatable {
    let maxConsecutiveFailures: Int
    private(set) var consecutiveFailures = 0

    init(maxConsecutiveFailures: Int = 3) {
        self.maxConsecutiveFailures = maxConsecutiveFailures
    }

    var isOpen: Bool { consecutiveFailures >= maxConsecutiveFailures }

    mutating func recordSuccess() {
        consecutiveFailures = 0
    }

    mutating func recordFailure() {
        consecutiveFailures += 1
    }
}

/// Пауза между показами, чтобы прикол не перезапускался от каждого движения телефона.
struct Cooldown: Equatable {
    let interval: TimeInterval
    private(set) var lastEnd: Date?

    init(interval: TimeInterval) {
        self.interval = interval
    }

    func isActive(now: Date = Date()) -> Bool {
        guard let lastEnd else { return false }
        return now.timeIntervalSince(lastEnd) < interval
    }

    mutating func start(now: Date = Date()) {
        lastEnd = now
    }
}
