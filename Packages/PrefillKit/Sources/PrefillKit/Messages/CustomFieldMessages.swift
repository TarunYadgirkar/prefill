import Foundation

// Fields with no contact or link meaning ("School", "How did you hear about us?") send the
// words of their label, name, id and placeholder; the app answers with the person's custom
// field values that match each one. Like links, this reply carries values back to the page.
public struct CustomSuggestionsRequest: Codable, Sendable, Hashable {
    public struct Field: Codable, Sendable, Hashable {
        public let text: String

        public init(text: String) {
            self.text = text
        }
    }

    public let host: String
    public let fields: [Field]

    public init(host: String, fields: [Field]) {
        self.host = host
        self.fields = fields
    }
}

public struct CustomSuggestionsResponse: Codable, Sendable, Hashable {
    public struct Field: Codable, Sendable, Hashable {
        // Each with the custom field's label, or `learned` and the site it was saved from.
        public let values: [SuggestedValue]
        // What the on-device model thinks answers the field when no rule matched: offered
        // as a marked option, never filled in by itself. Their `why` is always `guess`.
        public let guesses: [String]
        // Answers to the same question kept for no scope or another kind of scope ("Work
        // authorization" for a question about Canada): offered, never filled.
        public let suggested: [SuggestedValue]
        // The question's scope when every answer to it is for another scope of the same kind,
        // so the list can say "No answer for Canada yet".
        public let noAnswerFor: String?

        public init(
            values: [SuggestedValue], guesses: [String] = [], suggested: [SuggestedValue] = [],
            noAnswerFor: String? = nil
        ) {
            self.values = values
            self.guesses = guesses
            self.suggested = suggested
            self.noAnswerFor = noAnswerFor
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CustomFieldKeys.self)
            values = try container.decode([SuggestedValue].self, forKey: .values)
            guesses = try container.decodeIfPresent([String].self, forKey: .guesses) ?? []
            suggested = try container.decodeIfPresent([SuggestedValue].self, forKey: .suggested) ?? []
            noAnswerFor = try container.decodeIfPresent(String.self, forKey: .noAnswerFor)
        }

        // Most fields have neither, so the reply leaves them out.
        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CustomFieldKeys.self)
            try container.encode(values, forKey: .values)
            try container.encode(guesses, forKey: .guesses)
            if !suggested.isEmpty { try container.encode(suggested, forKey: .suggested) }
            try container.encodeIfPresent(noAnswerFor, forKey: .noAnswerFor)
        }
    }

    // One entry per requested field, in the same order.
    public let fields: [Field]

    public init(fields: [Field]) {
        self.fields = fields
    }
}

private enum CustomFieldKeys: String, CodingKey {
    case values, guesses, suggested, noAnswerFor
}

private typealias Answered = (field: CustomSuggestionsResponse.Field, unanswered: String?)

// What answering one question needs from the card and the events.
private struct CustomContext {
    let custom: [CustomField]
    let recorded: ExtensionEvents
    let state: AppState
    let variant: String
}

extension MessageRouter {
    // Every list is empty before the card is linked or when it can't be read. The answer the
    // person last picked for the same question comes first. A field no rule matched gets the
    // model's cached guess, or is noted for the app to ask about.
    func customSuggestions(_ request: CustomSuggestionsRequest) -> CustomSuggestionsResponse {
        guard let state = currentState(), let link = state.cardLink,
              let card = try? gateway.fetchCard(identifier: link.contactIdentifier) else {
            return CustomSuggestionsResponse(fields: request.fields.map { _ in .init(values: []) })
        }
        let context = CustomContext(
            custom: card.customFields.filter { Self.fits($0.value, max: MessageLimits.customValue) },
            recorded: events(), state: state, variant: Intelligence.modelVariant
        )
        let answered = request.fields.map { answer($0.text, context) }
        if !context.custom.isEmpty { noteQuestions(answered.compactMap(\.unanswered), host: request.host) }
        return CustomSuggestionsResponse(fields: answered.map(\.field))
    }

