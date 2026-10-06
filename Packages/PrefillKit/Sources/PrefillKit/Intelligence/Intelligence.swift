import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

public enum IntelligenceState: Sendable, Hashable {
    case available, notEnabled, notReady, unsupported
}

// Breaks the ties Prefill's rules leave, with Apple's on-device model. Always the
// on-device SystemLanguageModel, never Private Cloud Compute, so nothing leaves the
// iPhone. Every call falls back to the rules: Apple Intelligence off, still downloading,
// an older iPhone, a guardrail or any other model error all end in the rules' answer.
// v1 calls it from the app only, never from the Safari handler. Prompts are never logged.
public actor Intelligence {
    // An actor-free answer to which model produced a cached result, so a new model asks again.
    public nonisolated static var modelVariant: String {
        #if canImport(FoundationModels)
        if #available(iOS 27, macOS 27, *) { return SystemLanguageModel.default.variant.displayName }
        #endif
        return "system"
    }

    public nonisolated static var state: IntelligenceState {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available: return .available
        case .unavailable(.appleIntelligenceNotEnabled): return .notEnabled
        case .unavailable(.modelNotReady): return .notReady
        case .unavailable: return .unsupported
        }
        #else
        return .unsupported
        #endif
    }

    public init() {}

    // Loads the model ahead of a batch, so the first answer isn't the slow one.
    public func prewarm() {
        #if canImport(FoundationModels)
        guard Self.state == .available else { return }
        LanguageModelSession(model: SystemLanguageModel.default, instructions: Prompts.siteInstructions).prewarm()
        #endif
    }

    public func labelValue(
        _ value: ContactValue, host: String, emailDomains: Set<String>
    ) async -> Insight<SuggestedLabel> {
        let guess = LabelRules.suggest(value, host: host, emailDomains: emailDomains)
        guard !guess.isSettled, case .email(let address) = value.payload,
              let answer = await modelLabel(address: address, host: host) else {
            return Insight(guess.label, source: .rules)
        }
        return Insight(answer, source: .model)
    }

    public func siteKind(host: String, emailDomains: Set<String>) async -> Insight<SiteKind> {
        let rule = SiteSense.rules(host: host, emailDomains: emailDomains)
        guard rule == .unknown, let answer = await modelSiteKind(host: Normalizer.registrableDomain(host)) else {
            return Insight(rule, source: .rules)
        }
        return Insight(answer, source: .model)
    }

    // Which of the person's saved answers, by label, answers a form question none of the
    // rules matched. Nil when the model has no answer or names a label that isn't there.
    public func answerLabel(question: String, labels: [String]) async -> String? {
        #if canImport(FoundationModels)
        guard !labels.isEmpty else { return nil }
        let prompt = "Question: \(question)\nNames: \(labels.joined(separator: ", ")), none"
        guard let answer = await ask(AnswerName.self, instructions: Prompts.answerInstructions, prompt: prompt) else {
            return nil
        }
        return labels.first { $0.caseInsensitiveCompare(answer.name) == .orderedSame }
        #else
        return nil
        #endif
    }

    private func modelLabel(address: String, host: String) async -> SuggestedLabel? {
        #if canImport(FoundationModels)
        let prompt = "Email address: \(address)\nWebsite: \(Normalizer.registrableDomain(host))"
        let answer = await ask(ValueContext.self, instructions: Prompts.labelInstructions, prompt: prompt)
        return answer.flatMap { Prompts.label(for: $0.context) }
        #else
        return nil
        #endif
    }

    private func modelSiteKind(host: String) async -> SiteKind? {
        #if canImport(FoundationModels)
        let answer = await ask(SiteCategory.self, instructions: Prompts.siteInstructions, prompt: "Website: \(host)")
        return answer.flatMap { SiteKind(rawValue: $0.category) }
        #else
        return nil
        #endif
    }

    #if canImport(FoundationModels)
    // A fresh single-turn session per call, greedy so the same input gives the same answer.
    private func ask<Answer: Generable & Sendable>(
        _ type: Answer.Type, instructions: String, prompt: String
    ) async -> Answer? {
        guard Self.state == .available else { return nil }
        let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
        do {
            return try await session.respond(to: prompt, generating: type, options: Prompts.options).content
        } catch {
            // LanguageModelError (guardrails, rate limits, timeouts) and anything else: the rules answer.
            return nil
        }
    }
    #endif
}

#if canImport(FoundationModels)
// Frozen wording. Phrases about signing in or filling forms trip the input guardrail, so
// these stay neutral (research/feature-scouting.md, Site sense).
private enum Prompts {
    static let options = GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 40)

    static let labelInstructions = """
        Sort an email address into the part of life it most likely belongs to. \
        Answer unknown when the address gives no clear sign.
        """

    // Without the examples the model names a saved answer for nearly any question.
    static let answerInstructions = """
        A questionnaire asks a question. You have the names of a person's saved answers. \
        Reply with the one name whose answer the question asks for. \
        Reply none unless a saved answer is exactly what is asked: a question about a company, \
        a favourite thing, a date of birth or anything the names don't cover is none.
        Examples: "Which university did you attend?" with School, Major is School. \
        "What is your favourite colour?" with School, Major is none. \
        "Employer name" with School, Major is none.
        """

    static let siteInstructions = """
        Sort a website into the category that best describes it. \
        Answer unknown when the name gives no clear sign.
        """

    // Shopping and personal both end up as home: Contacts has no shopping label.
    static func label(for context: String) -> SuggestedLabel? {
        switch context {
        case "work": .work
        case "school": .school
        case "personal", "shopping": .home
        default: nil
        }
    }
}

@Generable
private struct ValueContext {
    @Guide(.anyOf(["work", "school", "personal", "shopping", "unknown"]))
    let context: String
}

@Generable
private struct AnswerName {
    @Guide(description: "The name whose answer the question asks for, or none")
    let name: String
}

@Generable
private struct SiteCategory {
    @Guide(.anyOf(SiteKind.allCases.map(\.rawValue)))
    let category: String
}
#endif
