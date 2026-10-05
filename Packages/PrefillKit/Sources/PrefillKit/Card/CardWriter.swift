import Foundation
import os
import Synchronization

public protocol ContactsGateway: Sendable {
    func fetchCard(identifier: String) throws(CardWriteFailure) -> CardRecord
    // Saves `target` only if the card still reads as `basis`, the record the target was
    // planned from. Otherwise returns the card as it is now, so nothing added in between is lost.
    func save(_ target: CardRecord, basis: CardRecord, scope: CardSaveScope, transactionAuthor: String)
        throws(CardWriteFailure) -> CardSaveResult
    // What is on the person's own card, which Share Contact sends, and what Prefill's
    // contact holds.
    func placement(identifier: String) throws(CardWriteFailure) -> CardPlacement
    // Moves the chosen ones to Prefill's own contact. Only the person asks for this.
    func moveOffCard(_ chosen: [CardExtra], identifier: String) throws(CardWriteFailure)
    // Puts the chosen emails, phones and addresses (nil: all of them) back on the card, and
    // when leaving a minimal card, sends new ones to the card again. Only the person asks.
    func moveOntoCard(_ chosen: [CardExtra]?, identifier: String, leavingMinimal: Bool) throws(CardWriteFailure)
}

// What a save may change. Reordering and adding never removes a value; only an edit the
// person asked for in the app (remove, relabel, restore) may.
public enum CardSaveScope: Sendable, Hashable {
    // `addAnswers` also keeps every value, and may add custom fields after the ones there.
    case keepEveryValue, addAnswers, personEdit

    public func allows(_ target: CardRecord, over basis: CardRecord) -> Bool {
        switch self {
        case .keepEveryValue: target.keepsEveryValue(of: basis)
        case .addAnswers: target.keepsEveryValue(of: basis, addingAnswers: true)
        case .personEdit: true
        }
    }
}

extension ContactsGateway {
    public func placement(identifier: String) throws(CardWriteFailure) -> CardPlacement {
        CardPlacement(onCard: [])
    }
    public func moveOffCard(_ chosen: [CardExtra], identifier: String) throws(CardWriteFailure) {}
    public func moveOntoCard(
        _ chosen: [CardExtra]?, identifier: String, leavingMinimal: Bool
    ) throws(CardWriteFailure) {}

    public func save(
        _ target: CardRecord, basis: CardRecord, transactionAuthor: String
    ) throws(CardWriteFailure) -> CardSaveResult {
        try save(target, basis: basis, scope: .keepEveryValue, transactionAuthor: transactionAuthor)
    }
}

public enum CardSaveResult: Sendable, Hashable {
    case saved
    // Nothing needed writing: only Prefill's contact's order would have changed.
    case unchanged
    case stale(current: CardRecord)
}

public enum CardWriteFailure: Error, Sendable, Hashable, CaseIterable {
    case noAccess, cardMissing, notWritable, changedDuringSave, other

    public var reason: String {
        switch self {
        case .noAccess: "Prefill can't reach your contact card. Open Prefill to give it access again."
        case .cardMissing: "Prefill can't find your contact card. Open Prefill and choose your card again."
        case .notWritable: "Your contact card can't be edited on this iPhone, so Prefill left it as it was."
        case .changedDuringSave:
            "Your contact card kept changing while Prefill was saving, so Prefill left it as it was."
        case .other: "Prefill couldn't update your contact card, so nothing on it changed."
        }
    }
}

public enum CardWriteOutcome: Sendable, Hashable {
    case unchanged, saved, failed(CardWriteFailure)
}

public struct CardWriteResult: Sendable {
    public let outcome: CardWriteOutcome
    public let imported: [ContactValue]
}

public struct PageSignal: Sendable {
    public let host: String?
    public let hints: [ContactKind: SectionHint]
    public let now: Date
    public let matchEachSite: Bool
    // AppState.siteKinds and Settings.focusLabel. Without them the host rules still apply.
    public let siteKinds: [String: SiteKind]
    public let focusLabel: String?

