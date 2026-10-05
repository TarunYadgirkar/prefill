import Foundation

// The rows that still fit what's typed in the field, or all of them while it's empty. A
// field that already holds one of them offers nothing. Same rule as `matching` in
// web/src/dropdown.ts.
public enum RowFilter {
    public static let maxRows = 5

    private static let minPhoneDigits = 7

    public static func matching(_ rows: [AutofillRow], typed: String) -> [AutofillRow] {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return Array(rows.prefix(maxRows)) }
        if rows.contains(where: { isSame($0.value, text) }) { return [] }
        return Array(rows.filter { fits($0.value, text) }.prefix(maxRows))
    }

    // A phone number reads the same whatever its spaces, dashes and brackets, and with or
    // without a country code in front, so numbers are compared by their digits.
    private static func isPhoneLike(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy { $0.isNumber || $0.isWhitespace || "()+.-".contains($0) }
    }

    private static func digits(_ text: String) -> String {
        text.filter(\.isNumber)
    }

    private static func isSame(_ value: String, _ text: String) -> Bool {
        let typed = digits(text)
        let held = digits(value)
        guard isPhoneLike(text), isPhoneLike(value), typed.count >= minPhoneDigits, held.count >= minPhoneDigits else {
            return value.lowercased() == text
        }
        return held.hasSuffix(typed) || typed.hasSuffix(held)
    }

    private static func fits(_ value: String, _ text: String) -> Bool {
        if value.lowercased().contains(text) { return true }
        let typed = digits(text)
        return isPhoneLike(text) && isPhoneLike(value) && !typed.isEmpty && digits(value).contains(typed)
    }
}
