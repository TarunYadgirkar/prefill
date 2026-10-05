import Foundation
import Synchronization
import Testing
@testable import PrefillKit

final class FakeGateway: ContactsGateway {
    struct State {
        var card: CardRecord
        var fetches = 0
        var saves: [(card: CardRecord, author: String)] = []
        var calls: [String] = []
        var fetchError: CardWriteFailure?
        var saveError: CardWriteFailure?
        // Edits that land on the card between the fetch and the save, one per save call.
        var editsBeforeSave: [(CardRecord) -> CardRecord] = []
        var fetchDelay: TimeInterval = 0
        var placement = CardPlacement(onCard: [])
    }

    let state: Mutex<State>

    init(card: CardRecord = Alex.card) {
        state = Mutex(State(card: card))
    }

    var card: CardRecord { state.withLock { $0.card } }
    var fetches: Int { state.withLock { $0.fetches } }
    var saves: [(card: CardRecord, author: String)] { state.withLock { $0.saves } }

    func fetchCard(identifier: String) throws(CardWriteFailure) -> CardRecord {
        let delay = state.withLock { $0.fetchDelay }
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        let result: Result<CardRecord, CardWriteFailure> = state.withLock { state in
            state.fetches += 1
            state.calls.append("fetch")
            if let error = state.fetchError { return .failure(error) }
            guard state.card.identifier == identifier else { return .failure(.cardMissing) }
            return .success(state.card)
        }
        return try result.get()
    }

    func placement(identifier: String) throws(CardWriteFailure) -> CardPlacement {
        state.withLock { $0.placement }
    }

    func save(
        _ target: CardRecord, basis: CardRecord, scope: CardSaveScope, transactionAuthor: String
    ) throws(CardWriteFailure) -> CardSaveResult {
        let result: Result<CardSaveResult, CardWriteFailure> = state.withLock { state in
            if let error = state.saveError { return .failure(error) }
            guard scope.allows(target, over: basis) else { return .failure(.other) }
            if !state.editsBeforeSave.isEmpty { state.card = state.editsBeforeSave.removeFirst()(state.card) }
            guard state.card == basis else {
                state.calls.append("stale")
                return .success(.stale(current: state.card))
            }
            state.calls.append("save")
            state.saves.append((target, transactionAuthor))
            state.card = target
            return .success(.saved)
        }
        return try result.get()
    }
}

struct CardWriterTests {
    private func sync(
        _ gateway: FakeGateway,
        known: [ContactValue] = Alex.allValues,
        additions: [ContactValue] = [],
        usage: [UsageEvent] = [],
        pins: [SitePin] = [],
        hints: [ContactKind: SectionHint] = [:]
    ) -> CardWriteResult {
        let request = CardSyncRequest(
            cardIdentifier: "alex-card", known: known, additions: additions, usage: usage, pins: pins,
            page: PageSignal(host: "shop.example.net", hints: hints, now: .testNow, matchEachSite: true)
        )
        return CardWriter(gateway: gateway).sync(request)
    }

    private func pin(_ value: ContactValue) -> SitePin {
        SitePin(host: "example.net", kind: value.kind, valueID: value.id)
    }

    @Test func skipsTheSaveWhenTheFirstTwoAlreadyMatch() {
        let gateway = FakeGateway()
        let result = sync(gateway)
        #expect(result.outcome == .unchanged)
        #expect(gateway.saves.isEmpty)
        #expect(gateway.fetches == 1)
    }

    @Test func rewritesTheCardInRankedOrderInOneSave() {
        let gateway = FakeGateway()
        let result = sync(gateway, pins: [pin(Alex.schoolEmail)])
        #expect(result.outcome == .saved)
        #expect(gateway.saves.count == 1)
        #expect(gateway.card.emails == [Alex.schoolEmail.entry, Alex.homeEmail.entry, Alex.workEmail.entry])
        #expect(gateway.card.phones == Alex.card.phones)
        #expect(gateway.card.addresses == Alex.card.addresses)
    }

    @Test func tagsEverySaveWithPrefillAsTheAuthor() {
        let gateway = FakeGateway()
        _ = sync(gateway, pins: [pin(Alex.workPhone)])
        #expect(gateway.saves.map(\.author) == ["prefill"])
    }

