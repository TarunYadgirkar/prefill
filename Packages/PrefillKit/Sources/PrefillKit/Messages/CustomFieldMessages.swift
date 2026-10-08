import Foundation

// Fields with no contact or link meaning ("School", "How did you hear about us?") send the
// words of their label, name, id and placeholder; the app answers with the person's custom
// field values that match each one. Like links, this reply carries values back to the page.
public struct CustomSuggestionsRequest: Codable, Sendable, Hashable {
    public struct Field: Codable, Sendable, Hashable {
        public let text: String
        // The nearest heading above the field and a list's options, which the on-device model
        // reads with the question when no rule matched it.
        public let heading: String?
        public let options: [String]?
        // Set only by the focus handler, for the text area the person just focused: the one
        // request that may carry drafts back.
        public let focused: Bool?

        public init(text: String, heading: String? = nil, options: [String]? = nil, focused: Bool? = nil) {
            self.text = text
            self.heading = heading
            self.options = options
            self.focused = focused
        }

        // The heading and options, which the cached verdict for the question depends on.
        var context: String {
            AnswerQuestion.contextKey(heading: heading, options: options ?? [])
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
        // Drafts whose label matches, `why` draft: offered, never filled. Only a request about
        // one field marked `focused` (the text area the person is in) gets them, which keeps long
        // text off every page-load request.
        public let drafts: [SuggestedValue]

        public init(
            values: [SuggestedValue], guesses: [String] = [], suggested: [SuggestedValue] = [],
            noAnswerFor: String? = nil, drafts: [SuggestedValue] = []
        ) {
            self.values = values
            self.guesses = guesses
            self.suggested = suggested
            self.noAnswerFor = noAnswerFor
            self.drafts = drafts
        }

        func adding(drafts: [SuggestedValue]) -> Field {
            Field(values: values, guesses: guesses, suggested: suggested, noAnswerFor: noAnswerFor, drafts: drafts)
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CustomFieldKeys.self)
            values = try container.decode([SuggestedValue].self, forKey: .values)
            guesses = try container.decodeIfPresent([String].self, forKey: .guesses) ?? []
            suggested = try container.decodeIfPresent([SuggestedValue].self, forKey: .suggested) ?? []
            noAnswerFor = try container.decodeIfPresent(String.self, forKey: .noAnswerFor)
            drafts = try container.decodeIfPresent([SuggestedValue].self, forKey: .drafts) ?? []
        }

        // Most fields have neither, so the reply leaves them out.
        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CustomFieldKeys.self)
            try container.encode(values, forKey: .values)
            try container.encode(guesses, forKey: .guesses)
            if !suggested.isEmpty { try container.encode(suggested, forKey: .suggested) }
            try container.encodeIfPresent(noAnswerFor, forKey: .noAnswerFor)
            if !drafts.isEmpty { try container.encode(drafts, forKey: .drafts) }
        }
    }

    // One entry per requested field, in the same order.
    public let fields: [Field]

    public init(fields: [Field]) {
        self.fields = fields
    }
}

private enum CustomFieldKeys: String, CodingKey {
    case values, guesses, suggested, noAnswerFor, drafts
}

private typealias Answered = (field: CustomSuggestionsResponse.Field, unanswered: String?)

// What answering one question needs from the card and the events.
private struct CustomContext {
    let custom: [CustomField]
    // Of every answer on the card, which the app's cached verdicts were made against.
    let revision: String
    let recorded: ExtensionEvents
    // What the person kept on this site for an answer's label ("Just here").
    let kept: [String: String]
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
            custom: card.customFields.filter { !$0.isDraft && Self.fits($0.value, max: MessageLimits.customValue) },
            revision: AnswerRevision.of(card.customFields), recorded: events(), kept: keptHere(host: request.host),
            state: state,
            variant: Intelligence.modelVariant
        )
        let answered = request.fields.map { answer($0, context) }
        let unanswered = zip(request.fields, answered).compactMap { field, answer in
            answer.unanswered.map { _ in field }
        }
        if !context.custom.isEmpty { noteQuestions(unanswered, host: request.host) }
        guard request.fields.count == 1, let only = request.fields.first, only.focused == true,
              let first = answered.first else {
            return CustomSuggestionsResponse(fields: answered.map(\.field))
        }
        return CustomSuggestionsResponse(fields: [first.field.adding(drafts: Self.drafts(for: only.text, in: card))])
    }

    // A draft matches by its label and match words, whatever the question's scope.
    static func drafts(for text: String, in card: CardRecord) -> [SuggestedValue] {
        let drafts = card.customFields.filter { field in
            field.isDraft && field.value.utf16.count <= MessageLimits.draftValue
                && MessageText.isPlain(field.value, allowingNewlines: true)
        }
        return CustomFieldMatcher.offered(CustomFieldMatcher.candidates(for: text, in: drafts)).map { field in
            let label = MessageText.oneLine(field.label, max: MessageLimits.text)
            return SuggestedValue(value: field.value, why: .draft, label: label)
        }
    }

    // A pick only reorders what the question already matches, or stands in for a guess where
    // nothing matched, so copying a question's words reaches no other answer, and an answer
    // withheld for its scope stays withheld.
    private func answer(_ asked: CustomSuggestionsRequest.Field, _ context: CustomContext) -> Answered {
        let text = asked.text
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
        let suggested = Self.kept(scoped.fill, context.kept) + source(suggest, scoped.suggest)
        let field = CustomSuggestionsResponse.Field(
            values: source(fill, scoped.fill), suggested: Array(suggested.prefix(MessageLimits.customOptions)),
            noAnswerFor: fill.isEmpty ? scoped.missing?.name : nil
        )
        guard fill.isEmpty, scoped.isEmpty, !CustomFieldMatcher.words(text).isEmpty else { return (field, nil) }
        return guess(asked, context)
    }

    private func guess(_ asked: CustomSuggestionsRequest.Field, _ context: CustomContext) -> Answered {
        let (state, variant) = (context.state, context.variant)
        let key = InsightKey.answer(asked.text, variant: variant, revision: context.revision, context: asked.context)
        if let guess = state.guessedAnswer(key: key, in: context.custom) {
            return (.init(values: [], guesses: [guess.value]), nil)
        }
        let known = state.insight(key) != nil
        let text = asked.text
        return (.init(values: []), known ? nil : text)
    }

    // An answer the person kept on this site in place of the saved one, offered first among the
    // suggestions there and never filled: the site's page sent it.
    private static func kept(_ fields: [CustomField], _ kept: [String: String]) -> [SuggestedValue] {
        let values = fields.compactMap { field in
            kept[field.id].flatMap { value in
                fits(value, max: MessageLimits.customValue) && value != field.value
                    ? SuggestedValue(
                        value: value, why: .used, label: MessageText.oneLine(field.label, max: MessageLimits.text)
                    )
                    : nil
            }
        }
        return Array(values.prefix(1))
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

    // A question is kept once, with the heading and options the page showed with it.
    private func noteQuestions(_ fields: [CustomSuggestionsRequest.Field], host: String) {
        guard !fields.isEmpty else { return }
        Self.eventLock.withLock { _ in
            let site = Normalizer.registrableDomain(host)
            var known = Set(events().questions.map { "\($0.text)\u{1F}\(AnswerQuestion($0).context)" })
            let fresh = fields.filter { known.insert("\($0.text)\u{1F}\($0.context)").inserted }.map { field in
                FormQuestion(host: site, text: field.text, date: now(), heading: field.heading, options: field.options)
            }
            if !fresh.isEmpty { _ = append(ExtensionEvents(questions: fresh)) }
        }
    }
}
