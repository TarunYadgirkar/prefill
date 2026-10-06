import Foundation

// An answer of the person's own with no place on a contact card, such as "School" =
// "UC Berkeley". Prefill offers the value on a page field whose label, name or placeholder
// names the field's label or one of its extra match words.
public struct CustomField: Codable, Sendable, Hashable, Identifiable {
    public static let maxCount = 20
    public static let maxLabel = 40
    public static let maxValue = 200
    public static let maxMatchWords = 100

    public let label: String
    public let value: String
    public let matchWords: [String]

    public var id: String { label.lowercased() }

    init(label: String, value: String, matchWords: [String]) {
        self.label = label
        self.value = value
        self.matchWords = matchWords
    }

    public struct Problem: Error, Sendable, Hashable {
        public let message: String
    }

    // Checks what the person typed: trimmed, within the limits, on one line, and free of
    // the separator the card's label uses. `alsoMatches` is comma-separated.
    public static func make(label: String, value: String, alsoMatches: String) -> Result<CustomField, Problem> {
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = alsoMatches.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if let problem = check(label: label, value: value, words: words) { return .failure(Problem(message: problem)) }
        return .success(CustomField(label: label, value: value, matchWords: words))
    }

    private static func check(label: String, value: String, words: [String]) -> String? {
        if label.isEmpty { return String(localized: "Enter a label, like School.") }
        if value.isEmpty { return String(localized: "Enter what Prefill should fill in.") }
        if label.count > maxLabel { return String(localized: "Keep the label under \(maxLabel) characters.") }
        if value.count > maxValue { return String(localized: "Keep the answer under \(maxValue) characters.") }
        if words.joined(separator: ", ").count > maxMatchWords {
            return String(localized: "Keep the extra words under \(maxMatchWords) characters.")
        }
        let texts = [label, value] + words
        guard texts.allSatisfy({ MessageText.isPlain($0) && !$0.contains(CustomFieldLabel.separatorCharacter) }) else {
            return String(localized: "Leave out line breaks and the · character.")
        }
        return nil
    }

    public var alsoMatches: String { matchWords.joined(separator: ", ") }

    func relabeled(_ label: String) -> CustomField {
        CustomField(label: label, value: value, matchWords: matchWords)
    }
}

extension [CustomField] {
    // The list with `field` in place of `replacing` (or added at the end), or why it can't be.
    public func saving(
        _ field: CustomField, replacing old: CustomField?
    ) -> Result<[CustomField], CustomField.Problem> {
        let others = filter { $0.id != old?.id }
        if others.contains(where: { $0.id == field.id }) {
            return .failure(.init(message: String(localized: "You already have a field called \(field.label).")))
        }
        guard let old, let index = firstIndex(where: { $0.id == old.id }) else {
            guard count < CustomField.maxCount else {
                let limit = CustomField.maxCount
                return .failure(.init(message: String(localized: "Prefill keeps up to \(limit) fields.")))
            }
            return .success(self + [field])
        }
        var saved = self
        saved[index] = field
        return .success(saved)
    }
}

// How a custom field sits on the card: one of its related names, whose label is the field's
// label followed by " · Prefill" and any match words, such as "School · Prefill · university,
// college". The marker keeps the person's real related names (a spouse, a parent) out of
// Prefill's hands, and still reads as a label in the Contacts app.
public enum CustomFieldLabel {
    static let separatorCharacter: Character = "·"
    static let separator = " · "
    static let marker = "Prefill"

    public static func encode(_ field: CustomField) -> String {
        ([field.label, marker] + (field.matchWords.isEmpty ? [] : [field.alsoMatches])).joined(separator: separator)
    }

    // Nil for a related name Prefill didn't make.
    public static func decode(label: String?, value: String) -> CustomField? {
        guard let parts = label?.components(separatedBy: separator), (2...3).contains(parts.count),
              parts[1] == marker, !parts[0].isEmpty, !value.isEmpty else { return nil }
        let words = parts.count == 3 ? parts[2].split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty } : []
        return CustomField(label: parts[0], value: value, matchWords: words)
    }
}
