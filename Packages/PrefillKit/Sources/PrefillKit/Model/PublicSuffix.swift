import Foundation

// A stand-in for the Public Suffix List, which iOS doesn't expose: a name under a country
// code is one level deeper when its second level is a generic one (shop.com.ar, not
// com.ar), and a short list of hosting services give every customer a site of their own
// (alice.github.io and bob.github.io are two sites). History is keyed on what this returns,
// so two sites that share a key share their suggestions.
enum PublicSuffix {
    private static let countryCodeLength = 2
    private static let genericSecondLevels: Set<String> = [
        "com", "net", "org", "edu", "gov", "gob", "gouv", "mil", "int", "co", "ac", "ne", "or", "go",
        "nic", "ltd", "plc", "me", "gen", "biz", "info", "nom", "sch", "web", "res", "firm", "ind", "nhs"
    ]
    private static let hostingSuffixes: Set<String> = [
        "github.io", "gitlab.io", "vercel.app", "netlify.app", "pages.dev", "workers.dev", "web.app",
        "firebaseapp.com", "appspot.com", "herokuapp.com", "blogspot.com", "azurewebsites.net",
        "cloudfront.net", "s3.amazonaws.com", "onrender.com", "fly.dev", "glitch.me", "myshopify.com",
        "wixsite.com", "ngrok.io", "ngrok-free.app", "replit.app", "repl.co", "surge.sh", "deno.dev",
        "streamlit.app", "webflow.io", "framer.app", "carrd.co", "neocities.org", "pythonanywhere.com"
    ]

    static func registrableDomain(_ host: String) -> String {
        let lowered = host.lowercased()
        if lowered.hasPrefix("[") { return bracketed(lowered) }
        let bare = lowered.split(separator: ":", maxSplits: 1).first.map(String.init) ?? ""
        let labels = bare.split(separator: ".").map(String.init)
        guard labels.count > 2, !isIPv4(labels) else { return labels.joined(separator: ".") }
        return labels.suffix(suffixLength(labels) + 1).joined(separator: ".")
    }

    private static func suffixLength(_ labels: [String]) -> Int {
        if let hosting = hostingSuffixes.first(where: { labels.joined(separator: ".").hasSuffix("." + $0) }) {
            return hosting.split(separator: ".").count
        }
        let topLevel = labels[labels.count - 1]
        let secondLevel = labels[labels.count - 2]
        let isCountryGeneric = topLevel.count == countryCodeLength && genericSecondLevels.contains(secondLevel)
        return isCountryGeneric ? 2 : 1
    }

    // An IPv6 literal is a whole host, written in brackets and maybe followed by a port.
    private static func bracketed(_ host: String) -> String {
        guard let end = host.firstIndex(of: "]") else { return host }
        return String(host[...end])
    }

    private static func isIPv4(_ labels: [String]) -> Bool {
        labels.count == 4 && labels.allSatisfy { UInt8($0) != nil }
    }
}
