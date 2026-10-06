import Foundation

// The person picked a value from Prefill's list under a field. The app remembers the pick
// for the site (contact values and links) or for the question (custom answers), so the
// value comes first there next time. Nothing is written to the card.
public enum PickKind: String, Codable, Sendable, CaseIterable {
    case email, phone, address, link, custom

    var contactKind: ContactKind? { ContactKind(rawValue: rawValue) }
}

public struct PickedRequest: Codable, Sendable, Hashable {
    public let host: String
    public let kind: PickKind
    // The text that went into the field: an address's street line for an address.
    public let value: String
    // The field's own words, for a custom answer.
    public let question: String?

    public init(host: String, kind: PickKind, value: String, question: String? = nil) {
        self.host = host
        self.kind = kind
        self.value = value
        self.question = question
    }
}

public struct PickedResponse: Codable, Sendable, Hashable {
    public let remembered: Bool

    public init(remembered: Bool) {
        self.remembered = remembered
    }
}
