import Contacts
import Foundation
import PrefillKit
import Testing

// Setup and cleanup for the Safari extension end-to-end run (scripts/test.sh e2e). They run
// inside Prefill.app, so they write the same shared store the extension reads, the way
// onboarding will. All stay disabled unless the script sets PREFILL_E2E, so the unit run
// never touches the Alex Rivera card.
@Suite(.serialized)
struct E2ESetupHostTests {
    private static let mode = ProcessInfo.processInfo.environment["PREFILL_E2E"]

    // The emails on testbed/alex-rivera.vcf, in the vCard's order.
    private static let emails: [(label: String?, value: String)] = [
        (CNLabelHome, "alex.rivera@example.com"),
        (CNLabelWork, "alex@work.example.org"),
        (nil, "alex.school@example.edu")
    ]

    private func alexIdentifier() throws -> String {
        let keys = [CNContactIdentifierKey as CNKeyDescriptor]
        let matches = try CNContactStore().unifiedContacts(
            matching: CNContact.predicateForContacts(matchingName: "Alex Rivera"), keysToFetch: keys
        )
        return try #require(matches.first?.identifier, "Alex Rivera is missing from this simulator")
    }

    // Puts the card's emails back to the vCard's three and takes off any links and custom
    // fields, which also drops anything an earlier run added. Phones and addresses are left
    // as they are.
    private func resetEmails(_ identifier: String) throws {
        let keys = [CNContactEmailAddressesKey, CNContactUrlAddressesKey, CNContactRelationsKey]
            .map { $0 as CNKeyDescriptor }
        let contact = try CNContactStore().unifiedContact(withIdentifier: identifier, keysToFetch: keys)
        let card = try #require(contact.mutableCopy() as? CNMutableContact)
        card.emailAddresses = Self.emails.map { CNLabeledValue(label: $0.label, value: $0.value as NSString) }
        card.urlAddresses = []
        card.contactRelations = card.contactRelations.filter {
            CustomFieldLabel.decode(label: $0.label, value: $0.value.name) == nil
        }
        let request = CNSaveRequest()
        request.update(card)
        try CNContactStore().execute(request)
    }

    private func sharedStore() throws -> KeychainStore {
        try #require(StoreFactory.make() as? KeychainStore)
    }

    @Test(.enabled(if: mode == "link"))
    func linkAlexCard() throws {
        let identifier = try alexIdentifier()
        try resetEmails(identifier)
        let card = try CNContactStoreGateway().fetchCard(identifier: identifier)
        let values = [card.emails, card.phones, card.addresses, card.links].joined().map { entry in
            ContactValue(payload: entry.payload, label: entry.label, source: .card, createdAt: .now)
        }
        let link = CardLink(
            contactIdentifier: identifier, containerIdentifier: nil, linkedIdentifiers: [],
            original: card, snapshotAt: .now
        )
        let store = try sharedStore()
        try store.removeAll()
        try store.writeAppState(AppState(values: values, cardLink: link))
        #expect(try store.readAppState().cardLink?.contactIdentifier == identifier)
        #expect(try store.readEvents() == ExtensionEvents())
    }

    // The positive control for the gift step of ExtensionE2ETests: its capture reached the
    // app, which recorded the buyer's own email as used on site A and kept nothing of the
    // recipient's, not even for review.
    @Test(.enabled(if: mode == "verify"))
    func verifyGiftCapture() throws {
        let events = try sharedStore().readEvents()
        let buyer = ContactValue(payload: .email(Self.emails[0].value), label: nil, source: .card, createdAt: .now)
        #expect(events.usage.contains { $0.valueID == buyer.id && $0.host == "localhost" })
        let kept = events.captures.map { Normalizer.key(for: $0.value.payload) }
        #expect(!kept.contains("jordan.lee@example.net"))
        #expect(!kept.contains { $0.hasPrefix("77 gift way") })
    }

    @Test(.enabled(if: mode == "restore"))
    func restoreAlexCard() throws {
        try resetEmails(try alexIdentifier())
        try sharedStore().removeAll()
    }
}
