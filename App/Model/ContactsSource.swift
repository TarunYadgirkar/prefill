import Contacts
import PrefillKit

enum ContactsAccess: Sendable, Equatable {
    case notDetermined, limited, full, denied

    var isGranted: Bool { self == .limited || self == .full }
}

// A card the person shared with Prefill, as offered when asking which one is theirs.
struct CardChoice: Sendable, Hashable, Identifiable {
    let id: String
    let name: String
    let detail: String?
}

protocol ContactsSource: Sendable {
    var access: ContactsAccess { get }
    func requestAccess() async -> ContactsAccess
    func cards() async -> [CardChoice]
    func link(_ identifier: String) async throws(CardWriteFailure) -> CardLink
}

// The app is the only process that ever asks for Contacts access. The Safari extension
// inherits this grant and must never prompt (REPORT.md, Spike results).
nonisolated struct LiveContactsSource: ContactsSource {
    private static let statuses: [CNAuthorizationStatus: ContactsAccess] = [
        .notDetermined: .notDetermined, .limited: .limited, .authorized: .full,
        .denied: .denied, .restricted: .denied
    ]

    let gateway: CNContactStoreGateway

    var access: ContactsAccess {
        Self.statuses[CNContactStore.authorizationStatus(for: .contacts)] ?? .denied
    }

    func requestAccess() async -> ContactsAccess {
        _ = try? await CNContactStore().requestAccess(for: .contacts)
        return access
    }

    @concurrent func cards() async -> [CardChoice] {
        let keys = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactDepartmentNameKey as CNKeyDescriptor
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.sortOrder = .userDefault
        var choices: [CardChoice] = []
        try? CNContactStore().enumerateContacts(with: request) { contact, _ in
            guard !PrefillContact.isMarker(contact.departmentName) else { return }
            choices.append(Self.choice(contact))
        }
        return choices
    }

    @concurrent func link(_ identifier: String) async throws(CardWriteFailure) -> CardLink {
        let original = try gateway.fetchCard(identifier: identifier)
        let predicate = CNContainer.predicateForContainerOfContact(withIdentifier: identifier)
        let container = try? CNContactStore().containers(matching: predicate).first?.identifier
        return CardLink(
            contactIdentifier: identifier, containerIdentifier: container, linkedIdentifiers: [],
            original: original, snapshotAt: .now
        )
    }

    private static func choice(_ contact: CNContact) -> CardChoice {
        let name = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
        let detail = contact.emailAddresses.first.map { $0.value as String }
            ?? contact.phoneNumbers.first?.value.stringValue
        return CardChoice(id: contact.identifier, name: name, detail: detail)
    }
}
