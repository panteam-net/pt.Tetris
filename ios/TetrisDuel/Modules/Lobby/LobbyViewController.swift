import UIKit

final class LobbyViewController: UIViewController, LobbyViewing, UITableViewDataSource, UITableViewDelegate {
    private let presenter: LobbyPresenting
    private let role: NearbyRole
    private let playerName: String
    private let status = Theme.label(size: 16, color: Theme.muted)
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private var peers: [NearbyPeer] = []
    init(presenter: LobbyPresenting, role: NearbyRole, name: String) {
        self.presenter = presenter; self.role = role; playerName = name
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use dependency-injected initializer") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = role == .host ? "Host a game" : "Join a game"
        view.backgroundColor = Theme.background
        let icon = UIImageView(image: UIImage(systemName: "wifi", withConfiguration: UIImage.SymbolConfiguration(pointSize: 48, weight: .medium)))
        icon.tintColor = Theme.mint; icon.contentMode = .scaleAspectFit
        icon.heightAnchor.constraint(equalToConstant: 72).isActive = true
        let name = Theme.label(role == .host ? playerName : "NEARBY GAMES", size: 28, weight: .bold)
        name.textAlignment = .center
        status.textAlignment = .center; status.numberOfLines = 0
        spinner.color = Theme.mint; spinner.hidesWhenStopped = true
        let hint = Theme.label(role == .host ? "On the other device, choose Join a nearby game.\nAccept your opponent’s invitation here." : "Choose a host below. Both devices need Wi-Fi\nand Local Network permission enabled.", size: 14, color: Theme.muted)
        hint.numberOfLines = 0; hint.textAlignment = .center
        table.backgroundColor = .clear; table.dataSource = self; table.delegate = self
        table.rowHeight = 68; table.isHidden = role == .host
        table.accessibilityIdentifier = "nearby-peers"
        let stack = UIStackView(arrangedSubviews: [icon, name, status, spinner, hint, table])
        stack.axis = .vertical; stack.spacing = 18
        view.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            table.heightAnchor.constraint(greaterThanOrEqualToConstant: 220)
        ])
        presenter.load()
    }
    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        if parent == nil && isViewLoaded { presenter.leave() }
    }
    func showStatus(_ text: String, failed: Bool) {
        status.text = text; status.textColor = failed ? Theme.amber : Theme.muted
        if failed { spinner.stopAnimating(); table.isUserInteractionEnabled = false }
        else { spinner.startAnimating() }
    }
    func showPeers(_ peers: [NearbyPeer]) { self.peers = peers; table.reloadData() }
    func showInvitation(name: String, answer: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: "Play with \(name)?", message: "This player wants to join your nearby duel.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Decline", style: .cancel) { _ in answer(false) })
        alert.addAction(UIAlertAction(title: "Play", style: .default) { _ in answer(true) })
        present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 18) { [weak alert] in
            guard let alert = alert, alert.presentingViewController != nil else { return }
            alert.dismiss(animated: true); answer(false)
        }
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { peers.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.backgroundColor = Theme.panel; cell.textLabel?.textColor = Theme.text
        cell.detailTextLabel?.textColor = Theme.muted
        cell.textLabel?.text = peers[indexPath.row].name; cell.detailTextLabel?.text = "Tap to request a duel"
        cell.accessoryType = .disclosureIndicator
        return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        presenter.select(peers[indexPath.row])
    }
}
