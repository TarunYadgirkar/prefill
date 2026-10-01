import Foundation

// What a typed value must look like before Prefill keeps it. A page decides what goes in
// its fields, so anything that isn't plainly an email, a phone number or an address is
// dropped rather than offered back to the person by Safari.
enum ValueRules {
    private static let maxEmail = 254
    private static let maxEmailLocal = 64
    private static let maxDomainLabel = 63
    private static let minPhoneDigits = 7
    private static let maxPhoneDigits = 15
    // Digit runs of this size typed with no separators are PINs or one-time codes unless
    // the field says it holds a whole phone number.
    private static let maxCodeDigits = 8
    private static let cardDigits = 13...15
    private static let fullPhoneTokens: Set<String> = ["tel", "tel-national"]
    private static let phoneSymbols: Set<Character> = ["+", "(", ")", "-", ".", "/", "#", "x", "X", " "]
    private static let urlMarks = ["://", "www.", "http"]

    static func isEmail(_ text: String) -> Bool {
        let parts = text.split(separator: "@", omittingEmptySubsequences: false)
        guard text.count <= maxEmail, parts.count == 2, let local = parts.first, let domain = parts.last,
              !text.contains(where: { $0.isWhitespace || isControl($0) }) else { return false }
        return !local.isEmpty && local.count <= maxEmailLocal && isDomain(domain)
    }

    static func isPhone(_ text: String, autocomplete: String?) -> Bool {
        guard text.allSatisfy({ ($0.isASCII && $0.isNumber) || phoneSymbols.contains($0) }) else { return false }
        let digits = text.filter(\.isNumber)
        guard (minPhoneDigits...maxPhoneDigits).contains(digits.count) else { return false }
        let isTagged = !FieldWords.tokens(autocomplete).isDisjoint(with: fullPhoneTokens)
        if digits == text, digits.count <= maxCodeDigits, !isTagged { return false }
        return text.hasPrefix("+") || !(cardDigits.contains(digits.count) && passesLuhn(digits))
    }

    static func isAddress(_ address: PostalAddress) -> Bool {
        let parts = [address.city, address.state, address.postalCode, address.country]
        return !address.street.isEmpty && address.street.count <= MessageLimits.street
            && parts.allSatisfy { $0.count <= MessageLimits.part }
            && ([address.street] + parts).allSatisfy(isPlainText)
    }

    private static func isDomain(_ domain: Substring) -> Bool {
        let labels = domain.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.last?.allSatisfy(\.isNumber) == false else { return false }
        return labels.allSatisfy { label in
            !label.isEmpty && label.count <= maxDomainLabel && label.first != "-" && label.last != "-"
                && label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }
    }

    private static func isPlainText(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return !text.contains { $0 != "\n" && isControl($0) } && !urlMarks.contains(where: lowered.contains)
    }

    private static func isControl(_ character: Character) -> Bool {
        character.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    private static func passesLuhn(_ digits: String) -> Bool {
        let values = digits.reversed().compactMap(\.wholeNumberValue)
        let sum = values.enumerated().reduce(0) { total, item in
            let doubled = item.offset.isMultiple(of: 2) ? item.element : item.element * 2
            return total + (doubled > 9 ? doubled - 9 : doubled)
        }
        return sum.isMultiple(of: 10)
    }
}
