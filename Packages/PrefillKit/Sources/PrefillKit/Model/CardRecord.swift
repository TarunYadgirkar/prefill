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

// The three ordered arrays on the person's contact card, free of the Contacts framework
// so ranking and the write plan can be tested without a contact store.
public struct CardRecord: Codable, Sendable, Hashable {
    public let identifier: String
    public let givenName: String
    public let familyName: String
    public let emails: [CardEntry]
    public let phones: [CardEntry]
    public let addresses: [CardEntry]

    public init(
        identifier: String, givenName: String, familyName: String,
        emails: [CardEntry], phones: [CardEntry], addresses: [CardEntry]
    ) {
        self.identifier = identifier
        self.givenName = givenName
        self.familyName = familyName
        self.emails = emails
        self.phones = phones
        self.addresses = addresses
    }

    public func entries(_ kind: ContactKind) -> [CardEntry] {
        switch kind {
        case .email: emails
        case .phone: phones
        case .address: addresses
        }
    }

    public func replacing(_ kind: ContactKind, with entries: [CardEntry]) -> CardRecord {
        CardRecord(
            identifier: identifier, givenName: givenName, familyName: familyName,
            emails: kind == .email ? entries : emails,
            phones: kind == .phone ? entries : phones,
            addresses: kind == .address ? entries : addresses
        )
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
