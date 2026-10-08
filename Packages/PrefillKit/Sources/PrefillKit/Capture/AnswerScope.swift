import Foundation

// What an answer applies to, read from the question's own words by rules: a country ("Are
// you legally authorized to work in the United States?") or a term ("Summer 2026"). It rides
// in the custom field's label, "Work authorization (US)", so it syncs through Contacts with
// the label. Employers and schools aren't scopes: in real forms they appear as "work for
// Braeburn", where the answer doesn't depend on the employer.
public struct AnswerScope: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case country, term
    }

    public let kind: Kind
    // "US", "Canada", "Summer 2026": what the label and the list show.
    public let name: String

    // Case matters for the short codes, so "tell us" isn't the US. Regex isn't Sendable, but
    // these are never changed after they're made.
    nonisolated(unsafe) private static let countries: [(name: String, pattern: Regex<Substring>)] = [
        ("US", /\b(?:USA?|U\.S\.?(?:A\.?)?)(?![A-Za-z])|(?i:\bunited states\b|\bH-?1B\b|\bgreen card\b)/),
        ("Canada", /(?i)\bcanad(?:a|ian)\b/),
        ("UK", /\bU\.?K\.?(?![A-Za-z])|(?i:\bunited kingdom\b|\bgreat britain\b|\bbritain\b)/),
        ("EU", /\bEU\b|(?i:\beuropean union\b)/),
        ("India", /(?i)\bindia\b/),
        ("Australia", /(?i)\baustralia\b/),
        ("New Zealand", /(?i)\bnew zealand\b/),
        ("Ireland", /(?i)\bireland\b/),
        ("Germany", /(?i)\bgermany\b/),
        ("France", /(?i)\bfrance\b/),
        ("Netherlands", /(?i)\bnetherlands\b/),
        ("Switzerland", /(?i)\bswitzerland\b/),
        ("Singapore", /(?i)\bsingapore\b/),
        ("Israel", /(?i)\bisrael\b/),
        ("Japan", /(?i)\bjapan\b/),
        ("Mexico", /(?i)\bmexico\b/),
        ("Brazil", /(?i)\bbrazil\b/)
    ]
    nonisolated(unsafe) private static let term = /(?i)\b(spring|summer|fall|autumn|winter)\s+(20\d\d)\b/
    // "Work authorization (US)": a label, a space, and a scope in brackets at the end.
    nonisolated(unsafe) private static let scoped = /^(.*\S) \(([^()]+)\)$/

    // The one country the text names, else its term. A question that names two countries
    // asks about neither alone, so it has no country.
    public static func find(in text: String, kinds: Set<Kind>) -> AnswerScope? {
        if kinds.contains(.country) {
            let named = countries.filter { text.contains($0.pattern) }
            if named.count == 1, let country = named.first { return AnswerScope(kind: .country, name: country.name) }
        }
        guard kinds.contains(.term), let match = text.firstMatch(of: term) else { return nil }
        let season = match.1.lowercased() == "autumn" ? "Fall" : match.1.capitalized
        return AnswerScope(kind: .term, name: "\(season) \(match.2)")
    }

    // A label's question and scope: "Work authorization (US)" is Work authorization in the US.
    // Brackets holding anything else ("Phone (work)") are part of the label.
    public static func split(_ label: String) -> (base: String, scope: AnswerScope?) {
        guard let match = label.wholeMatch(of: scoped) else { return (label, nil) }
        let inner = String(match.2)
        if countries.contains(where: { $0.name == inner }) {
            return (String(match.1), AnswerScope(kind: .country, name: inner))
        }
        guard let found = find(in: inner, kinds: [.term]), found.name == inner else { return (label, nil) }
        return (String(match.1), found)
    }

    public func label(_ base: String) -> String {
        "\(base) (\(name))"
    }
}

// How a saved answer's scope sits with the question's: the same (or both unscoped) fills,
// a clash (a US answer for a Canada question) is never offered, and anything else (one
// side unscoped, or a country against a term) is offered without being filled.
enum ScopeFit {
    case same, other, clash

    init(answer: AnswerScope?, asked: AnswerScope?) {
        switch (answer, asked) {
        case (nil, nil): self = .same
        case let (answer?, asked?) where answer == asked: self = .same
        case let (answer?, asked?) where answer.kind == asked.kind: self = .clash
        default: self = .other
        }
    }
}

// The custom fields a question matches, sorted by how their scope sits with the question's.
struct ScopedMatches {
    var fill: [CustomField] = []
    var suggest: [CustomField] = []
    var withheld: [CustomField] = []
    // The question's scope when an answer was withheld for clashing with it.
    var missing: AnswerScope?

    var isEmpty: Bool { fill.isEmpty && suggest.isEmpty && withheld.isEmpty }
}

extension JobQuestion {
    // What an answer to the question can depend on. Work rules differ by country and can
    // change by term; a GPA changes by term; the rest stay put.
    public var scopeKinds: Set<AnswerScope.Kind> {
        switch self {
        case .authorization, .sponsorship: [.country, .term]
        case .gpa: [.term]
        case .school, .degree, .major, .graduation, .heard: []
        }
    }

    init?(label: String) {
        let wanted = label.lowercased()
        guard let found = Self.allCases.first(where: { $0.label.lowercased() == wanted }) else { return nil }
        self = found
    }
}

extension CustomFieldMatcher {
    // Each match with how its scope sits with the question. A field's scope kinds are its
    // question's, so a person's own "Visa" field fills any question it matches, as before.
    static func scopedMatches(for fieldText: String, in fields: [CustomField]) -> ScopedMatches {
        candidates(for: fieldText, in: fields).reduce(into: ScopedMatches()) { found, field in
            let (base, scope) = AnswerScope.split(field.label)
            let kinds = (JobQuestion(label: base)?.scopeKinds ?? []).union(scope.map { [$0.kind] } ?? [])
            let asked = AnswerScope.find(in: fieldText, kinds: kinds)
            switch ScopeFit(answer: scope, asked: asked) {
            case .same: found.fill.append(field)
            case .other: found.suggest.append(field)
            case .clash:
                found.withheld.append(field)
                found.missing = found.missing ?? asked
            }
        }
    }
}
