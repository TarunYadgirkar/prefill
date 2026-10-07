import Foundation
import Testing
@testable import PrefillKit

struct ModelTests {
    @Test func valueIdentityComesFromKindAndNormalizedValue() {
        let typed = Alex.value(.email(" ALEX.Rivera@example.com"), label: nil, source: .typedInApp)
        #expect(typed.id == Alex.homeEmail.id)
        #expect(typed.key == "alex.rivera@example.com")
        #expect(typed.kind == .email)
    }

    @Test func sameTextOfDifferentKindsGetsDifferentIDs() {
        let phone = Alex.value(.phone("5105550134"), label: nil)
        let email = Alex.value(.email("5105550134"), label: nil)
        #expect(phone.id != email.id)
    }

    @Test func displayKeepsWhatThePersonTyped() {
        #expect(Alex.mobile.display == "+1 (510) 555-0134")
        #expect(Alex.homeAddress.display == "2400 Durant Ave\nBerkeley CA 94704\nUnited States")
    }

    @Test func relabelingKeepsIdentity() {
        let relabeled = Alex.schoolEmail.with(label: "School")
        #expect(relabeled.id == Alex.schoolEmail.id)
        #expect(relabeled.label == "School")
        #expect(Alex.schoolEmail.label == nil)
    }

    @Test func settingsDefaultToOn() {
        let settings = Settings()
        #expect(settings.matchEachSite)
        #expect(settings.saveNewInfo)
    }

    @Test func appStateRoundTripsThroughJSON() throws {
        let state = AppState(
            values: Alex.allValues,
            pins: [SitePin(host: "example.org", kind: .email, valueID: Alex.workEmail.id)],
            settings: Settings(matchEachSite: false, saveNewInfo: true),
            cardLink: CardLink(
                contactIdentifier: "alex-card", containerIdentifier: "local",
                linkedIdentifiers: [], original: Alex.card, snapshotAt: .testNow
            ),
            rejectedValueIDs: [Alex.schoolEmail.id]
        )
        let decoded = try DocumentCoder.decode(AppState.self, from: DocumentCoder.encode(state))
        #expect(decoded == state)
    }

    @Test func settingsStoredWithAFocusLabelStillRead() throws {
        let old = try DocumentCoder.encode(AppState(values: [Alex.homeEmail], settings: Settings(matchEachSite: false)))
        var json = try #require(JSONSerialization.jsonObject(with: old) as? [String: Any])
        json["settings"] = ["matchEachSite": false, "saveNewInfo": true, "focusLabel": "work"]
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try DocumentCoder.decode(AppState.self, from: data)
        #expect(decoded == AppState(values: [Alex.homeEmail], settings: Settings(matchEachSite: false)))
    }

    @Test func rejectingKeepsTheNewestIDsOnceUpToTheCap() {
        let many = (0..<AppState.maxRejected).map { Alex.value(.email("old\($0)@example.net"), label: nil).id }
        let state = AppState(rejectedValueIDs: many).rejecting(many[1]).rejecting(Alex.schoolEmail.id)
        #expect(state.rejectedValueIDs.count == AppState.maxRejected)
        #expect(state.rejectedValueIDs.suffix(2) == [many[1], Alex.schoolEmail.id])
        #expect(!state.rejectedValueIDs.contains(many[0]))
        #expect(state.rejectedValueIDs.filter { $0 == many[1] }.count == 1)
    }

    @Test func extensionEventsRoundTripThroughJSON() throws {
        let capture = Capture(host: "example.org", value: Alex.workEmail, date: .testNow, verdict: .needsReview)
        let events = ExtensionEvents(
            usage: [UsageEvent(valueID: Alex.workEmail.id, host: "example.org", date: .testNow)],
            captures: [capture]
        )
        let decoded = try DocumentCoder.decode(ExtensionEvents.self, from: DocumentCoder.encode(events))
        #expect(decoded == events)
        #expect(decoded.captures.first?.kind == .email)
    }

    @Test func appendingEventsKeepsOnlyTheNewestUpToTheCap() {
        let old = (0..<ExtensionEvents.maxUsage).map { index in
            UsageEvent(valueID: Alex.homeEmail.id, host: "old.example", date: .daysAgo(Double(1000 - index)))
        }
        let newest = UsageEvent(valueID: Alex.workEmail.id, host: "example.org", date: .testNow)
        let events = ExtensionEvents(usage: old, captures: []).appending(usage: [newest], captures: [])
        #expect(events.usage.count == ExtensionEvents.maxUsage)
        #expect(events.usage.last == newest)
        #expect(events.usage.first == old[1])
    }

    @Test func capturesAreCappedToo() {
        let captures = (0...ExtensionEvents.maxCaptures).map { index in
            Capture(host: "example.org", value: Alex.schoolEmail, date: .daysAgo(Double(index)), verdict: .saved)
        }
        let events = ExtensionEvents().appending(usage: [], captures: captures)
        #expect(events.captures.count == ExtensionEvents.maxCaptures)
        #expect(events.captures.last == captures.last)
    }

    @Test func reviewSpamNeverPushesOutSavedOrUndoneRecords() {
        let saved = Capture(host: "example.org", value: Alex.schoolEmail, date: .daysAgo(9), verdict: .saved)
        let undone = Capture(host: "example.org", value: Alex.workEmail, date: .daysAgo(8), verdict: .dismissed)
        let spam = (0..<ExtensionEvents.maxCaptures).map { index in
            Capture(
                host: "spam.example", value: Alex.value(.email("junk\(index)@spam.example"), label: nil),
                date: .testNow, verdict: .needsReview
            )
        }
        let events = ExtensionEvents(captures: [saved, undone]).appending(usage: [], captures: spam)
        #expect(events.captures.count == ExtensionEvents.maxCaptures)
        #expect(Array(events.captures.prefix(2)) == [saved, undone])
        #expect(events.captures.last == spam.last)
    }

    @Test func cardRecordReturnsAndReplacesEntriesByKind() {
        let replaced = Alex.card.replacing(.email, with: [Alex.schoolEmail.entry])
        #expect(replaced.entries(.email) == [Alex.schoolEmail.entry])
        #expect(replaced.entries(.phone) == Alex.card.phones)
        #expect(Alex.card.entries(.email).count == 3)
    }
}
