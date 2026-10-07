import Foundation

// A pick from Prefill's list under a field. A contact value or link is pinned for the
// site, so the list puts it first there from the next focus on; unlike a pick in Safari's
// sheet, it doesn't rewrite the card. A custom answer is kept for the question's words, so
// the same question on any site offers it first, and a picked guess becomes a real answer
// to that question. Only a value the person already has is ever remembered.
extension MessageRouter {
    static let maxPicksPerWindow = 10
    static let pickWindow: TimeInterval = 60

    func picked(_ request: PickedRequest) -> PickedResponse {
        Self.eventLock.withLock { _ in
            guard !request.value.isEmpty, let state = currentState(), let link = state.cardLink, hasRoomForPick(),
                  let card = try? gateway.fetchCard(identifier: link.contactIdentifier) else {
                return PickedResponse(remembered: false)
            }
            let remembered = request.kind == .custom
                ? rememberAnswer(request, card: card)
                : rememberValue(request, card: card, state: state)
            return PickedResponse(remembered: remembered)
        }
    }

    private func hasRoomForPick() -> Bool {
        let date = now()
        let events = events()
        let dates = events.pins.map(\.date) + events.answerPicks.map(\.date)
        return dates.count { date.timeIntervalSince($0) < Self.pickWindow } < Self.maxPicksPerWindow
    }

    private func rememberValue(_ request: PickedRequest, card: CardRecord, state: AppState) -> Bool {
        guard state.settings.matchEachSite, let kind = request.kind.contactKind,
              let value = Self.value(matching: request.value, kind: kind, on: card, at: now()) else { return false }
        let site = Normalizer.registrableDomain(request.host)
        if state.pinnedValue(value.kind, on: site) == value.id { return true }
        let date = now()
        return append(ExtensionEvents(
            usage: [UsageEvent(valueID: value.id, host: site, date: date)],
            pins: [PinEvent(host: site, kind: value.kind, valueID: value.id, date: date)]
        ))
    }

    private func rememberAnswer(_ request: PickedRequest, card: CardRecord) -> Bool {
        let key = CustomFieldMatcher.key(request.question ?? "")
        guard !key.isEmpty, let field = card.customFields.first(where: { $0.value == request.value }) else {
            return false
        }
        if events().answerPicks.last(where: { $0.words == key })?.label == field.label { return true }
        let pick = AnswerPick(
            words: key, label: field.label, date: now(), host: Normalizer.registrableDomain(request.host)
        )
        return append(ExtensionEvents(answerPicks: [pick]))
    }

    static func value(matching text: String, kind: ContactKind, on card: CardRecord, at date: Date) -> ContactValue? {
        card.entries(kind)
            .map { ContactValue(entry: $0, createdAt: date) }
            .first { $0.isFilled(as: text) }
    }

    // The answer last picked for a question with these words, if the person still has it.
    static func pickedAnswer(for text: String, in fields: [CustomField], picks: [AnswerPick]) -> String? {
        let key = CustomFieldMatcher.key(text)
        guard !key.isEmpty, let pick = picks.last(where: { $0.words == key }) else { return nil }
        return fields.first { $0.label == pick.label }?.value
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
