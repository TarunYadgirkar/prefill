import Foundation
import Testing
@testable import PrefillKit

// Values a page can put in a field that aren't an email, a phone number or an address.
struct CaptureValueTests: CaptureTesting {
    @Test(arguments: ["alex.new@example.net", "a+tag@mail.example.co.uk", "álex@exämple.de"])
    func plainEmailsAreKept(email: String) {
        #expect(ValueRules.isEmail(email))
    }

    @Test(arguments: [
        "a b@example.net", "alex@example", "alex@.example.net", "alex@example..net", "alex@-example.net",
        "alex@example.123", "@example.net", "alex@@example.net", "alex@exa_mple.net", "alex@example.net\u{0}",
        String(repeating: "a", count: 65) + "@example.net"
    ])
    func malformedEmailsAreDropped(email: String) {
        #expect(!ValueRules.isEmail(email))
    }

    @Test(arguments: [
        ("+1 (510) 555-0134", nil), ("510.555.0134", nil), ("5105550134", nil), ("+44 20 7946 0958", nil),
        ("510-555-0134 x12", nil), ("5550134", "tel"), ("+86 138 0013 8000", nil)
    ] as [(String, String?)])
    func phoneNumbersAreKept(phone: String, autocomplete: String?) {
        #expect(ValueRules.isPhone(phone, autocomplete: autocomplete))
    }

    @Test(arguments: [
        "Call 5551234567 now: https://evil.example/pay", "5105550134 then press 2", "٥١٠٥٥٥٠١٣٤", "55½1234567",
        "4111111111111111", "4111 1111 1111 1111", "378282246310005", "12345678", "1234567", "123456",
        "+1 510 555 0134 0000 0000"
    ])
    func whatIsNotAPhoneNumberIsDropped(text: String) {
        #expect(!ValueRules.isPhone(text, autocomplete: nil))
    }

    @Test(arguments: [
        PostalAddress(street: "Visit https://evil.example", city: "", state: "", postalCode: "", country: ""),
        PostalAddress(street: "2400 Durant Ave", city: "www.evil.example", state: "", postalCode: "", country: ""),
        PostalAddress(street: "2400 Durant\u{7} Ave", city: "", state: "", postalCode: "", country: ""),
        PostalAddress(street: String(repeating: "a", count: 401), city: "", state: "", postalCode: "", country: ""),
        PostalAddress(street: "", city: "Berkeley", state: "", postalCode: "94704", country: "")
    ])
    func addressesThatArentAddressesAreDropped(address: PostalAddress) {
        #expect(!ValueRules.isAddress(address))
    }

    @Test func aTwoLineStreetIsAnAddress() {
        let address = PostalAddress(
            street: "2400 Durant Ave\nApt 4", city: "Berkeley", state: "CA", postalCode: "94704", country: ""
        )
        #expect(ValueRules.isAddress(address))
    }

    @Test func aCardNumberInATelBoxIsNeverSavedEvenNextToYourEmail() {
        let decisions = decide([
            field(.email, "alex.rivera@example.com", autocomplete: "email"),
            field(.phone, "4111111111111111")
        ], hasPassword: true)
        #expect(decisions[1] == .ignore(.invalid))
    }

    @Test(arguments: [
        (nil, "Account number"), (nil, "Routing number"), (nil, "Enter the code we texted you"), (nil, "PIN"),
        ("dob", nil), ("bank_account", nil)
    ] as [(String?, String?)])
    func aPhoneBoxThatAsksForSomethingElseIsSensitive(name: String?, label: String?) {
        let decisions = decide([field(.phone, "(510) 555-0134", name: name, label: label)])
        #expect(decisions == [.ignore(.sensitive)])
    }

    @Test func aZipCodeLabelIsNotSensitiveForAnAddress() {
        let address = field(.address, label: "Street, ZIP Code", address: Alex.market)
        #expect(decide([address]) == [.duplicate(Alex.workAddress.id)])
    }
}
