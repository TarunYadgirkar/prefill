import Foundation

// The content script offers the person's emails, phones, addresses and name in Prefill's
// own list under each field, in every browser, from the card and Prefill's contact alike.
// Like links, this reply carries values back to the page.
public struct ContactSuggestionsRequest: Codable, Sendable, Hashable {
    public let host: String
    public let fields: [PageField]

    public init(host: String, fields: [PageField]) {
        self.host = host
        self.fields = fields
    }

    var hints: [ContactKind: SectionHint] {
        SectionHint.firstPerKind(fields.map { ($0.kind, $0.section) })
    }
}

public struct SuggestedName: Codable, Sendable, Hashable {
    public let given: String
    public let family: String

    public init(given: String, family: String) {
        self.given = given
        self.family = family
    }
}

public struct ContactSuggestionsResponse: Codable, Sendable, Hashable {
    public let emails: [SuggestedValue]
    public let phones: [SuggestedValue]
    public let addresses: [SuggestedAddress]
    public let name: SuggestedName?

    public init(
        emails: [SuggestedValue] = [], phones: [SuggestedValue] = [], addresses: [SuggestedAddress] = [],
        name: SuggestedName? = nil
    ) {
        self.emails = emails
        self.phones = phones
        self.addresses = addresses
        self.name = name
    }
}

extension MessageRouter {
    // The person's values of the kinds the page asks for, ranked for this site, without
    // writing the card.
    func contactSuggestions(_ request: ContactSuggestionsRequest) -> ContactSuggestionsResponse {
        notePageSeen()
        guard let state = currentState(), let link = state.cardLink,
              let card = try? gateway.fetchCard(identifier: link.contactIdentifier) else {
            return ContactSuggestionsResponse()
        }
        return contactSuggestions(request, state: state, link: link, card: card)
    }

    private func contactSuggestions(
        _ request: ContactSuggestionsRequest, state: AppState, link: CardLink, card: CardRecord
    ) -> ContactSuggestionsResponse {
        let page = PageSignal(
            host: request.host, hints: request.hints, now: now(), matchEachSite: state.settings.matchEachSite,
            siteKinds: state.siteKinds
        )
        let sync = syncRequest(state, link: link, page: page)
        let target = CardPlan(card: card, request: sync).target
        let kinds = Set(request.fields.map(\.kind))
        let ranked = { (kind: ContactKind) -> [Ranked] in
            guard let field = FieldKind(rawValue: kind.rawValue), kinds.contains(field) else { return [] }
            let values = target.entries(kind).map { ContactValue(entry: $0, createdAt: page.now) }
            // The target is already in order; ranking again only reads each value's tier.
            let tiers = Ranker.rankWithTiers(
                values, usage: sync.usage, pins: sync.pins, context: page.context(for: kind, siteKind: .unknown)
            )
            let why = Dictionary(tiers.map { ($0.value.id, SuggestionWhy($0.tier)) }) { first, _ in first }
            return values.map { Ranked(value: $0, why: why[$0.id] ?? .card) }
        }
        return ContactSuggestionsResponse(
            emails: Self.texts(ranked(.email)), phones: Self.texts(ranked(.phone)),
            addresses: Self.addresses(ranked(.address)), name: kinds.contains(.name) ? Self.name(card) : nil
        )
    }

    private struct Ranked {
        let value: ContactValue
        let why: SuggestionWhy

        // The card's label as Safari's bar captions it, or none for an unlabeled value.
        var label: String? {
            guard let label = value.label, !label.isEmpty else { return nil }
            return MessageText.oneLine(LabelChoices.caption(label, kind: value.kind), max: MessageLimits.text)
        }
    }

    private static func texts(_ ranked: [Ranked]) -> [SuggestedValue] {
        let values = ranked.compactMap { item -> SuggestedValue? in
            switch item.value.payload {
            case .email(let text), .phone(let text): SuggestedValue(value: text, why: item.why, label: item.label)
            case .address, .link: nil
            }
        }
        return Array(values.filter { fits($0.value, max: MessageLimits.value) }.prefix(MessageLimits.suggestions))
    }

    private static func addresses(_ ranked: [Ranked]) -> [SuggestedAddress] {
        let addresses = ranked.compactMap { item -> SuggestedAddress? in
            guard case .address(let address) = item.value.payload, address.fitsMessage else { return nil }
            return SuggestedAddress(address: address, why: item.why, label: item.label)
        }
        return Array(addresses.prefix(MessageLimits.suggestions))
    }

    private static func name(_ card: CardRecord) -> SuggestedName? {
        let parts = [card.givenName, card.familyName]
        guard parts.contains(where: { !$0.isEmpty }), parts.allSatisfy({ fits($0, max: MessageLimits.part) }) else {
            return nil
        }
        return SuggestedName(given: card.givenName, family: card.familyName)
    }

    // The content script turns away a reply with anything its parser wouldn't accept, so
    // a value it can't take is left out here rather than losing the whole reply.
    static func fits(_ text: String, max: Int) -> Bool {
        text.utf16.count <= max && MessageText.isPlain(text)
    }
}

private extension PostalAddress {
    var fitsMessage: Bool {
        street.utf16.count <= MessageLimits.street && MessageText.isPlain(street, allowingNewlines: true)
            && [city, state, postalCode, country].allSatisfy { MessageRouter.fits($0, max: MessageLimits.part) }
    }
}
