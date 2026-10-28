import SwiftUI
import UIKit
import Agentation

/// Hosts the UIKit settings screen inside the SwiftUI tab view.
struct SettingsScreen: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UINavigationController {
        UINavigationController(rootViewController: SettingsViewController())
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}
}

/// Plain UIKit screen, to show capture of UIKit views, identifiers and `agentationTag`.
final class SettingsViewController: UITableViewController {
    private let rows: [(title: String, detail: String)] = [
        ("Account", "you@example.com"),
        ("Notifications", "On"),
        ("Appearance", "System"),
        ("Privacy", ""),
    ]

    init() {
        super.init(style: .insetGrouped)
        title = "Settings"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.navigationBar.prefersLargeTitles = true
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.tableHeaderView = makeHeader()
    }

    private func makeHeader() -> UIView {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 96))
        container.agentationTag = "ProfileHeader"

        let label = UILabel()
        label.text = "Signed in as Alex"
        label.font = .preferredFont(forTextStyle: .title3)
        label.accessibilityIdentifier = "settings.profileName"
        label.translatesAutoresizingMaskIntoConstraints = false

        let button = UIButton(configuration: .tinted())
        button.setTitle("Edit profile", for: .normal)
        button.accessibilityIdentifier = "settings.editProfile"
        button.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(label)
        container.addSubview(button)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.layoutMarginsGuide.leadingAnchor, constant: 8),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            button.leadingAnchor.constraint(equalTo: label.leadingAnchor),
            button.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 8),
        ])
        return container
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let row = rows[indexPath.row]
        var content = UIListContentConfiguration.valueCell()
        content.text = row.title
        content.secondaryText = row.detail
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        cell.accessibilityIdentifier = "settings.row.\(row.title.lowercased())"
        return cell
    }
}
