import UIKit

/// Простой хост-экран «как будто SberKids». Оверлей игры поверх него.
final class HostViewController: UIViewController {
    private let shake = ShakeDetector()
    private let overlay = PrankOverlayController()
    private var overlayInstalled = false

    private let titleLabel = UILabel()
    private let hintLabel = UILabel()
    private let playButton = UIButton(type: .system)
    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.95, green: 0.96, blue: 0.98, alpha: 1)
        buildUI()
        installOverlay()

        shake.onShake = { [weak self] in
            self?.triggerPrank(source: "shake")
        }
        shake.start()

        overlay.onHidden = { [weak self] in
            self?.statusLabel.text = "Готово. Встряхните снова или нажмите «Играть»."
        }
    }

    deinit {
        shake.stop()
    }

    private func buildUI() {
        titleLabel.text = "SberKids"
        titleLabel.font = .systemFont(ofSize: 34, weight: .bold)
        titleLabel.textColor = UIColor(red: 0.1, green: 0.45, blue: 0.25, alpha: 1)
        titleLabel.textAlignment = .center

        hintLabel.text = "Встряхните телефон — появится игра с котами.\nНаклоняйте устройство, чтобы катить клубки."
        hintLabel.font = .systemFont(ofSize: 16)
        hintLabel.textColor = .secondaryLabel
        hintLabel.numberOfLines = 0
        hintLabel.textAlignment = .center

        var config = UIButton.Configuration.filled()
        config.title = "Играть (без тряски)"
        config.baseBackgroundColor = UIColor(red: 0.12, green: 0.72, blue: 0.35, alpha: 1)
        config.baseForegroundColor = .white
        config.cornerStyle = .medium
        config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 24, bottom: 14, trailing: 24)
        playButton.configuration = config
        playButton.addTarget(self, action: #selector(manualPlay), for: .touchUpInside)

        statusLabel.text = shake.isAvailable
            ? "Ожидание тряски…"
            : "Акселерометр недоступен — используйте кнопку."
        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textColor = .tertiaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [titleLabel, hintLabel, playButton, statusLabel])
        stack.axis = .vertical
        stack.spacing = 20
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            playButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 220)
        ])
    }

    private func installOverlay() {
        guard !overlayInstalled else { return }
        overlayInstalled = true
        addChild(overlay)
        overlay.view.frame = view.bounds
        overlay.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.view.isHidden = true
        view.addSubview(overlay.view)
        overlay.didMove(toParent: self)
    }

    @objc private func manualPlay() {
        triggerPrank(source: "manual")
    }

    private func triggerPrank(source: String) {
        statusLabel.text = "Игра запущена (\(source)). Наклоняйте телефон."
        overlay.showGame()
    }

    // Симулятор: Hardware → Shake Gesture
    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            triggerPrank(source: "shake-gesture")
        }
    }
}