    public init(
        host: String?, hints: [ContactKind: SectionHint], now: Date, matchEachSite: Bool,
        siteKinds: [String: SiteKind] = [:], focusLabel: String? = nil
    ) {
        self.host = host
        self.hints = hints
        self.now = now
        self.matchEachSite = matchEachSite
        self.siteKinds = siteKinds
        self.focusLabel = focusLabel
    }

    // The rules first, then what the app's model batch stored for hosts the rules can't place.
    func siteKind(emailDomains: Set<String>) -> SiteKind {
        guard let host else { return .unknown }
        let rule = SiteSense.rules(host: host, emailDomains: emailDomains)
        return rule == .unknown ? siteKinds[Normalizer.registrableDomain(host)] ?? .unknown : rule
    }

    func context(for kind: ContactKind, siteKind: SiteKind) -> RankingContext {
        RankingContext(
            host: host, hint: hints[kind], now: now, matchEachSite: matchEachSite,
            siteKind: siteKind, focusLabel: focusLabel
        )
    }
}

public struct CardSyncRequest: Sendable {
    public let cardIdentifier: String
    public let known: [ContactValue]
    public let additions: [ContactValue]
    public let usage: [UsageEvent]
    public let pins: [SitePin]
    public let page: PageSignal

    public init(
        cardIdentifier: String, known: [ContactValue], additions: [ContactValue],
        usage: [UsageEvent], pins: [SitePin], page: PageSignal
    ) {
        self.cardIdentifier = cardIdentifier
        self.known = known
        self.additions = additions
        self.usage = usage
        self.pins = pins
        self.page = page
    }
}

public struct CardWriter: Sendable {
    public static let transactionAuthor = "prefill"
    private static let visibleSlots = 2
    private static let attempts = 2
    private static let log = PrefillLog.logger("card")
    // Safari can deliver a capture and a page context to the same handler process at once.
    private static let syncLock = Mutex(())

    private let gateway: any ContactsGateway

    public init(gateway: any ContactsGateway) {
        self.gateway = gateway
    }

    // `current` is a card the caller has just read. If it changed since, the save finds
    // that out and plans again from the card as it is.
    public func sync(_ request: CardSyncRequest, current: CardRecord? = nil) -> CardWriteResult {
        Self.syncLock.withLock { _ in
            do throws(CardWriteFailure) {
                let card = if let current { current } else { try gateway.fetchCard(identifier: request.cardIdentifier) }
                return write(CardPlan(card: card, request: request), request: request, attempt: 1)
            } catch {
                Self.log.error("fetch failed: \(String(describing: error), privacy: .public)")
                return CardWriteResult(outcome: .failed(error), imported: [])
            }
        }
    }

    private func write(_ plan: CardPlan, request: CardSyncRequest, attempt: Int) -> CardWriteResult {
        guard plan.needsSave(visibleSlots: Self.visibleSlots) else {
            return CardWriteResult(outcome: .unchanged, imported: plan.imported)
        }
        do {
            switch try gateway.save(plan.target, basis: plan.card, transactionAuthor: Self.transactionAuthor) {
            case .saved:
                Self.log.info("card saved, \(plan.target.emails.count, privacy: .public) emails")
                return CardWriteResult(outcome: .saved, imported: plan.imported)
            case .unchanged:
                return CardWriteResult(outcome: .unchanged, imported: plan.imported)
            case .stale(let current) where attempt < Self.attempts:
                return write(CardPlan(card: current, request: request), request: request, attempt: attempt + 1)
            case .stale:
                Self.log.error("card kept changing, save skipped")
                return CardWriteResult(outcome: .failed(.changedDuringSave), imported: plan.imported)
            }
        } catch {
            Self.log.error("save failed: \(String(describing: error), privacy: .public)")
            return CardWriteResult(outcome: .failed(error), imported: plan.imported)
        }
    }
}

