import Foundation

// The person's own order for the values on their card, the order Safari follows on any
// site Prefill has nothing to go on. Values only the card has are placed the way
// CardWriter places them, so the app and the extension agree on it.
public enum ManualOrder {
    public static func values(
        _ kind: ContactKind, card: CardRecord, known: [ContactValue], now: Date
    ) -> [ContactValue] {
        let request = CardSyncRequest(
            cardIdentifier: card.identifier, known: known, additions: [], usage: [], pins: [],
            page: PageSignal(host: nil, hints: [:], now: now, matchEachSite: false)
        )
        let byID = Dictionary(known.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return CardPlan(card: card, request: request).target.entries(kind)
            .map { entry in
                let fresh = ContactValue(entry: entry, createdAt: now)
                return byID[fresh.id].map { $0.with(entry: entry) } ?? fresh
            }
            .uniqued()
    }

    // Every kind in the person's order, for storing back as AppState.values.
    public static func allValues(card: CardRecord, known: [ContactValue], now: Date) -> [ContactValue] {
        ContactKind.allCases.flatMap { values($0, card: card, known: known, now: now) }
    }

    // `known` with one kind's values replaced by `ordered`, the other kinds untouched.
    public static func replacing(
        _ kind: ContactKind, with ordered: [ContactValue], in known: [ContactValue]
    ) -> [ContactValue] {
        ContactKind.allCases.flatMap { each in
            each == kind ? ordered : known.filter { $0.kind == each }
        }
    }
}
