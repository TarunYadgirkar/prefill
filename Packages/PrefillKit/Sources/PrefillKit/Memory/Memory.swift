import Foundation

// Everything the person has given Prefill, read from their card, Prefill's contact and
// the per-device state, so callers don't reach into CardRecord, CustomField and the
// events separately. Read-only: writes still go through CardWriter and CardEditor.
public struct Memory: Hashable, Sendable {
    public struct Name: Hashable, Sendable {
        public let given: String
        public let family: String
    }

    // The card's order: its own values, then the ones only Prefill's contact holds, then
    // custom fields.
    public let answers: [Answer]
    public let name: Name

    public func answers(for question: Answer.Question) -> [Answer] {
        answers.filter { $0.question == question }
    }

    public static func read(
        gateway: some ContactsGateway, identifier: String, state: AppState, events: ExtensionEvents
    ) throws(CardWriteFailure) -> Memory {
        let card = try gateway.fetchCard(identifier: identifier)
        let placement = try gateway.placement(identifier: identifier)
        return read(card: card, placement: placement, state: state, events: events)
    }

    // `card` is the merged record CNContactStoreGateway.fetchCard returns.
    public static func read(
        card: CardRecord, placement: CardPlacement, state: AppState, events: ExtensionEvents
    ) -> Memory {
        let reader = AnswerReader(placement: placement, state: state, events: events)
        let entries = ContactKind.allCases.flatMap { card.entries($0).uniquedByKey() }
        let answers = entries.map(reader.answer(for:)) + card.customFields.map(reader.answer(for:))
        var seen = Set<UUID>()
        return Memory(
            answers: answers.filter { seen.insert($0.id).inserted },
            name: Name(given: card.givenName, family: card.familyName)
        )
    }
}