// Duplicate entries on the card ride along at the end, so nothing on the card is dropped.
struct CardPlan {
    let card: CardRecord
    let target: CardRecord
    let imported: [ContactValue]

    init(card: CardRecord, request: CardSyncRequest) {
        let knownIDs = Set(request.known.map(\.id))
        let onCard = ContactKind.allCases.flatMap { kind in
            card.entries(kind).map { ContactValue(entry: $0, createdAt: request.page.now) }
        }
        self.card = card
        self.imported = onCard.uniqued().filter { !knownIDs.contains($0.id) }
        let siteKind = request.page.siteKind(emailDomains: SiteSense.workDomains(onCard))
        self.target = ContactKind.allCases.reduce(card) { partial, kind in
            partial.replacing(kind, with: Self.targetEntries(kind, card: card, request: request, siteKind: siteKind))
        }
    }

    func needsSave(visibleSlots: Int) -> Bool {
        ContactKind.allCases.contains { kind in
            let before = card.entries(kind).map(\.key)
            let after = target.entries(kind).map(\.key)
            return before.count != after.count || before.prefix(visibleSlots) != after.prefix(visibleSlots)
        }
    }

    private static func targetEntries(
        _ kind: ContactKind, card: CardRecord, request: CardSyncRequest, siteKind: SiteKind
    ) -> [CardEntry] {
        let entries = card.entries(kind)
        let onCard = Dictionary(entries.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let pool = manualOrder(kind, entries: entries, request: request)
            .map { value in onCard[value.key].map(value.with(entry:)) ?? value }
        // Links aren't in Safari's contact bar, so they keep the person's order on every site.
        let context = request.page.context(for: kind, siteKind: siteKind)
        let ranked = kind == .link
            ? pool : Ranker.rank(pool, usage: request.usage, pins: request.pins, context: context)
        return ranked.map { CardEntry(label: $0.label, payload: $0.payload) } + duplicates(in: entries)
    }

    private static func manualOrder(
        _ kind: ContactKind, entries: [CardEntry], request: CardSyncRequest
    ) -> [ContactValue] {
        let fromCard = entries.map { ContactValue(entry: $0, createdAt: request.page.now) }.uniqued()
        let onCard = Set(fromCard.map(\.id))
        let known = request.known.filter { $0.kind == kind && onCard.contains($0.id) }.uniqued()
        let added = request.additions.filter { $0.kind == kind }
        return (placing(fromCard, among: known) + added).uniqued()
    }

    // A value only the card has goes just before the next value below it on the card that
    // Prefill knows. A value edited in place on another device so takes the place of the
    // one it replaced, and a value added at the bottom stays at the bottom.
    private static func placing(_ card: [ContactValue], among known: [ContactValue]) -> [ContactValue] {
        let knownIDs = Set(known.map(\.id))
        return card.indices.reduce(known) { order, index in
            guard !knownIDs.contains(card[index].id) else { return order }
            let next = card[(index + 1)...].first { knownIDs.contains($0.id) }
            let position = next.flatMap { below in order.firstIndex { $0.id == below.id } } ?? order.endIndex
            var placed = order
            placed.insert(card[index], at: position)
            return placed
        }
    }

    private static func duplicates(in entries: [CardEntry]) -> [CardEntry] {
        var seen = Set<String>()
        return entries.filter { !seen.insert($0.key).inserted }
    }
}

extension ContactValue {
    init(entry: CardEntry, createdAt: Date) {
        self.init(payload: entry.payload, label: entry.label, source: .card, createdAt: createdAt)
    }

    // Text and label as the card has them, history as the store has it.
    func with(entry: CardEntry) -> ContactValue {
        ContactValue(payload: entry.payload, label: entry.label, source: source, createdAt: createdAt)
    }
}

extension Array where Element == ContactValue {
    func uniqued() -> [ContactValue] {
        var seen = Set<UUID>()
        return filter { seen.insert($0.id).inserted }
    }
}
