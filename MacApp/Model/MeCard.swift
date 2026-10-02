import Contacts
import Foundation
import PrefillKit

// On the Mac, Contacts knows which card is the person's own (Card > Make This My Card), so
// Prefill follows it instead of asking. The card it writes to is one of the cards linked
// into that one, preferring the one in the default account so changes reach the iPhone
// through iCloud.
enum MeCard {
    enum Failure: Error {
        case noAccess, noMeCard
    }

    static func link(gateway: any ContactsGateway, now: Date) throws(Failure) -> CardLink {
        let store = CNContactStore()
        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else { throw .noAccess }
        let keys = [CNContactIdentifierKey as CNKeyDescriptor]
        guard let meCard = try? store.unifiedMeContactWithKeys(toFetch: keys) else {
            throw .noMeCard
        }
        let identifier = writableMember(of: meCard, store: store)
        guard let original = try? gateway.fetchCard(identifier: identifier) else { throw .noMeCard }
        let predicate = CNContainer.predicateForContainerOfContact(withIdentifier: identifier)
        let container = try? store.containers(matching: predicate).first?.identifier
        return CardLink(
            contactIdentifier: identifier, containerIdentifier: container, linkedIdentifiers: [],
            original: original, snapshotAt: now
        )
    }

    private static func writableMember(of meCard: CNContact, store: CNContactStore) -> String {
        let request = CNContactFetchRequest(keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor])
        request.unifyResults = false
        var members: [String] = []
        try? store.enumerateContacts(with: request) { contact, _ in
            if meCard.isUnifiedWithContact(withIdentifier: contact.identifier) { members.append(contact.identifier) }
        }
        let defaultContainer = store.defaultContainerIdentifier()
        let inDefault = members.first { member in
            let predicate = CNContainer.predicateForContainerOfContact(withIdentifier: member)
            return (try? store.containers(matching: predicate).first?.identifier) == defaultContainer
        }
        return inDefault ?? members.first ?? meCard.identifier
    }
}
