import Foundation

// A form question none of the rules matched, as the page shows it: its words, the nearest
// heading above it and, for a list, its options.
public struct AnswerQuestion: Hashable, Sendable {
    public let text: String
    public let heading: String?
    public let options: [String]

    public init(text: String, heading: String? = nil, options: [String] = []) {
        self.text = text
        self.heading = heading
        self.options = options
    }

    init(_ question: FormQuestion) {
        self.init(text: question.text, heading: question.heading, options: question.options ?? [])
    }

    // What the cached verdict depends on besides the words, so a page that shows a question
    // under its own heading or options can't settle the verdict for that question elsewhere.
    // Empty for a question shown with neither.
    public var context: String {
        Self.contextKey(heading: heading, options: options)
    }

    static func contextKey(heading: String?, options: [String]) -> String {
        guard heading != nil || !options.isEmpty else { return "" }
        return AnswerRevision.hash(([heading ?? ""] + options).joined(separator: "\u{1E}"))
    }
}

// A saved answer the model may pick, with what it applies to.
public struct AnswerCandidate: Hashable, Sendable {
    public let label: String
    public let value: String
    public let scope: AnswerScope?

    // Drafts are only ever offered by the person's own pick, so the model never sees them.
    public static func from(_ fields: [CustomField]) -> [AnswerCandidate] {
        fields.filter { !$0.isDraft }.map { field in
            AnswerCandidate(label: field.label, value: field.value, scope: AnswerScope.split(field.label).scope)
        }
    }
}

// What the model makes of a question: use one saved answer, the question needs a new one, or
// it can't tell. Only `use` shows, as "Suggested", and never fills.
public enum AnswerVerdict: Hashable, Sendable {
    case use(label: String)
    case needsNew
    case unsure

    // The model's raw reply, held to the candidates: a name that isn't one is unsure, and an
    // answer kept for another country or term than the question names needs a new one.
    public static func checked(
        verdict: String, name: String, question: AnswerQuestion, candidates: [AnswerCandidate]
    ) -> AnswerVerdict {
        switch verdict {
        case "needsNew": return .needsNew
        case "use": break
        default: return .unsure
        }
        guard let chosen = candidates.first(where: { $0.label.caseInsensitiveCompare(name) == .orderedSame }) else {
            return .unsure
        }
        let kinds: Set<AnswerScope.Kind> = chosen.scope.map { [$0.kind] } ?? []
        let asked = AnswerScope.find(in: question.text, kinds: kinds)
        return ScopeFit(answer: chosen.scope, asked: asked) == .clash ? .needsNew : .use(label: chosen.label)
    }

    // How the app's cache keeps it, read by the Safari handler.
    var cached: String {
        switch self {
        case .use(let label): "use:\(label)"
        case .needsNew: "needsNew"
        case .unsure: "unsure"
        }
    }

    init?(cached: String) {
        switch cached {
        case "needsNew": self = .needsNew
        case "unsure", "none": self = .unsure
        default:
            guard cached.hasPrefix("use:") else { return nil }
            self = .use(label: String(cached.dropFirst(4)))
        }
    }
}

// Anything that can judge a question against the saved answers: Apple's on-device model, or
// a stand-in in tests.
public protocol AnswerJudging: Sendable {
    func judge(_ question: AnswerQuestion, candidates: [AnswerCandidate]) async -> AnswerVerdict
}

// Which set of answers a cached verdict was made against. Any change to a label or a value
// gives a new revision, and verdicts made against another one are ignored.
public enum AnswerRevision {
    public static func of(_ fields: [CustomField]) -> String {
        let lines = AnswerCandidate.from(fields).map { "\($0.label.lowercased())\u{1F}\($0.value)" }.sorted()
        return hash(lines.joined(separator: "\u{1E}"))
    }

    // FNV-1a, which gives the same number on every launch, unlike Hasher.
    static func hash(_ text: String) -> String {
        let hash = text.utf8.reduce(UInt64(0xcbf2_9ce4_8422_2325)) { hash, byte in
            (hash ^ UInt64(byte)) &* 0x100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}

public enum AnswerGuessing {
    // Asks about each question once and returns the verdicts to cache, keyed by the question's
    // words, the model and the answers' revision.
    public static func ask(
        _ questions: [FormQuestion], fields: [CustomField], judge: some AnswerJudging, variant: String
    ) async -> [CachedInsight] {
        let candidates = AnswerCandidate.from(fields)
        guard !candidates.isEmpty else { return [] }
        let revision = AnswerRevision.of(fields)
        var answers: [CachedInsight] = []
        for question in questions {
            let verdict = await judge.judge(AnswerQuestion(question), candidates: candidates)
            let key = InsightKey.answer(
                question.text, variant: variant, revision: revision, context: AnswerQuestion(question).context
            )
            answers.append(CachedInsight(key: key, answer: verdict.cached))
        }
        return answers
    }

    // The saved answer to suggest for a question asked live (the Mac's panel), if the model
    // says to use one.
    public static func suggestion(
        for question: AnswerQuestion, fields: [CustomField], judge: some AnswerJudging
    ) async -> CustomField? {
        let candidates = AnswerCandidate.from(fields)
        guard !candidates.isEmpty,
              case .use(let label) = await judge.judge(question, candidates: candidates) else { return nil }
        return fields.first { !$0.isDraft && $0.label == label }
    }
}
