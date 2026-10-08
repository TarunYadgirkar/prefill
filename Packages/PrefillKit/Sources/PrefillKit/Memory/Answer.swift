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

    // What sort of thing Prefill remembers, read from how it's stored: an answer whose label
    // names a country or term is a fact only there ("Work authorization (US)"), a draft is
    // text the person edits each time, and a preference is a rule Prefill follows.
    public enum Kind: Hashable, Sendable {
        case fact, contextualFact, preference, draft
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
    // The parts of an address, for callers that lay it out on one line.
    public let address: PostalAddress?
    public let kind: Kind
    // What a contextual fact applies to.
    public let scope: AnswerScope?

    public init(
        id: UUID, question: Question, text: String, label: String?, origin: Origin, place: Place, createdAt: Date?,
        address: PostalAddress? = nil, kind: Kind = .fact, scope: AnswerScope? = nil
    ) {
        self.id = id
        self.question = question
        self.text = text
        self.label = label
        self.origin = origin
        self.place = place
        self.createdAt = createdAt
        self.address = address
        self.kind = kind
        self.scope = scope
    }

    static func customID(_ field: CustomField) -> UUID {
        ValueID.make(name: "custom:\(field.id)")
    }

    static func kind(of field: CustomField) -> (Kind, AnswerScope?) {
        if field.isDraft { return (.draft, nil) }
        let scope = AnswerScope.split(field.label).scope
        return (scope == nil ? .fact : .contextualFact, scope)
    }
}

// A rule Prefill follows on every form, shown with the person's answers but not editable.
public struct Preference: Hashable, Sendable {
    public let title: String
    public let rule: String
    public var kind: Answer.Kind { .preference }

    // Self-identification questions (gender, race, veteran, disability) always get the option
    // that declines, or "No" when there is none; a text box asking one is left alone.
    public static let demographics = Preference(
        title: String(localized: "Demographic questions"),
        rule: String(localized: "Declines when the form offers it, otherwise answers No")
    )
}