    // A pick only reorders what the question already matches, or stands in for a guess where
    // nothing matched, so copying a question's words reaches no other answer, and an answer
    // withheld for its scope stays withheld.
    private func answer(_ text: String, _ context: CustomContext) -> Answered {
        let scoped = CustomFieldMatcher.scopedMatches(for: text, in: context.custom)
        let source = { (values: [String], fields: [CustomField]) in
            Self.sourced(values, from: fields + context.custom, learned: context.recorded.answers)
        }
        var fill = CustomFieldMatcher.offered(scoped.fill).map(\.value)
        var suggest = CustomFieldMatcher.offered(scoped.suggest).map(\.value).filter { !fill.contains($0) }
        if let picked = Self.pickedAnswer(for: text, in: context.custom, picks: context.recorded.answerPicks),
           scoped.isEmpty || fill.contains(picked) || suggest.contains(picked) {
            fill = Array(([picked] + fill.filter { $0 != picked }).prefix(MessageLimits.customOptions))
            suggest.removeAll { $0 == picked }
        }
        let field = CustomSuggestionsResponse.Field(
            values: source(fill, scoped.fill), suggested: source(suggest, scoped.suggest),
            noAnswerFor: fill.isEmpty ? scoped.missing?.name : nil
        )
        guard fill.isEmpty, scoped.isEmpty, !CustomFieldMatcher.words(text).isEmpty else { return (field, nil) }
        return guess(text, context)
    }

    private func guess(_ text: String, _ context: CustomContext) -> Answered {
        if let guess = context.state.guessedAnswer(for: text, in: context.custom, variant: context.variant) {
            return (.init(values: [], guesses: [guess.value]), nil)
        }
        let known = context.state.insight(InsightKey.answer(text, variant: context.variant)) != nil
        return (.init(values: []), known ? nil : text)
    }

    // A value Prefill learned from a form and that still reads as learned says where from;
    // any other is the person's own, under its label. `fields` holds the question's matches
    // first, so a value two fields share takes the label of the one that matched.
    static func sourced(
        _ values: [String], from fields: [CustomField], learned: [LearnedAnswer]
    ) -> [SuggestedValue] {
        values.map { value in
            guard let field = fields.first(where: { $0.value == value }) else { return SuggestedValue(value: value) }
            // A label synced from another device may hold characters the page's parser refuses.
            let plain = MessageText.oneLine(field.label, max: MessageLimits.text)
            let label = plain.trimmingCharacters(in: .whitespaces).isEmpty ? nil : plain
            guard let answer = learned.last(where: { $0.matches(field) }) else {
                return SuggestedValue(value: value, label: label)
            }
            // The page's parser turns away a reply with a site it can't take, and every
            // answer with it, so a site that isn't a plain host name is left out.
            let site = MessageText.isHost(answer.host) && answer.host.utf16.count <= MessageLimits.host
                ? answer.host : nil
            return SuggestedValue(value: value, why: .learned, label: label, site: site)
        }
    }

    // The person's custom fields, for a guess made outside the router (the Mac's panel).
    public func savedAnswers() -> [CustomField] {
        guard let link = currentState()?.cardLink,
              let card = try? gateway.fetchCard(identifier: link.contactIdentifier) else { return [] }
        return card.customFields
    }

    private func noteQuestions(_ texts: [String], host: String) {
        guard !texts.isEmpty else { return }
        Self.eventLock.withLock { _ in
            let site = Normalizer.registrableDomain(host)
            let known = Set(events().questions.map(\.text))
            let fresh = texts.filter { !known.contains($0) }.map { FormQuestion(host: site, text: $0, date: now()) }
            if !fresh.isEmpty { _ = append(ExtensionEvents(questions: fresh)) }
        }
    }
}
