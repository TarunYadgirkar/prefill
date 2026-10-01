import Foundation
@testable import PrefillKit

// Mirrors testbed/alex-rivera.vcf, the card set as My Info on the dev simulator.
enum Alex {
    static let workLabel = "_$!<Work>!$_"
    static let homeLabel = "_$!<Home>!$_"
    static let mobileLabel = "_$!<Mobile>!$_"
    static let created = Date(timeIntervalSince1970: 1_790_000_000)

    static let homeEmail = value(.email("alex.rivera@example.com"), label: homeLabel)
    static let workEmail = value(.email("alex@work.example.org"), label: workLabel)
    static let schoolEmail = value(.email("alex.school@example.edu"), label: nil)
    static let mobile = value(.phone("+1 (510) 555-0134"), label: mobileLabel)
    static let workPhone = value(.phone("+1 (415) 555-0199"), label: workLabel)
    static let homeAddress = value(.address(durant), label: homeLabel)
    static let workAddress = value(.address(market), label: workLabel)

    static let durant = PostalAddress(
        street: "2400 Durant Ave", city: "Berkeley", state: "CA", postalCode: "94704", country: "United States"
    )
    static let market = PostalAddress(
        street: "1 Market St Suite 300", city: "San Francisco", state: "CA", postalCode: "94105",
        country: "United States"
    )

    static let emails = [homeEmail, workEmail, schoolEmail]
    static let allValues = emails + [mobile, workPhone, homeAddress, workAddress]

    static let card = CardRecord(
        identifier: "alex-card",
        givenName: "Alex",
        familyName: "Rivera",
        emails: emails.map(\.entry),
        phones: [mobile.entry, workPhone.entry],
        addresses: [homeAddress.entry, workAddress.entry]
    )

    static func value(_ payload: ContactPayload, label: String?, source: ValueSource = .card) -> ContactValue {
        ContactValue(payload: payload, label: label, source: source, createdAt: created)
    }
}

extension ContactValue {
    var entry: CardEntry { CardEntry(label: label, payload: payload) }
}

extension Date {
    static let testNow = Date(timeIntervalSince1970: 1_791_000_000)

    static func daysAgo(_ days: Double) -> Date {
        testNow.addingTimeInterval(-days * 86_400)
    }
}
