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
        let page = words(fieldText)
        guard !page.isEmpty else { return [] }
        let scored = fields.compactMap { field in score(field, page: page).map { (field, $0) } }
        guard let best = scored.map(\.1).max() else { return [] }
        var seen = Set<String>()
        let values = scored.filter { $0.1 == best }.map(\.0.value).filter { seen.insert($0).inserted }
        return Array(values.prefix(maxOffered))
    }

    static func score(_ field: CustomField, page: Set<String>) -> Int? {
        ([field.label] + field.matchWords)
            .map(words)
            .filter { !$0.isEmpty && $0.isSubset(of: page) }
            .map(\.count)
            .max()
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
