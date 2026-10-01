import Contacts
import Foundation

// Never calls requestAccess: the Safari extension inherits the app's grant, and a prompt
// from the extension can deny the app permanently (REPORT.md, Spike results).
public struct CNContactStoreGateway: ContactsGateway {
    #if os(iOS)
    private static let grantedStatuses: Set<CNAuthorizationStatus> = [.authorized, .limited]
    #else
    private static let grantedStatuses: Set<CNAuthorizationStatus> = [.authorized]
    #endif

    public init() {}

    public func fetchCard(identifier: String) throws(CardWriteFailure) -> CardRecord {
        CNCardMapping.record(from: try fetch(identifier, store: CNContactStore()), identifier: identifier)
    }

    // Contacts has no compare-and-swap, so the basis check narrows the race with another
    // writer to the save call itself rather than closing it.
    public func save(
        _ target: CardRecord, basis: CardRecord, transactionAuthor: String
    ) throws(CardWriteFailure) -> CardSaveResult {
        let store = CNContactStore()
        let current = try fetch(target.identifier, store: store)
        let record = CNCardMapping.record(from: current, identifier: target.identifier)
        guard record == basis else { return .stale(current: record) }
        guard let contact = current.mutableCopy() as? CNMutableContact else { throw .other }
        CNCardMapping.apply(target, to: contact)
        let request = CNSaveRequest()
        request.transactionAuthor = transactionAuthor
        request.update(contact)
        do {
            try store.execute(request)
        } catch {
            throw CNCardMapping.failure(for: error)
        }
        return .saved
    }

    private func fetch(_ identifier: String, store: CNContactStore) throws(CardWriteFailure) -> CNContact {
        guard Self.grantedStatuses.contains(CNContactStore.authorizationStatus(for: .contacts)) else {
            throw .noAccess
        }
        let request = CNContactFetchRequest(keysToFetch: CNCardMapping.keys)
        request.predicate = CNContact.predicateForContacts(withIdentifiers: [identifier])
        request.unifyResults = false
        do {
            var found: CNContact?
            try store.enumerateContacts(with: request) { contact, stop in
                found = contact
                stop.pointee = true
            }
            guard let found else { throw CardWriteFailure.cardMissing }
            return found
        } catch let failure as CardWriteFailure {
            throw failure
        } catch {
            throw CNCardMapping.failure(for: error)
        }
    }
}

enum CNCardMapping {
    static var keys: [CNKeyDescriptor] {
        [
            CNContactIdentifierKey, CNContactGivenNameKey, CNContactFamilyNameKey,
            CNContactEmailAddressesKey, CNContactPhoneNumbersKey, CNContactPostalAddressesKey
        ].map { $0 as CNKeyDescriptor }
    }

    private static let failures: [CNError.Code: CardWriteFailure] = [
        .authorizationDenied: .noAccess,
        .recordDoesNotExist: .cardMissing,
        .recordNotWritable: .notWritable,
        .parentContainerNotWritable: .notWritable,
        .policyViolation: .notWritable
    ]

    static func record(from contact: CNContact, identifier: String) -> CardRecord {
        CardRecord(
            identifier: identifier,
            givenName: contact.givenName,
            familyName: contact.familyName,
            emails: contact.emailAddresses.map { CardEntry(label: $0.label, payload: .email($0.value as String)) },
            phones: contact.phoneNumbers.map { CardEntry(label: $0.label, payload: .phone($0.value.stringValue)) },
            addresses: contact.postalAddresses.map { CardEntry(label: $0.label, payload: .address(postal($0.value))) }
        )
    }

    // Every value goes out as a fresh CNLabeledValue so the save renumbers stored
    // identifiers 0..n in array order, which is the order Safari's bar follows.
    // Existing value objects are reused so fields the record doesn't model survive.
    static func apply(_ record: CardRecord, to contact: CNMutableContact) {
        contact.emailAddresses = fresh(record.emails, originals: contact.emailAddresses) {
            Normalizer.email($0 as String)
        } make: { entry in
            guard case .email(let text) = entry.payload else { return nil }
            return text as NSString
        }
        contact.phoneNumbers = fresh(record.phones, originals: contact.phoneNumbers) {
            Normalizer.phone($0.stringValue)
        } make: { entry in
            guard case .phone(let text) = entry.payload else { return nil }
            return CNPhoneNumber(stringValue: text)
        }
        contact.postalAddresses = fresh(record.addresses, originals: contact.postalAddresses) {
            Normalizer.address(postal($0))
        } make: { entry in
            guard case .address(let address) = entry.payload else { return nil }
            return cnPostal(address)
        }
    }

    static func failure(for error: any Error) -> CardWriteFailure {
        guard let error = error as? CNError else { return .other }
        return failures[error.code] ?? .other
    }

    private static func fresh<Value>(
        _ entries: [CardEntry],
        originals: [CNLabeledValue<Value>],
        key: (Value) -> String,
        make: (CardEntry) -> Value?
    ) -> [CNLabeledValue<Value>] {
        var pool = Dictionary(grouping: originals.map(\.value), by: key)
        return entries.compactMap { entry in
            let reused = pool[entry.key]?.isEmpty == false ? pool[entry.key]?.removeFirst() : nil
            guard let value = reused ?? make(entry) else { return nil }
            return CNLabeledValue(label: entry.label, value: value)
        }
    }

    private static func postal(_ address: CNPostalAddress) -> PostalAddress {
        PostalAddress(
            street: address.street, city: address.city, state: address.state,
            postalCode: address.postalCode, country: address.country
        )
    }

    private static func cnPostal(_ address: PostalAddress) -> CNPostalAddress {
        let postal = CNMutablePostalAddress()
        postal.street = address.street
        postal.city = address.city
        postal.state = address.state
        postal.postalCode = address.postalCode
        postal.country = address.country
        return postal
    }
}
