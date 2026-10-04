import UIKit

final class PlayerPanel: UIView {
    let seat: Int
    let controls: TouchControls
    private let name = Theme.label(size: 12, weight: .bold)
    private let score = Theme.label(size: 24, weight: .bold)
    private let stats = Theme.label(size: 10, weight: .medium, color: Theme.muted)
    private let hold = PiecePreview(frame: .zero)
    private let nextPreviews = (0..<3).map { _ in PiecePreview(frame: .zero) }
    private let board = CubeBoardView(frame: .zero)

    init(seat: Int, controlled: Bool) {
        self.seat = seat; controls = TouchControls(seat: seat)
        super.init(frame: .zero)
        Theme.card(self)
        name.textColor = Theme.accent(seat)
        name.accessibilityIdentifier = "player-\(seat)-name"
        score.font = .monospacedDigitSystemFont(ofSize: 24, weight: .bold)
        score.adjustsFontSizeToFitWidth = true; score.minimumScaleFactor = 0.55
        score.accessibilityLabel = L10n.text("player.score")
        stats.adjustsFontSizeToFitWidth = true; stats.minimumScaleFactor = 0.7
        stats.accessibilityIdentifier = "player-\(seat)-stats"
        board.seat = seat
        let holdLabel = Theme.label(
            L10n.text("player.hold"),
            size: 8,
            weight: .bold,
            color: Theme.muted
        )
        let nextLabel = Theme.label(
            L10n.text("player.next"),
            size: 8,
            weight: .bold,
            color: Theme.muted
        )
        let previews = UIStackView(
            arrangedSubviews: [holdLabel, hold, nextLabel] + nextPreviews
        )
        previews.spacing = 4; previews.alignment = .center
        hold.widthAnchor.constraint(
            equalTo: nextPreviews[0].widthAnchor
        ).isActive = true
        for preview in [hold] + nextPreviews {
            preview.heightAnchor.constraint(equalToConstant: 32).isActive = true
            preview.widthAnchor.constraint(greaterThanOrEqualToConstant: 20).isActive = true
        }

        nextPreviews[1].widthAnchor.constraint(
            equalTo: nextPreviews[0].widthAnchor
        ).isActive = true
        nextPreviews[2].widthAnchor.constraint(
            equalTo: nextPreviews[0].widthAnchor
        ).isActive = true
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
        score.accessibilityValue = score.text
        stats.text = L10n.format(
            "player.stats",
            state.lines,
            state.level,
            state.sent,
            state.incoming
        )
        hold.kind = state.held; hold.dimmed = state.holdUsed
        for (index, preview) in nextPreviews.enumerated() {
            preview.kind = state.next[index]
        }

        board.snapshot = state
        controls.setEnabled(enabled)
    }
}
