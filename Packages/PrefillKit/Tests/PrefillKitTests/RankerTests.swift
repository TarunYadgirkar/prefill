import Foundation
import Testing
@testable import PrefillKit

struct RankerTests {
    private let site = "shop.example.net"

    private func rank(
        _ values: [ContactValue] = Alex.emails,
        usage: [UsageEvent] = [],
        pins: [SitePin] = [],
        host: String? = "shop.example.net",
        hint: SectionHint? = nil,
        matchEachSite: Bool = true,
        siteKind: SiteKind = .unknown,
        focusLabel: String? = nil
    ) -> [ContactValue] {
        let context = RankingContext(
            host: host, hint: hint, now: .testNow, matchEachSite: matchEachSite,
            siteKind: siteKind, focusLabel: focusLabel
        )
        return Ranker.rank(values, usage: usage, pins: pins, context: context)
    }

    private func use(_ value: ContactValue, on host: String, daysAgo: Double) -> UsageEvent {
        UsageEvent(valueID: value.id, host: Normalizer.registrableDomain(host), date: .daysAgo(daysAgo))
    }

    @Test func withNoSignalsTheManualOrderStands() {
        #expect(rank() == Alex.emails)
    }

    @Test func returnsEveryValueExactlyOnce() {
        let ranked = rank(usage: [use(Alex.schoolEmail, on: site, daysAgo: 1)], hint: .work)
        #expect(Set(ranked) == Set(Alex.emails))
        #expect(ranked.count == Alex.emails.count)
    }

    @Test func aSitePinComesFirst() {
        let pin = SitePin(host: "example.net", kind: .email, valueID: Alex.schoolEmail.id)
        #expect(rank(pins: [pin]).first == Alex.schoolEmail)
    }

    @Test func aPinBeatsMoreRecentUseOnTheSameSite() {
        let pin = SitePin(host: "example.net", kind: .email, valueID: Alex.schoolEmail.id)
        let ranked = rank(usage: [use(Alex.workEmail, on: site, daysAgo: 0)], pins: [pin])
        #expect(ranked.prefix(2) == [Alex.schoolEmail, Alex.workEmail])
    }

    @Test func pinsForOtherSitesOrKindsAreIgnored() {
        let otherSite = SitePin(host: "example.org", kind: .email, valueID: Alex.schoolEmail.id)
        let otherKind = SitePin(host: "example.net", kind: .phone, valueID: Alex.schoolEmail.id)
        #expect(rank(pins: [otherSite, otherKind]) == Alex.emails)
    }

    @Test func theValueUsedMostRecentlyOnThisSiteComesNext() {
        let usage = [
            use(Alex.workEmail, on: site, daysAgo: 30),
            use(Alex.schoolEmail, on: site, daysAgo: 2)
        ]
        #expect(rank(usage: usage) == [Alex.schoolEmail, Alex.workEmail, Alex.homeEmail])
    }

    @Test func subdomainsShareTheirSitesHistory() {
        let usage = [use(Alex.schoolEmail, on: "accounts.example.net", daysAgo: 5)]
        #expect(rank(usage: usage).first == Alex.schoolEmail)
    }

    @Test func useOnThisSiteBeatsTheSectionHint() {
        let ranked = rank(usage: [use(Alex.schoolEmail, on: site, daysAgo: 60)], hint: .work)
        #expect(ranked.prefix(2) == [Alex.schoolEmail, Alex.workEmail])
    }

    @Test func aWorkHintLiftsTheWorkLabeledValue() {
        #expect(rank(hint: .work).first == Alex.workEmail)
    }

    // A "work-domain" email is one at the same registrable domain as an email the card
    // labels work, so an unlabeled second work address still counts.
    @Test func aWorkHintAlsoLiftsOtherEmailsAtTheWorkDomain() {
        let other = Alex.value(.email("a.rivera@team.example.org"), label: nil)
        let ranked = rank(Alex.emails + [other], hint: .work)
        #expect(ranked.prefix(2) == [Alex.workEmail, other])
    }

    @Test func homeHintLiftsHomeLabeledValue() {
        let addresses = [Alex.workAddress, Alex.homeAddress]
        #expect(rank(addresses, hint: .home).first == Alex.homeAddress)
    }

    @Test(arguments: [SectionHint.shipping, .billing])
    func shippingAndBillingPreferTheHomeAddress(hint: SectionHint) {
        let addresses = [Alex.workAddress, Alex.homeAddress]
        #expect(rank(addresses, hint: hint).first == Alex.homeAddress)
    }

