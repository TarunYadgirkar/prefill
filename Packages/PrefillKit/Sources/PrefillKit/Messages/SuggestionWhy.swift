import Foundation

// Why a value is in Prefill's list, so the list can say so under it. Mirrored by WHYS in
// web/src/messages.ts.
public enum SuggestionWhy: String, Codable, Sendable, CaseIterable {
    // Picked on this site before.
    case pinned
    // Typed or picked on this site before.
    case used
    // On the person's card or Prefill's contact.
    case card
    // Saved from a form the person submitted.
    case learned
    // The on-device model's pick.
    case guess
    // From a resume import.
    case resume
    // A draft the person wrote in the app: offered, never filled.
    case draft

    init(_ tier: Ranker.Tier) {
        switch tier {
        case .pinned: self = .pinned
        case .usedHere: self = .used
        default: self = .card
        }
    }
}

// One suggested value: an email, phone number or custom answer. `label` is the card's
// label for it ("work") or the custom field's ("School"); `site` is where a learned answer
// was saved from.
public struct SuggestedValue: Codable, Sendable, Hashable {
    public let value: String
    public let why: SuggestionWhy
    public let label: String?
    public let site: String?

    public init(value: String, why: SuggestionWhy = .card, label: String? = nil, site: String? = nil) {
        self.value = value
        self.why = why
        self.label = label
        self.site = why == .learned ? site : nil
    }
}

public struct SuggestedAddress: Codable, Sendable, Hashable {
    public let address: PostalAddress
    public let why: SuggestionWhy
    public let label: String?

    public init(address: PostalAddress, why: SuggestionWhy = .card, label: String? = nil) {
        self.address = address
        self.why = why
        self.label = label
    }
}
