import UIKit

final class GameViewController: UIViewController, GameViewing {
    private let presenter: GamePresenting
    private let mode: MatchMode
    private var panels: [PlayerPanel] = []
    private let timerLabel = Theme.label("00:00", size: 15, weight: .bold)
    private let opponentLabel = Theme.label(size: 11, weight: .medium, color: Theme.muted)
    private let statusLabel = Theme.label(size: 10, weight: .semibold, color: Theme.mint)
    private let overlay = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let overlayTitle = Theme.label(size: 32, weight: .heavy)
    private let overlayDetail = Theme.label(size: 15, color: Theme.muted)
    private let primaryButton = Theme.button(
        L10n.text("common.resume"),
        primary: true
    )
    private var observers: [NSObjectProtocol] = []
    private var lastPhase: MatchPhase?
    private var heldKeys = Set<Int>()

    init(presenter: GamePresenting, mode: MatchMode) {
        self.presenter = presenter; self.mode = mode
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) { fatalError("Use dependency-injected initializer") }
    
    override var canBecomeFirstResponder: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.text("game.title")
        view.backgroundColor = Theme.background
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(
                image: UIImage(systemName: "pause.fill"),
                style: .plain,
                target: self,
                action: #selector(pausePressed)),
            UIBarButtonItem(
                image: UIImage(systemName: "questionmark.circle"),
                style: .plain,
                target: self,
                action: #selector(helpPressed)),
            UIBarButtonItem(
                image: UIImage(systemName: "speaker.wave.2"),
                style: .plain,
                target: self,
                action: #selector(soundPressed))
        ]
        navigationItem
            .rightBarButtonItems?[0]
            .accessibilityLabel = L10n.text("game.pause.accessibility")
        navigationItem
            .rightBarButtonItems?[0]
            .accessibilityIdentifier = "game-pause"
        navigationItem
            .rightBarButtonItems?[1]
            .accessibilityLabel = L10n.text("game.help.title")
        navigationItem
            .rightBarButtonItems?[1]
            .accessibilityIdentifier = "game-help"
        navigationItem
            .rightBarButtonItems?[2]
            .accessibilityIdentifier = "game-sound"
        let spacer = UIView()
        let header = UIStackView(arrangedSubviews: [statusLabel, spacer, timerLabel])
        header
            .heightAnchor
            .constraint(equalToConstant: 24)
            .isActive = true
        let area = UIStackView()
        area.axis = .horizontal
        area.distribution = .fillEqually
        area.spacing = 12
        let seats = mode == .solo
            ? [0]
        : (UIDevice.current.userInterfaceIdiom == .pad
           ? [0, 1]
           : [mode.localSeat])
        for seat in seats {
            let controlled = mode == .sharedDevice || seat == mode.localSeat
            let panel = PlayerPanel(seat: seat, controlled: controlled)
            panel.controls.onInput = { [weak self] action, pressed in self?.presenter.input(action, seat: seat, pressed: pressed) }
            panels.append(panel)
            area.addArrangedSubview(panel)
        }
        
        opponentLabel.isHidden = !mode.isNearby || UIDevice.current.userInterfaceIdiom == .pad
        opponentLabel.numberOfLines = 1; opponentLabel.adjustsFontSizeToFitWidth = true
        let content = UIStackView(arrangedSubviews: [header, opponentLabel, area])
        content.axis = .vertical
        content.spacing = 8
        view.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            content.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            content.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            content.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8)
        ])
        buildOverlay()
        observers = [
            NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                self?.heldKeys.removeAll(); self?.presenter.setAvailable(false)
            },
            NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                self?.presenter.setAvailable(true)
            }
        ]
        presenter.load()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated); becomeFirstResponder(); UIApplication.shared.isIdleTimerDisabled = true
    }
    
    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        if parent == nil && isViewLoaded {
            presenter.exit()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private func buildOverlay() {
        overlay.layer.cornerRadius = 24
        overlay.clipsToBounds = true
        overlay.layer.borderColor = Theme.line.cgColor
        overlay.layer.borderWidth = 1
        overlayTitle.numberOfLines = 0
        overlayTitle.textAlignment = .center
        overlayTitle.accessibilityIdentifier = "game-overlay-title"
        overlayTitle.adjustsFontSizeToFitWidth = true
        overlayTitle.minimumScaleFactor = 0.65
        overlayDetail.numberOfLines = 0
        overlayDetail.textAlignment = .center
        primaryButton.addTarget(
            self,
            action: #selector(primaryPressed),
            for: .touchUpInside)
        primaryButton.accessibilityIdentifier = "game-primary"
        let stack = UIStackView(
            arrangedSubviews: [overlayTitle, overlayDetail, primaryButton])
        stack.axis = .vertical
        stack.spacing = 20
        overlay.contentView.addSubview(stack)
        stack.pinEdges(to: overlay.contentView, inset: 28)
        view.addSubview(overlay)
        overlay.translatesAutoresizingMaskIntoConstraints = false
        let fillWidth = overlay.widthAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.widthAnchor,
            constant: -40)
        fillWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            overlay.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            overlay.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            overlay.widthAnchor.constraint(lessThanOrEqualToConstant: 520), fillWidth
        ])
    }

    func render(_ model: GameViewModel) {
        let seconds = Int(model.snapshot.elapsed)
        timerLabel.text = String(format: "%02d:%02d", seconds/60, seconds%60)
        statusLabel.text = mode == .solo ? model.title : L10n.format(
            "game.header",
            model.title,
            model.snapshot.wins[0],
            model.snapshot.wins[1]
        )
        if model.snapshot.boards.count == 2 {
            let other = model.snapshot.boards[1-mode.localSeat]
            opponentLabel.text = L10n.format(
                "game.opponent.summary",
                model.opponentName.uppercased(),
                other.score,
                other.lines
            )
        }
        for panel in panels where model.snapshot.boards.indices.contains(panel.seat) {
            let title: String
            if mode == .sharedDevice {
                title = L10n.format("player.numbered", panel.seat + 1)
            } else {
                title = panel.seat == mode.localSeat
                    ? L10n.text("player.you") : model.opponentName.uppercased()
            }

            panel.render(model.snapshot.boards[panel.seat], title: title, enabled: model.snapshot.phase == .playing)
        }
        overlay.isHidden = model.overlayTitle == nil
        overlayTitle.text = model.overlayTitle; overlayDetail.text = model.overlayDetail
        primaryButton.isHidden = model.primaryTitle == nil
        primaryButton.configuration?.title = model.primaryTitle
        navigationItem.rightBarButtonItems?[2].image = UIImage(systemName: model.soundEnabled ? "speaker.wave.2" : "speaker.slash")
        navigationItem.rightBarButtonItems?[2].accessibilityLabel = L10n.text(
            model.soundEnabled ? "game.sound.disable" : "game.sound.enable"
        )
        if lastPhase != model.snapshot.phase {
            heldKeys.removeAll()
            if let title = model.overlayTitle { UIAccessibility.post(notification: .announcement, argument: title) }
            lastPhase = model.snapshot.phase
        }
    }

    func showHelp() {
        let alert = UIAlertController(
            title: L10n.text("game.help.title"),
            message: L10n.text("game.help.body"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: L10n.text("common.gotIt"),
            style: .default
        ))
        present(alert, animated: true)
    }

    @objc private func pausePressed() { presenter.pause() }
    @objc private func helpPressed() { presenter.help() }
    @objc private func soundPressed() { presenter.toggleFeedback() }
    @objc private func primaryPressed() { presenter.primaryAction() }

    private func binding(_ code: Int) -> (Int, GameAction)? {
        let left: [Int: GameAction] = [4:.left,7:.right,22:.softDrop,26:.rotate,20:.reverse,44:.hardDrop,225:.hold]
        let right: [Int: GameAction] = [80:.left,79:.right,81:.softDrop,82:.rotate,56:.reverse,40:.hardDrop,88:.hardDrop,229:.hold]
        if let action = left[code] { return (mode == .sharedDevice ? 0 : mode.localSeat, action) }
        if let action = right[code] { return (mode == .sharedDevice ? 1 : mode.localSeat, action) }
        return nil
    }
    
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            guard let key = press.key else { continue }
            let code = Int(key.keyCode.rawValue)
            guard heldKeys.insert(code).inserted else { continue }
            if code == 19 || code == 41 {
                presenter.pause()
                handled = true
            }
            else if let (seat, action) = binding(code) {
                presenter.input(action, seat: seat, pressed: true)
                handled = true
            }
        }
        if !handled { super.pressesBegan(presses, with: event) }
    }
    
    override func pressesEnded(
        _ presses: Set<UIPress>,
        with event: UIPressesEvent?) {
        release(presses)
        super.pressesEnded(presses, with: event)
    }
    
    override func pressesCancelled(
        _ presses: Set<UIPress>,
        with event: UIPressesEvent?) {
        release(presses)
        super.pressesCancelled(presses, with: event)
    }
    
    private func release(_ presses: Set<UIPress>) {
        for press in presses {
            guard let key = press.key else { continue }
            
            let code = Int(key.keyCode.rawValue)
            heldKeys.remove(code)
            if let (seat, action) = binding(code) {
                presenter.input(action, seat: seat, pressed: false)
            }
        }
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
}