    @Test func aCustomLabelMatchingTheHintCounts() {
        let gift = Alex.value(.address(Alex.market), label: "Shipping")
        #expect(rank([Alex.homeAddress, gift], hint: .shipping).first == gift)
    }

    // Global order: manual position (1 for the top value down to 1/n for the last) plus
    // half of a 14-day half-life recency score for the last use on any site.
    @Test func recentUseElsewhereLiftsAValueOneStep() {
        let ranked = rank(usage: [use(Alex.schoolEmail, on: "example.org", daysAgo: 1)])
        #expect(ranked == [Alex.homeEmail, Alex.schoolEmail, Alex.workEmail])
    }

    @Test func recentUseElsewhereCanOvertakeTheTopValueWhenItIsAlsoNearTheTop() {
        let ranked = rank(usage: [use(Alex.workEmail, on: "example.org", daysAgo: 0)])
        #expect(ranked.first == Alex.workEmail)
    }

    @Test func oldUseElsewhereBarelyMatters() {
        let ranked = rank(usage: [use(Alex.schoolEmail, on: "example.org", daysAgo: 120)])
        #expect(ranked == Alex.emails)
    }

    @Test func turningOffMatchEachSiteIgnoresPinsHostUseAndHints() {
        let pin = SitePin(host: "example.net", kind: .email, valueID: Alex.schoolEmail.id)
        let usage = [use(Alex.schoolEmail, on: site, daysAgo: 90)]
        #expect(rank(usage: usage, pins: [pin], hint: .work, matchEachSite: false) == Alex.emails)
    }

    @Test func withoutAHostOnlyTheGlobalOrderApplies() {
        let pin = SitePin(host: "example.net", kind: .email, valueID: Alex.schoolEmail.id)
        #expect(rank(pins: [pin], host: nil) == Alex.emails)
    }

    @Test func tiesFallBackToManualOrder() {
        let usage = [
            use(Alex.schoolEmail, on: site, daysAgo: 3),
            use(Alex.workEmail, on: site, daysAgo: 3)
        ]
        #expect(rank(usage: usage) == [Alex.workEmail, Alex.schoolEmail, Alex.homeEmail])
        #expect(rank(usage: usage) == rank(usage: usage.reversed()))
    }

    @Test func aSchoolSiteLiftsTheSchoolValueEvenUnlabeled() {
        #expect(rank(siteKind: .school).first == Alex.schoolEmail)
    }

    @Test func theSectionHintBeatsTheSiteKind() {
        #expect(rank(hint: .work, siteKind: .school).prefix(2) == [Alex.workEmail, Alex.schoolEmail])
    }

    @Test func useOnThisSiteBeatsTheSiteKind() {
        let ranked = rank(usage: [use(Alex.homeEmail, on: site, daysAgo: 60)], siteKind: .school)
        #expect(ranked.prefix(2) == [Alex.homeEmail, Alex.schoolEmail])
    }

    @Test func theSiteKindBeatsTheFocusLabel() {
        #expect(rank(siteKind: .school, focusLabel: "work") == [Alex.schoolEmail, Alex.workEmail, Alex.homeEmail])
    }

    @Test func aFocusLabelLiftsItsValueEvenWithoutAHost() {
        #expect(rank(host: nil, focusLabel: "work").first == Alex.workEmail)
        #expect(rank(matchEachSite: false, focusLabel: "work").first == Alex.workEmail)
    }

    @Test func aPinBeatsTheFocusLabel() {
        let pin = SitePin(host: "example.net", kind: .email, valueID: Alex.schoolEmail.id)
        #expect(rank(pins: [pin], focusLabel: "work").first == Alex.schoolEmail)
    }

    // Recent use lifts a value the card has by half a step, a captured one by a fifth.
    @Test func aCapturedValueGetsASmallerRecencyBoost() {
        let captured = Alex.value(.email("alex.news@example.com"), label: nil, source: .captured)
        let emails = [Alex.homeEmail, Alex.workEmail, captured]
        let usage = [use(captured, on: "example.org", daysAgo: 0)]
        #expect(rank(emails, usage: usage) == emails)
        let fromCard = Alex.value(.email("alex.news@example.com"), label: nil)
        #expect(rank([Alex.homeEmail, Alex.workEmail, fromCard], usage: usage)[1] == fromCard)
    }
}
