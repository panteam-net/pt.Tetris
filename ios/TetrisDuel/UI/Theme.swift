import UIKit

enum Theme {
    static let background = UIColor(red: 0.043, green: 0.059, blue: 0.090, alpha: 1)
    static let panel = UIColor(red: 0.067, green: 0.090, blue: 0.129, alpha: 1)
    static let well = UIColor(red: 0.031, green: 0.051, blue: 0.082, alpha: 1)
    static let line = UIColor(red: 0.15, green: 0.19, blue: 0.25, alpha: 1)
    static let text = UIColor(red: 0.90, green: 0.93, blue: 0.96, alpha: 1)
    static let muted = UIColor(red: 0.55, green: 0.62, blue: 0.70, alpha: 1)
    static let mint = UIColor(red: 0.36, green: 0.91, blue: 0.77, alpha: 1)
    static let amber = UIColor(red: 1, green: 0.69, blue: 0.41, alpha: 1)
    static func accent(_ seat: Int) -> UIColor { seat == 0 ? mint : amber }
    static func color(_ kind: Tetromino) -> UIColor {
        switch kind {
        case .i: return UIColor(red: 0.27, green: 0.82, blue: 0.89, alpha: 1)
        case .j: return UIColor(red: 0.36, green: 0.53, blue: 0.96, alpha: 1)
        case .l: return UIColor(red: 0.96, green: 0.64, blue: 0.32, alpha: 1)
        case .o: return UIColor(red: 0.94, green: 0.81, blue: 0.36, alpha: 1)
        case .s: return UIColor(red: 0.32, green: 0.80, blue: 0.60, alpha: 1)
        case .t: return UIColor(red: 0.66, green: 0.51, blue: 0.93, alpha: 1)
        case .z: return UIColor(red: 0.94, green: 0.41, blue: 0.51, alpha: 1)
        case .garbage: return UIColor(red: 0.39, green: 0.44, blue: 0.53, alpha: 1)
        }
    }
    static func label(_ text: String = "", size: CGFloat = 14, weight: UIFont.Weight = .regular,
                      color: UIColor = Theme.text) -> UILabel {
        let label = UILabel()
        label.text = text; label.textColor = color; label.font = .systemFont(ofSize: size, weight: weight)
        return label
    }
    static func button(_ title: String, symbol: String? = nil, primary: Bool = false) -> UIButton {
        var config = primary ? UIButton.Configuration.filled() : .tinted()
        config.title = title
        config.baseBackgroundColor = mint
        config.baseForegroundColor = primary ? background : mint
        config.cornerStyle = .large
        config.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18)
        if let symbol = symbol { config.image = UIImage(systemName: symbol); config.imagePadding = 12 }
        let button = UIButton(configuration: config)
        button.isExclusiveTouch = false
        return button
    }
    static func card(_ view: UIView) {
        view.backgroundColor = panel
        view.layer.cornerRadius = 18
        view.layer.borderWidth = 1
        view.layer.borderColor = line.cgColor
    }
}

extension UIView {
    func pinEdges(to other: UIView, inset: CGFloat = 0) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: other.leadingAnchor, constant: inset),
            trailingAnchor.constraint(equalTo: other.trailingAnchor, constant: -inset),
            topAnchor.constraint(equalTo: other.topAnchor, constant: inset),
            bottomAnchor.constraint(equalTo: other.bottomAnchor, constant: -inset)
        ])
    }
}
