import Foundation

// Deterministic guesses about hosts and captured values. They run everywhere, the Safari
// handler included; the model only breaks the ties they leave, and only in the app.
public enum SiteSense {
    public static func rules(host: String, emailDomains: Set<String> = []) -> SiteKind {
        let labels = host.lowercased().split(separator: ".").map(String.init)
        if isAcademic(labels) { return .school }
        if isGovernment(labels) { return .government }
        let site = Normalizer.registrableDomain(host)
        if emailDomains.contains(site) { return .work }
        if knownStores.contains(site) { return .shopping }
        return .unknown
    }

    // Domains of the person's own emails that name an organization rather than a mail
    // provider, so a site at one of them is where they work.
    public static func workDomains(_ values: [ContactValue]) -> Set<String> {
        Set(values.filter { LabelName.of($0.label) != SuggestedLabel.home.rawValue }
            .compactMap(\.emailDomain)
            .filter { !freemail.contains($0) })
    }

    static func isAcademic(_ labels: [String]) -> Bool {
        labels.last == "edu" || secondToLast(labels).map { $0 == "ac" || $0 == "edu" } == true
    }

    static func isGovernment(_ labels: [String]) -> Bool {
        ["gov", "mil"].contains(labels.last ?? "") || secondToLast(labels) == "gov"
    }

    // Country domains put the category one level down: ox.ac.uk, unimelb.edu.au, www.gov.uk.
    private static func secondToLast(_ labels: [String]) -> String? {
        guard labels.count >= 3, labels.last?.count == 2 else { return nil }
        return labels[labels.count - 2]
    }

    static let freemail: Set<String> = [
        "gmail.com", "googlemail.com", "icloud.com", "me.com", "mac.com", "outlook.com", "hotmail.com",
        "live.com", "msn.com", "yahoo.com", "ymail.com", "aol.com", "proton.me", "protonmail.com",
        "pm.me", "fastmail.com", "hey.com", "gmx.com", "gmx.de", "mail.com", "zoho.com", "yandex.com",
        "qq.com", "163.com", "naver.com", "duck.com"
    ]

    static let knownStores: Set<String> = [
        "amazon.com", "target.com", "walmart.com", "bestbuy.com", "etsy.com", "ebay.com", "costco.com",
        "homedepot.com", "lowes.com", "ikea.com", "wayfair.com", "macys.com", "nordstrom.com",
        "kohls.com", "rei.com", "zappos.com", "nike.com", "adidas.com", "sephora.com", "ulta.com",
        "chewy.com", "instacart.com", "doordash.com", "ubereats.com", "shein.com", "temu.com",
        "aliexpress.com", "newegg.com", "uniqlo.com", "zara.com", "hm.com", "gap.com"
    ]
}

// A suggested label for a value Prefill caught on a form. `isSettled` is false only when
// the rules had to guess, which for now means a freemail address.
public struct LabelGuess: Sendable, Hashable {
    public let label: SuggestedLabel
    public let isSettled: Bool
}

public enum LabelRules {
    public static func suggest(_ value: ContactValue, host: String, emailDomains: Set<String> = []) -> LabelGuess {
        guard let domain = value.emailDomain else { return fromSite(host, emailDomains: emailDomains) }
        let labels = domain.split(separator: ".").map(String.init)
        if SiteSense.isAcademic(labels) { return LabelGuess(label: .school, isSettled: true) }
        if SiteSense.freemail.contains(domain) { return LabelGuess(label: .home, isSettled: false) }
        return LabelGuess(label: .work, isSettled: true)
    }

    // Phones and addresses carry no domain, so the site they were typed on decides.
    private static func fromSite(_ host: String, emailDomains: Set<String>) -> LabelGuess {
        let kind = SiteSense.rules(host: host, emailDomains: emailDomains)
        let label = kind.preferredLabel.flatMap(SuggestedLabel.init(rawValue:)) ?? .home
        return LabelGuess(label: label, isSettled: true)
    }
}
