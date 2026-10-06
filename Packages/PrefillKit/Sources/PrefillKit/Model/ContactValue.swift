import CryptoKit
import Foundation

public enum ContactKind: String, Codable, Sendable, CaseIterable {
    case email, phone, address, link
}

public struct PostalAddress: Codable, Sendable, Hashable {
    public let street: String
    public let city: String
    public let state: String
    public let postalCode: String
    public let country: String

    public init(street: String, city: String, state: String, postalCode: String, country: String) {
        self.street = street
        self.city = city
        self.state = state
        self.postalCode = postalCode
        self.country = country
    }

    var lines: [String] {
        let locality = [city, state, postalCode].filter { !$0.isEmpty }.joined(separator: " ")
        return [street, locality, country].filter { !$0.isEmpty }
    }
}

public enum ContactPayload: Codable, Sendable, Hashable {
    case email(String)
    case phone(String)
    case address(PostalAddress)
    // A profile or website address, kept as written with a scheme in front.
    case link(String)

    public var kind: ContactKind {
        switch self {
        case .email: .email
        case .phone: .phone
        case .address: .address
        case .link: .link
        }
    }

    public var display: String {
        switch self {
        case .email(let text), .phone(let text), .link(let text): text
        case .address(let address): address.lines.joined(separator: "\n")
        }
    }
}

public enum ValueSource: String, Codable, Sendable {
    case card, captured, typedInApp
}

public struct ContactValue: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let key: String
    public let payload: ContactPayload
    public let label: String?
    public let source: ValueSource
    public let createdAt: Date

    public init(payload: ContactPayload, label: String?, source: ValueSource, createdAt: Date) {
        let key = Normalizer.key(for: payload)
        self.id = ValueID.make(kind: payload.kind, key: key)
        self.key = key
        self.payload = payload
        self.label = label
        self.source = source
        self.createdAt = createdAt
    }

    public var kind: ContactKind { payload.kind }
    public var display: String { payload.display }

    public func with(label: String?) -> ContactValue {
        ContactValue(payload: payload, label: label, source: source, createdAt: createdAt)
    }
}

// The app and the extension both mint IDs for values they find on the card, and neither
// may write the other's document, so an ID has to be a pure function of the value.
// Name-based (RFC 4122 version 5 style) so the stored ID is not the value itself.
enum ValueID {
    private static let namespace = Array("com.tarunyadgirkar.prefill.value".utf8)

    static func make(kind: ContactKind, key: String) -> UUID {
        make(name: "\(kind.rawValue):\(key)")
    }

    static func make(name: String) -> UUID {
        let digest = Insecure.SHA1.hash(data: namespace + Array(name.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
