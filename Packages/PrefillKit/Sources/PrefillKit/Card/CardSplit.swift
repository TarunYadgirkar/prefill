import Foundation

// Safari's AutoFill My Info and the Contacts My Card are one setting (REPORT.md, Spike
// results), so emails, phones and addresses have to stay on the person's own card for
// Safari's bar. Links and custom fields don't feed the bar, and Share Contact sends them
// along, so Prefill keeps them on a contact of its own in the same account, which iCloud
// syncs to the person's other devices.
public enum PrefillContact {
    // The marker Prefill finds its contact by, in the department field.
    public static let marker = "Links and custom fields for Prefill"
    public static let searchName = "Prefill"

    public static func name(for card: CardRecord) -> String {
        let person = [card.givenName, card.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        return person.isEmpty ? searchName : "\(searchName) · \(person)"
    }
}

// The links and custom fields held on one contact.
public struct CardExtras: Sendable, Hashable {
    public let links: [CardEntry]
    public let customFields: [CustomField]

    public init(links: [CardEntry], customFields: [CustomField]) {
        self.links = links
        self.customFields = customFields
    }

    init(_ record: CardRecord) {
        self.init(links: record.links, customFields: record.customFields)
    }

    var isEmpty: Bool { links.isEmpty && customFields.isEmpty }

    // Everything on either, this one's first, each value once.
    func merging(_ other: CardExtras) -> CardExtras {
        let linkKeys = Set(links.map(\.key))
        let fieldIDs = Set(customFields.map(\.id))
        return CardExtras(
            links: links + other.links.filter { !linkKeys.contains($0.key) }.uniquedByKey(),
            customFields: customFields + other.customFields.filter { !fieldIDs.contains($0.id) }
        )
    }
}

// A link or custom field still on the person's own card, which Share Contact would send.
public enum CardExtra: Sendable, Hashable, Identifiable {
    case link(CardEntry)
    case customField(CustomField)

    public var id: String {
        switch self {
        case .link(let entry): "link-\(entry.key)"
        case .customField(let field): "field-\(field.id)"
        }
    }

    public var title: String {
        switch self {
        case .link(let entry): LabelChoices.caption(entry.label, kind: .link)
        case .customField(let field): field.label
        }
    }

    public var value: String {
        switch self {
        case .link(let entry): entry.payload.display
        case .customField(let field): field.value
        }
    }
}

// The person's card as stored, and the links and custom fields on Prefill's contacts
// (normally one; two devices can each make one before iCloud syncs, so it's every copy
// merged). Without a Prefill contact the card's own links and custom fields stand in.
struct CardSplit: Equatable {
    struct Writes: Equatable {
        // The card to save, nil when it is unchanged.
        var card: CardRecord?
        // Whether the card's own links and custom fields are written too. Only before the
        // person has a Prefill contact, or when they move values off the card.
        var includesCardExtras = false
        // What every Prefill contact should hold. Nil when unchanged.
        var extras: CardExtras?
    }

    let card: CardRecord
    let copies: [CardExtras]

    var extras: CardExtras? {
        guard let first = copies.first else { return nil }
        return copies.dropFirst().reduce(first) { $0.merging($1) }
    }

    var record: CardRecord {
        guard let extras else { return card }
        return card.replacing(.link, with: extras.links).replacingCustomFields(with: extras.customFields)
    }

    // Until the person moves them, links and custom fields stay on the card the way they
    // always were, so Prefill never makes a contact of its own without being asked.
    func writes(for target: CardRecord) -> Writes {
        guard let extras else {
            return Writes(card: target == card ? nil : target, includesCardExtras: true)
        }
        let core: [ContactKind] = [.email, .phone, .address]
        let coreChanged = core.contains { card.entries($0) != target.entries($0) }
        let wanted = CardExtras(target)
        let extrasChanged = wanted != extras || copies.contains { $0 != wanted }
        let nextCard = core.reduce(card) { $0.replacing($1, with: target.entries($1)) }
        return Writes(card: coreChanged ? nextCard : nil, extras: extrasChanged ? wanted : nil)
    }

    // Every link and Prefill custom field left on the card.
    var extrasOnCard: [CardExtra] {
        card.links.map(CardExtra.link) + card.customFields.map(CardExtra.customField)
    }

    // Takes `chosen` off the card after making sure Prefill's contact holds them, so
    // moving never loses one. Returns nil when nothing chosen is still on the card.
    func moving(_ chosen: [CardExtra]) -> Writes? {
        let ids = Set(chosen.map(\.id))
        let moved = CardExtras(
            links: card.links.filter { ids.contains(CardExtra.link($0).id) },
            customFields: card.customFields.filter { ids.contains(CardExtra.customField($0).id) }
        )
        guard !moved.isEmpty else { return nil }
        let kept = card
            .replacing(.link, with: card.links.filter { !ids.contains(CardExtra.link($0).id) })
            .replacingCustomFields(with: card.customFields.filter { !ids.contains(CardExtra.customField($0).id) })
        let merged = (extras ?? CardExtras(links: [], customFields: [])).merging(moved)
        let needsExtras = merged != extras || copies.contains { $0 != merged }
        return Writes(card: kept, includesCardExtras: true, extras: needsExtras ? merged : nil)
    }
}

extension [CardEntry] {
    func uniquedByKey() -> [CardEntry] {
        var seen = Set<String>()
        return filter { seen.insert($0.key).inserted }
    }
}
