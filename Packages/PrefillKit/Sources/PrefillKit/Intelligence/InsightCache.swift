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

    // A question's words, sorted, so the same question on two sites shares an answer, and the
    // revision of the answers it was judged against, so a changed answer asks again.
    public static func answer(_ question: String, variant: String, revision: String) -> String {
        "answer|\(variant)|\(revision)|\(CustomFieldMatcher.words(question).sorted().joined(separator: " "))"
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

    // The saved answer the model said to use for a question, judged against the answers as
    // they are now (`revision`), if it's still among `fields`.
    func guessedAnswer(
        for question: String, in fields: [CustomField], revision: String, variant: String
    ) -> CustomField? {
        guard let cached = insight(InsightKey.answer(question, variant: variant, revision: revision)),
              case .use(let label)? = AnswerVerdict(cached: cached) else { return nil }
        return fields.first { !$0.isDraft && $0.id == label.lowercased() }
    }

    func guessedAnswer(for question: String, in fields: [CustomField], variant: String) -> CustomField? {
        guessedAnswer(for: question, in: fields, revision: AnswerRevision.of(fields), variant: variant)
    }

    // The person said the model's guess doesn't answer the question.
    func rejectingGuess(for question: String, fields: [CustomField], variant: String) -> AppState {
        let key = InsightKey.answer(question, variant: variant, revision: AnswerRevision.of(fields))
        return recording([CachedInsight(key: key, answer: AnswerVerdict.unsure.cached)], siteKinds: [:])
    }

    // The kind of `host`: what the model said if the rules couldn't tell, else the rules.
    func siteKind(_ host: String) -> SiteKind {
        let site = Normalizer.registrableDomain(host)
        let rule = SiteSense.rules(host: host, emailDomains: SiteSense.workDomains(values))
        return rule == .unknown ? siteKinds[site] ?? .unknown : rule
    }
}
