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

        public init(values: [SuggestedValue], guesses: [String] = []) {
            self.values = values
            self.guesses = guesses
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            values = try container.decode([SuggestedValue].self, forKey: .values)
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
        let recorded = events()
        let picks = recorded.answerPicks
        var unanswered: [String] = []
        let fields = request.fields.map { field -> CustomSuggestionsResponse.Field in
            let matched = CustomFieldMatcher.matches(for: field.text, in: custom)
            let values = matched.map(\.value)
            let sourced = { (values: [String]) in
                Self.sourced(values, from: matched + custom, learned: recorded.answers)
            }
            // A pick only reorders what the question already matches, or stands in for a guess
            // where nothing matched, so copying a question's words reaches no other answer.
            if let picked = Self.pickedAnswer(for: field.text, in: custom, picks: picks),
               values.isEmpty || values.contains(picked) {
                let ordered = [picked] + values.filter { $0 != picked }
                return .init(values: sourced(Array(ordered.prefix(MessageLimits.customOptions))))
            }
            guard values.isEmpty, !CustomFieldMatcher.words(field.text).isEmpty else {
                return .init(values: sourced(values))
            }
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
