import Foundation

// Safari's AutoFill My Info and the Contacts My Card are one setting (REPORT.md, Spike
// results), so whatever Safari's bar offers has to be on the person's own card. Links and
// custom fields don't feed the bar, and Share Contact sends them along, so Prefill keeps
// them on a contact of its own in the same account, which iCloud syncs to the person's
// other devices. With a minimal card the person also moves emails, addresses and extra
// phone numbers there, and Prefill offers them itself through a datalist.
public enum PrefillContact {
    // The markers Prefill finds its contact by, in the department field. The second also
    // says the person chose a minimal card: their card keeps only their name and the phone
    // numbers they picked.
    public static let marker = "Links and custom fields for Prefill"
    public static let minimalMarker = "Contact details for Prefill"
    public static let searchName = "Prefill"

    public static func name(for card: CardRecord) -> String {
        let person = [card.givenName, card.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        return person.isEmpty ? searchName : "\(searchName) · \(person)"
    }

    static func isMarker(_ department: String) -> Bool {
        department == marker || department == minimalMarker
    }
}

extension ContactKind {
    // The kinds Safari's bar reads from the card.
    static let core: [ContactKind] = [.email, .phone, .address]
}

// What one Prefill contact holds: links, custom fields and, with a minimal card, the
// emails, phones and addresses that came off the person's card.
public struct CardExtras: Sendable, Hashable {
    public let links: [CardEntry]
    public let customFields: [CustomField]
    public let emails: [CardEntry]
    public let phones: [CardEntry]
    public let addresses: [CardEntry]
    public let isMinimal: Bool

    public init(
        links: [CardEntry], customFields: [CustomField], emails: [CardEntry] = [], phones: [CardEntry] = [],
        addresses: [CardEntry] = [], isMinimal: Bool = false
    ) {
        self.links = links
        self.customFields = customFields
        self.emails = emails
        self.phones = phones
        self.addresses = addresses
        self.isMinimal = isMinimal
    }

    init(_ record: CardRecord, isMinimal: Bool) {
        self.init(
            links: record.links, customFields: record.customFields, emails: record.emails, phones: record.phones,
            addresses: record.addresses, isMinimal: isMinimal
        )
    }

    var isEmpty: Bool {
        links.isEmpty && customFields.isEmpty && ContactKind.core.allSatisfy { entries($0).isEmpty }
    }

    func entries(_ kind: ContactKind) -> [CardEntry] {
        switch kind {
        case .email: emails
        case .phone: phones
        case .address: addresses
        case .link: links
        }
    }

    func replacing(_ kind: ContactKind, with entries: [CardEntry]) -> CardExtras {
        CardExtras(
            links: kind == .link ? entries : links, customFields: customFields,
            emails: kind == .email ? entries : emails, phones: kind == .phone ? entries : phones,
            addresses: kind == .address ? entries : addresses, isMinimal: isMinimal
        )
    }

    func with(customFields: [CustomField]? = nil, isMinimal: Bool? = nil) -> CardExtras {
        CardExtras(
            links: links, customFields: customFields ?? self.customFields, emails: emails, phones: phones,
            addresses: addresses, isMinimal: isMinimal ?? self.isMinimal
        )
    }

    // Everything on either, this one's first, each value once. Minimal if either is.
    func merging(_ other: CardExtras) -> CardExtras {
        let fieldIDs = Set(customFields.map(\.id))
        let kinds: [ContactKind] = [.link] + ContactKind.core
        let merged = kinds.reduce(self) { partial, kind in
            partial.replacing(kind, with: partial.entries(kind).adding(other.entries(kind)))
        }
        return merged.with(
            customFields: customFields + other.customFields.filter { !fieldIDs.contains($0.id) },
            isMinimal: isMinimal || other.isMinimal
        )
    }
}

// A value or custom field on one of the two contacts, as the Sharing screen lists it.
public enum CardExtra: Sendable, Hashable, Identifiable {
    case entry(CardEntry)
    case customField(CustomField)

    public var id: String {
        switch self {
        case .entry(let entry): "\(entry.payload.kind.rawValue)-\(entry.key)"
        case .customField(let field): "field-\(field.id)"
        }
    }

    // Nil for a custom field.
    public var kind: ContactKind? {
        guard case .entry(let entry) = self else { return nil }
        return entry.payload.kind
    }

