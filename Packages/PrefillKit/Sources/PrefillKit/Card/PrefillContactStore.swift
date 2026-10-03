import Contacts
import Foundation

// Finds and writes Prefill's own contact (PrefillContact). It is an organization card named
// "Prefill · <the person's name>", recognized by its department field, and made in the same
// account as the person's card so iCloud carries it to their other devices.
enum PrefillContactStore {
    static func isPrefillContact(_ contact: CNContact) -> Bool {
        contact.isKeyAvailable(CNContactDepartmentNameKey) && PrefillContact.isMarker(contact.departmentName)
    }

    // Every copy in the card's own account, oldest identifier first so each device picks the
    // same one. A look-alike in another account (a shared or work directory) is never read
    // or written.
    static func find(
        besideCard cardIdentifier: String, in store: CNContactStore, keys: [CNKeyDescriptor]
    ) throws(CardWriteFailure) -> [CNContact] {
        let account = try container(of: cardIdentifier, store: store)
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.predicate = CNContact.predicateForContacts(matchingName: PrefillContact.searchName)
        request.unifyResults = false
        var found: [CNContact] = []
        do {
            try store.enumerateContacts(with: request) { contact, _ in
                if isPrefillContact(contact) { found.append(contact) }
            }
        } catch {
            throw CNCardMapping.failure(for: error)
        }
        return found
            .filter { (try? container(of: $0.identifier, store: store)) == account }
            .sorted { $0.identifier < $1.identifier }
    }

    // Writes `extras` to every copy, or adds the contact when there is none yet. Copies are
    // never deleted: one another device can't see yet would come back empty-handed.
    static func write(
        _ extras: CardExtras, copies: [CNContact], beside card: CardRecord, store: CNContactStore,
        request: CNSaveRequest
    ) throws(CardWriteFailure) {
        guard !copies.isEmpty else {
            let contact = CNMutableContact()
            contact.contactType = .organization
            contact.organizationName = PrefillContact.name(for: card)
            CNCardMapping.applyPrefill(extras, to: contact)
            request.add(contact, toContainerWithIdentifier: try container(of: card.identifier, store: store))
            return
        }
        for copy in copies {
            guard let contact = copy.mutableCopy() as? CNMutableContact else { throw .other }
            CNCardMapping.applyPrefill(extras, to: contact)
            request.update(contact)
        }
    }

    // The account the card lives in, so Prefill's contact syncs wherever the card does.
    private static func container(of identifier: String, store: CNContactStore) throws(CardWriteFailure) -> String {
        let predicate = CNContainer.predicateForContainerOfContact(withIdentifier: identifier)
        guard let container = try? store.containers(matching: predicate).first?.identifier else { throw .other }
        return container
    }
}
