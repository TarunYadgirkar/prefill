import Testing
@testable import PrefillKit

struct PublicSuffixTests {
    @Test(arguments: [
        ("shop.example.net", "example.net"),
        ("bank.com.ar", "bank.com.ar"),
        ("www.bank.com.ar", "bank.com.ar"),
        ("evil.co.id", "evil.co.id"),
        ("checkout.shop.co.uk", "shop.co.uk"),
        ("alice.github.io", "alice.github.io"),
        ("docs.alice.github.io", "alice.github.io"),
        ("a.vercel.app", "a.vercel.app"),
        ("bucket.s3.amazonaws.com", "bucket.s3.amazonaws.com"),
        ("github.io", "github.io"),
        ("[::1]", "[::1]"),
        ("[2001:db8::1]:8443", "[2001:db8::1]"),
        ("192.168.1.10", "192.168.1.10"),
        ("localhost", "localhost")
    ])
    func registrableDomain(host: String, expected: String) {
        #expect(Normalizer.registrableDomain(host) == expected)
    }

    @Test func sitesUnderOneHostingServiceDontShareHistory() {
        #expect(Normalizer.registrableDomain("a.vercel.app") != Normalizer.registrableDomain("b.vercel.app"))
        #expect(Normalizer.registrableDomain("evil.com.ar") != Normalizer.registrableDomain("bank.com.ar"))
    }
}
