import Foundation

// One value the Prefill keyboard offers: what it types and the caption over it.
public struct KeyboardValue: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case email, phone, address, name, link, custom
    }

    public static let fullNameLabel = "Name"
    public static let givenNameLabel = "First name"
    public static let familyNameLabel = "Last name"

    public let kind: Kind
    // "Work email", "LinkedIn", "School".
    public let label: String
    // What gets typed; an address is one line.
    public let text: String
    public let lastUsed: Date?

    public var id: String { "\(kind.rawValue):\(label):\(text)" }

    // Kept short so the keyboard, which runs under a tight memory limit, decodes little.
    public static let maxLabel = 100
    public static let maxText = 2_000

    public init(kind: Kind, label: String, text: String, lastUsed: Date? = nil) {
        self.kind = kind
        self.label = String(label.prefix(Self.maxLabel))
        self.text = String(text.prefix(Self.maxText))
        self.lastUsed = lastUsed
    }

    // Links are typed in full but shown without the scheme, as Safari's bar shows them.
    public var shownText: String {
        guard kind == .link else { return text }
        return text.replacing(/^https?:\/\//.ignoresCase(), with: "")
    }
}

// The values the app shares with the keyboard, newest use first within each kind.
public struct KeyboardSnapshot: Codable, Hashable, Sendable {
    public static let maxValues = 80
    // Far above 80 capped values; anything bigger didn't come from the app.
    public static let maxBytes = 256 * 1024

    public let values: [KeyboardValue]
    public let writtenAt: Date

    public init(values: [KeyboardValue], writtenAt: Date) {
        self.values = values
        self.writtenAt = writtenAt
    }
}

extension PostalAddress {
    // "2400 Durant Ave, Berkeley, CA 94704": the way most one-line address boxes want it.
    public var oneLine: String {
        let region = [state, postalCode].filter { !$0.isEmpty }.joined(separator: " ")
        return [street.replacing("\n", with: ", "), city, region].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
