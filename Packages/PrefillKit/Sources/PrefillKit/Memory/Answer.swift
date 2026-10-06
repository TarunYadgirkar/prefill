import Foundation

// One thing Prefill can fill in for the person: a contact value, a link or a custom
// field's answer, with where it came from and which contact holds it now.
public struct Answer: Identifiable, Hashable, Sendable {
    public enum Question: Hashable, Sendable {
        case kind(ContactKind)
        case custom(label: String)
    }

    public enum Origin: Hashable, Sendable {
        case card
        // Nil host once the capture that saved it has aged out of the extension's events.
        case captured(host: String?)
        case learned(host: String)
        case typedInApp
        case resume
    }

    public enum Place: Hashable, Sendable {
        case meCard, prefillContact
    }

    // The value's ValueID, so usage and pins line up; for a custom field one minted the
    // same way from its folded label, so an edited answer keeps its history.
    public let id: UUID
    public let question: Question
    public let text: String
    // The card's label for a contact value or link ("_$!<Work>!$_", "GitHub"); nil for a
    // custom field, whose label is its question.
    public let label: String?
    public let origin: Origin
    public let place: Place
    public let createdAt: Date?

    public init(
        id: UUID, question: Question, text: String, label: String?, origin: Origin, place: Place, createdAt: Date?
    ) {
        self.id = id
        self.question = question
        self.text = text
        self.label = label
        self.origin = origin
        self.place = place
        self.createdAt = createdAt
    }

    static func customID(_ field: CustomField) -> UUID {
        ValueID.make(name: "custom:\(field.id)")
    }
}
