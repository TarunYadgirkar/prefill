import Foundation

// A pick from Prefill's list under a field pins the value for the site, so the list puts
// it first there from the next focus on. Unlike a pick in Safari's sheet it doesn't
// rewrite the card. Only a value the person already has can be pinned.
extension MessageRouter {
    static let maxPicksPerWindow = 10
    static let pickWindow: TimeInterval = 60

    func picked(_ request: PickedRequest) -> PickedResponse {
        Self.eventLock.withLock { _ in
            guard let kind = request.kind.contactKind, let state = currentState(), state.settings.matchEachSite,
                  let link = state.cardLink,
                  let card = try? gateway.fetchCard(identifier: link.contactIdentifier),
                  let value = Self.value(matching: request.value, kind: kind, on: card, at: now()) else {
                return PickedResponse(remembered: false)
            }
            return PickedResponse(remembered: remember(value, on: request.host, state: state))
        }
    }

    private func remember(_ value: ContactValue, on host: String, state: AppState) -> Bool {
        let site = Normalizer.registrableDomain(host)
        if state.pinnedValue(value.kind, on: site) == value.id { return true }
        let date = now()
        let recent = events().pins.count { date.timeIntervalSince($0.date) < Self.pickWindow }
        guard recent < Self.maxPicksPerWindow else { return false }
        return append(ExtensionEvents(
            usage: [UsageEvent(valueID: value.id, host: site, date: date)],
            pins: [PinEvent(host: site, kind: value.kind, valueID: value.id, date: date)]
        ))
    }

    static func value(matching text: String, kind: ContactKind, on card: CardRecord, at date: Date) -> ContactValue? {
        card.entries(kind)
            .map { ContactValue(entry: $0, createdAt: date) }
            .first { $0.isFilled(as: text) }
    }
}

private extension ContactValue {
    // An address goes into a form one part at a time, so a pick names it by its street line.
    func isFilled(as text: String) -> Bool {
        switch payload {
        case .address(let address): Normalizer.street(address.street) == Normalizer.street(text)
        case .email: key == Normalizer.email(text)
        case .phone: key == Normalizer.phone(text)
        case .link: key == Normalizer.link(text)
        }
    }
}
