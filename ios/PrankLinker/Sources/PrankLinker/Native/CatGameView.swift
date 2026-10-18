import UIKit

/// «Котики и клубки» нативно: физика как в `web/src/game-engine.js`, спрайты из того же атласа.
///
/// Наклон катает клубки, котик ловит по два клубка, после чего танцуют все котики.
/// Координаты нормализованы (0…1), коллизии между объектами считаются в долях короткой
/// стороны экрана — круг остаётся кругом и на вытянутом экране.
/// Рисуем слоями `CALayer`: ~12 объектов, без перерисовки битмапов — 60 fps с запасом.
@MainActor
final class CatGameView: UIView {

    /// `cat_caught`, `game_won` — те же действия, что шлёт JS-игра.
    var onAction: ((String) -> Void)?

    private struct Cat {
        let id: Int
        var x: CGFloat
        var y: CGFloat
        var balls = 0
        let layer = CALayer()
    }

    private struct Yarn {
        var x: CGFloat
        var y: CGFloat
        let variant: Int
        var rotation: CGFloat
        var isCaught = false
        let layer = CALayer()
    }

    // Константы из game-engine.js
    private let yarnCatchRadius: CGFloat = 0.06
    private let catCatchRadius: CGFloat = 0.12
    private let yarnBodyRadius: CGFloat = 0.06
    private let catBodyRadius: CGFloat = 0.17
    private let speedPerFrame: CGFloat = 0.012
    private let danceFrameInterval: CFTimeInterval = 0.14

    private let atlas: PrankAtlas
    private let tiltSource: any PrankTiltSource
    private var cats: [Cat] = []
    private var yarns: [Yarn] = []
    private var calibration: CGPoint?
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var danceStartedAt: CFTimeInterval?
    private var isPlaying = false
    private var catHeight: CGFloat = 120
    private var yarnHeight: CGFloat = 46

