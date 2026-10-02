import Foundation
import Testing
@testable import PrefillKit

struct CaptureFilterTests: CaptureTesting {
    @Test func nameFieldsAreContextNotValues() {
        #expect(decide([field(.name, "Alex Rivera")]) == [.ignore(.notContact)])
    }

    struct Words: Sendable {
        var autocomplete: String?
        var name: String?
        var label: String?
    }

    @Test(arguments: [
        Words(name: "user_password"),
        Words(autocomplete: "current-password"),
        Words(autocomplete: "one-time-code"),
        Words(autocomplete: "cc-number"),
        Words(name: "otp"),
        Words(label: "Card number")
    ])
    func sensitiveFieldsAreNeverKept(words: Words) {
        let phone = field(.phone, "5105550188", autocomplete: words.autocomplete, name: words.name, label: words.label)
        let decisions = decide([phone])
        #expect(decisions == [.ignore(.sensitive)])
    }

    @Test(arguments: [
        (nil, "recipientEmail"),
        (nil, "friend_email"),
        ("Gift message email", nil),
        (nil, "invite[]"),
        ("Send to", nil),
        ("Invitee's email", nil),
        (nil, "friendemail"),
        ("Email of the person you're inviting", nil),
        (nil, "invitedEmail"),
        ("Invited by", nil),
        (nil, "to_email"),
        (nil, "toEmail"),
        ("Referral email", nil)
    ] as [(String?, String?)])
    func fieldsForSomeoneElseAreIgnored(label: String?, name: String?) {
        let decisions = decide([field(.email, newEmail, name: name, label: label)], hasPassword: true)
        #expect(decisions == [.ignore(.someoneElse)])
    }

    @Test(arguments: [
        (nil, "customer_email"),
        (nil, "shipToEmail"),
        (nil, "bill_to_email"),
        ("Ship to", nil),
        ("Bill to", nil),
        ("Email to receive your receipt", nil),
        ("Send my receipt to this email", nil)
    ] as [(String?, String?)])
    func yourOwnFieldsThatSayToAreKept(label: String?, name: String?) {
        let email = field(.email, newEmail, autocomplete: "email", name: name, label: label)
        let decisions = decide([field(.name, "Alex Rivera"), email], hasPassword: true)
        #expect(decisions[1] == .save(newValue(.email(newEmail))))
    }

    @Test(arguments: ["shipToAddress1", "shipTo.street"])
    func aShipToAddressNextToYourEmailIsSaved(name: String) {
        let gym = PostalAddress(
            street: "50 Shattuck Sq", city: "Berkeley", state: "CA", postalCode: "94704", country: ""
        )
        let decisions = decide([field(.email, "alex.rivera@example.com"), field(.address, name: name, address: gym)])
        #expect(decisions[1] == .save(newValue(.address(gym))))
    }

    @Test func aPhoneLabeledToReachYouIsKept() {
        let phone = field(.phone, "(925) 555-0101", autocomplete: "tel", label: "Phone number to reach you")
        let decisions = decide([field(.name, "Alex Rivera"), phone])
        #expect(decisions[1] == .save(newValue(.phone("(925) 555-0101"))))
    }

    @Test(arguments: [
        (FieldKind.email, "alex"),
        (.email, "alex@localhost"),
        (.email, ""),
        (.phone, "123")
    ])
    func malformedValuesAreIgnored(kind: FieldKind, value: String) {
        #expect(decide([field(kind, value)]) == [.ignore(.invalid)])
    }

    @Test func aValueAlreadyOnTheCardIsADuplicate() {
        let decisions = decide([field(.email, " Alex@Work.Example.org")])
        #expect(decisions == [.duplicate(Alex.workEmail.id)])
    }

    @Test func aRepeatedFieldInTheSameFormIsADuplicate() {
        let decisions = decide([
            field(.email, newEmail, autocomplete: "email"),
            field(.email, newEmail.uppercased(), name: "confirm_email")
        ], hasPassword: true)
        let value = newValue(.email(newEmail))
        #expect(decisions == [.review(value), .duplicate(value.id)])
    }

