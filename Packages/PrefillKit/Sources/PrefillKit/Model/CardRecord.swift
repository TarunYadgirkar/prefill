import Foundation

public struct CardEntry: Codable, Sendable, Hashable {
    public let label: String?
    public let payload: ContactPayload

    public init(label: String?, payload: ContactPayload) {
        self.label = label
        self.payload = payload
    }

    public var key: String { Normalizer.key(for: payload) }
}

// The ordered arrays on the person's contact card, free of the Contacts framework so
// ranking and the write plan can be tested without a contact store.
public struct CardRecord: Codable, Sendable, Hashable {
    public let identifier: String
    public let givenName: String
    public let familyName: String
    public let emails: [CardEntry]
    public let phones: [CardEntry]
    public let addresses: [CardEntry]
    // Nil in a record stored before Prefill read the card's links, such as the original
    // card snapshot, which then says nothing about them.
    private let storedLinks: [CardEntry]?
    // The related names Prefill made for the person's custom fields, in the card's order.
    // Nil in a record stored before Prefill read them.
    private let storedCustomFields: [CustomField]?

    public var links: [CardEntry] { storedLinks ?? [] }
    var knowsLinks: Bool { storedLinks != nil }
    public var customFields: [CustomField] { storedCustomFields ?? [] }
    var knowsCustomFields: Bool { storedCustomFields != nil }

    public init(
        identifier: String, givenName: String, familyName: String,
        emails: [CardEntry], phones: [CardEntry], addresses: [CardEntry], links: [CardEntry] = [],
        customFields: [CustomField] = []
    ) {
        self.init(
            identifier: identifier, givenName: givenName, familyName: familyName,
            emails: emails, phones: phones, addresses: addresses, storedLinks: links,
            storedCustomFields: customFields
        )
    }

    private init(
        identifier: String, givenName: String, familyName: String,
        emails: [CardEntry], phones: [CardEntry], addresses: [CardEntry], storedLinks: [CardEntry]?,
        storedCustomFields: [CustomField]?
    ) {
        self.identifier = identifier
        self.givenName = givenName
        self.familyName = familyName
        self.emails = emails
        self.phones = phones
        self.addresses = addresses
        self.storedLinks = storedLinks
        self.storedCustomFields = storedCustomFields
    }

    private enum CodingKeys: String, CodingKey {
        case identifier, givenName, familyName, emails, phones, addresses
        case storedLinks = "links"
        case storedCustomFields = "customFields"
    }

    public func entries(_ kind: ContactKind) -> [CardEntry] {
        switch kind {
        case .email: emails
        case .phone: phones
        case .address: addresses
        case .link: links
        }
    }

    public func replacing(_ kind: ContactKind, with entries: [CardEntry]) -> CardRecord {
        CardRecord(
            identifier: identifier, givenName: givenName, familyName: familyName,
            emails: kind == .email ? entries : emails,
            phones: kind == .phone ? entries : phones,
            addresses: kind == .address ? entries : addresses,
            storedLinks: kind == .link ? entries : storedLinks, storedCustomFields: storedCustomFields
        )
    }

    public func replacingCustomFields(with fields: [CustomField]) -> CardRecord {
        CardRecord(
            identifier: identifier, givenName: givenName, familyName: familyName, emails: emails,
            phones: phones, addresses: addresses, storedLinks: storedLinks, storedCustomFields: fields
        )
    }
}

// The last line against losing a value: whatever planned a save, a save that only reorders
// and adds keeps every value the card had and adds only a few. Custom fields change only
// when the person edits them in the app, so such a save leaves them exactly as they were.
extension CardRecord {
    static let maxAdditionsPerKind = 3

    func keepsEveryValue(of basis: CardRecord) -> Bool {
        customFields == basis.customFields && ContactKind.allCases.allSatisfy { kind in
            let before = Set(basis.entries(kind).map(\.key))
            let after = Set(entries(kind).map(\.key))
            return before.isSubset(of: after) && after.subtracting(before).count <= Self.maxAdditionsPerKind
        }
    }

    // This card with any value or custom field of `basis` it lost put back at the end.
    func restoringValues(of basis: CardRecord) -> CardRecord {
        let present = Set(customFields)
        let lostFields = basis.customFields.filter { !present.contains($0) }
        let restored = lostFields.isEmpty ? self : replacingCustomFields(with: customFields + lostFields)
        return ContactKind.allCases.reduce(restored) { card, kind in
            let present = Set(card.entries(kind).map(\.key))
            let lost = basis.entries(kind).filter { !present.contains($0.key) }
            return lost.isEmpty ? card : card.replacing(kind, with: card.entries(kind) + lost)
        }
    }
}

public struct CardLink: Codable, Sendable, Hashable {
    public let contactIdentifier: String
    public let containerIdentifier: String?
    public let linkedIdentifiers: [String]
    public let original: CardRecord
    public let snapshotAt: Date

    public init(
        contactIdentifier: String, containerIdentifier: String?,
        linkedIdentifiers: [String], original: CardRecord, snapshotAt: Date
    ) {
        self.contactIdentifier = contactIdentifier
        self.containerIdentifier = containerIdentifier
        self.linkedIdentifiers = linkedIdentifiers
        self.original = original
        self.snapshotAt = snapshotAt
    }
}