    init(atlas: PrankAtlas, tiltSource: any PrankTiltSource) {
        self.atlas = atlas
        self.tiltSource = tiltSource
        super.init(frame: .zero)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) не используется")
    }

    // MARK: Жизненный цикл

    func start() {
        layoutIfNeeded()
        generateLevel()
        isPlaying = true
        calibration = nil
        tiltSource.start()
        let link = CADisplayLink(target: GameLinkProxy(self), selector: #selector(GameLinkProxy.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        isPlaying = false
        displayLink?.invalidate()
        displayLink = nil
        tiltSource.stop()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateLayout()
        render()
    }

    // MARK: Уровень

    private func generateLevel() {
        layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        cats = []
        yarns = []

        let catCount = Int.random(in: 3...4) // 3 или 4 котика
        for id in 0..<catCount {
            var spawn = CGPoint.zero
            var attempts = 0
            repeat {
                spawn = CGPoint(x: .random(in: 0.15...0.85), y: .random(in: 0.15...0.85))
                attempts += 1
            } while cats.contains(where: { distance(spawn, CGPoint(x: $0.x, y: $0.y)) < catBodyRadius * 2 }) && attempts < 200
            let cat = Cat(id: id, x: spawn.x, y: spawn.y)
            layer.addSublayer(cat.layer)
            cats.append(cat)
        }

        for _ in 0..<(catCount * 2) { // по 2 клубка на котика
            var spawn = CGPoint.zero
            var attempts = 0
            var blocked = false
            repeat {
                spawn = CGPoint(x: .random(in: 0.1...0.9), y: .random(in: 0.1...0.9))
                blocked = cats.contains { hypot(spawn.x - $0.x, spawn.y - $0.y) < yarnCatchRadius + catCatchRadius }
                    || yarns.contains { distance(spawn, CGPoint(x: $0.x, y: $0.y)) < yarnBodyRadius * 2 }
                attempts += 1
            } while blocked && attempts < 200
            let yarn = Yarn(
                x: spawn.x, y: spawn.y,
                variant: Int.random(in: 0..<atlas.yarns.count),
                rotation: .random(in: 0...(2 * .pi))
            )
            layer.insertSublayer(yarn.layer, at: 0) // клубки под котиками
            yarns.append(yarn)
        }

        for layer in cats.map(\.layer) + yarns.map(\.layer) {
            layer.contentsGravity = .resizeAspect
            layer.contentsScale = UIScreen.main.scale
            layer.actions = ["position": NSNull(), "bounds": NSNull(), "transform": NSNull(), "contents": NSNull()]
        }
        updateLayout()
        render()
    }

    /// Размеры как в `computeLayout` из animation-core.js.
    private func updateLayout() {
        let width = max(bounds.width, 1)
        let height = max(bounds.height, 1)
        let short = min(width, height)
        let columns = CGFloat(max(3, min(4, cats.count)))
        catHeight = min(max(min(width / columns * 0.92, height * 0.24, short * 0.36), 72), 164)
        yarnHeight = min(max(min(short * 0.12, height * 0.085), 28), 58)
    }

    // MARK: Кадр

    fileprivate func step(_ link: CADisplayLink) {
        let now = link.targetTimestamp
        let frames = lastTimestamp == 0 ? 1 : CGFloat(min(max((now - lastTimestamp) * 60, 0), 3))
        lastTimestamp = now

        if let started = danceStartedAt {
            render(danceElapsed: now - started)
            if (now - started) * 1000 >= atlas.danceDurationMs {
                danceStartedAt = nil
                stop()
                onAction?("game_won")
            }
            return
        }
        guard isPlaying else { return }

        let tilt = currentTilt()
        let aspect = aspectScale()
        for index in yarns.indices where !yarns[index].isCaught {
            let previous = CGPoint(x: yarns[index].x, y: yarns[index].y)
            yarns[index].x = clamp(yarns[index].x + tilt.x * speedPerFrame * frames)
            yarns[index].y = clamp(yarns[index].y + tilt.y * speedPerFrame * frames)
            // Клубок вращается пропорционально пройденному пути — катится, а не скользит.
            let travelX = (yarns[index].x - previous.x) * aspect.x
            let travelY = (yarns[index].y - previous.y) * aspect.y
            let direction: CGFloat = abs(travelX) >= abs(travelY)
                ? (travelX < 0 ? -1 : 1)
                : (travelY < 0 ? -1 : 1)
            yarns[index].rotation += hypot(travelX, travelY) / yarnBodyRadius * direction
        }
        separateYarns()
        catchYarns()
        render()

        if yarns.allSatisfy(\.isCaught) {
            isPlaying = false
            danceStartedAt = now
        }
    }

    /// Наклон как в JS: gamma/beta в градусах относительно положения в момент старта, /45°.
    private func currentTilt() -> CGPoint {
        let raw = tiltSource.current
        let degrees = CGPoint(
            x: asin(max(-1, min(1, raw.x))) * 180 / .pi,
            y: asin(max(-1, min(1, raw.y))) * 180 / .pi
        )
        guard let calibration else {
            calibration = degrees
            return .zero
        }
        return CGPoint(x: (degrees.x - calibration.x) / 45, y: (degrees.y - calibration.y) / 45)
    }

    private func catchYarns() {
        for yarnIndex in yarns.indices where !yarns[yarnIndex].isCaught {
            for catIndex in cats.indices where cats[catIndex].balls < 2 {
                let distance = hypot(yarns[yarnIndex].x - cats[catIndex].x, yarns[yarnIndex].y - cats[catIndex].y)
                guard distance < yarnCatchRadius + catCatchRadius else { continue }
                yarns[yarnIndex].isCaught = true
                yarns[yarnIndex].layer.removeFromSuperlayer()
                cats[catIndex].balls += 1
                playCatch(at: CGPoint(x: yarns[yarnIndex].x * bounds.width, y: yarns[yarnIndex].y * bounds.height))
                bump(cats[catIndex].layer)
                onAction?("cat_caught")
                break
            }
        }
    }

    /// Клубки расталкиваются, а не слипаются. Края экрана — жёсткие.
    private func separateYarns() {
        let aspect = aspectScale()
        let minDistance = yarnBodyRadius * 2
        let active = yarns.indices.filter { !yarns[$0].isCaught }
        for _ in 0..<3 {
            for i in 0..<active.count {
                for j in (i + 1)..<max(i + 1, active.count) {
                    let a = active[i], b = active[j]
                    var dx = (yarns[b].x - yarns[a].x) * aspect.x
                    var dy = (yarns[b].y - yarns[a].y) * aspect.y
                    var dist = hypot(dx, dy)
                    guard dist < minDistance else { continue }
                    if dist < 1e-6 {
                        let angle = CGFloat.random(in: 0...(2 * .pi))
                        dx = cos(angle); dy = sin(angle); dist = 1
                    }
                    let push = (minDistance - min(dist, minDistance)) / 2
                    let nx = dx / dist, ny = dy / dist
                    yarns[a].x = clamp(yarns[a].x - nx * push / aspect.x)
                    yarns[a].y = clamp(yarns[a].y - ny * push / aspect.y)
                    yarns[b].x = clamp(yarns[b].x + nx * push / aspect.x)
                    yarns[b].y = clamp(yarns[b].y + ny * push / aspect.y)
                }
            }
        }
    }

    // MARK: Отрисовка

    private func render(danceElapsed: CFTimeInterval? = nil) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for cat in cats {
            let image: CGImage?
            if let elapsed = danceElapsed, !atlas.danceFrames.isEmpty {
                image = atlas.danceFrames[Int(elapsed / danceFrameInterval) % atlas.danceFrames.count]
            } else {
                image = atlas.catStates[cat.balls <= 0 ? .ready : cat.balls == 1 ? .oneBall : .twoBalls]
            }
            place(cat.layer, image: image, height: catHeight, x: cat.x, y: cat.y, rotation: 0)
        }
        for yarn in yarns where !yarn.isCaught {
            place(yarn.layer, image: atlas.yarns[yarn.variant % atlas.yarns.count],
                  height: yarnHeight, x: yarn.x, y: yarn.y, rotation: yarn.rotation)
        }
        CATransaction.commit()
    }

    private func place(_ layer: CALayer, image: CGImage?, height: CGFloat, x: CGFloat, y: CGFloat, rotation: CGFloat) {
        guard let image else { return }
        layer.contents = image
        let ratio = CGFloat(image.width) / CGFloat(max(image.height, 1))
        layer.bounds = CGRect(x: 0, y: 0, width: height * ratio, height: height)
        layer.position = CGPoint(x: x * bounds.width, y: y * bounds.height)
        layer.setAffineTransform(CGAffineTransform(rotationAngle: rotation))
    }

    /// Котик подпрыгивает, поймав клубок.
    private func bump(_ layer: CALayer) {
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.y")
        animation.values = [0, -catHeight * 0.075, 0]
        animation.duration = 0.35
        animation.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeIn)]
        layer.add(animation, forKey: "bump")
    }

    /// Разноцветные искры, как в JS-рендере.
    private func playCatch(at point: CGPoint) {
        let colors: [UIColor] = [
            UIColor(red: 1, green: 0.37, blue: 0.43, alpha: 1), UIColor(red: 1, green: 0.85, blue: 0.24, alpha: 1),
            UIColor(red: 0.4, green: 0.84, blue: 0.65, alpha: 1), UIColor(red: 0.33, green: 0.72, blue: 1, alpha: 1)
        ]
        let scale = min(max(min(bounds.width, bounds.height) / 390, 0.75), 1.2)
        for index in 0..<12 {
            let dot = CALayer()
            let radius = CGFloat.random(in: 3...7) * scale
            dot.bounds = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
            dot.cornerRadius = radius
            dot.backgroundColor = colors[index % colors.count].cgColor
            dot.position = point
            layer.addSublayer(dot)

            let angle = CGFloat(index) / 12 * 2 * .pi + .random(in: 0...0.25)
            let speed = CGFloat.random(in: 35...100) * 0.6
            let duration = Double.random(in: 0.55...0.8)
            let move = CABasicAnimation(keyPath: "position")
            move.toValue = CGPoint(x: point.x + cos(angle) * speed, y: point.y + sin(angle) * speed + 20)
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.toValue = 0
            let group = CAAnimationGroup()
            group.animations = [move, fade]
            group.duration = duration
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            group.fillMode = .forwards
            group.isRemovedOnCompletion = false
            dot.add(group, forKey: "spark")
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { dot.removeFromSuperlayer() }
        }
    }

    // MARK: Утилиты

    private func clamp(_ value: CGFloat) -> CGFloat { max(0.05, min(0.95, value)) }

    private func aspectScale() -> CGPoint {
        let width = max(bounds.width, 1), height = max(bounds.height, 1)
        let short = min(width, height)
        return CGPoint(x: width / short, y: height / short)
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let k = aspectScale()
        return hypot((a.x - b.x) * k.x, (a.y - b.y) * k.y)
    }
}

/// `CADisplayLink` держит цель сильно — прокси разрывает цикл.
private final class GameLinkProxy: NSObject {
    private weak var view: CatGameView?

    init(_ view: CatGameView) {
        self.view = view
    }

    @MainActor @objc func tick(_ link: CADisplayLink) {
        view?.step(link)
    }
}
