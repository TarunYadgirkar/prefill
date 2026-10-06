import Foundation

// A focused field as plain data, read through Accessibility on the Mac. Mirrors
// FieldDescription in web/src/classify.ts, which decides what the field asks for.
public struct FieldDescription: Codable, Sendable, Hashable {
    public enum Tag: String, Codable, Sendable {
        case input, select, textarea
    }

    public let tag: Tag
    public let type: String
    public let autocomplete: String?
    public let label: String
    public let names: [String]
    public let placeholder: String
    public let signIn: Bool

    public init(
        tag: Tag, type: String = "text", autocomplete: String? = nil, label: String = "", names: [String] = [],
        placeholder: String = "", signIn: Bool = false
    ) {
        self.tag = tag
        self.type = type
        self.autocomplete = autocomplete
        self.label = label
        self.names = names
        self.placeholder = placeholder
        self.signIn = signIn
    }
}

// One row of the suggestion panel: the value, a few words on what it is, and its kind
// (a contact kind, "link" or "custom") for the symbol.
public struct AutofillRow: Codable, Sendable, Hashable {
    public let value: String
    public let detail: String
    public let kind: String
    // What to tell the router when the person picks the row, with an empty host.
    public let pick: PickedRequest?

    public init(value: String, detail: String, kind: String, pick: PickedRequest? = nil) {
        self.value = value
        self.detail = detail
        self.kind = kind
        self.pick = pick
    }
}

// The question a field answers when the page only prints it before the field, with nothing
// tying the two together, as Partiful's event questionnaires do: "First name", " *", then
// the box. Read from what comes before the field among its siblings, nearest first.
public enum NearbyLabel {
    public static let reach = 4

    // `preceding` holds the text of each sibling before the field, nearest first, and nil
    // for one that isn't plain text. A marker such as " *" is skipped; another control or
    // a group ends the search, since the words before it belong to that one.
    public static func pick(preceding: [String?]) -> String? {
        for text in preceding.prefix(reach) {
            guard let text else { return nil }
            if text.contains(where: \.isLetter) { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        return nil
    }
}
