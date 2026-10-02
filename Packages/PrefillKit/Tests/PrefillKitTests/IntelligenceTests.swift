import Foundation
import Testing
@testable import PrefillKit

struct SiteSenseTests {
    @Test(arguments: [
        ("bcourses.berkeley.edu", SiteKind.school), ("www.ox.ac.uk", .school), ("lms.unimelb.edu.au", .school),
        ("www.irs.gov", .government), ("www.gov.uk", .government), ("portal.work.example.org", .work),
        ("www.target.com", .shopping), ("news.ycombinator.com", .unknown), ("edu.example.com", .unknown)
    ])
    func hostRules(host: String, kind: SiteKind) {
        #expect(SiteSense.rules(host: host, emailDomains: SiteSense.workDomains(Alex.emails)) == kind)
    }

    @Test func freemailAndHomeDomainsNeverMakeASiteWork() {
        let gmail = Alex.value(.email("alex.rivera99@gmail.com"), label: nil)
        let domains = SiteSense.workDomains(Alex.emails + [gmail])
        #expect(!domains.contains("gmail.com"))
        #expect(!domains.contains("example.com"))
    }

    @Test(arguments: [
        ("alex.r@berkeley.edu", SuggestedLabel.school, true), ("a.rivera@acme-robotics.com", .work, true),
        ("alex.r.shops@gmail.com", .home, false)
    ])
    func emailLabelRules(address: String, label: SuggestedLabel, isSettled: Bool) {
        let guess = LabelRules.suggest(Alex.value(.email(address), label: nil), host: "target.com")
        #expect(guess == LabelGuess(label: label, isSettled: isSettled))
    }

    @Test func phonesTakeTheirLabelFromTheSite() {
        let guess = LabelRules.suggest(Alex.mobile, host: "canvas.stanford.edu")
        #expect(guess.label == .school)
    }

    // Settled rules never reach the model, so this holds with Apple Intelligence on or off.
    @Test func settledRulesAnswerWithoutTheModel() async {
        let school = Alex.value(.email("alex.r@berkeley.edu"), label: nil)
        let label = await Intelligence().labelValue(school, host: "calcentral.berkeley.edu", emailDomains: [])
        #expect(label == Insight(.school, source: .rules))
        let site = await Intelligence().siteKind(host: "irs.gov", emailDomains: [])
        #expect(site == Insight(.government, source: .rules))
    }
}

struct InsightCacheTests {
    @Test func stateStoredBeforeSiteKindsStillReads() throws {
        let old = try DocumentCoder.encode(AppState(values: [Alex.homeEmail]))
        var json = try #require(JSONSerialization.jsonObject(with: old) as? [String: Any])
        json["siteKinds"] = nil
        json["insights"] = nil
        let data = try JSONSerialization.data(withJSONObject: json)
        #expect(try DocumentCoder.decode(AppState.self, from: data) == AppState(values: [Alex.homeEmail]))
    }

    @Test func modelKindsFillInOnlyWhereTheRulesCantTell() {
        let state = AppState(values: Alex.emails).recording(
            [CachedInsight(key: InsightKey.siteKind("canvas.instructure.com", variant: "v"), answer: "school")],
            siteKinds: ["instructure.com": .school, "irs.gov": .shopping]
        )
        #expect(state.siteKind("canvas.instructure.com") == .school)
        #expect(state.siteKind("irs.gov") == .government)
        #expect(state.insight(InsightKey.siteKind("instructure.com", variant: "v")) == "school")
    }
}
