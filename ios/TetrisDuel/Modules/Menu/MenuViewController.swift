import UIKit

final class MenuViewController: UIViewController, MenuViewing {
    private let presenter: MenuPresenting
    private let nameField = UITextField()
    private let buttons = UIStackView()
    init(presenter: MenuPresenting) {
        self.presenter = presenter
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("Use dependency-injected initializer")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        navigationItem.backButtonTitle = L10n.text("common.menu")
        let scroll = UIScrollView()
        scroll.keyboardDismissMode = .onDrag
        view.addSubview(scroll)
        scroll.pinEdges(to: view)
        let eyebrow = Theme.label(
            L10n.text("menu.eyebrow"),
            size: 12,
            weight: .bold,
            color: Theme.mint
        )
        let title = Theme.label(
            L10n.text("menu.title"),
            size: 54,
            weight: .heavy
        )
        title.numberOfLines = 2
        let subtitle = Theme.label(
            L10n.text("menu.subtitle"),
            size: 20,
            color: Theme.muted
        )
        subtitle.numberOfLines = 0
        let nameLabel = Theme.label(
            L10n.text("menu.name"),
            size: 11,
            weight: .bold,
            color: Theme.muted
        )
        nameField.textColor = Theme.text
        nameField.backgroundColor = Theme.panel
        nameField.layer.cornerRadius = 12
        nameField.font = .systemFont(ofSize: 17)
        nameField.leftView = UIView(frame: CGRect(
            x: 0,
            y: 0,
            width: 14,
            height: 1))
        nameField.leftViewMode = .always
        nameField.autocorrectionType = .no
        nameField.returnKeyType = .done
        nameField.accessibilityIdentifier = "player-name"
        nameField.accessibilityLabel = L10n.text("menu.name")
        nameField
            .heightAnchor
            .constraint(equalToConstant: 50)
            .isActive = true
        nameField.addTarget(
            self,
            action: #selector(endEditing),
            for: .editingDidEndOnExit)
        buttons.axis = .vertical
        buttons.spacing = 12
        let footnote = Theme.label(
            L10n.text("menu.footnote"),
            size: 12,
            color: Theme.muted
        )
        footnote.numberOfLines = 0
        let content = UIStackView(
            arrangedSubviews: [eyebrow, title, subtitle, nameLabel, nameField, buttons, footnote])
        content.axis = .vertical
        content.spacing = 16
        content.setCustomSpacing(28, after: subtitle)
        content.setCustomSpacing(8, after: nameLabel)
        scroll.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        let width = content.widthAnchor.constraint(
            equalTo: scroll.frameLayoutGuide.widthAnchor,
            constant: -48)
        width.priority = .defaultHigh
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(
                equalTo: scroll.contentLayoutGuide.topAnchor,
                constant: 20),
            content.bottomAnchor.constraint(
                equalTo: scroll.contentLayoutGuide.bottomAnchor,
                constant: -30),
            content.centerXAnchor.constraint(
                equalTo: scroll.frameLayoutGuide.centerXAnchor),
            content.widthAnchor.constraint(
                lessThanOrEqualToConstant: 500),
            width,
            scroll.contentLayoutGuide.widthAnchor.constraint(
                equalTo: scroll.frameLayoutGuide.widthAnchor)
        ])
        presenter.load()
    }
    
    @objc private func endEditing() {
        view.endEditing(true)
    }
    
    func show(items: [MenuItem], name: String) {
        nameField.text = name
        for item in items {
            let button = Theme.button(
                item.title,
                symbol: item.symbol,
                primary: item.choice == .solo)
            button.accessibilityIdentifier = "menu-\(item.choice)"
            button.addAction(UIAction { [weak self] _ in
                guard let self = self else { return }
                self.view.endEditing(true)
                self.presenter.select(
                    item.choice,
                    name: self.nameField.text ?? L10n.text("player.default")
                )
            }, for: .touchUpInside)
            buttons.addArrangedSubview(button)
        }
    }
}
