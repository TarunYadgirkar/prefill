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

    public init(value: String, detail: String, kind: String) {
        self.value = value
        self.detail = detail
        self.kind = kind
    }
}
