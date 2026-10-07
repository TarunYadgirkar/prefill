import Foundation
import Testing
@testable import PrefillKit

struct ManualOrderTests {
    @Test func followsTheStoredOrderForValuesPrefillKnows() {
        let known = [Alex.schoolEmail, Alex.homeEmail, Alex.workEmail]
        let order = ManualOrder.values(.email, card: Alex.card, known: known, now: .testNow)
        #expect(order.map(\.id) == known.map(\.id))
    }

    @Test func placesCardOnlyValuesByTheirPositionOnTheCard() {
        let known = [Alex.workEmail, Alex.schoolEmail]
        let order = ManualOrder.values(.email, card: Alex.card, known: known, now: .testNow)
        #expect(order.map(\.id) == [Alex.homeEmail, Alex.workEmail, Alex.schoolEmail].map(\.id))
    }

    @Test func leavesOutValuesThatAreNoLongerOnTheCard() {
        let gone = Alex.value(.email("old@example.com"), label: nil)
        let order = ManualOrder.values(.email, card: Alex.card, known: [gone] + Alex.emails, now: .testNow)
        #expect(!order.contains(gone))
        #expect(order.count == 3)
    }

    @Test func replacingOneKindKeepsTheOthers() {
        let reordered = [Alex.workPhone, Alex.mobile]
        let values = ManualOrder.replacing(.phone, with: reordered, in: Alex.allValues)
        #expect(values.filter { $0.kind == .phone } == reordered)
        #expect(values.filter { $0.kind == .email } == Alex.emails)
    }
}

struct CardEditorTests {
    @Test func removesOneValueAndKeepsTheRestInOrder() {
        let gateway = FakeGateway()
        let outcome = CardEditor(gateway: gateway).apply(.remove(Alex.workEmail), cardIdentifier: Alex.card.identifier)
        #expect(outcome == .saved)
        #expect(gateway.card.emails == [Alex.homeEmail.entry, Alex.schoolEmail.entry])
        #expect(gateway.saves.first?.author == CardWriter.transactionAuthor)
    }

    @Test func relabelsOnlyTheChosenValue() {
        let gateway = FakeGateway()
        let edit = CardEditor.Edit.relabel(Alex.schoolEmail, label: "_$!<School>!$_")
        #expect(CardEditor(gateway: gateway).apply(edit, cardIdentifier: Alex.card.identifier) == .saved)
        #expect(gateway.card.emails.map(\.label) == [Alex.homeLabel, Alex.workLabel, "_$!<School>!$_"])
    }

    @Test func anEditThatChangesNothingSkipsTheSave() {
        let gateway = FakeGateway()
        let edit = CardEditor.Edit.relabel(Alex.homeEmail, label: Alex.homeLabel)
        #expect(CardEditor(gateway: gateway).apply(edit, cardIdentifier: Alex.card.identifier) == .unchanged)
        #expect(gateway.saves.isEmpty)
    }

    @Test func aValueAddedElsewhereMeanwhileSurvivesARemove() {
        let gateway = FakeGateway()
        let added = CardEntry(label: nil, payload: .email("alex.new@example.net"))
        gateway.state.withLock { $0.editsBeforeSave = [{ $0.replacing(.email, with: $0.emails + [added]) }] }
        let outcome = CardEditor(gateway: gateway).apply(.remove(Alex.workEmail), cardIdentifier: Alex.card.identifier)
        #expect(outcome == .saved)
        #expect(gateway.card.emails == [Alex.homeEmail.entry, Alex.schoolEmail.entry, added])
    }

    @Test func restorePutsTheOriginalValuesBack() {
        let edited = Alex.card.replacing(.email, with: [Alex.workEmail.entry])
        let gateway = FakeGateway(card: edited)
        let outcome = CardEditor(gateway: gateway).apply(.restore(Alex.card), cardIdentifier: Alex.card.identifier)
        #expect(outcome == .saved)
        #expect(gateway.card == Alex.card)
    }

    @Test func aMissingCardIsReported() {
        let outcome = CardEditor(gateway: FakeGateway()).apply(.remove(Alex.workEmail), cardIdentifier: "someone-else")
        #expect(outcome == .failed(.cardMissing))
    }
}

