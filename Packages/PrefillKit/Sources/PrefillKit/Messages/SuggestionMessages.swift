import Foundation

// Chrome and Arc don't fill contact fields from the card, so there the content script
// offers the card's values itself through a datalist. Like links, this reply carries
// values back to the page.
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
    public let emails: [String]
    public let phones: [String]
    public let addresses: [PostalAddress]
    public let name: SuggestedName?

    public init(
        emails: [String] = [], phones: [String] = [], addresses: [PostalAddress] = [], name: SuggestedName? = nil
    ) {
        self.emails = emails
        self.phones = phones
        self.addresses = addresses
        self.name = name
    }
}

extension MessageRouter {
    // The card's values of the kinds the page asks for, in the order the card would take
    // on this site, without writing the card: nothing here reads it in Chrome.
    func contactSuggestions(_ request: ContactSuggestionsRequest) -> ContactSuggestionsResponse {
        guard let state = currentState(), let link = state.cardLink,
              let card = try? gateway.fetchCard(identifier: link.contactIdentifier) else {
            return ContactSuggestionsResponse()
        }
        let page = PageSignal(
            host: request.host, hints: request.hints, now: now(), matchEachSite: state.settings.matchEachSite,
            siteKinds: state.siteKinds, focusLabel: state.settings.focusLabel
        )
        let ranked = CardPlan(card: card, request: syncRequest(state, link: link, page: page)).target
        let kinds = Set(request.fields.map(\.kind))
        return ContactSuggestionsResponse(
            emails: kinds.contains(.email) ? Self.texts(ranked.emails) : [],
            phones: kinds.contains(.phone) ? Self.texts(ranked.phones) : [],
            addresses: kinds.contains(.address) ? Self.addresses(ranked.addresses) : [],
            name: kinds.contains(.name) ? Self.name(card) : nil
        )
    }

    private static func texts(_ entries: [CardEntry]) -> [String] {
        let texts = entries.compactMap { entry -> String? in
            switch entry.payload {
            case .email(let text), .phone(let text): text
            case .address, .link: nil
            }
        }
        return Array(texts.filter { fits($0, max: MessageLimits.value) }.prefix(MessageLimits.suggestions))
    }

    private static func addresses(_ entries: [CardEntry]) -> [PostalAddress] {
        let addresses = entries.compactMap { entry -> PostalAddress? in
            guard case .address(let address) = entry.payload else { return nil }
            return address
        }
        return Array(addresses.filter(\.fitsMessage).prefix(MessageLimits.suggestions))
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
