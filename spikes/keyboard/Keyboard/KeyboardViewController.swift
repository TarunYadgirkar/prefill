import Contacts
import Security
import UIKit

// A test keyboard: a row of the person's values over a globe key, delete, space and return.
// It reads values from the keychain item the app shares and, failing that, tries Contacts
// itself, and its status line says which worked, so a run on the phone answers the spike.
final class KeyboardViewController: UIInputViewController {
    private struct Value: Codable { let label: String; let text: String }

    private let row = UIStackView()
    private let status = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        row.axis = .horizontal
        row.spacing = 8
        scroll.addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        status.font = .preferredFont(forTextStyle: .caption2)
        status.textColor = .secondaryLabel
        status.numberOfLines = 2
        let keys = UIStackView(arrangedSubviews: [
            key("🌐", action: #selector(handleInputModeList(from:with:))),
            key("space", action: #selector(space)), key("⌫", action: #selector(deleteBackwardKey)),
            key("return", action: #selector(returnKey))
        ])
        keys.distribution = .fillProportionally
        keys.spacing = 6
        let stack = UIStackView(arrangedSubviews: [status, scroll, keys])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            scroll.heightAnchor.constraint(equalToConstant: 52),
            keys.heightAnchor.constraint(equalToConstant: 44),
            row.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            row.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            row.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            row.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    private func reload() {
        let (values, source) = load()
        row.arrangedSubviews.forEach { $0.removeFromSuperview() }
        values.forEach { row.addArrangedSubview(chip($0)) }
        let context = textDocumentProxy.documentContextBeforeInput?.suffix(30) ?? ""
        let type = textDocumentProxy.textContentType?.rawValue ?? "none"
        status.text = "\(values.count) values from \(source) · full access \(hasFullAccess ? "on" : "off") · field \(type) · before: \(context)"
    }

    private func load() -> ([Value], String) {
        if let shared = keychainValues(), !shared.isEmpty { return (shared, "keychain") }
        let contacts = contactValues()
        return contacts.isEmpty ? ([], "nowhere (contacts \(CNContactStore.authorizationStatus(for: .contacts).rawValue))") : (contacts, "Contacts")
    }

    private func keychainValues() -> [Value]? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.tarunyadgirkar.prefill.spike.keyboard.values",
            kSecAttrAccessGroup as String: "5AKJYZ7USP.com.tarunyadgirkar.prefill.spike.keyboard.shared",
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode([Value].self, from: data)
    }

    private func contactValues() -> [Value] {
        let keys = [CNContactUrlAddressesKey, CNContactEmailAddressesKey, CNContactRelationsKey] as [CNKeyDescriptor]
        let predicate = CNContact.predicateForContacts(matchingName: "Prefill")
        let found = (try? CNContactStore().unifiedContacts(matching: predicate, keysToFetch: keys)) ?? []
        return found.flatMap { contact in
            contact.urlAddresses.map { Value(label: "Link", text: $0.value as String) }
                + contact.emailAddresses.map { Value(label: "Email", text: $0.value as String) }
                + contact.contactRelations.map { Value(label: $0.label ?? "Answer", text: $0.value.name) }
        }
    }

    private func chip(_ value: Value) -> UIButton {
        var config = UIButton.Configuration.gray()
        config.title = value.text
        config.subtitle = value.label
        config.titleLineBreakMode = .byTruncatingMiddle
        config.cornerStyle = .medium
        let button = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in
            self?.textDocumentProxy.insertText(value.text)
        })
        button.widthAnchor.constraint(lessThanOrEqualToConstant: 260).isActive = true
        return button
    }

    private func key(_ title: String, action: Selector) -> UIButton {
        var config = UIButton.Configuration.gray()
        config.title = title
        let button = UIButton(configuration: config)
        button.addTarget(self, action: action, for: title == "🌐" ? .allTouchEvents : .touchUpInside)
        return button
    }

    @objc private func space() { textDocumentProxy.insertText(" ") }
    @objc private func deleteBackwardKey() { textDocumentProxy.deleteBackward() }
    @objc private func returnKey() { textDocumentProxy.insertText("\n") }
}
