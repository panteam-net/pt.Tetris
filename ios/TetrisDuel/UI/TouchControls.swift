import UIKit

/// Each control owns its own touch. No exclusive-touch gesture recognizer can
/// steal the other iPad player's press. Repetition lives in the interactor.
final class GameTouchButton: UIControl {
    let action: GameAction
    var onChange: ((GameAction, Bool) -> Void)?
    private let icon = UIImageView()
    private let caption: UILabel
    private var down = false

    init(action: GameAction, symbol: String, title: String, accent: UIColor) {
        self.action = action
        caption = Theme.label(title, size: 9, weight: .semibold, color: accent)
        super.init(frame: .zero)
        isExclusiveTouch = false
        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityTraits = .button
        backgroundColor = Theme.line.withAlphaComponent(0.6)
        layer.cornerRadius = 11
        icon.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold))
        icon.tintColor = accent; icon.contentMode = .scaleAspectFit
        let stack = UIStackView(arrangedSubviews: [icon, caption])
        stack.axis = .vertical; stack.alignment = .center; stack.spacing = 3; stack.isUserInteractionEnabled = false
        addSubview(stack); stack.pinEdges(to: self, inset: 5)
        heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
    }
    required init?(coder: NSCoder) { fatalError("Use designated initializer") }
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard isEnabled else { return false }
        setDown(true); return true
    }
    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let inside = bounds.insetBy(dx: -8, dy: -8).contains(touch.location(in: self))
        if !inside { setDown(false) }
        return inside
    }
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) { setDown(false) }
    override func cancelTracking(with event: UIEvent?) { setDown(false) }
    func release() { setDown(false) }
    private func setDown(_ value: Bool) {
        guard down != value else { return }
        down = value; alpha = value ? 0.55 : 1
        onChange?(action, value)
    }
    override func accessibilityActivate() -> Bool {
        setDown(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in self?.setDown(false) }
        return true
    }
}

final class TouchControls: UIView {
    var onInput: ((GameAction, Bool) -> Void)?
    private var buttons: [GameTouchButton] = []
    init(seat: Int) {
        super.init(frame: .zero)
        let definitions: [[(GameAction, String, String)]] = [
            [(.left,"arrow.left","LEFT"),(.reverse,"arrow.counterclockwise","ROTATE"),
             (.rotate,"arrow.clockwise","ROTATE"),(.right,"arrow.right","RIGHT")],
            [(.hold,"arrow.left.arrow.right","HOLD"),(.softDrop,"arrow.down","DOWN"),
             (.hardDrop,"arrow.down.to.line","DROP")]
        ]
        let rows = definitions.map { row -> UIStackView in
            let controls = row.map { action, symbol, title -> GameTouchButton in
                let button = GameTouchButton(action: action, symbol: symbol, title: title, accent: Theme.accent(seat))
                button.onChange = { [weak self] in self?.onInput?($0, $1) }
                buttons.append(button)
                return button
            }
            let row = UIStackView(arrangedSubviews: controls)
            row.axis = .horizontal; row.spacing = 6; row.distribution = .fillEqually
            return row
        }
        let stack = UIStackView(arrangedSubviews: rows)
        stack.axis = .vertical; stack.spacing = 6; stack.distribution = .fillEqually
        addSubview(stack); stack.pinEdges(to: self)
    }
    func setEnabled(_ enabled: Bool) {
        buttons.forEach { if !enabled { $0.release() }; $0.isEnabled = enabled }
        alpha = enabled ? 1 : 0.35
    }
    required init?(coder: NSCoder) { fatalError("Use init(seat:)") }
}
