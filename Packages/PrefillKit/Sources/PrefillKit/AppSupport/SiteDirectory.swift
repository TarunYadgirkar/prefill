import Foundation

// Sites Prefill has seen a form on, by registrable domain, newest first.
public enum SiteDirectory {
    public static func hosts(state: AppState, events: ExtensionEvents) -> [String] {
        lastSeen(events: events, pins: state.pins)
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .map(\.key)
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
