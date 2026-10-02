import Foundation
import Testing
@testable import PrefillKit

// Only what the person typed, in a form they submitted, can reach the card on its own.
struct CaptureProvenanceTests: CaptureTesting {
    private let cardEmail = "alex.rivera@example.com"

    @Test func aValueThePageFilledInIsNeverKept() {
        let decisions = decide([field(.email, cardEmail), field(.email, newEmail, userTyped: false)])
        #expect(decisions[1] == .ignore(.untyped))
    }

    @Test func aCardValueThePageFilledInProvesNothing() {
        let decisions = decide([field(.email, cardEmail, userTyped: false), field(.phone, "(925) 555-0101")])
        #expect(decisions[1] == .review(newValue(.phone("(925) 555-0101"))))
    }

    @Test func aNamePageFilledInProvesNothing() {
        let decisions = decide([field(.name, "Alex Rivera", userTyped: false), field(.email, newEmail)])
        #expect(decisions[1] == .review(newValue(.email(newEmail))))
    }

    @Test func aFlushedFormNeverSaves() {
        let decisions = decide([field(.name, "Alex Rivera"), field(.email, cardEmail), field(.email, newEmail)],
                               trigger: .flush)
        #expect(decisions[2] == .review(newValue(.email(newEmail))))
    }

    @Test func aPasswordBoxAndAFirstNameAreNotProof() {
        let email = field(.email, newEmail, autocomplete: "email")
        let decisions = decide([field(.name, "Alex"), email], hasPassword: true)
        #expect(decisions[1] == .review(newValue(.email(newEmail))))
    }

    @Test func aTypedCardValueInTheSameFormIsProof() {
        let decisions = decide([field(.email, cardEmail), field(.phone, "(925) 555-0101", autocomplete: "tel")])
        #expect(decisions[1] == .save(newValue(.phone("(925) 555-0101"))))
    }

    @Test(arguments: [
        (nil, "ccnum"), (nil, "card_no"), (nil, "cvv2"), (nil, "user_pwd"), (nil, "passwd"),
        ("Security code", nil), ("Tax ID", nil), (nil, "accountPhone"), ("Social security", nil)
    ] as [(String?, String?)])
    func aPhoneBoxForSomethingElseIsNeverKept(name: String?, label: String?) {
        let decisions = decide([field(.email, cardEmail), field(.phone, "(510) 555-0134", name: name, label: label)])
        #expect(decisions[1] == .ignore(.sensitive))
    }

    @Test(arguments: ["4222 2222 22222", "3782-822463-10005", "51O5550134", "510555০134"])
    func digitsThatArentAPhoneNumberAreDropped(text: String) {
        #expect(!ValueRules.isPhone(text, autocomplete: "tel"))
    }
}