    @Test func aChangePastTheSecondSlotIsNotWorthASave() {
        let extra = Alex.value(.email("rivera.alex@example.info"), label: nil)
        let card = Alex.card.replacing(.email, with: (Alex.emails + [extra]).map(\.entry))
        let gateway = FakeGateway(card: card)
        let usage = [UsageEvent(valueID: extra.id, host: "example.org", date: .daysAgo(1))]
        let result = sync(gateway, known: Alex.allValues + [extra], usage: usage)
        #expect(result.outcome == .unchanged)
        #expect(gateway.saves.isEmpty)
    }

    @Test func importsValuesAddedToTheCardElsewhere() {
        let gateway = FakeGateway()
        let known = Alex.allValues.filter { $0 != Alex.schoolEmail }
        let result = sync(gateway, known: known)
        #expect(result.imported.map(\.id) == [Alex.schoolEmail.id])
        #expect(result.imported.first?.source == .card)
        #expect(result.outcome == .unchanged)
    }

    @Test func aFirstRunImportsTheWholeCardInCardOrder() {
        let gateway = FakeGateway()
        let result = sync(gateway, known: [])
        #expect(result.imported.map(\.id) == Alex.allValues.map(\.id))
        #expect(result.outcome == .unchanged)
    }

    @Test func neverDropsAValueThatIsOnTheCard() {
        let duplicate = CardEntry(label: nil, payload: .email("ALEX.RIVERA@example.com"))
        let card = Alex.card.replacing(.email, with: Alex.card.emails + [duplicate])
        let gateway = FakeGateway(card: card)
        let deletedElsewhere = Alex.value(.email("old@example.net"), label: nil)
        _ = sync(gateway, known: [deletedElsewhere] + Alex.allValues, pins: [pin(Alex.workEmail)])
        let written = gateway.card.emails
        #expect(written.count == card.emails.count)
        #expect(Set(written) == Set(card.emails))
        #expect(written.first == Alex.workEmail.entry)
        #expect(written.last == duplicate)
    }

    @Test func valuesDeletedElsewhereAreNotWrittenBack() {
        let gateway = FakeGateway()
        let deletedElsewhere = Alex.value(.email("old@example.net"), label: nil)
        _ = sync(gateway, known: [deletedElsewhere] + Alex.allValues, pins: [pin(Alex.workEmail)])
        #expect(!gateway.card.emails.contains(deletedElsewhere.entry))
    }

    @Test func anAdditionIsSavedEvenWhenTheTopTwoStay() {
        let gateway = FakeGateway()
        let new = Alex.value(.email("alex.new@example.net"), label: nil, source: .captured)
        let result = sync(gateway, additions: [new])
        #expect(result.outcome == .saved)
        #expect(gateway.card.emails == (Alex.emails + [new]).map(\.entry))
    }

    @Test func anAdditionAlreadyOnTheCardIsNotAddedTwice() {
        let gateway = FakeGateway()
        let again = Alex.value(.email(" Alex@Work.example.org"), label: nil, source: .captured)
        let result = sync(gateway, additions: [again])
        #expect(result.outcome == .unchanged)
        #expect(gateway.card.emails.count == 3)
    }

    @Test func labelsOnTheCardWinOverStoredLabels() {
        let card = Alex.card.replacing(.email, with: [
            CardEntry(label: "School", payload: Alex.schoolEmail.payload), Alex.homeEmail.entry, Alex.workEmail.entry
        ])
        let gateway = FakeGateway(card: card)
        _ = sync(gateway, pins: [pin(Alex.workEmail)])
        #expect(gateway.card.emails.contains(CardEntry(label: "School", payload: Alex.schoolEmail.payload)))
    }

    @Test func theCardsSpellingWinsOverTheStoredSpelling() {
        let asTyped = CardEntry(label: Alex.workLabel, payload: .email("Alex@Work.example.org"))
        let card = Alex.card.replacing(.email, with: [Alex.homeEmail.entry, asTyped, Alex.schoolEmail.entry])
        let gateway = FakeGateway(card: card)
        _ = sync(gateway, pins: [pin(Alex.workEmail)])
        #expect(gateway.card.emails.first == asTyped)
    }

