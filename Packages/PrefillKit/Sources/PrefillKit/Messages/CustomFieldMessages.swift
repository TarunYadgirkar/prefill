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
        public let values: [String]
        // What the on-device model thinks answers the field when no rule matched: offered
        // as a marked option, never filled in by itself.
        public let guesses: [String]

        public init(values: [String], guesses: [String] = []) {
            self.values = values
            self.guesses = guesses
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            values = try container.decode([String].self, forKey: .values)
            guesses = try container.decodeIfPresent([String].self, forKey: .guesses) ?? []
        }
    }

    // One entry per requested field, in the same order.
    public let fields: [Field]

    public init(fields: [Field]) {
        self.fields = fields
    }
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
        let custom = card.customFields.filter { Self.fits($0.value, max: MessageLimits.customValue) }
        let variant = Intelligence.modelVariant
        let picks = events().answerPicks
        var unanswered: [String] = []
        let fields = request.fields.map { field -> CustomSuggestionsResponse.Field in
            let values = CustomFieldMatcher.values(for: field.text, in: custom)
            // A pick only reorders what the question already matches, or stands in for a guess
            // where nothing matched, so copying a question's words reaches no other answer.
            if let picked = Self.pickedAnswer(for: field.text, in: custom, picks: picks),
               values.isEmpty || values.contains(picked) {
                let ordered = [picked] + values.filter { $0 != picked }
                return .init(values: Array(ordered.prefix(MessageLimits.customOptions)))
            }
            guard values.isEmpty, !CustomFieldMatcher.words(field.text).isEmpty else { return .init(values: values) }
            guard let guess = state.guessedAnswer(for: field.text, in: custom, variant: variant) else {
                let key = InsightKey.answer(field.text, variant: variant)
                if state.insight(key) == nil { unanswered.append(field.text) }
                return .init(values: [])
            }
            return .init(values: [], guesses: [guess.value])
        }
        if !custom.isEmpty { noteQuestions(unanswered, host: request.host) }
        return CustomSuggestionsResponse(fields: fields)
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
