import Foundation

// Picks the custom fields a page field asks for from the words of its label, name, id and
// placeholder. Each custom field brings phrases: its label and each match word. A phrase
// matches when every word in it appears in the page field's words, so "Graduation year"
// matches "Expected graduation year" but not "Year of birth". The field whose matching
// phrase has the most words wins; fields that tie are all offered, in the card's order.
public enum CustomFieldMatcher {
    static let maxOffered = 3

    // Words a question uses around what it asks for, which never tell two fields apart.
    private static let fillers: Set<String> = [
        "a", "an", "the", "of", "for", "and", "or", "to", "in", "on", "at", "by", "with", "from",
        "your", "you", "my", "our", "us", "we", "i", "me", "did", "do", "does", "how", "what", "which",
        "where", "when", "who", "is", "are", "was", "were", "be", "please", "enter", "select", "choose",
        "provide", "about", "this", "that", "if", "any", "required", "optional", "e", "g", "eg"
    ]

    public static func values(for fieldText: String, in fields: [CustomField]) -> [String] {
        matches(for: fieldText, in: fields).map(\.value)
    }

    // The fields behind `values`: for a value two fields share, the first in the card's order.
    static func matches(for fieldText: String, in fields: [CustomField]) -> [CustomField] {
        offered(candidates(for: fieldText, in: fields))
    }

    // Every field whose phrase matches with the most words, before scopes sort them.
    static func candidates(for fieldText: String, in fields: [CustomField]) -> [CustomField] {
        let page = words(fieldText)
        guard !page.isEmpty else { return [] }
        let scored = fields.compactMap { field in score(field, page: page).map { (field, $0) } }
        guard let best = scored.map(\.1).max() else { return [] }
        return scored.filter { $0.1 == best }.map(\.0)
    }

    // At most three, one per value.
    static func offered(_ fields: [CustomField]) -> [CustomField] {
        var seen = Set<String>()
        return Array(fields.filter { seen.insert($0.value).inserted }.prefix(maxOffered))
    }

    // A scope in the label ("Work authorization (Canada)") doesn't have to be in the question:
    // the scope rules decide what it means for the match.
    static func score(_ field: CustomField, page: Set<String>) -> Int? {
        ([AnswerScope.split(field.label).base] + field.matchWords)
            .map(words)
            .filter { !$0.isEmpty && $0.isSubset(of: page) }
            .map(\.count)
            .max()
    }

    // A question's words in one string, the same however the question orders them.
    static func key(_ text: String) -> String {
        words(text).sorted().joined(separator: " ")
    }

    // Lowercased words, split at camelCase, digits and punctuation, without fillers, and
    // with a plural "s" dropped so "Schools" and "school" agree.
    static func words(_ text: String) -> Set<String> {
        let spaced = text.replacing(/([a-z])([A-Z])/) { "\($0.1) \($0.2)" }
        let parts = spaced.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        return Set(parts.filter { !fillers.contains($0) }.map(singular))
    }

    private static func singular(_ word: String) -> String {
        guard word.count > 3, word.hasSuffix("s"), !word.hasSuffix("ss") else { return word }
        return String(word.dropLast())
    }
}
