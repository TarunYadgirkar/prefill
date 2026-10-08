import Foundation

// "Just here": the person changed an answer Prefill filled and chose to keep the saved one
// everywhere else. The card doesn't change; an event notes the value they used on this site,
// so Prefill doesn't ask again there and offers it there as a suggestion, never filling it.
extension MessageRouter {
    // Returns the labels kept. Only an answer the person changed after Prefill filled it, for a
    // question the card answers with a learned answer, is kept, and no more in a day than one
    // application's answers, as for `update`.
    func keepHere(_ request: AnswersRequest, card: CardRecord) -> [String] {
        let date = now()
        let site = Normalizer.registrableDomain(request.host)
        let recent = events().overrides.count { date.timeIntervalSince($0.date) < Self.answerWindow }
        let room = max(0, Self.maxAnswersPerWindow - recent)
        let learned = events().answers
        let kept = request.answers.compactMap { answer -> AnswerOverride? in
            guard answer.changedFill == true, let asked = answer.field,
                  let field = card.customFields.first(where: { !$0.isDraft && $0.id == asked.id }),
                  field.value != asked.value, learned.contains(where: { $0.matches(field) }) else { return nil }
            return AnswerOverride(host: site, label: field.label, value: asked.value, date: date)
        }.prefix(room)
        guard !kept.isEmpty else { return [] }
        append(ExtensionEvents(overrides: Array(kept)))
        return kept.map { MessageText.oneLine($0.label, max: MessageLimits.text) }
    }

    // What the person kept on `host` for each label, newest last.
    func keptHere(host: String) -> [String: String] {
        let site = Normalizer.registrableDomain(host)
        return Dictionary(
            events().overrides.filter { $0.host == site }.map { ($0.label.lowercased(), $0.value) }
        ) { _, newer in newer }
    }
}
