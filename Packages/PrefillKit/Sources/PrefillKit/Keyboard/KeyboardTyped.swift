import Foundation

// What the person has already typed before the cursor, and how well each value continues it.
// Scores: 3 starts with the word, 2 contains it, 1 is the kind the word suggests ("@" for an
// email, digits for a phone), 0 no match.
struct KeyboardTyped {
    private static let phoneCharacters = Set("0123456789+()-. ")

    private let word: String
    private let field: String
    private let phoneRun: String
    private let phoneDigits: String

    init(_ before: String) {
        let trimmed = before.trimmingCharacters(in: .whitespacesAndNewlines)
        field = trimmed.lowercased()
        word = trimmed.split(whereSeparator: \.isWhitespace).last.map { String($0).lowercased() } ?? ""
        let run = String(trimmed.reversed().prefix { Self.phoneCharacters.contains($0) }.reversed())
        let isPhoneLike = !word.isEmpty && word.allSatisfy { Self.phoneCharacters.contains($0) }
        phoneRun = isPhoneLike ? run.trimmingCharacters(in: .whitespaces) : ""
        phoneDigits = phoneRun.filter(\.isNumber)
    }

    func score(_ value: KeyboardValue) -> Int {
        if value.kind == .phone, !phoneDigits.isEmpty { return phoneScore(value) }
        guard !word.isEmpty else { return 0 }
        let texts = Self.matchable(value)
        if texts.contains(where: { $0.hasPrefix(word) }) { return 3 }
        if texts.contains(where: { $0.contains(word) }) { return 2 }
        return value.kind == .email && word.contains("@") ? 1 : 0
    }

    func replacedLength(for value: KeyboardValue) -> Int {
        guard score(value) > 0 else { return 0 }
        return value.kind == .phone && !phoneDigits.isEmpty ? phoneRun.count : word.count
    }

    // The field already ends with this value, so offering it again would type it twice.
    func isAlreadyIn(_ value: KeyboardValue) -> Bool {
        guard !field.isEmpty else { return false }
        return [value.text, value.shownText].contains { field.hasSuffix($0.lowercased()) }
    }

    private func phoneScore(_ value: KeyboardValue) -> Int {
        let digits = value.text.filter(\.isNumber)
        let local = digits.hasPrefix("1") ? String(digits.dropFirst()) : digits
        if digits.hasPrefix(phoneDigits) || local.hasPrefix(phoneDigits) { return 3 }
        return digits.contains(phoneDigits) ? 2 : 1
    }

    private static func matchable(_ value: KeyboardValue) -> [String] {
        let shown = value.shownText.lowercased()
        let bare = shown.hasPrefix("www.") ? String(shown.dropFirst(4)) : shown
        return [value.text.lowercased(), shown, bare, value.label.lowercased()]
    }
}
