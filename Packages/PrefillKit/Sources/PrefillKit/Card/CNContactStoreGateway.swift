import Contacts
import Foundation

// Never calls requestAccess: the Safari extension inherits the app's grant, and a prompt
// from the extension can deny the app permanently (REPORT.md, Spike results).
public struct CNContactStoreGateway: ContactsGateway {
    private static let log = PrefillLog.logger("contacts")
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
    // writer to the save call itself rather than closing it. A save that may not remove
    // values is refused if it would, and checked again afterwards: a value lost to a write
    // that landed in between is put back.
    public func save(
        _ target: CardRecord, basis: CardRecord, scope: CardSaveScope, transactionAuthor: String
    ) throws(CardWriteFailure) -> CardSaveResult {
        if scope == .keepEveryValue, !target.keepsEveryValue(of: basis) {
            Self.log.error("save refused, it would drop or flood values")
            throw .other
        }
        let store = CNContactStore()
        let current = try fetch(target.identifier, store: store)
        let record = CNCardMapping.record(from: current, identifier: target.identifier)
        guard record == basis else { return .stale(current: record) }
        try execute(target, on: current, store: store, author: transactionAuthor)
        if scope == .keepEveryValue {
            restoreLostValues(of: basis, identifier: target.identifier, author: transactionAuthor)
        }
        return .saved
    }

    private func execute(
        _ target: CardRecord, on current: CNContact, store: CNContactStore, author: String
    ) throws(CardWriteFailure) {
        guard let contact = current.mutableCopy() as? CNMutableContact else { throw .other }
        CNCardMapping.apply(target, to: contact)
        let request = CNSaveRequest()
        request.transactionAuthor = author
        request.update(contact)
        do {
            try store.execute(request)
        } catch {
            throw CNCardMapping.failure(for: error)
        }
    }

    private func restoreLostValues(of basis: CardRecord, identifier: String, author: String) {
        let store = CNContactStore()
        do throws(CardWriteFailure) {
            let saved = try fetch(identifier, store: store)
            let record = CNCardMapping.record(from: saved, identifier: identifier)
            let restored = record.restoringValues(of: basis)
            guard restored != record else { return }
            Self.log.error("a value went missing during a save, putting it back")
            try execute(restored, on: saved, store: store, author: author)
        } catch {
            Self.log.error("save check failed: \(String(describing: error), privacy: .public)")
        }
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
            CNContactEmailAddressesKey, CNContactPhoneNumbersKey, CNContactPostalAddressesKey,
            CNContactUrlAddressesKey
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
            addresses: contact.postalAddresses.map { CardEntry(label: $0.label, payload: .address(postal($0.value))) },
            links: contact.urlAddresses.map { CardEntry(label: $0.label, payload: .link($0.value as String)) }
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
        contact.urlAddresses = fresh(record.links, originals: contact.urlAddresses) {
            Normalizer.link($0 as String)
        } make: { entry in
            guard case .link(let text) = entry.payload else { return nil }
            return text as NSString
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
