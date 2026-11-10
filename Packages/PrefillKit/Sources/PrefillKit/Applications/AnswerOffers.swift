import Foundation

// An answer from an application the person sent that Prefill offers to keep: "Save your
// School answer?". Nothing is saved until they say so in the Inbox. Offers aren't stored:
// they are read from the recent applications each time, less what is already saved, what the
// person dismissed and what neither the rules nor the on-device model call reusable.
public struct AnswerOffer: Sendable, Hashable, Identifiable {
    public let question: String
    public let field: CustomField
    public let host: String
    public let date: Date

    public var id: String { field.id }
}

// Anything that can say whether an answer is one the person would give again on another form,
// and name it: Apple's on-device model, or a stand-in in tests.
public protocol OfferJudging: Sendable {
    // A short name for the answer ("Years of experience"), or nil for a one-off.
    func reusableLabel(question: String, answer: String) async -> String?
}

public enum AnswerOffers {
    // Applications older than this no longer offer anything.
    static let window: TimeInterval = 14 * 86_400
    static let maxApplications = 10
    public static let maxOffers = 5
    // Questions the model is asked about in one batch.
    static let maxAsked = 12
    static let maxQuestion = 200
    private static let notReusable = "no"

    struct Candidate: Hashable {
        let question: String
        let answer: String
        let host: String
        let date: Date
    }

    // Contact details live on the card and files aren't answers; the person adds demographic
    // answers themselves; a consent box isn't an answer at all.
    nonisolated(unsafe) private static let notAnAnswer: [Regex<Substring>] = [
        /(?i)\bname\b|e-?mail|phone|mobile|address|\bcity\b|\bstate\b|zip|postal|country of residence/,
        /(?i)linkedin|github|website|portfolio|\burl\b|resume|\bcv\b|cover letter/,
        /(?i)gender|\brace\b|ethnic|hispanic|latino|veteran|disab|orientation|pronoun/,
        /(?i)birth|\bage\b|social security|\bssn\b|passport|licen[sc]e|password|salary|compensation/,
        /(?i)agree|acknowledge|certify|consent|signature|i understand/
    ]
    nonisolated(unsafe) private static let contactLike = /@|https?:|www\.|\.com\b|(?:\d[\s().-]*){7,}/

    // The questions the rules know, as web/src/learn.ts tells them apart.
    nonisolated(unsafe) private static let rules: [(JobQuestion, Regex<Substring>)] = [
        (.heard, /(?i)how did you (?:hear|find)|hear about/),
        (.gpa, /(?i)\bgpa\b|grade point/),
        (.graduation, /(?i)graduation|grad (?:date|year)/),
        (.major, /(?i)\bmajor\b|field of study|discipline/),
        (.degree, /(?i)\bdegree\b/),
        (.school, /(?i)\bschool\b|university|college/)
    ]
    nonisolated(unsafe) private static let notAsked = /(?i)high school|\bid\b|\bnumber\b/

    static func jobQuestion(asking text: String) -> JobQuestion? {
        switch WorkQuestion(asking: text) {
        case .both: return nil
        case .authorization: return .authorization
        case .sponsorship: return .sponsorship
        case nil: break
        }
        guard !text.contains(notAsked) else { return nil }
        return rules.first { text.contains($0.1) }?.0
    }

    // What the recent applications asked that no saved answer covers, newest first, each
    // question's wording once.
    static func candidates(
        _ applications: [SubmittedApplication], fields: [CustomField], now: Date
    ) -> [Candidate] {
        let recent = applications.filter { now.timeIntervalSince($0.date) < window }
            .sorted { $0.date > $1.date }
            .prefix(maxApplications)
        let values = Set(fields.map { $0.value.lowercased() })
        var seen = Set<String>()
        return recent.flatMap { application in
            application.fields.compactMap { field -> Candidate? in
                let question = field.question.trimmingCharacters(in: .whitespacesAndNewlines)
                let answer = field.answer.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !question.isEmpty, question.count <= maxQuestion,
                      !notAnAnswer.contains(where: { question.contains($0) }),
                      !answer.isEmpty, answer.count <= CustomField.maxValue, !answer.contains("\n"),
                      !answer.contains(contactLike), !values.contains(answer.lowercased()),
                      CustomFieldMatcher.matches(for: question, in: fields).isEmpty,
                      seen.insert(CustomFieldMatcher.key(question)).inserted else { return nil }
                return Candidate(question: question, answer: answer, host: application.host, date: application.date)
            }
        }
    }

