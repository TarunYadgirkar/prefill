import Foundation
import Testing
@testable import PrefillKit

protocol CaptureTesting {}

extension CaptureTesting {
    var newEmail: String { "alex.new@example.net" }

    func field(
        _ kind: FieldKind, _ value: String? = nil, autocomplete: String? = nil,
        name: String? = nil, label: String? = nil, section: SectionHint? = nil, address: PostalAddress? = nil,
        userTyped: Bool = true
    ) -> CapturedField {
        CapturedField(
            kind: kind, value: value, address: address, autocomplete: autocomplete,
            name: name, label: label, section: section, userTyped: userTyped
        )
    }

    func decide(
        _ fields: [CapturedField], hasPassword: Bool = false, trigger: CaptureTrigger = .submit,
        filter: CaptureFilter = CaptureFilter(card: Alex.card, settings: Settings())
    ) -> [CaptureDecision] {
        let request = CaptureRequest(
            host: "shop.example.net", fields: fields, hasPassword: hasPassword, trigger: trigger
        )
        return filter.evaluate(request, at: .testNow)
    }

    func newValue(_ payload: ContactPayload, label: String? = nil) -> ContactValue {
        ContactValue(payload: payload, label: label, source: .captured, createdAt: .testNow)
    }
}

// Whose details a form holds: the card's own name and values against someone else's.
struct CaptureOwnershipTests: CaptureTesting {
    @Test func aTaggedPhoneNextToSomeoneElsesNameNeedsReview() {
        let decisions = decide([field(.name, "Sam Lee"), field(.phone, "(925) 555-0101", autocomplete: "shipping tel")])
        #expect(decisions[1] == .review(newValue(.phone("(925) 555-0101"))))
    }

    @Test(arguments: [
        CapturedField(
            kind: .email, value: "alex.new@example.net", address: nil, autocomplete: nil,
            name: "email", label: nil, section: nil, userTyped: true
        ),
        CapturedField(
            kind: .phone, value: "(925) 555-0101", address: nil, autocomplete: nil,
            name: "phone", label: nil, section: nil, userTyped: true
        )
    ])
    func aNewValueNextToSomeoneElsesNameNeedsReview(value: CapturedField) {
        let decisions = decide([field(.name, "Sam Lee"), value])
        #expect(decisions[1] == .review(newValue(value.kind == .email ? .email(newEmail) : .phone("(925) 555-0101"))))
    }

    @Test func aGiftCheckoutSendsTheRecipientsDetailsToReview() {
        let bob = PostalAddress(street: "9 Elm St", city: "Austin", state: "TX", postalCode: "78701", country: "")
        let decisions = decide([
            field(.email, "alex.rivera@example.com", autocomplete: "email"),
            field(.name, "Bob Smith", autocomplete: "shipping name", section: .shipping),
            field(.address, section: .shipping, address: bob),
            field(.phone, "512-555-0100", autocomplete: "shipping tel", section: .shipping)
        ])
        #expect(decisions == [
            .duplicate(Alex.homeEmail.id), .ignore(.notContact),
            .review(newValue(.address(bob))), .review(newValue(.phone("512-555-0100")))
        ])
    }

    @Test func theBuyersOwnSectionIsStillSavedInAGiftCheckout() {
        let bob = PostalAddress(street: "9 Elm St", city: "Austin", state: "TX", postalCode: "78701", country: "")
        let office = PostalAddress(street: "77 Main St", city: "Oakland", state: "CA", postalCode: "94607", country: "")
        let decisions = decide([
            field(.name, "Alex Rivera", section: .billing),
            field(.address, section: .billing, address: office),
            field(.name, "Bob Smith", section: .shipping),
            field(.address, section: .shipping, address: bob)
        ])
        #expect(decisions[1] == .save(newValue(.address(office))))
        #expect(decisions[3] == .review(newValue(.address(bob))))
    }

    @Test func yourEmailNextToAGiftRecipientsNameIsSavedWhenYourNameIsThereToo() {
        let decisions = decide([
            field(.name, "Rivera, Alex"),
            field(.name, "Bob Smith", section: .shipping),
            field(.email, newEmail, autocomplete: "email")
        ])
        #expect(decisions[2] == .save(newValue(.email(newEmail))))
    }

    @Test func aSplitNameMatchesTheCard() {
        let decisions = decide([field(.name, "Alex"), field(.name, "Rivera"), field(.email, newEmail)])
        #expect(decisions[2] == .save(newValue(.email(newEmail))))
    }

    @Test func withNoNameOnTheCardNameFieldsDecideNothing() {
        let nameless = CardRecord(
            identifier: "x", givenName: "", familyName: "", emails: Alex.card.emails, phones: [], addresses: []
        )
        let filter = CaptureFilter(card: nameless, settings: Settings())
        let decisions = decide([
            field(.email, "alex.rivera@example.com"), field(.name, "Sam Lee"), field(.phone, "(925) 555-0101")
        ], filter: filter)
        #expect(decisions[2] == .save(newValue(.phone("(925) 555-0101"))))
    }

    @Test func aValueThePersonRejectedIsNotSavedAgain() {
        let rejected = newValue(.email(newEmail))
        let filter = CaptureFilter(card: Alex.card, settings: Settings(), rejected: [rejected.id])
        let decisions = decide([field(.name, "Alex Rivera"), field(.email, newEmail.uppercased())], filter: filter)
        #expect(decisions[1] == .ignore(.rejected))
    }

    @Test(arguments: [
        PostalAddress(street: "2400 Durant Ave", city: "Berkeley", state: "CA", postalCode: "94704", country: ""),
        PostalAddress(street: "2400 Durant Ave", city: "Berkeley", state: "CA", postalCode: "94704", country: "US"),
        PostalAddress(
            street: "2400 Durant Avenue", city: "Berkeley", state: "California", postalCode: "94704-1234",
            country: "USA"
        ),
        PostalAddress(street: "2400 durant ave.", city: "", state: "", postalCode: "94704", country: "")
    ])
    func yourOwnAddressAsAFormSpellsItIsADuplicate(address: PostalAddress) {
        let decisions = decide([field(.name, "Alex Rivera"), field(.address, address: address)])
        #expect(decisions[1] == .duplicate(Alex.homeAddress.id))
    }
}
