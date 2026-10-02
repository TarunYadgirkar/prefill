import Foundation

// Answers for Siri and Shortcuts: which value Safari offers first, on one site or everywhere.
public enum ValueLookup {
    // Every value of `kind` in the order Prefill puts on the card for `host`, or for any site
    // Prefill has nothing to go on when `host` is nil.
    public static func ranked(
        _ kind: ContactKind, host: String?, state: AppState, events: ExtensionEvents, card: CardRecord, now: Date
    ) -> [ContactValue] {
        let order = ManualOrder.values(kind, card: card, known: state.values, now: now)
        guard let host else {
            let context = RankingContext(
                host: nil, hint: nil, now: now, matchEachSite: false, focusLabel: state.settings.focusLabel
            )
            return Ranker.rank(order, usage: [], pins: [], context: context)
        }
        let context = RankingContext(
            host: host, hint: nil, now: now, matchEachSite: state.settings.matchEachSite,
            siteKind: state.siteKind(host), focusLabel: state.settings.focusLabel
        )
        return Ranker.rank(order, usage: events.usage, pins: state.pins, context: context)
    }

    // `ranked` with the values that fit `purpose` moved to the front, so "shipping address"
    // finds the home address even when the work one is first.
    public static func answer(_ ranked: [ContactValue], purpose: SectionHint?) -> ContactValue? {
        guard let purpose else { return ranked.first }
        return ranked.first { fits($0, purpose: purpose) } ?? ranked.first
    }

    // Sites Prefill has seen or pinned, newest first, whose name contains `text`.
    public static func sites(matching text: String?, state: AppState, events: ExtensionEvents) -> [String] {
        let dated = events.usage.map { ($0.host, $0.date) } + events.captures.map { ($0.host, $0.date) }
            + state.pins.map { ($0.host, Date.distantPast) }
        let newest = Dictionary(dated.map { (Normalizer.registrableDomain($0.0), $0.1) }, uniquingKeysWith: max)
        let hosts = newest.keys.sorted { (newest[$0] ?? .distantPast, $1) > (newest[$1] ?? .distantPast, $0) }
        let query = text.map(Normalizer.fold) ?? ""
        return query.isEmpty ? hosts : hosts.filter { $0.contains(query) }
    }

    private static func fits(_ value: ContactValue, purpose: SectionHint) -> Bool {
        let label = LabelName.of(value.label)
        switch purpose {
        case .home, .work: return label == purpose.rawValue
        case .shipping, .billing: return label == purpose.rawValue || label == SectionHint.home.rawValue
        }
    }
}