    private static func ruleField(_ candidate: Candidate) -> CustomField? {
        guard let question = jobQuestion(asking: candidate.question) else { return nil }
        let scope = AnswerScope.find(in: candidate.question, kinds: question.scopeKinds)
        return question.field(answer: candidate.answer, scope: scope)
    }

    static func verdictKey(_ question: String, variant: String) -> String {
        "offer|\(variant)|\(CustomFieldMatcher.key(question))"
    }

    static func dismissKey(_ field: CustomField) -> String {
        "offerNo|\(field.id)|\(AnswerRevision.hash(field.value))"
    }

    private static func field(for candidate: Candidate, state: AppState, variant: String) -> CustomField? {
        if let field = ruleField(candidate) { return field }
        guard let label = state.insight(verdictKey(candidate.question, variant: variant)), label != notReusable else {
            return nil
        }
        return try? CustomField.make(label: label, value: candidate.answer, alsoMatches: "").get()
    }

    // What offers are read from: the applications, the saved answers, the cached verdicts and
    // dismissals in the app's state, and which model gave the verdicts.
    public struct Source: Sendable {
        let applications: [SubmittedApplication]
        let fields: [CustomField]
        let state: AppState
        let variant: String
        let now: Date

        public init(
            applications: [SubmittedApplication], fields: [CustomField], state: AppState, variant: String, now: Date
        ) {
            self.applications = applications
            self.fields = fields
            self.state = state
            self.variant = variant
            self.now = now
        }

        var candidates: [Candidate] { AnswerOffers.candidates(applications, fields: fields, now: now) }
    }

    // What to show in the Inbox: one per answer name, newest first.
    public static func offers(_ source: Source) -> [AnswerOffer] {
        var seen = Set(source.fields.map(\.id))
        let offers = source.candidates.compactMap { candidate -> AnswerOffer? in
            guard let field = field(for: candidate, state: source.state, variant: source.variant),
                  source.state.insight(dismissKey(field)) == nil, seen.insert(field.id).inserted else { return nil }
            return AnswerOffer(question: candidate.question, field: field, host: candidate.host, date: candidate.date)
        }
        return Array(offers.prefix(maxOffers))
    }

    // Asks the model about each question the rules don't know, once per model, and returns the
    // verdicts to cache. A name that can't label an answer counts as a one-off.
    public static func ask(_ source: Source, judge: some OfferJudging) async -> [CachedInsight] {
        let unjudged = source.candidates.filter { candidate in
            let key = verdictKey(candidate.question, variant: source.variant)
            return ruleField(candidate) == nil && source.state.insight(key) == nil
        }
        var verdicts: [CachedInsight] = []
        for candidate in unjudged.prefix(maxAsked) {
            let name = await judge.reusableLabel(question: candidate.question, answer: candidate.answer)
            let named = name.flatMap {
                try? CustomField.make(label: $0, value: candidate.answer, alsoMatches: "").get()
            }
            verdicts.append(CachedInsight(
                key: verdictKey(candidate.question, variant: source.variant), answer: named?.label ?? notReusable
            ))
        }
        return verdicts
    }
}

public extension AppState {
    // The person said not to keep this answer; the same answer isn't offered again.
    func dismissing(_ offer: AnswerOffer) -> AppState {
        recording([CachedInsight(key: AnswerOffers.dismissKey(offer.field), answer: "no")], siteKinds: [:])
    }
}