    @Test func sectionHintsApplyPerKind() {
        let gateway = FakeGateway()
        let result = sync(gateway, hints: [.email: .work])
        #expect(result.outcome == .saved)
        #expect(gateway.card.emails.first == Alex.workEmail.entry)
        #expect(gateway.card.phones == Alex.card.phones)
    }

    @Test func refetchesBeforeEverySync() {
        let gateway = FakeGateway()
        _ = sync(gateway)
        let fromPhone = CardEntry(label: nil, payload: .email("added.on.mac@example.net"))
        gateway.state.withLock { $0.card = $0.card.replacing(.email, with: $0.card.emails + [fromPhone]) }
        _ = sync(gateway, pins: [pin(Alex.workEmail)])
        #expect(gateway.fetches == 2)
        #expect(gateway.card.emails.contains(fromPhone))
    }

    @Test func storedOrderWinsOverCardOrderWithoutSiteSignals() {
        let gateway = FakeGateway()
        let stored = [Alex.schoolEmail, Alex.homeEmail, Alex.workEmail] + Alex.allValues.filter { $0.kind != .email }
        let result = sync(gateway, known: stored)
        #expect(result.outcome == .saved)
        #expect(gateway.card.emails == [Alex.schoolEmail, Alex.homeEmail, Alex.workEmail].map(\.entry))
    }

    // A reorder made on the card outside Prefill is undone here. The app is meant to pick
    // such reorders up through Contacts change history and update the stored order first.
    @Test func aReorderMadeOutsidePrefillGivesWayToTheStoredOrder() {
        let outsideOrder = [Alex.workEmail, Alex.schoolEmail, Alex.homeEmail]
        let reordered = Alex.card.replacing(.email, with: outsideOrder.map(\.entry))
        let gateway = FakeGateway(card: reordered)
        let result = sync(gateway)
        #expect(result.outcome == .saved)
        #expect(gateway.card.emails == Alex.card.emails)
    }

    @Test func aValueEditedInPlaceElsewhereKeepsItsSlot() {
        let edited = Alex.value(.email("alex.r@example.com"), label: Alex.homeLabel)
        let card = Alex.card.replacing(.email, with: [edited, Alex.workEmail, Alex.schoolEmail].map(\.entry))
        let gateway = FakeGateway(card: card)
        let result = sync(gateway)
        #expect(result.outcome == .unchanged)
        #expect(result.imported.map(\.id) == [edited.id])
        #expect(gateway.saves.isEmpty)
    }

    @Test func aValueEditedInTheMiddleStaysInTheMiddle() {
        let edited = Alex.value(.email("alex@new-job.example.org"), label: Alex.workLabel)
        let card = Alex.card.replacing(.email, with: [Alex.homeEmail, edited, Alex.schoolEmail].map(\.entry))
        let gateway = FakeGateway(card: card)
        _ = sync(gateway, pins: [pin(Alex.homeEmail)])
        #expect(gateway.card.emails == card.emails)
    }

    @Test func anEditedValueTakesTheStoredPlaceOfTheValueItReplaced() {
        let edited = Alex.value(.email("alex.r@example.com"), label: Alex.homeLabel)
        let card = Alex.card.replacing(.email, with: [edited, Alex.workEmail, Alex.schoolEmail].map(\.entry))
        let gateway = FakeGateway(card: card)
        let stored = [Alex.schoolEmail, Alex.homeEmail, Alex.workEmail]
        _ = sync(gateway, known: stored)
        #expect(gateway.card.emails == [Alex.schoolEmail, edited, Alex.workEmail].map(\.entry))
    }

    @Test func aCardChangedBetweenFetchAndSaveIsPlannedAgain() {
        let gateway = FakeGateway()
        let captured = CardEntry(label: nil, payload: .email("alex.new@example.net"))
        gateway.state.withLock { state in
            state.editsBeforeSave = [{ $0.replacing(.email, with: $0.emails + [captured]) }]
        }
        let result = sync(gateway, pins: [pin(Alex.schoolEmail)])
        #expect(result.outcome == .saved)
        #expect(gateway.state.withLock(\.calls) == ["fetch", "stale", "save"])
        #expect(gateway.card.emails.first == Alex.schoolEmail.entry)
        #expect(gateway.card.emails.contains(captured))
        #expect(result.imported.map(\.key) == ["alex.new@example.net"])
    }