    public var title: String {
        switch self {
        case .entry(let entry): LabelChoices.caption(entry.label, kind: entry.payload.kind)
        case .customField(let field): field.label
        }
    }

    public var value: String {
        switch self {
        case .entry(let entry): entry.payload.display
        case .customField(let field): field.value
        }
    }

    var isCore: Bool { kind.map(ContactKind.core.contains) ?? false }
}

// Where the person's values are: what is on their own card, which Share Contact sends,
// and what Prefill's contact holds.
public struct CardPlacement: Sendable, Hashable {
    public let onCard: [CardExtra]
    public let onPrefill: [CardExtra]
    public let isMinimal: Bool

    public init(onCard: [CardExtra], onPrefill: [CardExtra] = [], isMinimal: Bool = false) {
        self.onCard = onCard
        self.onPrefill = onPrefill
        self.isMinimal = isMinimal
    }

    // What the Sharing screen suggests moving: everything on the card but the phone numbers
    // the person keeps, which is the first one, or on a minimal card every one still there.
    public var suggestedMoves: [CardExtra] {
        let phones = onCard.filter { $0.kind == .phone }
        let kept = isMinimal ? phones : Array(phones.prefix(1))
        return onCard.filter { !kept.contains($0) }
    }

    // Keys of the emails, phones and addresses on the card itself, which Safari offers.
    public var cardKeys: Set<String> {
        Set(onCard.compactMap { extra in
            guard case .entry(let entry) = extra, extra.isCore else { return nil }
            return entry.key
        })
    }
}

// The person's card as stored, and what Prefill's contacts hold (normally one; two devices
// can each make one before iCloud syncs, so it's every copy merged). Without a Prefill
// contact the card's own links and custom fields stand in.
struct CardSplit: Equatable {
    struct Writes: Equatable {
        // The card to save, nil when it is unchanged.
        var card: CardRecord?
        // Whether the card's own links and custom fields are written too. Only before the
        // person has a Prefill contact, or when they move values off the card.
        var includesCardExtras = false
        // What every Prefill contact should hold. Nil when unchanged.
        var extras: CardExtras?

        var isEmpty: Bool { card == nil && extras == nil }
    }

    let card: CardRecord
    let copies: [CardExtras]

    var extras: CardExtras? {
        guard let first = copies.first else { return nil }
        return copies.dropFirst().reduce(first) { $0.merging($1) }
    }

    var isMinimal: Bool { extras?.isMinimal ?? false }

    // The card's own values first, then the ones only Prefill's contact holds.
    var record: CardRecord {
        guard let extras else { return card }
        let core = ContactKind.core.reduce(card) { partial, kind in
            partial.replacing(kind, with: card.entries(kind).adding(extras.entries(kind)))
        }
        return core.replacing(.link, with: extras.links).replacingCustomFields(with: extras.customFields)
    }

    var placement: CardPlacement {
        CardPlacement(onCard: Self.listed(card), onPrefill: extras.map(Self.listed) ?? [], isMinimal: isMinimal)
    }

    // Until the person moves them, links and custom fields stay on the card the way they
    // always were, so Prefill never makes a contact of its own without being asked. Emails,
    // phones and addresses stay on the card unless the person chose a minimal card; then a
    // value stays where it is and a new one goes to Prefill's contact.
    func writes(for target: CardRecord) -> Writes {
        guard let extras else {
            return Writes(card: target == card ? nil : target, includesCardExtras: true)
        }
        let wanted = isMinimal ? minimalExtras(for: target, extras: extras) : CardExtras(
            links: target.links, customFields: target.customFields
        )
        let nextCard = ContactKind.core.reduce(card) { partial, kind in
            let onCard = Set(card.entries(kind).map(\.key))
            let kept = isMinimal ? target.entries(kind).filter { onCard.contains($0.key) } : target.entries(kind)
            return partial.replacing(kind, with: kept)
        }
        let coreChanged = ContactKind.core.contains { card.entries($0) != nextCard.entries($0) }
        let extrasChanged = wanted != extras || copies.contains { $0 != wanted }
        return Writes(card: coreChanged ? nextCard : nil, extras: extrasChanged ? wanted : nil)
    }

