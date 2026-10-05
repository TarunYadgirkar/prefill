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

    // The person's card with the links and custom fields from Prefill's own contact.
    public func fetchCard(identifier: String) throws(CardWriteFailure) -> CardRecord {
        try load(identifier, store: CNContactStore()).split.record
    }

    // Contacts has no compare-and-swap, so the basis check narrows the race with another
    // writer to the save call itself rather than closing it. A save that may not remove
    // values is refused if it would, and checked again afterwards: a value lost to a write
    // that landed in between is put back.
    public func save(
        _ target: CardRecord, basis: CardRecord, scope: CardSaveScope, transactionAuthor: String
    ) throws(CardWriteFailure) -> CardSaveResult {
        guard scope.allows(target, over: basis) else {
            Self.log.error("save refused, it would drop or flood values")
            throw .other
        }
        let store = CNContactStore()
        let loaded = try load(target.identifier, store: store)
        guard loaded.split.record == basis else { return .stale(current: loaded.split.record) }
        let writes = loaded.split.writes(for: target)
        guard !writes.isEmpty else { return .unchanged }
        try execute(writes, on: loaded, store: store, author: transactionAuthor)
        if scope != .personEdit {
            restoreLostValues(of: basis, identifier: target.identifier, author: transactionAuthor)
        }
        return .saved
    }

    public func placement(identifier: String) throws(CardWriteFailure) -> CardPlacement {
        try load(identifier, store: CNContactStore()).split.placement
    }

    // One save request: Prefill's contact gains the chosen values, and only then does the
    // card lose them, so a failed save leaves both as they were. Read back afterwards: a
    // value that isn't on either contact any more is put back.
    public func moveOffCard(_ chosen: [CardExtra], identifier: String) throws(CardWriteFailure) {
        let store = CNContactStore()
        let loaded = try load(identifier, store: store)
        guard let writes = loaded.split.moving(chosen) else { return }
        let before = loaded.split.record
        // Only what was still on the card moves; another device may have taken the rest.
        let onCard = Set(loaded.split.extrasOnCard.map(\.id))
        let moved = chosen.filter { onCard.contains($0.id) }
        try execute(writes, on: loaded, store: store, author: CardWriter.transactionAuthor)
        let after = try load(identifier, store: CNContactStore())
        let held = Set(after.split.placement.onPrefill.map(\.id))
        guard moved.allSatisfy({ held.contains($0.id) }) else {
            Self.log.error("a moved value is missing from Prefill's contact")
            restoreLostValues(of: before, identifier: identifier, author: CardWriter.transactionAuthor)
            throw .other
        }
    }

    // One save request, read back afterwards like moveOffCard: a value that isn't on the
    // card is put back.
    public func moveOntoCard(
        _ chosen: [CardExtra]?, identifier: String, leavingMinimal: Bool
    ) throws(CardWriteFailure) {
        let store = CNContactStore()
        let loaded = try load(identifier, store: store)
        guard let writes = loaded.split.movingOntoCard(chosen, leavingMinimal: leavingMinimal) else { return }
        let before = loaded.split.record
        let ids = chosen.map { Set($0.map(\.id)) }
        let moved = loaded.split.placement.onPrefill.filter { $0.isCore && (ids?.contains($0.id) ?? true) }
        try execute(writes, on: loaded, store: store, author: CardWriter.transactionAuthor)
        let after = try load(identifier, store: CNContactStore())
        let held = Set(after.split.placement.onCard.map(\.id))
        guard moved.allSatisfy({ held.contains($0.id) }) else {
            Self.log.error("a moved value is missing from the card")
            restoreLostValues(of: before, identifier: identifier, author: CardWriter.transactionAuthor)
            throw .other
        }
    }

    private struct Loaded {
        let card: CNContact
        let copies: [CNContact]
        let split: CardSplit
    }

    private func load(_ identifier: String, store: CNContactStore) throws(CardWriteFailure) -> Loaded {
        let card = try fetch(identifier, store: store)
        // A Prefill contact picked as the card would also be found as its own copy.
        guard !PrefillContact.isMarker(card.departmentName) else { throw .cardMissing }
        let copies = try PrefillContactStore.find(besideCard: identifier, in: store, keys: CNCardMapping.keys)
        let split = CardSplit(
            card: CNCardMapping.record(from: card, identifier: identifier),
            copies: copies.map { copy in
                CardExtras(
                    CNCardMapping.record(from: copy, identifier: copy.identifier),
                    isMinimal: copy.departmentName == PrefillContact.minimalMarker
                )
            }
        )
        return Loaded(card: card, copies: copies, split: split)
    }

    // One save request, which Contacts applies as a whole or not at all.
    private func execute(
        _ writes: CardSplit.Writes, on loaded: Loaded, store: CNContactStore, author: String
    ) throws(CardWriteFailure) {
        guard writes.card != nil || writes.extras != nil else { return }
        let request = CNSaveRequest()
        request.transactionAuthor = author
        if let card = writes.card {
            guard let contact = loaded.card.mutableCopy() as? CNMutableContact else { throw .other }
            CNCardMapping.applyCore(card, to: contact)
            if writes.includesCardExtras {
                CNCardMapping.applyExtras(CardExtras(links: card.links, customFields: card.customFields), to: contact)
            }
            request.update(contact)
        }
        if let extras = writes.extras {
            try PrefillContactStore.write(
                extras, copies: loaded.copies, beside: loaded.split.card, store: store, request: request
            )
        }
        do {
            try store.execute(request)
        } catch {
            throw CNCardMapping.failure(for: error)
        }
    }

    private func restoreLostValues(of basis: CardRecord, identifier: String, author: String) {
        let store = CNContactStore()
        do throws(CardWriteFailure) {
            let loaded = try load(identifier, store: store)
            let record = loaded.split.record
            let restored = record.restoringValues(of: basis)
            guard restored != record else { return }
            Self.log.error("a value went missing during a save, putting it back")
            try execute(loaded.split.writes(for: restored), on: loaded, store: store, author: author)
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
            CNContactUrlAddressesKey, CNContactRelationsKey, CNContactDepartmentNameKey
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
            links: contact.urlAddresses.map { CardEntry(label: $0.label, payload: .link($0.value as String)) },
            customFields: customFields(of: contact)
        )
    }

    static func customFields(of contact: CNContact) -> [CustomField] {
        contact.contactRelations.compactMap { CustomFieldLabel.decode(label: $0.label, value: $0.value.name) }
    }

    // Related names Prefill didn't make keep their place and their objects; Prefill's own
    // follow them in the record's order. Untouched when they already match, so a save that
    // only reorders values never rewrites them.
    private static func applyCustomFields(_ fields: [CustomField], to contact: CNMutableContact) {
        guard customFields(of: contact) != fields else { return }
        let others = contact.contactRelations.filter {
            CustomFieldLabel.decode(label: $0.label, value: $0.value.name) == nil
        }
        contact.contactRelations = others + fields.map {
            CNLabeledValue(label: CustomFieldLabel.encode($0), value: CNContactRelation(name: $0.value))
        }
    }

    // Every value goes out as a fresh CNLabeledValue so the save renumbers stored
    // identifiers 0..n in array order, which is the order Safari's bar follows.
    // Existing value objects are reused so fields the record doesn't model survive.
    static func apply(_ record: CardRecord, to contact: CNMutableContact) {
        applyCore(record, to: contact)
        // A record stored before Prefill read custom fields says nothing about them.
        if record.knowsCustomFields {
            applyExtras(CardExtras(links: record.links, customFields: record.customFields), to: contact)
        } else {
            applyLinks(record.links, to: contact)
        }
    }

    static func applyCore(_ record: CardRecord, to contact: CNMutableContact) {
        applyCore(emails: record.emails, phones: record.phones, addresses: record.addresses, to: contact)
    }

    static func applyCore(
        emails: [CardEntry], phones: [CardEntry], addresses: [CardEntry], to contact: CNMutableContact
    ) {
        contact.emailAddresses = fresh(emails, originals: contact.emailAddresses) {
            Normalizer.email($0 as String)
        } make: { entry in
            guard case .email(let text) = entry.payload else { return nil }
            return text as NSString
        }
        // NameDrop and Share Contact remember the number the person picked by its stored
        // identifier, and a rewritten value gets a new one. So phones are written only when
        // they change, and a save that reorders emails leaves them exactly as stored.
        if !isStored(phones, as: contact.phoneNumbers) {
            contact.phoneNumbers = fresh(phones, originals: contact.phoneNumbers) {
                Normalizer.phone($0.stringValue)
            } make: { entry in
                guard case .phone(let text) = entry.payload else { return nil }
                return CNPhoneNumber(stringValue: text)
            }
        }
        contact.postalAddresses = fresh(addresses, originals: contact.postalAddresses) {
            Normalizer.address(postal($0))
        } make: { entry in
            guard case .address(let address) = entry.payload else { return nil }
            return cnPostal(address)
        }
    }

    // Links and custom fields only, the part of CardExtras the person's own card can hold.
    static func applyExtras(_ extras: CardExtras, to contact: CNMutableContact) {
        applyLinks(extras.links, to: contact)
        applyCustomFields(extras.customFields, to: contact)
    }

    // Everything Prefill's contact holds, and the marker that says whether the card is minimal.
    static func applyPrefill(_ extras: CardExtras, to contact: CNMutableContact) {
        applyExtras(extras, to: contact)
        applyCore(emails: extras.emails, phones: extras.phones, addresses: extras.addresses, to: contact)
        contact.departmentName = extras.isMinimal ? PrefillContact.minimalMarker : PrefillContact.marker
    }

    private static func applyLinks(_ links: [CardEntry], to contact: CNMutableContact) {
        contact.urlAddresses = fresh(links, originals: contact.urlAddresses) {
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

    private static func isStored(_ phones: [CardEntry], as stored: [CNLabeledValue<CNPhoneNumber>]) -> Bool {
        phones.count == stored.count && zip(phones, stored).allSatisfy { entry, value in
            entry.key == Normalizer.phone(value.value.stringValue) && entry.label == value.label
        }
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
