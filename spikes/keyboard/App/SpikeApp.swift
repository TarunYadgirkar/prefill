import Contacts
import ContactsUI
import Security
import SwiftUI

// Test app for a Prefill keyboard. It copies the values on a contact card and on Prefill's
// own contact into a keychain item the keyboard can read, since the free team has no App
// Groups, and reports whether the keyboard can also read Contacts itself.
@main
struct SpikeApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

enum Shared {
    static let service = "com.tarunyadgirkar.prefill.spike.keyboard.values"
    // The personal team's ID is its app identifier prefix.
    static let group: String? = "5AKJYZ7USP.com.tarunyadgirkar.prefill.spike.keyboard.shared"
}

struct Value: Codable, Hashable {
    let label: String
    let text: String
}

struct ContentView: View {
    @State private var status = "Not shared yet."
    @State private var picking = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Choose your contact card") { picking = true }
                } footer: {
                    Text(status)
                }
                Section("Then") {
                    Text("Settings › General › Keyboard › Keyboards › Add New Keyboard › Prefill Keys, then turn on Allow Full Access.")
                    Text("In any app, tap a text field, hold the globe key and pick Prefill Keys.")
                }
            }
            .navigationTitle("Prefill Keys test")
            .sheet(isPresented: $picking) {
                ContactPicker { contact in share(contact) }
            }
        }
    }

    private func share(_ picked: CNContact) {
        Task { @MainActor in
            let store = CNContactStore()
            let granted = (try? await store.requestAccess(for: .contacts)) ?? false
            let values = granted ? Self.values(for: picked, store: store) : Self.values(of: picked)
            let saved = KeychainShare.save(values)
            status = "\(values.count) values, keychain \(saved ? "saved" : "failed"), Contacts access \(granted ? "on" : "off")."
        }
    }

    private static let keys: [CNKeyDescriptor] = [
        CNContactEmailAddressesKey, CNContactPhoneNumbersKey, CNContactUrlAddressesKey,
        CNContactRelationsKey, CNContactGivenNameKey, CNContactFamilyNameKey, CNContactOrganizationNameKey
    ].map { $0 as CNKeyDescriptor }

    // The picked card plus Prefill's own contact, which holds links and custom answers.
    private static func values(for picked: CNContact, store: CNContactStore) -> [Value] {
        let card = (try? store.unifiedContact(withIdentifier: picked.identifier, keysToFetch: keys)) ?? picked
        let prefill = (try? store.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: "Prefill"),
                                                   keysToFetch: keys)) ?? []
        return Array(([card] + prefill).flatMap(values(of:)).uniqued().prefix(40))
    }

    static func values(of contact: CNContact) -> [Value] {
        let name = contact.isKeyAvailable(CNContactGivenNameKey) && !contact.givenName.isEmpty
            ? [Value(label: "Name", text: "\(contact.givenName) \(contact.familyName)")] : []
        let emails = contact.isKeyAvailable(CNContactEmailAddressesKey)
            ? contact.emailAddresses.map { Value(label: label($0.label, "Email"), text: $0.value as String) } : []
        let phones = contact.isKeyAvailable(CNContactPhoneNumbersKey)
            ? contact.phoneNumbers.map { Value(label: label($0.label, "Phone"), text: $0.value.stringValue) } : []
        let links = contact.isKeyAvailable(CNContactUrlAddressesKey)
            ? contact.urlAddresses.map { Value(label: label($0.label, "Link"), text: $0.value as String) } : []
        let answers = contact.isKeyAvailable(CNContactRelationsKey)
            ? contact.contactRelations.compactMap { relation -> Value? in
                guard let raw = relation.label, raw.contains("· Prefill") else { return nil }
                let question = raw.components(separatedBy: " · ").first ?? raw
                return Value(label: question, text: relation.value.name)
            } : []
        return (name + emails + phones + links + answers).filter { !$0.text.isEmpty && !$0.label.hasPrefix("Prefill ·") }
    }

    private static func label(_ raw: String?, _ fallback: String) -> String {
        guard let raw else { return fallback }
        return CNLabeledValue<NSString>.localizedString(forLabel: raw)
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

enum KeychainShare {
    static func save(_ values: [Value]) -> Bool {
        guard let data = try? JSONEncoder().encode(values) else { return false }
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Shared.service]
        if let group = Shared.group { query[kSecAttrAccessGroup as String] = group }
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }
}

struct ContactPicker: UIViewControllerRepresentable {
    let picked: (CNContact) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(picked: picked) }

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: CNContactPickerViewController, context: Context) {}

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let picked: (CNContact) -> Void
        init(picked: @escaping (CNContact) -> Void) { self.picked = picked }
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) { picked(contact) }
    }
}
