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

    // The real card takes answers learned from an application, and Undo takes them back.
    @Test func learnedAnswersReachTheRealCardAndUndoRemovesThem() throws {
        try withThrowawayCard { identifier in
            let card = try gateway.fetchCard(identifier: identifier)
            let link = CardLink(
                contactIdentifier: identifier, containerIdentifier: nil, linkedIdentifiers: [],
                original: card, snapshotAt: .now
            )
            let router = MessageRouter(store: InMemoryStore(state: AppState(cardLink: link)), gateway: gateway)
            let learn: [String: Any] = [
                "type": "answers", "host": "boards.example.io", "action": "learn",
                "answers": [["question": "school", "value": "University of California, Berkeley"]]
            ]
            #expect(router.route(learn) == .answers(AnswersResponse(saved: 1)))
            let learned = try gateway.fetchCard(identifier: identifier)
            #expect(learned.customFields.map(\.value) == ["University of California, Berkeley"])
            #expect(learned.emails == card.emails)
            let undo: [String: Any] = ["type": "answers", "host": "boards.example.io", "action": "undo", "answers": []]
            #expect(router.route(undo) == .answers(AnswersResponse(saved: 1)))
            #expect(try gateway.fetchCard(identifier: identifier).customFields.isEmpty)
        }
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

    private func prefillContacts() throws -> [CNContact] {
        let keys = [CNContactDepartmentNameKey, CNContactOrganizationNameKey, CNContactUrlAddressesKey,
                    CNContactRelationsKey, CNContactEmailAddressesKey].map { $0 as CNKeyDescriptor }
        return try CNContactStore().unifiedContacts(
            matching: CNContact.predicateForContacts(matchingName: PrefillContact.searchName), keysToFetch: keys
        ).filter { [PrefillContact.marker, PrefillContact.minimalMarker].contains($0.departmentName) }
    }

    private func removePrefillContacts() throws {
        let request = CNSaveRequest()
        for contact in try prefillContacts() {
            if let mutable = contact.mutableCopy() as? CNMutableContact { request.delete(mutable) }
        }
        try CNContactStore().execute(request)
    }

    private func storedLinks(_ identifier: String) throws -> [String] {
        let keys = [CNContactUrlAddressesKey as CNKeyDescriptor]
        return try CNContactStore().unifiedContact(withIdentifier: identifier, keysToFetch: keys)
            .urlAddresses.map { $0.value as String }
    }

    @Test func movingOffTheCardCopiesFirstThenRemoves() throws {
        try removePrefillContacts()
        defer { try? removePrefillContacts() }
        try withThrowawayCard { identifier in
            let keys = [CNContactUrlAddressesKey as CNKeyDescriptor]
            let stored = try CNContactStore().unifiedContact(withIdentifier: identifier, keysToFetch: keys)
            let edited = try #require(stored.mutableCopy() as? CNMutableContact)
            edited.urlAddresses = [CNLabeledValue(label: "homepage", value: "https://casey.example.com")]
            let update = CNSaveRequest()
            update.update(edited)
            try CNContactStore().execute(update)

            let onCard = try gateway.placement(identifier: identifier).onCard.filter { $0.kind == .link }
            #expect(onCard.count == 1)
            try gateway.moveOffCard(onCard, identifier: identifier)
            #expect(try storedLinks(identifier).isEmpty)
            #expect(try gateway.placement(identifier: identifier).onCard.allSatisfy { $0.kind == .email })
            #expect(try gateway.placement(identifier: identifier).isMinimal == false)
            #expect(try gateway.fetchCard(identifier: identifier).links.map(\.payload) == [
                .link("https://casey.example.com")
            ])
            #expect(try storedEmails(identifier).map { $0.value as String } == emails)

            let copies = try prefillContacts()
            #expect(copies.count == 1)
            #expect(copies.first?.organizationName == "Prefill · Casey Prefill-Host-Test")

            let card = try gateway.fetchCard(identifier: identifier)
            let github = CardEntry(label: "GitHub", payload: .link("https://github.com/casey"))
            let target = card.replacing(.link, with: card.links + [github])
            #expect(try gateway.save(target, basis: card, transactionAuthor: CardWriter.transactionAuthor) == .saved)
            #expect(try storedLinks(identifier).isEmpty)
            #expect(try prefillContacts().first?.urlAddresses.count == 2)
        }
    }

    @Test func aMinimalCardKeepsNewEmailsOffTheCardUntilThePersonLeavesIt() throws {
        try removePrefillContacts()
        defer { try? removePrefillContacts() }
        try withThrowawayCard { identifier in
            try gateway.moveOffCard(try gateway.placement(identifier: identifier).onCard, identifier: identifier)
            #expect(try storedEmails(identifier).isEmpty)
            let placement = try gateway.placement(identifier: identifier)
            #expect(placement.isMinimal)
            #expect(placement.onPrefill.count == emails.count)
            #expect(try prefillContacts().first?.departmentName == PrefillContact.minimalMarker)

            let card = try gateway.fetchCard(identifier: identifier)
            #expect(card.emails.map(\.payload) == emails.map(ContactPayload.email))
            let added = CardEntry(label: nil, payload: .email("casey.new@example.net"))
            let target = card.replacing(.email, with: card.emails + [added])
            #expect(try gateway.save(target, basis: card, transactionAuthor: CardWriter.transactionAuthor) == .saved)
            #expect(try storedEmails(identifier).isEmpty)
            #expect(try prefillContacts().first?.emailAddresses.count == emails.count + 1)

            try gateway.moveOntoCard(nil, identifier: identifier, leavingMinimal: true)
            #expect(try storedEmails(identifier).map { $0.value as String } == emails + ["casey.new@example.net"])
            #expect(try gateway.placement(identifier: identifier).isMinimal == false)
            #expect(try prefillContacts().first?.emailAddresses.isEmpty == true)
        }
    }
}
