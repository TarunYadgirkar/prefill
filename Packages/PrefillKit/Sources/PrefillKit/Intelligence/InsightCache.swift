import Foundation

// One model answer, keyed by task, input and model variant, so a new model asks again.
// Label inputs use the value's ID, never the value itself.
public struct CachedInsight: Codable, Sendable, Hashable {
    public let key: String
    public let answer: String

    public init(key: String, answer: String) {
        self.key = key
        self.answer = answer
    }
}

public enum InsightKey {
    public static func label(_ value: ContactValue, host: String, variant: String) -> String {
        "label|\(variant)|\(value.id.uuidString)|\(Normalizer.registrableDomain(host))"
    }

    // A question's words, sorted, so the same question on two sites shares an answer.
    public static func answer(_ question: String, variant: String) -> String {
        "answer|\(variant)|\(CustomFieldMatcher.words(question).sorted().joined(separator: " "))"
    }

    public static func siteKind(_ host: String, variant: String) -> String {
        "site|\(variant)|\(Normalizer.registrableDomain(host))"
    }
}

public extension AppState {
    static let maxInsights = 300

    func insight(_ key: String) -> String? {
        insights.last { $0.key == key }?.answer
    }

    // Adds model answers, newest last, and keeps the site kinds the handler reads in step.
    func recording(_ answers: [CachedInsight], siteKinds kinds: [String: SiteKind]) -> AppState {
        let keys = Set(answers.map(\.key))
        let kept = insights.filter { !keys.contains($0.key) } + answers
        return copy(
            siteKinds: siteKinds.merging(kinds) { _, new in new },
            insights: Array(kept.suffix(Self.maxInsights))
        )
    }

    // The saved answer the model picked for a question, if it's still on the card.
    public func guessedAnswer(for question: String, in fields: [CustomField], variant: String) -> CustomField? {
        guard let label = insight(InsightKey.answer(question, variant: variant)), label != "none" else { return nil }
        return fields.first { $0.id == label.lowercased() }
    }

    // The kind of `host`: what the model said if the rules couldn't tell, else the rules.
    func siteKind(_ host: String) -> SiteKind {
        let site = Normalizer.registrableDomain(host)
        let rule = SiteSense.rules(host: host, emailDomains: SiteSense.workDomains(values))
        return rule == .unknown ? siteKinds[site] ?? .unknown : rule
    }
}
