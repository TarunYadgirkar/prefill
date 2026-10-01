import Foundation

public struct SiteSummary: Sendable, Hashable, Identifiable {
    public let host: String
    public let lastSeen: Date
    // Every value of each kind in the order Prefill puts on the card for this site.
    public let ranked: [ContactKind: [ContactValue]]
    public let pinned: [ContactKind: UUID]

    public var id: String { host }

    public func values(_ kind: ContactKind) -> [ContactValue] {
        ranked[kind] ?? []
    }
}

// Sites Prefill has seen a form on, newest first, each with what Safari will offer there.
public enum SiteDirectory {
    public static func sites(state: AppState, events: ExtensionEvents, card: CardRecord, now: Date) -> [SiteSummary] {
        let orders = Dictionary(uniqueKeysWithValues: ContactKind.allCases.map { kind in
            (kind, ManualOrder.values(kind, card: card, known: state.values, now: now))
        })
        return lastSeen(events: events, pins: state.pins)
            .map { host, date in
                SiteSummary(
                    host: host, lastSeen: date,
                    ranked: rank(orders, host: host, state: state, usage: events.usage, now: now),
                    pinned: pinned(state.pins, host: host)
                )
            }
            .sorted { ($0.lastSeen, $1.host) > ($1.lastSeen, $0.host) }
    }

    private static func rank(
        _ orders: [ContactKind: [ContactValue]], host: String, state: AppState, usage: [UsageEvent], now: Date
    ) -> [ContactKind: [ContactValue]] {
        let context = RankingContext(host: host, hint: nil, now: now, matchEachSite: state.settings.matchEachSite)
        return orders.mapValues { Ranker.rank($0, usage: usage, pins: state.pins, context: context) }
    }

    private static func pinned(_ pins: [SitePin], host: String) -> [ContactKind: UUID] {
        let here = pins.filter { Normalizer.registrableDomain($0.host) == host }
        return Dictionary(here.map { ($0.kind, $0.valueID) }, uniquingKeysWith: { _, last in last })
    }

    private static func lastSeen(events: ExtensionEvents, pins: [SitePin]) -> [String: Date] {
        let dated = events.usage.map { ($0.host, $0.date) } + events.captures.map { ($0.host, $0.date) }
        var seen = Dictionary(dated.map { (Normalizer.registrableDomain($0.0), $0.1) }, uniquingKeysWith: max)
        for pin in pins where seen[Normalizer.registrableDomain(pin.host)] == nil {
            seen[Normalizer.registrableDomain(pin.host)] = .distantPast
        }
        return seen
    }
}

public extension AppState {
    // Pins `valueID` for `kind` on `host`, replacing any earlier pin there. A nil value unpins.
    func pinning(_ valueID: UUID?, kind: ContactKind, host: String) -> AppState {
        let site = Normalizer.registrableDomain(host)
        let others = pins.filter { !(Normalizer.registrableDomain($0.host) == site && $0.kind == kind) }
        let added = valueID.map { [SitePin(host: site, kind: kind, valueID: $0)] } ?? []
        return AppState(
            values: values, pins: others + added, settings: settings, cardLink: cardLink,
            rejectedValueIDs: rejectedValueIDs
        )
    }

    func with(values: [ContactValue]) -> AppState {
        AppState(values: values, pins: pins, settings: settings, cardLink: cardLink, rejectedValueIDs: rejectedValueIDs)
    }

    func with(settings: Settings) -> AppState {
        AppState(values: values, pins: pins, settings: settings, cardLink: cardLink, rejectedValueIDs: rejectedValueIDs)
    }

    func with(cardLink: CardLink?) -> AppState {
        AppState(values: values, pins: pins, settings: settings, cardLink: cardLink, rejectedValueIDs: rejectedValueIDs)
    }
}
