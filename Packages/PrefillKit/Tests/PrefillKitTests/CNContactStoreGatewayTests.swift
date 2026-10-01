import Contacts
import Testing
@testable import PrefillKit

// Exercises the CNContact <-> CardRecord mapping on in-memory contacts, so no
// Contacts permission is needed. The real store round trip runs in the app on the
// simulator: HostTests/ContactsGatewayHostTests.swift.
struct CNContactStoreGatewayTests {
    private func alexContact() -> CNMutableContact {
        let contact = CNMutableContact()
        contact.givenName = "Alex"
        contact.familyName = "Rivera"
        contact.emailAddresses = [
            CNLabeledValue(label: CNLabelHome, value: "alex.rivera@example.com"),
            CNLabeledValue(label: CNLabelWork, value: "alex@work.example.org"),
            CNLabeledValue(label: nil, value: "alex.school@example.edu")
        ]
        contact.phoneNumbers = [
            CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: "+1 (510) 555-0134")),
            CNLabeledValue(label: CNLabelWork, value: CNPhoneNumber(stringValue: "+1 (415) 555-0199"))
        ]
        contact.postalAddresses = [
            CNLabeledValue(label: CNLabelHome, value: postal(Alex.durant, iso: "us")),
            CNLabeledValue(label: CNLabelWork, value: postal(Alex.market, iso: "us"))
        ]
        return contact
    }

    private func postal(_ address: PostalAddress, iso: String) -> CNPostalAddress {
        let postal = CNMutablePostalAddress()
        postal.street = address.street
        postal.city = address.city
        postal.state = address.state
        postal.postalCode = address.postalCode
        postal.country = address.country
        postal.isoCountryCode = iso
        return postal
    }

    @Test func readsTheCardIntoARecord() {
        let record = CNCardMapping.record(from: alexContact(), identifier: "alex-card")
        #expect(record == Alex.card)
    }

    @Test func writesFreshLabeledValuesInTargetOrder() {
        let contact = alexContact()
        let oldIDs = Set(contact.emailAddresses.map(\.identifier))
        let reordered = [Alex.schoolEmail, Alex.homeEmail, Alex.workEmail].map(\.entry)
        let target = Alex.card.replacing(.email, with: reordered)
        CNCardMapping.apply(target, to: contact)
        #expect(contact.emailAddresses.map { $0.value as String } == [
            "alex.school@example.edu", "alex.rivera@example.com", "alex@work.example.org"
        ])
        #expect(contact.emailAddresses.map(\.label) == [nil, CNLabelHome, CNLabelWork])
        #expect(oldIDs.isDisjoint(with: contact.emailAddresses.map(\.identifier)))
        #expect(CNCardMapping.record(from: contact, identifier: "alex-card") == target)
    }

    @Test func keepsFieldsTheRecordDoesNotModel() {
        let contact = alexContact()
        let target = Alex.card.replacing(.address, with: [Alex.workAddress.entry, Alex.homeAddress.entry])
        CNCardMapping.apply(target, to: contact)
        #expect(contact.postalAddresses.map(\.value.isoCountryCode) == ["us", "us"])
        #expect(contact.postalAddresses.first?.value.street == Alex.market.street)
    }

    @Test func buildsNewValuesForAdditions() {
        let contact = alexContact()
        let phone = CardEntry(label: CNLabelOther, payload: .phone("(925) 555-0101"))
        let address = CardEntry(label: nil, payload: .address(Alex.market))
        let target = Alex.card
            .replacing(.phone, with: Alex.card.phones + [phone])
            .replacing(.address, with: [address])
        CNCardMapping.apply(target, to: contact)
        #expect(contact.phoneNumbers.last?.value.stringValue == "(925) 555-0101")
        #expect(contact.phoneNumbers.last?.label == CNLabelOther)
        #expect(contact.postalAddresses.count == 1)
        #expect(contact.postalAddresses.first?.value.city == "San Francisco")
    }

    @Test func keepsEachDuplicateOnce() {
        let contact = alexContact()
        contact.emailAddresses += [CNLabeledValue(label: nil, value: "Alex.Rivera@example.com")]
        let record = CNCardMapping.record(from: contact, identifier: "alex-card")
        CNCardMapping.apply(record, to: contact)
        #expect(contact.emailAddresses.map { $0.value as String }.last == "Alex.Rivera@example.com")
        #expect(contact.emailAddresses.count == 4)
    }

    @Test(arguments: [
        (CNError.Code.authorizationDenied, CardWriteFailure.noAccess),
        (.recordDoesNotExist, .cardMissing),
        (.recordNotWritable, .notWritable),
        (.parentContainerNotWritable, .notWritable),
        (.policyViolation, .notWritable),
        (.communicationError, .other)
    ])
    func mapsContactsErrors(code: CNError.Code, expected: CardWriteFailure) {
        #expect(CNCardMapping.failure(for: CNError(code)) == expected)
    }

    // A prompt from the Safari extension can deny the app's Contacts access for good
    // (REPORT.md, Spike results), so neither PrefillKit nor the extension may ask.
    @Test func nothingAsksForContactsAccess() throws {
        let root = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let folders = ["Packages/PrefillKit/Sources", "Extension"].map { root.appending(path: $0) }
        let sources = folders.flatMap { folder in
            (FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?.allObjects ?? [])
                .compactMap { $0 as? URL }
                .filter { $0.pathExtension == "swift" }
        }
        #expect(sources.count > 10)
        for source in sources {
            let text = try String(contentsOf: source, encoding: .utf8)
            #expect(!text.contains("requestAccess("), "\(source.lastPathComponent) asks for Contacts access")
        }
    }
}