    @Test func aCardThatKeepsChangingIsLeftAlone() {
        let gateway = FakeGateway()
        let edit: (CardRecord) -> CardRecord = { card in
            let another = CardEntry(label: nil, payload: .email("\(card.emails.count)@example.net"))
            return card.replacing(.email, with: card.emails + [another])
        }
        gateway.state.withLock { $0.editsBeforeSave = [edit, edit] }
        let result = sync(gateway, pins: [pin(Alex.schoolEmail)])
        #expect(result.outcome == .failed(.changedDuringSave))
        #expect(gateway.saves.isEmpty)
        #expect(gateway.card.emails.count == Alex.card.emails.count + 2)
    }

    @Test func concurrentSyncsInOneProcessTakeTurns() async {
        let gateway = FakeGateway()
        gateway.state.withLock { $0.fetchDelay = 0.005 }
        let additions = (0..<6).map { Alex.value(.email("new\($0)@example.net"), label: nil, source: .captured) }
        await withTaskGroup(of: Void.self) { group in
            for addition in additions {
                group.addTask { _ = self.sync(gateway, additions: [addition]) }
            }
        }
        let calls = gateway.state.withLock(\.calls)
        #expect(calls == Array(repeating: ["fetch", "save"], count: additions.count).flatMap(\.self))
        #expect(Set(additions.map(\.entry)).isSubset(of: Set(gateway.card.emails)))
    }

    @Test(arguments: [CardWriteFailure.noAccess, .cardMissing, .notWritable, .changedDuringSave, .other])
    func aFailedFetchIsReportedInPlainLanguage(failure: CardWriteFailure) {
        let gateway = FakeGateway()
        gateway.state.withLock { $0.fetchError = failure }
        let result = sync(gateway, pins: [pin(Alex.workEmail)])
        #expect(result.outcome == .failed(failure))
        #expect(!failure.reason.isEmpty)
        #expect(gateway.saves.isEmpty)
    }

    @Test func aFailedSaveIsReported() {
        let gateway = FakeGateway()
        gateway.state.withLock { $0.saveError = .notWritable }
        let result = sync(gateway, pins: [pin(Alex.workEmail)])
        #expect(result.outcome == .failed(.notWritable))
        #expect(gateway.card == Alex.card)
    }

    @Test func aMissingCardIsReported() {
        let gateway = FakeGateway(card: Alex.card)
        let request = CardSyncRequest(
            cardIdentifier: "someone-else", known: [], additions: [], usage: [], pins: [],
            page: PageSignal(host: nil, hints: [:], now: .testNow, matchEachSite: true)
        )
        #expect(CardWriter(gateway: gateway).sync(request).outcome == .failed(.cardMissing))
    }
}

// The gateway's own check, whatever planned the save.
struct CardSaveGuardTests {
    private func email(_ text: String) -> CardEntry {
        CardEntry(label: nil, payload: .email(text))
    }

    @Test func aReorderKeepsEveryValue() {
        let target = Alex.card.replacing(.email, with: Alex.card.emails.reversed())
        #expect(target.keepsEveryValue(of: Alex.card))
    }

    @Test func droppingAValueIsRefused() {
        let target = Alex.card.replacing(.email, with: Array(Alex.card.emails.dropLast()))
        #expect(!target.keepsEveryValue(of: Alex.card))
    }

    @Test func addingMoreThanAFewValuesAtOnceIsRefused() {
        let added = (1...4).map { email("new\($0)@example.net") }
        #expect(Alex.card.replacing(.email, with: Alex.card.emails + added.prefix(3)).keepsEveryValue(of: Alex.card))
        #expect(!Alex.card.replacing(.email, with: Alex.card.emails + added).keepsEveryValue(of: Alex.card))
    }

    @Test func aLostValueIsPutBackAtTheEnd() {
        let lost = Alex.card.emails[0]
        let saved = Alex.card.replacing(.email, with: Array(Alex.card.emails.dropFirst()) + [email("new@example.net")])
        let restored = saved.restoringValues(of: Alex.card)
        #expect(restored.emails.last == lost)
        #expect(restored.keepsEveryValue(of: Alex.card))
        #expect(Alex.card.restoringValues(of: Alex.card) == Alex.card)
    }
}