    @Test func aNewValueNextToOneOnTheCardIsSaved() {
        let decisions = decide([field(.email, "alex@work.example.org"), field(.phone, "(925) 555-0101")])
        #expect(decisions[1] == .save(newValue(.phone("(925) 555-0101"))))
    }

    @Test func aNewValueNextToYourNameIsSaved() {
        let decisions = decide([field(.name, " alex  rivera"), field(.email, newEmail)])
        #expect(decisions[1] == .save(newValue(.email(newEmail))))
    }

    @Test func aTaggedEmailInASignUpFormWaitsForReview() {
        let decisions = decide([field(.email, newEmail, autocomplete: "username email")], hasPassword: true)
        #expect(decisions == [.review(newValue(.email(newEmail)))])
    }

    @Test func aTaggedPhoneInACheckoutWithYourNameIsSaved() {
        let phone = field(.phone, "(925) 555-0101", autocomplete: "shipping tel")
        let decisions = decide([field(.name, "Alex Rivera"), phone])
        #expect(decisions[1] == .save(newValue(.phone("(925) 555-0101"))))
    }

    @Test(arguments: ["tel-area-code", "tel-local", "tel-local-prefix", "tel-country-code", "tel-extension"])
    func partsOfASplitPhoneAreIgnored(token: String) {
        let decisions = decide([field(.name, "Alex Rivera"), field(.phone, "555-0177", autocomplete: token)])
        #expect(decisions[1] == .ignore(.partial))
    }

    @Test func aNationalPhoneIsAWholeNumber() {
        let phone = field(.phone, "(925) 555-0101", autocomplete: "tel-national")
        let decisions = decide([field(.name, "Alex Rivera"), phone])
        #expect(decisions[1] == .save(newValue(.phone("(925) 555-0101"))))
    }

    @Test func anUntaggedEmailInASignUpFormNeedsReview() {
        let decisions = decide([field(.email, newEmail, name: "newsletter")], hasPassword: true)
        #expect(decisions == [.review(newValue(.email(newEmail)))])
    }

    @Test func aLoneTaggedEmailNeedsReview() {
        let decisions = decide([field(.email, newEmail, autocomplete: "email")])
        #expect(decisions == [.review(newValue(.email(newEmail)))])
    }

    @Test func anAddressNextToYourEmailIsSaved() {
        let gym = PostalAddress(
            street: "50 Shattuck Sq", city: "Berkeley", state: "CA", postalCode: "94704", country: ""
        )
        let decisions = decide([field(.email, "alex.rivera@example.com"), field(.address, address: gym)])
        #expect(decisions[1] == .save(newValue(.address(gym))))
    }

    @Test func withSaveNewInfoOffEverythingNewNeedsReview() {
        let off = CaptureFilter(card: Alex.card, settings: Settings(saveNewInfo: false))
        let decisions = decide([field(.email, newEmail, autocomplete: "email")], hasPassword: true, filter: off)
        #expect(decisions == [.review(newValue(.email(newEmail)))])
    }

    @Test func theSectionBecomesTheLabel() {
        let decisions = decide([field(.email, newEmail, autocomplete: "work email", section: .work)], hasPassword: true)
        #expect(decisions == [.review(newValue(.email(newEmail), label: "_$!<Work>!$_"))])
    }

    @Test func capturesKeepEverythingButIgnoredFields() {
        let value = newValue(.email(newEmail))
        let decisions: [CaptureDecision] = [
            .save(value), .review(value), .duplicate(Alex.workEmail.id), .ignore(.sensitive)
        ]
        let captures = CaptureFilter.captures(from: decisions, host: "Shop.Example.net", at: .testNow)
        #expect(captures.map(\.verdict) == [.saved, .needsReview])
        #expect(captures.allSatisfy { $0.host == "example.net" })
    }

    @Test func usageCoversSavedAndDuplicateValues() {
        let value = newValue(.email(newEmail))
        let decisions: [CaptureDecision] = [.save(value), .review(value), .duplicate(Alex.workEmail.id)]
        let usage = CaptureFilter.usage(from: decisions, host: "shop.example.net", at: .testNow)
        #expect(usage.map(\.valueID) == [value.id, Alex.workEmail.id])
        #expect(usage.allSatisfy { $0.host == "example.net" })
    }
}
