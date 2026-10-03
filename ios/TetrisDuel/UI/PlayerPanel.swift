import UIKit

final class PlayerPanel: UIView {
    let seat: Int
    let controls: TouchControls
    private let name = Theme.label(size: 12, weight: .bold)
    private let score = Theme.label(size: 24, weight: .bold)
    private let stats = Theme.label(size: 10, weight: .medium, color: Theme.muted)
    private let hold = PiecePreview(frame: .zero)
    private let next = (0..<3).map { _ in PiecePreview(frame: .zero) }
    private let board = CubeBoardView(frame: .zero)

    init(seat: Int, controlled: Bool) {
        self.seat = seat; controls = TouchControls(seat: seat)
        super.init(frame: .zero)
        Theme.card(self)
        name.textColor = Theme.accent(seat)
        name.accessibilityIdentifier = "player-\(seat)-name"
        score.font = .monospacedDigitSystemFont(ofSize: 24, weight: .bold)
        score.adjustsFontSizeToFitWidth = true; score.minimumScaleFactor = 0.55
        stats.adjustsFontSizeToFitWidth = true; stats.minimumScaleFactor = 0.7
        board.seat = seat
        let holdLabel = Theme.label("HOLD", size: 8, weight: .bold, color: Theme.muted)
        let nextLabel = Theme.label("NEXT", size: 8, weight: .bold, color: Theme.muted)
        let previews = UIStackView(arrangedSubviews: [holdLabel, hold, nextLabel] + next)
        previews.spacing = 4; previews.alignment = .center
        hold.widthAnchor.constraint(equalTo: next[0].widthAnchor).isActive = true
        for preview in [hold] + next {
            preview.heightAnchor.constraint(equalToConstant: 32).isActive = true
            preview.widthAnchor.constraint(greaterThanOrEqualToConstant: 20).isActive = true
        }
        next[1].widthAnchor.constraint(equalTo: next[0].widthAnchor).isActive = true
        next[2].widthAnchor.constraint(equalTo: next[0].widthAnchor).isActive = true
        let stack = UIStackView(arrangedSubviews: [name, score, stats, previews, board, controls])
        stack.axis = .vertical; stack.spacing = 5
        addSubview(stack); stack.pinEdges(to: self, inset: 10)
        controls.heightAnchor.constraint(equalToConstant: 102).isActive = true
        controls.isHidden = !controlled
        board.setContentHuggingPriority(.defaultLow, for: .vertical)
        board.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    }
    required init?(coder: NSCoder) { fatalError("Use designated initializer") }
    func render(_ state: BoardSnapshot, title: String, enabled: Bool) {
        name.text = title
        score.text = state.score.formatted()
        stats.text = "LINES \(state.lines)   LV \(state.level)   SENT \(state.sent)   +\(state.incoming)"
        hold.kind = state.held; hold.dimmed = state.holdUsed
        for (index, preview) in next.enumerated() { preview.kind = state.next[index] }
        board.snapshot = state
        controls.setEnabled(enabled)
    }
}
