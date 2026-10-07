import Foundation

public extension AppState {
    // Pins `valueID` for `kind` on `host`, replacing any earlier pin there. A nil value unpins.
    func pinning(_ valueID: UUID?, kind: ContactKind, host: String) -> AppState {
        let site = Normalizer.registrableDomain(host)
        let others = pins.filter { !(Normalizer.registrableDomain($0.host) == site && $0.kind == kind) }
        let added = valueID.map { [SitePin(host: site, kind: kind, valueID: $0)] } ?? []
        return copy(pins: others + added)
    }

    // Forgets that the person turned this value down, so it can be saved again.
    func unrejecting(_ id: UUID) -> AppState {
        copy(rejectedValueIDs: rejectedValueIDs.filter { $0 != id })
    }

    func with(values: [ContactValue]) -> AppState {
        copy(values: values)
    }

    func with(settings: Settings) -> AppState {
        copy(settings: settings)
    }

    func with(cardLink: CardLink?) -> AppState {
        copy(cardLink: .some(cardLink))
    }
}
