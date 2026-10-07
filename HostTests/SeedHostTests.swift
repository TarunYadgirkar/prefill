import Contacts
import Foundation
import PrefillKit
import Testing

// Puts the simulator in a known state for the UI tour (scripts/ui-tour.sh), which sets
// PREFILL_SEED through TEST_RUNNER_PREFILL_SEED. It runs inside Prefill.app, so it writes
// the app's real store and the Alex Rivera card. scripts/test.sh never sets the variable,
// so the unit run skips it and leaves the simulator alone.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["PREFILL_SEED"] != nil))
struct SeedHostTests {
    private static let home = "_$!<Home>!$_"
    private static let work = "_$!<Work>!$_"
    private static let mobile = "_$!<Mobile>!$_"

    // testbed/alex-rivera.vcf, plus a newsletter email the extension saved from a form.
    private static let newsletter = CardEntry(label: nil, payload: .email("alex.news@example.com"))
    private static let emails = [
        CardEntry(label: home, payload: .email("alex.rivera@example.com")),
        CardEntry(label: work, payload: .email("alex@work.example.org")),
        CardEntry(label: nil, payload: .email("alex.school@example.edu")),
        newsletter
    ]
    private static let phones = [
        CardEntry(label: mobile, payload: .phone("+1 (510) 555-0134")),
        CardEntry(label: work, payload: .phone("+1 (415) 555-0199"))
    ]
    private static let addresses = [
        CardEntry(label: home, payload: .address(PostalAddress(
            street: "2400 Durant Ave", city: "Berkeley", state: "CA", postalCode: "94704", country: "United States"
        ))),
        CardEntry(label: work, payload: .address(PostalAddress(
            street: "1 Market St Suite 300", city: "San Francisco", state: "CA", postalCode: "94105",
            country: "United States"
        )))
    ]

    private static let mode = ProcessInfo.processInfo.environment["PREFILL_SEED"]

    @Test(.enabled(if: mode != "school"))
    func seedTheTour() async throws {
        let identifier = try alexIdentifier()
        try resetCard(identifier)
        // The host app reacts to the card change by storing its state; let that land first.
        try await Task.sleep(for: .seconds(2))
        let store = try #require(StoreFactory.make() as? KeychainStore)
        try store.removeAll()
        let events = Self.events(now: .now)
        try store.appendEvents(events)
        UserDefaults.standard.removeObject(forKey: "finishedOnboarding")
        #expect(try store.readAppState() == AppState())
        #expect(try store.readEvents().captures.count == events.captures.count)
    }

    // The tour's history plus a school email waiting for review, on a linked card past
    // onboarding, so Recently added opens straight onto its suggested label.
    @Test(.enabled(if: mode == "school"))
    func seedSchoolCapture() async throws {
        let identifier = try alexIdentifier()
        try resetCard(identifier)
        try await Task.sleep(for: .seconds(2))
        let store = try #require(StoreFactory.make() as? KeychainStore)
        try store.removeAll()
        let card = try CNContactStoreGateway().fetchCard(identifier: identifier)
        let link = CardLink(
            contactIdentifier: identifier, containerIdentifier: nil, linkedIdentifiers: [],
            original: card, snapshotAt: .now
        )
        try store.writeAppState(AppState(cardLink: link))
        let school = ContactValue(
            payload: .email("alex.rivera@learn.example.edu"), label: nil, source: .captured, createdAt: .now
        )
        let events = Self.events(now: .now)
        let capture = Capture(host: "courses.example.edu", value: school, date: .now, verdict: .needsReview)
        try store.appendEvents(usage: events.usage, captures: events.captures + [capture])
        UserDefaults.standard.set(true, forKey: "finishedOnboarding")
        // The test host quits right after, sometimes before the default is written out.
        UserDefaults.standard.synchronize()
        #expect(try store.readEvents().captures.last?.value.id == school.id)
    }

    private func alexIdentifier() throws -> String {
        let predicate = CNContact.predicateForContacts(matchingName: "Alex Rivera")
        let keys = [CNContactIdentifierKey as CNKeyDescriptor]
        let matches = try CNContactStore().unifiedContacts(matching: predicate, keysToFetch: keys)
        return try #require(matches.first?.identifier)
    }

    private func resetCard(_ identifier: String) throws {
        let gateway = CNContactStoreGateway()
        let current = try gateway.fetchCard(identifier: identifier)
        let target = current
            .replacing(.email, with: Self.emails)
            .replacing(.phone, with: Self.phones)
            .replacing(.address, with: Self.addresses)
        guard target != current else { return }
        let result = try gateway.save(target, basis: current, scope: .personEdit, transactionAuthor: "prefill-seed")
        #expect(result == .saved)
    }

    // A hand-written history: four sites with their own picks, one saved capture, two
    // waiting for review, and the work email picked on the work portal. The `.example` names
    // are reserved, so they can't be real sites.
    private static func events(now: Date) -> ExtensionEvents {
        func ago(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3_600) }
        func id(_ entry: CardEntry) -> UUID {
            ContactValue(payload: entry.payload, label: entry.label, source: .card, createdAt: now).id
        }
        let usage = [
            UsageEvent(valueID: id(emails[0]), host: "shop.northwind.example", date: ago(50)),
            UsageEvent(valueID: id(addresses[0]), host: "shop.northwind.example", date: ago(50)),
            UsageEvent(valueID: id(phones[0]), host: "shop.northwind.example", date: ago(50)),
            UsageEvent(valueID: id(emails[1]), host: "portal.work.example.org", date: ago(20)),
            UsageEvent(valueID: id(phones[1]), host: "portal.work.example.org", date: ago(20)),
            UsageEvent(valueID: id(emails[2]), host: "fernhill-library.example", date: ago(96)),
            UsageEvent(valueID: id(newsletter), host: "tidepool.example", date: ago(6))
        ]
        let saved = ContactValue(payload: newsletter.payload, label: nil, source: .captured, createdAt: ago(6))
        let phone = ContactValue(
            payload: .phone("+1 (510) 555-0172"), label: nil, source: .captured, createdAt: ago(26)
        )
        let address = ContactValue(
            payload: .address(PostalAddress(
                street: "88 Linden St", city: "Oakland", state: "CA", postalCode: "94607", country: "United States"
            )),
            label: nil, source: .captured, createdAt: ago(70)
        )
        let captures = [
            Capture(host: "bluebird-tickets.example", value: address, date: ago(70), verdict: .needsReview),
            Capture(host: "bluebird-tickets.example", value: phone, date: ago(26), verdict: .needsReview),
            Capture(host: "tidepool.example", value: saved, date: ago(6), verdict: .saved)
        ]
        let pins = [
            PinEvent(host: "portal.work.example.org", kind: .email, valueID: id(emails[1]), date: ago(20))
        ]
        return ExtensionEvents(usage: usage, captures: captures, pins: pins)
    }
}
