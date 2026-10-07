import Foundation

// A focused field that asks for profile links ("GitHub/Portfolio", "LinkedIn") wants the
// person's links of those types, which the content script offers in Prefill's own list
// under the field. Like the other suggestion replies, this one carries values to the page.
public struct LinkSuggestionsRequest: Codable, Sendable, Hashable {
    public let host: String
    public let types: [LinkType]

    public init(host: String, types: [LinkType]) {
        self.host = host
        self.types = types
    }
}

public struct SuggestedLink: Codable, Sendable, Hashable {
    public let type: LinkType
    public let url: String
    // `pinned` for the link picked on this site, `card` for the rest.
    public let why: SuggestionWhy

    public init(type: LinkType, url: String, why: SuggestionWhy = .card) {
        self.type = type
        self.url = url
        self.why = why
    }
}

public struct LinkSuggestionsResponse: Codable, Sendable, Hashable {
    public let links: [SuggestedLink]

    public init(links: [SuggestedLink]) {
        self.links = links
    }
}

extension MessageRouter {
    // The card's links of the asked-for types in the person's order, with the one last picked
    // on this site first, a few of each. Nothing
    // before the card is linked or when it can't be read.
    func linkSuggestions(_ request: LinkSuggestionsRequest) -> LinkSuggestionsResponse {
        guard let state = currentState(), let link = state.cardLink,
              let card = try? gateway.fetchCard(identifier: link.contactIdentifier) else {
            return LinkSuggestionsResponse(links: [])
        }
        let wanted = Set(request.types)
        let site = Normalizer.registrableDomain(request.host)
        let pinned = state.settings.matchEachSite ? state.pinnedValue(.link, on: site) : nil
        let order = ManualOrder.values(.link, card: card, known: state.values, now: now()).first(pinned)
        let links = order.compactMap { value -> SuggestedLink? in
            guard case .link(let text) = value.payload, ValueRules.isLink(text) else { return nil }
            let type = LinkType.of(text)
            guard wanted.contains(type) else { return nil }
            return SuggestedLink(type: type, url: LinkURL.full(text), why: value.id == pinned ? .pinned : .card)
        }
        let capped = request.types.flatMap { type in
            links.filter { $0.type == type }.prefix(MessageLimits.linksPerType)
        }
        return LinkSuggestionsResponse(links: Array(capped.prefix(MessageLimits.links)))
    }
}

private extension Array where Element == ContactValue {
    func first(_ id: UUID?) -> [ContactValue] {
        filter { $0.id == id } + filter { $0.id != id }
    }
}