    // Values already on Prefill's contact keep their stored order, so ranking a page never
    // rewrites it; the person's order lives in the app. New ones follow.
    private func minimalExtras(for target: CardRecord, extras: CardExtras) -> CardExtras {
        let base = CardExtras(links: target.links, customFields: target.customFields, isMinimal: true)
        return ContactKind.core.reduce(base) { partial, kind in
            let onCard = Set(card.entries(kind).map(\.key))
            let wanted = target.entries(kind).filter { !onCard.contains($0.key) }
            let byKey = Dictionary(wanted.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
            let stored = extras.entries(kind).compactMap { byKey[$0.key] }.uniquedByKey()
            let storedKeys = Set(stored.map(\.key))
            return partial.replacing(kind, with: stored + wanted.filter { !storedKeys.contains($0.key) }.uniquedByKey())
        }
    }

    // Every value and Prefill custom field left on the card.
    var extrasOnCard: [CardExtra] { Self.listed(card) }

    private static func listed(_ record: CardRecord) -> [CardExtra] {
        let kinds = ContactKind.core + [.link]
        return kinds.flatMap { record.entries($0).uniquedByKey().map(CardExtra.entry) }
            + record.customFields.map(CardExtra.customField)
    }

    private static func listed(_ extras: CardExtras) -> [CardExtra] {
        let kinds = ContactKind.core + [.link]
        return kinds.flatMap { extras.entries($0).map(CardExtra.entry) }
            + extras.customFields.map(CardExtra.customField)
    }

    // Takes `chosen` off the card after making sure Prefill's contact holds them, so moving
    // never loses one. Moving an email, phone or address makes the card minimal. Returns nil
    // when nothing chosen is still on the card.
    func moving(_ chosen: [CardExtra]) -> Writes? {
        let ids = Set(chosen.map(\.id))
        let picked = { (entry: CardEntry) in ids.contains(CardExtra.entry(entry).id) }
        let movedFields = card.customFields.filter { ids.contains(CardExtra.customField($0).id) }
        let kinds = ContactKind.core + [.link]
        let moved = kinds.reduce(CardExtras(links: [], customFields: movedFields)) { partial, kind in
            partial.replacing(kind, with: card.entries(kind).filter(picked).uniquedByKey())
        }
        guard !moved.isEmpty else { return nil }
        let kept = kinds.reduce(card) { partial, kind in
            partial.replacing(kind, with: card.entries(kind).filter { !picked($0) })
        }
        .replacingCustomFields(with: card.customFields.filter { !ids.contains(CardExtra.customField($0).id) })
        let becomesMinimal = isMinimal || chosen.contains(where: \.isCore)
        let merged = (extras ?? CardExtras(links: [], customFields: []))
            .merging(moved).with(isMinimal: becomesMinimal)
        let needsExtras = merged != extras || copies.contains { $0 != merged }
        return Writes(card: kept, includesCardExtras: true, extras: needsExtras ? merged : nil)
    }

    // Puts `chosen` emails, phones and addresses from Prefill's contact back on the card
    // (all of them when leaving a minimal card), in one save. Nil when there is nothing to do.
    func movingOntoCard(_ chosen: [CardExtra]?, leavingMinimal: Bool) -> Writes? {
        guard let extras else { return nil }
        let ids = chosen.map { Set($0.map(\.id)) }
        let picked = { (entry: CardEntry) in ids?.contains(CardExtra.entry(entry).id) ?? true }
        let nextCard = ContactKind.core.reduce(card) { partial, kind in
            partial.replacing(kind, with: card.entries(kind).adding(extras.entries(kind).filter(picked)))
        }
        let stays = ContactKind.core.reduce(extras) { partial, kind in
            partial.replacing(kind, with: extras.entries(kind).filter { !picked($0) })
        }
        let wanted = stays.with(isMinimal: leavingMinimal ? false : extras.isMinimal)
        let cardChanged = nextCard != card
        let extrasChanged = wanted != extras || copies.contains { $0 != wanted }
        guard cardChanged || extrasChanged else { return nil }
        return Writes(card: cardChanged ? nextCard : nil, extras: extrasChanged ? wanted : nil)
    }
}

extension [CardEntry] {
    func uniquedByKey() -> [CardEntry] {
        var seen = Set<String>()
        return filter { seen.insert($0.key).inserted }
    }

    // These entries, then each of `others` whose value isn't here yet.
    func adding(_ others: [CardEntry]) -> [CardEntry] {
        let keys = Set(map(\.key))
        return self + others.filter { !keys.contains($0.key) }.uniquedByKey()
    }
}
