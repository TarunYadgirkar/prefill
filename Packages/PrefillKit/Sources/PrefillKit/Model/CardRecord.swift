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

    public var links: [CardEntry] { storedLinks ?? [] }
    var knowsLinks: Bool { storedLinks != nil }

    public init(
        identifier: String, givenName: String, familyName: String,
        emails: [CardEntry], phones: [CardEntry], addresses: [CardEntry], links: [CardEntry] = []
    ) {
        self.init(
            identifier: identifier, givenName: givenName, familyName: familyName,
            emails: emails, phones: phones, addresses: addresses, storedLinks: links
        )
    }

    private init(
        identifier: String, givenName: String, familyName: String,
        emails: [CardEntry], phones: [CardEntry], addresses: [CardEntry], storedLinks: [CardEntry]?
    ) {
        self.identifier = identifier
        self.givenName = givenName
        self.familyName = familyName
        self.emails = emails
        self.phones = phones
        self.addresses = addresses
        self.storedLinks = storedLinks
    }

    private enum CodingKeys: String, CodingKey {
        case identifier, givenName, familyName, emails, phones, addresses
        case storedLinks = "links"
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
            storedLinks: kind == .link ? entries : storedLinks
        )
    }
}

// The last line against losing a value: whatever planned a save, a save that only reorders
// and adds keeps every value the card had and adds only a few.
extension CardRecord {
    static let maxAdditionsPerKind = 3

    func keepsEveryValue(of basis: CardRecord) -> Bool {
        ContactKind.allCases.allSatisfy { kind in
            let before = Set(basis.entries(kind).map(\.key))
            let after = Set(entries(kind).map(\.key))
            return before.isSubset(of: after) && after.subtracting(before).count <= Self.maxAdditionsPerKind
        }
    }

    // This card with any value of `basis` it lost put back at the end.
    func restoringValues(of basis: CardRecord) -> CardRecord {
        ContactKind.allCases.reduce(self) { card, kind in
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
