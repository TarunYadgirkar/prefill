import Foundation

// The words a field is described by: its autocomplete tokens, its name or id split at
// camelCase and punctuation, and its label.
struct FieldWords {
    private static let someoneElseStems = ["recipient", "friend", "gift", "invit", "referr"]
    private static let sendVerbs: Set<String> = ["send", "forward", "share"]
    private static let sensitiveWords: Set<String> = [
        "password", "passcode", "passwd", "pwd", "otp", "cvv", "cvc", "csc", "ssn", "mfa"
    ]
    // Parts of a run-together name (cvv2, ccnum, userpassword) that mark a sensitive field.
    private static let sensitiveStems = ["passw", "passcode", "cvv", "cardnumber", "ccnum", "secret"]
    // A box for a phone number that talks about any of these holds something else: a card
    // or bank account, a PIN, a code sent by text, a tax ID, a birth date.
    private static let sensitivePhoneWords: Set<String> = [
        "account", "acct", "routing", "iban", "pin", "code", "token", "dob", "birth", "birthday", "passport",
        "card", "cc", "pan", "social", "tax", "pass", "secret"
    ]
    private static let sensitivePhoneStems = [
        "card", "acct", "account", "routing", "iban", "expir", "birth", "token", "social", "ssn", "otp"
    ]
    private static let sensitiveAutocomplete: Set<String> = ["current-password", "new-password", "one-time-code"]
    private static let partialPhoneTokens: Set<String> = [
        "tel-country-code", "tel-area-code", "tel-local", "tel-local-prefix", "tel-local-suffix", "tel-extension"
    ]

    private let kind: FieldKind
    private let autocomplete: Set<String>
    private let name: [String]
    private let label: [String]

    init(_ field: CapturedField) {
        kind = field.kind
        autocomplete = Self.tokens(field.autocomplete)
        name = Self.words(field.name)
        label = Self.words(field.label)
    }

    static func tokens(_ autocomplete: String?) -> Set<String> {
        Set((autocomplete ?? "").lowercased().split(whereSeparator: \.isWhitespace).map(String.init))
    }

    var isSensitive: Bool {
        let words = name + label
        return autocomplete.contains { $0.hasPrefix("cc-") || Self.sensitiveAutocomplete.contains($0) }
            || words.contains(where: Self.sensitiveWords.contains)
            || Self.hasStem(Self.sensitiveStems, in: [name.joined(), label.joined()])
            || (kind == .phone && isSensitivePhone(words))
    }

    private func isSensitivePhone(_ words: [String]) -> Bool {
        words.contains(where: Self.sensitivePhoneWords.contains) || words.contains { $0.hasPrefix("cc") }
            || Self.hasStem(Self.sensitivePhoneStems, in: words)
    }

    private static func hasStem(_ stems: [String], in texts: [String]) -> Bool {
        texts.contains { text in stems.contains { text.contains($0) } }
    }

    // "to" alone would also catch "Ship to", shipToStreet and "Email to receive your
    // receipt", so it counts only as "send to" or as the first word of a field name (to_email).
    var isForSomeoneElse: Bool {
        let words = name + label
        let hasStem = words.contains { word in Self.someoneElseStems.contains { word.contains($0) } }
        return hasStem || name.first == "to" || [name, label].contains(where: Self.hasSendTo)
    }

    var isPartialPhone: Bool {
        !autocomplete.isDisjoint(with: Self.partialPhoneTokens) || name.joined().contains("areacode")
    }

    private static func hasSendTo(_ words: [String]) -> Bool {
        zip(words, words.dropFirst()).contains { sendVerbs.contains($0) && $1 == "to" }
    }

    private static func words(_ text: String?) -> [String] {
        var words: [String] = []
        var current = ""
        var previous: Character?
        for character in text ?? "" {
            let startsWord = character.isUppercase && (previous?.isLowercase ?? false)
            if (!character.isLetter && !character.isNumber) || startsWord {
                if !current.isEmpty { words.append(current) }
                current = ""
            }
            if character.isLetter || character.isNumber { current.append(Character(character.lowercased())) }
            previous = character
        }
        return current.isEmpty ? words : words + [current]
    }
}

// The card's own name, to tell the person's name fields from someone else's.
struct OwnerName {
    private let words: Set<String>
    private let given: Set<String>
    private let family: Set<String>

    init(givenName: String, familyName: String) {
        given = Set(Self.words(givenName))
        family = Set(Self.words(familyName))
        words = given.union(family)
    }

    var isKnown: Bool { !words.isEmpty }

    // Every word must be one of the card's, so "Alex", "Rivera" and "Rivera, Alex" match
    // while "Alex Smith" does not.
    func matches(_ text: String) -> Bool {
        let typed = Self.words(text)
        return isKnown && !typed.isEmpty && typed.allSatisfy(words.contains)
    }

    // The whole name as the card has it, given and family, typed in one box or split
    // across first and last name boxes. "Rivera, Alex" counts, a lone "Alex" does not.
    func coversFullName(_ texts: [String]) -> Bool {
        let typed = Set(texts.filter(matches).flatMap(Self.words))
        return !typed.isDisjoint(with: given) && !typed.isDisjoint(with: family)
    }

    private static func words(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split { !$0.isLetter }
            .map(String.init)
    }
}
