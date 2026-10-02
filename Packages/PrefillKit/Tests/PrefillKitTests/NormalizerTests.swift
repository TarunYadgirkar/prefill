import Foundation
import Testing
@testable import PrefillKit

struct NormalizerTests {
    @Test(arguments: [
        ("  Alex.Rivera@Example.COM ", "alex.rivera@example.com"),
        ("alex@work.example.org", "alex@work.example.org"),
        ("\tALEX.SCHOOL@example.edu\n", "alex.school@example.edu")
    ])
    func emailIsTrimmedAndLowercased(raw: String, expected: String) {
        #expect(Normalizer.email(raw) == expected)
    }

    @Test(arguments: [
        ("+1 (510) 555-0134", "+15105550134"),
        ("(415) 555-0199", "+14155550199"),
        ("415.555.0199", "+14155550199"),
        ("1 415 555 0199", "+14155550199"),
        ("+44 20 7946 0958", "+442079460958"),
        ("555-0134", "5550134")
    ])
    func phoneKeepsDigitsWithCountryCode(raw: String, expected: String) {
        #expect(Normalizer.phone(raw, region: "us") == expected)
    }

    @Test(arguments: [
        ("9876543210", "in", "+919876543210"),
        ("+91 98765 43210", "in", "+919876543210"),
        ("+91 98765 43210", "us", "+919876543210"),
        ("020 7946 0958", "gb", "+442079460958"),
        ("(416) 555-0123", "CA", "+14165550123"),
        ("9876543210", "", "9876543210")
    ])
    func aNumberWithoutACountryCodeTakesTheRegionsCode(raw: String, region: String, expected: String) {
        #expect(Normalizer.phone(raw, region: region) == expected)
    }

    @Test func addressKeyIsStreetAndPostalCode() {
        #expect(Normalizer.address(Alex.durant) == "2400 durant ave\n94704")
    }

    @Test(arguments: [
        PostalAddress(
            street: "2400  DURANT Ave ", city: "berkeley", state: "ca", postalCode: " 94704", country: "United  States"
        ),
        PostalAddress(
            street: "2400 Durant Avenue", city: "Berkeley", state: "California", postalCode: "94704", country: "US"
        ),
        PostalAddress(street: "2400 Durant Ave.", city: "", state: "", postalCode: "94704-2211", country: "")
    ])
    func addressSpellingsOfTheSamePlaceShareAKey(address: PostalAddress) {
        #expect(Normalizer.address(address) == Normalizer.address(Alex.durant))
    }

    @Test func unitWordsAndHashMeanTheSame() {
        let spelled = PostalAddress(
            street: "1 Market Street, Suite 300", city: "", state: "", postalCode: "94105", country: ""
        )
        let short = PostalAddress(street: "1 Market St #300", city: "", state: "", postalCode: "94105", country: "")
        #expect(Normalizer.address(spelled) == Normalizer.address(short))
        #expect(Normalizer.address(short) == "1 market st # 300\n94105")
    }

    @Test func differentStreetsOrPostalCodesStayApart() {
        let otherNumber = PostalAddress(
            street: "2402 Durant Ave", city: "Berkeley", state: "CA", postalCode: "94704", country: ""
        )
        let otherZip = PostalAddress(
            street: "2400 Durant Ave", city: "Berkeley", state: "CA", postalCode: "94705", country: ""
        )
        #expect(Normalizer.address(otherNumber) != Normalizer.address(Alex.durant))
        #expect(Normalizer.address(otherZip) != Normalizer.address(Alex.durant))
    }

    @Test func withoutAPostalCodeTheCityStandsIn() {
        let address = PostalAddress(
            street: "1 Market St\n  Suite 300", city: " San  Francisco", state: "", postalCode: "", country: ""
        )
        #expect(Normalizer.address(address) == "1 market st # 300\nsan francisco")
    }

    // Registrable domain = the last two labels, or three when the last two are a known
    // two-part public suffix (co.uk and friends). Deliberately not the full Public Suffix List.
    @Test(arguments: [
        ("example.com", "example.com"),
        ("www.example.com", "example.com"),
        ("Shop.Example.COM.", "example.com"),
        ("accounts.work.example.org", "example.org"),
        ("store.example.co.uk", "example.co.uk"),
        ("www.example.com.au", "example.com.au"),
        ("example.com:8443", "example.com"),
        ("localhost", "localhost"),
        ("127.0.0.1", "127.0.0.1"),
        ("", "")
    ])
    func registrableDomain(host: String, expected: String) {
        #expect(Normalizer.registrableDomain(host) == expected)
    }

    @Test func emailDomainIsRegistrable() {
        #expect(Normalizer.emailDomain("alex@mail.work.example.org") == "example.org")
        #expect(Normalizer.emailDomain("not-an-email") == nil)
    }
}

struct LinkTests {
    @Test(arguments: [
        ("https://GitHub.com/alexrivera/", "github.com/alexrivera"),
        ("github.com/alexrivera", "github.com/alexrivera"),
        ("http://www.linkedin.com/in/alex-rivera?trk=x", "linkedin.com/in/alex-rivera"),
        ("alexrivera.dev", "alexrivera.dev")
    ])
    func linkKeyIsHostAndPath(raw: String, expected: String) {
        #expect(Normalizer.link(raw) == expected)
    }

    @Test(arguments: [
        ("github.com/alexrivera", LinkType.github),
        ("https://www.linkedin.com/in/alex", .linkedin),
        ("https://twitter.com/alex", .x),
        ("x.com/alex", .x),
        ("https://alexrivera.github.io", .website),
        ("https://alexrivera.dev", .website)
    ])
    func typeComesFromTheHost(raw: String, expected: LinkType) {
        #expect(LinkType.of(raw) == expected)
    }

    @Test func onlyWebAddressesCount() {
        #expect(ValueRules.isLink("github.com/alex"))
        #expect(!ValueRules.isLink("alexrivera"))
        #expect(!ValueRules.isLink("javascript:alert(1)"))
        #expect(!ValueRules.isLink("https://github.com/alex - https://alex.dev"))
        #expect(LinkType.cardText("github.com/alex") == "https://github.com/alex")
    }
}

struct LinkCaptureTests: CaptureTesting {
    @Test func aTypedLinkNextToTheOwnEmailIsSavedWithItsType() {
        let decisions = decide([
            field(.email, "alex.rivera@example.com"), field(.link, "github.com/alexrivera/", label: "GitHub/Portfolio:")
        ])
        let saved = newValue(.link("https://github.com/alexrivera/"), label: "GitHub")
        #expect(decisions == [.duplicate(Alex.homeEmail.id), .save(saved)])
    }

    @Test func aRecordStoredBeforeLinksKeepsTheCardsLinksOnRestore() throws {
        let old = try JSONDecoder().decode(CardRecord.self, from: JSONEncoder().encode(Alex.card).dropLinks())
        let github = CardEntry(label: "GitHub", payload: .link("https://github.com/a"))
        let card = Alex.card.replacing(.link, with: [github])
        #expect(CardEditor.target(.restore(old), card: card).links == card.links)
    }
}

private extension Data {
    func dropLinks() throws -> Data {
        var object = try #require(try JSONSerialization.jsonObject(with: self) as? [String: Any])
        object["links"] = nil
        return try JSONSerialization.data(withJSONObject: object)
    }
}
