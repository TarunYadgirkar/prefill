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
        #expect(split.extrasOnCard.count == 10)
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
        let writes = try #require(split.moving([.entry(github), .customField(school)]))
        #expect(writes.card?.links == [homepage])
        #expect(writes.card?.customFields.isEmpty == true)
        #expect(writes.card?.emails == Alex.card.emails)
        #expect(writes.extras == CardExtras(links: [homepage, github], customFields: [school]))
    }

    @Test func movingWhatIsAlreadyOffTheCardDoesNothing() {
        #expect(CardSplit(card: Alex.card, copies: []).moving([.entry(github)]) == nil)
    }

    // The person keeps their name and mobile number on the card; the rest moves.
    private var minimalSplit: CardSplit {
        let moved = CardExtras(
            links: [], customFields: [], emails: Alex.card.emails, phones: [Alex.workPhone.entry],
            addresses: Alex.card.addresses, isMinimal: true
        )
        let card = Alex.card.replacing(.email, with: []).replacing(.phone, with: [Alex.mobile.entry])
            .replacing(.address, with: [])
        return CardSplit(card: card, copies: [moved])
    }

    @Test func movingEmailsPhonesAndAddressesLeavesNameAndPhoneAndMakesTheCardMinimal() throws {
        let split = CardSplit(card: Alex.card, copies: [])
        let chosen = split.extrasOnCard.filter { $0.id != CardExtra.entry(Alex.mobile.entry).id }
        let writes = try #require(split.moving(chosen))
        #expect(writes.card?.emails.isEmpty == true)
        #expect(writes.card?.addresses.isEmpty == true)
        #expect(writes.card?.phones == [Alex.mobile.entry])
        #expect(writes.extras == minimalSplit.extras)
        #expect(minimalSplit.record.emails == Alex.card.emails)
        #expect(Set(minimalSplit.record.phones) == Set(Alex.card.phones))
    }

    @Test func onAMinimalCardANewEmailGoesToThePrefillContact() {
        let split = minimalSplit
        let added = CardEntry(label: nil, payload: .email("alex@new.example.com"))
        let writes = split.writes(for: split.record.replacing(.email, with: split.record.emails + [added]))
        #expect(writes.card == nil)
        #expect(writes.extras?.emails == Alex.card.emails + [added])
        #expect(writes.extras?.isMinimal == true)
    }

    @Test func rankingAPageNeverRewritesThePrefillContact() {
        let split = minimalSplit
        let writes = split.writes(for: split.record.replacing(.email, with: Array(Alex.card.emails.reversed())))
        #expect(writes.isEmpty)
        #expect(split.placement.cardKeys == [Alex.mobile.entry.key])
    }

    // NameDrop keeps offering the number the person picked only while the card's phones stay put.
    @Test func aMinimalCardsPhonesAreNeverReordered() {
        let moved = CardExtras(links: [], customFields: [], emails: Alex.card.emails, isMinimal: true)
        let split = CardSplit(card: Alex.card.replacing(.email, with: []), copies: [moved])
        let reordered = split.record.replacing(.phone, with: [Alex.workPhone.entry, Alex.mobile.entry])
        #expect(split.writes(for: reordered).isEmpty)
        let trimmed = split.writes(for: split.record.replacing(.phone, with: [Alex.workPhone.entry]))
        #expect(trimmed.card?.phones == [Alex.workPhone.entry])
    }

    @Test func leavingAMinimalCardPutsEverythingBackOnIt() throws {
        let writes = try #require(minimalSplit.movingOntoCard(nil, leavingMinimal: true))
        #expect(writes.card?.emails == Alex.card.emails)
        #expect(writes.card?.phones == [Alex.mobile.entry, Alex.workPhone.entry])
        #expect(writes.extras == CardExtras(links: [], customFields: []))
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
