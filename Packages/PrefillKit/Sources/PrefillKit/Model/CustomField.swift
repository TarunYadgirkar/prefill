import Foundation

// An answer of the person's own with no place on a contact card, such as "School" =
// "UC Berkeley". Prefill offers the value on a page field whose label, name or placeholder
// names the field's label or one of its extra match words.
public struct CustomField: Codable, Sendable, Hashable, Identifiable {
    // Answers and drafts are counted apart, so drafts never take the room learned answers need.
    public static let maxCount = 20
    public static let maxDrafts = 5
    public static let maxLabel = 40
    public static let maxValue = 200
    // A draft (a cover letter, a "why this company" paragraph) may run to several lines.
    public static let maxDraftValue = 2_000
    public static let maxMatchWords = 100

    public let label: String
    public let value: String
    public let matchWords: [String]
    // Only ever offered in Prefill's list, never filled by Fill form.
    public let isDraft: Bool

    public var id: String { label.lowercased() }

    init(label: String, value: String, matchWords: [String], isDraft: Bool = false) {
        self.label = label
        self.value = value
        self.matchWords = matchWords
        self.isDraft = isDraft
    }

    private enum CodingKeys: String, CodingKey {
        case label, value, matchWords, isDraft
    }

    // Records saved before drafts existed have no `isDraft`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decode(String.self, forKey: .label)
        value = try container.decode(String.self, forKey: .value)
        matchWords = try container.decode([String].self, forKey: .matchWords)
        isDraft = try container.decodeIfPresent(Bool.self, forKey: .isDraft) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(label, forKey: .label)
        try container.encode(value, forKey: .value)
        try container.encode(matchWords, forKey: .matchWords)
        if isDraft { try container.encode(isDraft, forKey: .isDraft) }
    }

    public struct Problem: Error, Sendable, Hashable {
        public let message: String
    }

    // Checks what the person typed: trimmed, within the limits, on one line (a draft may span
    // lines), and free of the separator the card's label uses. `alsoMatches` is comma-separated.
    public static func make(
        label: String, value: String, alsoMatches: String, isDraft: Bool = false
    ) -> Result<CustomField, Problem> {
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = alsoMatches.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let field = CustomField(label: label, value: value, matchWords: words, isDraft: isDraft)
        if let problem = check(field) { return .failure(Problem(message: problem)) }
        return .success(field)
    }

    private static func check(_ field: CustomField) -> String? {
        let limit = field.isDraft ? maxDraftValue : maxValue
        if field.label.isEmpty { return String(localized: "Enter a label, like School.") }
        if field.value.isEmpty { return String(localized: "Enter what Prefill should fill in.") }
        if field.label.count > maxLabel { return String(localized: "Keep the label under \(maxLabel) characters.") }
        if field.value.utf16.count > limit { return String(localized: "Keep the answer under \(limit) characters.") }
        if field.alsoMatches.count > maxMatchWords {
            return String(localized: "Keep the extra words under \(maxMatchWords) characters.")
        }
        let lines = [field.label] + field.matchWords
        let isPlain = lines.allSatisfy { MessageText.isPlain($0) }
            && MessageText.isPlain(field.value, allowingNewlines: field.isDraft)
        guard isPlain, !(lines + [field.value]).contains(where: { $0.contains(CustomFieldLabel.separatorCharacter) })
        else {
            return field.isDraft
                ? String(localized: "Leave out the · character.")
                : String(localized: "Leave out line breaks and the · character.")
        }
        return nil
    }

    public var alsoMatches: String { matchWords.joined(separator: ", ") }

    func relabeled(_ label: String) -> CustomField {
        CustomField(label: label, value: value, matchWords: matchWords, isDraft: isDraft)
    }
}

extension [CustomField] {
    // Answers only: drafts have their own limit.
    public var answerCount: Int { count { !$0.isDraft } }

    // The list with `field` in place of `replacing` (or added at the end), or why it can't be.
    public func saving(
        _ field: CustomField, replacing old: CustomField?
    ) -> Result<[CustomField], CustomField.Problem> {
        let others = filter { $0.id != old?.id }
        if others.contains(where: { $0.id == field.id }) {
            return .failure(.init(message: String(localized: "You already have a field called \(field.label).")))
        }
        let sameKind = others.count { $0.isDraft == field.isDraft }
        let limit = field.isDraft ? CustomField.maxDrafts : CustomField.maxCount
        guard sameKind < limit || old?.isDraft == field.isDraft else {
            return .failure(.init(message: field.isDraft
                ? String(localized: "Prefill keeps up to \(limit) drafts.")
                : String(localized: "Prefill keeps up to \(limit) fields.")))
        }
        guard let old, let index = firstIndex(where: { $0.id == old.id }) else { return .success(self + [field]) }
        var saved = self
        saved[index] = field
        return .success(saved)
    }
}

// How a custom field sits on the card: one of its related names, whose label is the field's
// label followed by " · Prefill" and any match words, such as "School · Prefill · university,
// college". The marker keeps the person's real related names (a spouse, a parent) out of
// Prefill's hands, and still reads as a label in the Contacts app. A draft's marker is
// "Prefill draft": builds from before drafts read it as a related name Prefill didn't make,
// so they neither offer nor fill it, and keep it as it is when they rewrite the card.
public enum CustomFieldLabel {
    static let separatorCharacter: Character = "·"
    static let separator = " · "
    static let marker = "Prefill"
    static let draftMarker = "Prefill draft"

    public static func encode(_ field: CustomField) -> String {
        let words = field.matchWords.isEmpty ? [] : [field.alsoMatches]
        return ([field.label, field.isDraft ? draftMarker : marker] + words).joined(separator: separator)
    }

    // Nil for a related name Prefill didn't make.
    public static func decode(label: String?, value: String) -> CustomField? {
        guard let parts = label?.components(separatedBy: separator), (2...3).contains(parts.count),
              [marker, draftMarker].contains(parts[1]), !parts[0].isEmpty, !value.isEmpty else { return nil }
        let words = parts.count == 3 ? parts[2].split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty } : []
        return CustomField(label: parts[0], value: value, matchWords: words, isDraft: parts[1] == draftMarker)
    }
}
