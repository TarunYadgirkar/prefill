import Contacts
import Foundation
import PrefillKit
import Testing

// Runs the real CNContactStoreGateway against the simulator's contact store. scripts/test.sh
// grants the Personal app Contacts access first. Each test adds its own throwaway contact
// and removes it, so the Alex Rivera card set as My Info is never touched.
// Change history, where transactionAuthor shows up, is unavailable in Swift, so the author
// is covered by CardWriterTests through the fake gateway.
@Suite(.serialized)
struct ContactsGatewayHostTests {
    private let gateway = CNContactStoreGateway()
    private let emails = ["casey.home@example.com", "casey@work.example.org", "casey.school@example.edu"]

    private func withThrowawayCard(_ body: (String) throws -> Void) throws {
        let contact = CNMutableContact()
        contact.givenName = "Casey"
        contact.familyName = "Prefill-Host-Test"
        contact.emailAddresses = emails.map { CNLabeledValue(label: CNLabelHome, value: $0 as NSString) }
        let add = CNSaveRequest()
        add.add(contact, toContainerWithIdentifier: nil)
        try CNContactStore().execute(add)
        defer {
            let remove = CNSaveRequest()
            if let saved = contact.mutableCopy() as? CNMutableContact {
                remove.delete(saved)
                try? CNContactStore().execute(remove)
            }
        }
        try body(contact.identifier)
    }

    private func storedEmails(_ identifier: String) throws -> [CNLabeledValue<NSString>] {
        let keys = [CNContactEmailAddressesKey as CNKeyDescriptor]
        return try CNContactStore().unifiedContact(withIdentifier: identifier, keysToFetch: keys).emailAddresses
    }

    @Test func theAppHasContactsAccess() {
        #expect(CNContactStore.authorizationStatus(for: .contacts) == .authorized)
    }

    @Test func readsTheCardAsStored() throws {
        try withThrowawayCard { identifier in
            let card = try gateway.fetchCard(identifier: identifier)
            #expect(card.identifier == identifier)
            #expect(card.givenName == "Casey")
            #expect(card.emails.map(\.payload) == emails.map(ContactPayload.email))
        }
    }

    @Test func savesTheTargetOrderAsFreshValues() throws {
        try withThrowawayCard { identifier in
            let card = try gateway.fetchCard(identifier: identifier)
            let oldIDs = Set(try storedEmails(identifier).map(\.identifier))
            let target = card.replacing(.email, with: Array(card.emails.reversed()))
            let result = try gateway.save(target, basis: card, transactionAuthor: CardWriter.transactionAuthor)
            #expect(result == .saved)
            let stored = try storedEmails(identifier)
            #expect(stored.map { $0.value as String } == emails.reversed())
            #expect(oldIDs.isDisjoint(with: stored.map(\.identifier)))
            #expect(try gateway.fetchCard(identifier: identifier) == target)
        }
    }

    @Test func aCardChangedSinceThePlanIsNotOverwritten() throws {
        try withThrowawayCard { identifier in
            let card = try gateway.fetchCard(identifier: identifier)
            let keys = [CNContactEmailAddressesKey as CNKeyDescriptor]
            let elsewhere = try CNContactStore().unifiedContact(withIdentifier: identifier, keysToFetch: keys)
            let edited = try #require(elsewhere.mutableCopy() as? CNMutableContact)
            edited.emailAddresses += [CNLabeledValue(label: nil, value: "casey.new@example.net")]
            let update = CNSaveRequest()
            update.update(edited)
            try CNContactStore().execute(update)

            let target = card.replacing(.email, with: Array(card.emails.reversed()))
            let result = try gateway.save(target, basis: card, transactionAuthor: CardWriter.transactionAuthor)
            guard case .stale(let current) = result else {
                Issue.record("expected a stale result, got \(result)")
                return
            }
            #expect(current.emails.last?.payload == .email("casey.new@example.net"))
            #expect(try storedEmails(identifier).map { $0.value as String } == emails + ["casey.new@example.net"])
        }
    }

    @Test func cardWriterRewritesTheRealCardAndThenLeavesItAlone() throws {
        try withThrowawayCard { identifier in
            let school = ContactValue(
                payload: .email(emails[2]), label: CNLabelHome, source: .card, createdAt: .now
            )
            let request = CardSyncRequest(
                cardIdentifier: identifier, known: [], additions: [], usage: [],
                pins: [SitePin(host: "example.net", kind: .email, valueID: school.id)],
                page: PageSignal(host: "shop.example.net", hints: [:], now: .now, matchEachSite: true)
            )
            let writer = CardWriter(gateway: gateway)
            #expect(writer.sync(request).outcome == .saved)
            let first = try storedEmails(identifier).first.map { $0.value as String }
            #expect(first == emails[2])
            #expect(writer.sync(request).outcome == .unchanged)
        }
    }
}