struct SiteDirectoryTests {
    @Test func listsSitesNewestFirst() {
        let events = ExtensionEvents(usage: [
            UsageEvent(valueID: Alex.workEmail.id, host: "portal.work.example.org", date: .daysAgo(1)),
            UsageEvent(valueID: Alex.schoolEmail.id, host: "shop.example.net", date: .daysAgo(3))
        ])
        let pinned = AppState().pinning(Alex.homeEmail.id, kind: .email, host: "example.com")
        #expect(SiteDirectory.hosts(state: pinned, events: events) == ["example.org", "example.net", "example.com"])
    }
}

struct PinningTests {
    private let state = AppState(values: Alex.allValues)

    @Test func pinningAgainReplacesThePinAndNilRemovesIt() {
        let once = state.pinning(Alex.schoolEmail.id, kind: .email, host: "example.net")
        let twice = once.pinning(Alex.workEmail.id, kind: .email, host: "www.example.net")
        #expect(twice.pins == [SitePin(host: "example.net", kind: .email, valueID: Alex.workEmail.id)])
        #expect(twice.pinning(nil, kind: .email, host: "example.net").pins.isEmpty)
    }
}

struct RecentCapturesTests {
    private let added = Alex.value(.email("alex.new@example.net"), label: nil, source: .captured)
    private let review = Alex.value(.phone("+1 (510) 555-0100"), label: nil, source: .captured)

    private func capture(_ value: ContactValue, _ verdict: CaptureVerdict, daysAgo: Double) -> Capture {
        Capture(host: "example.net", value: value, date: .daysAgo(daysAgo), verdict: verdict)
    }

    @Test func showsWaitingAndSavedNewestFirst() {
        let card = Alex.card.replacing(.email, with: Alex.card.emails + [added.entry])
        let events = ExtensionEvents(captures: [
            capture(added, .saved, daysAgo: 2), capture(review, .needsReview, daysAgo: 1)
        ])
        let items = RecentCaptures.items(events: events, state: AppState(), card: card)
        #expect(items.map(\.value) == [review, added])
        #expect(items.map(\.state) == [.waiting, .saved])
    }

    @Test func aReviewedValueSavedFromTheAppCountsAsSaved() {
        let card = Alex.card.replacing(.phone, with: Alex.card.phones + [review.entry])
        let events = ExtensionEvents(captures: [capture(review, .needsReview, daysAgo: 1)])
        #expect(RecentCaptures.items(events: events, state: AppState(), card: card).map(\.state) == [.saved])
    }

    @Test func undoneAndDismissedBothShowAsRemoved() {
        let events = ExtensionEvents(captures: [
            capture(added, .saved, daysAgo: 2), capture(review, .needsReview, daysAgo: 1)
        ])
        let state = AppState().rejecting(added.id).rejecting(review.id)
        let items = RecentCaptures.items(events: events, state: state, card: Alex.card)
        #expect(items.map(\.value) == [review, added])
        #expect(items.map(\.state) == [.removed, .removed])
    }

    @Test func aValuePutBackOnTheCardCountsAsSavedAgain() {
        let card = Alex.card.replacing(.email, with: Alex.card.emails + [added.entry])
        let events = ExtensionEvents(captures: [capture(added, .saved, daysAgo: 2)])
        let state = AppState().rejecting(added.id).rejecting(review.id).unrejecting(added.id)
        #expect(state.rejectedValueIDs == [review.id])
        #expect(RecentCaptures.items(events: events, state: state, card: card).map(\.state) == [.saved])
    }

    @Test func aValueCapturedTwiceAppearsOnce() {
        let events = ExtensionEvents(captures: [
            capture(review, .needsReview, daysAgo: 3), capture(review, .needsReview, daysAgo: 1)
        ])
        let items = RecentCaptures.items(events: events, state: AppState(), card: Alex.card)
        #expect(items.count == 1)
        #expect(items.first?.date == .daysAgo(1))
    }
}

struct LabelChoicesTests {
    @Test func captionsMatchWhatSafariShows() {
        #expect(LabelChoices.caption(Alex.workLabel, kind: .email) == "work")
        #expect(LabelChoices.caption("Gym", kind: .email) == "Gym")
        #expect(LabelChoices.caption(nil, kind: .email) == "email")
        #expect(LabelChoices.caption(nil, kind: .phone) == "phone")
    }
}
