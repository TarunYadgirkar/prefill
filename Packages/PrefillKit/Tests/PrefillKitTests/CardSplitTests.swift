import Contacts
import Testing
@testable import PrefillKit

private let github = CardEntry(label: "GitHub", payload: .link("https://github.com/alexrivera"))
private let homepage = CardEntry(label: "homepage", payload: .link("https://alexrivera.dev"))
private let school = (try? CustomField.make(label: "School", value: "UC Berkeley", alsoMatches: "university").get())!
private let cardWithExtras = Alex.card.replacing(.link, with: [github, homepage]).replacingCustomFields(with: [school])

struct CardSplitTests {
    @Test func withoutAPrefillContactTheCardsOwnLinksStandIn() {
        let split = CardSplit(card: cardWithExtras, copies: [])
        #expect(split.record == cardWithExtras)
        #expect(split.extrasOnCard.count == 3)
    }

    @Test func linksAndCustomFieldsComeFromThePrefillContact() {
        let extras = CardExtras(links: [homepage], customFields: [])
        let split = CardSplit(card: cardWithExtras, copies: [extras])
        #expect(split.record.links == [homepage])
        #expect(split.record.customFields.isEmpty)
        #expect(split.record.emails == Alex.card.emails)
    }

    @Test func aReorderTouchesOnlyTheCardAndLeavesItsLinksAlone() {
        let split = CardSplit(card: cardWithExtras, copies: [CardExtras(links: [homepage], customFields: [school])])
        let target = split.record.replacing(.email, with: Array(Alex.card.emails.reversed()))
        let writes = split.writes(for: target)
        #expect(writes.extras == nil)
        #expect(writes.card?.emails == Array(Alex.card.emails.reversed()))
        #expect(writes.card?.links == [github, homepage])
        #expect(writes.card?.customFields == [school])
    }

    @Test func aNewLinkGoesToThePrefillContactNotTheCard() {
        let split = CardSplit(card: Alex.card, copies: [CardExtras(links: [], customFields: [])])
        let writes = split.writes(for: Alex.card.replacing(.link, with: [github]))
        #expect(writes.card == nil)
        #expect(writes.extras == CardExtras(links: [github], customFields: []))
    }

    @Test func beforeAnyMoveLinksStayOnTheCardAndNoContactIsMade() {
        let split = CardSplit(card: Alex.card, copies: [])
        let target = Alex.card.replacing(.link, with: [github])
        let writes = split.writes(for: target)
        #expect(writes.card == target)
        #expect(writes.includesCardExtras)
        #expect(writes.extras == nil)
    }

    @Test func copiesFromTwoDevicesMergeAndAllGetTheSameValues() {
        let split = CardSplit(card: Alex.card, copies: [
            CardExtras(links: [github], customFields: []), CardExtras(links: [homepage], customFields: [school])
        ])
        #expect(split.record.links == [github, homepage])
        #expect(split.writes(for: split.record).extras == CardExtras(links: [github, homepage], customFields: [school]))
    }

    @Test func movingOffTheCardKeepsEveryValueOnThePrefillContact() throws {
        let split = CardSplit(card: cardWithExtras, copies: [CardExtras(links: [homepage], customFields: [])])
        let writes = try #require(split.moving([.link(github), .customField(school)]))
        #expect(writes.card?.links == [homepage])
        #expect(writes.card?.customFields.isEmpty == true)
        #expect(writes.card?.emails == Alex.card.emails)
        #expect(writes.extras == CardExtras(links: [homepage, github], customFields: [school]))
    }

    @Test func movingWhatIsAlreadyOffTheCardDoesNothing() {
        #expect(CardSplit(card: Alex.card, copies: []).moving([.link(github)]) == nil)
    }

    @Test func theMappingWritesExtrasWithoutTouchingTheCoreFields() {
        let contact = CNMutableContact()
        contact.emailAddresses = [CNLabeledValue(label: nil, value: "alex.rivera@example.com")]
        CNCardMapping.applyExtras(CardExtras(links: [github], customFields: [school]), to: contact)
        #expect(contact.urlAddresses.map { $0.value as String } == ["https://github.com/alexrivera"])
        #expect(CNCardMapping.customFields(of: contact) == [school])
        #expect(contact.emailAddresses.count == 1)
    }
}
