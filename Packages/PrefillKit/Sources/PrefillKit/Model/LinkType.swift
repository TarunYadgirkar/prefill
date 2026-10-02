import Contacts
import Foundation

// What a link on the card is, read from its host, and the label it gets on the card.
public enum LinkType: String, Codable, Sendable, CaseIterable {
    case github, website, linkedin
    case x // swiftlint:disable:this identifier_name
    case other

    private static let hosts: [String: LinkType] = [
        "github.com": .github, "linkedin.com": .linkedin, "x.com": .x, "twitter.com": .x
    ]

    public static func of(_ raw: String) -> LinkType {
        guard let url = LinkURL(raw) else { return .other }
        let site = hosts.keys.first { url.host == $0 || url.host.hasSuffix("." + $0) }
        return site.flatMap { hosts[$0] } ?? .website
    }

    public var label: String {
        switch self {
        case .github: "GitHub"
        case .website: CNLabelURLAddressHomePage
        case .linkedin: "LinkedIn"
        case .x: "X"
        case .other: CNLabelOther
        }
    }
}

// A web address split the way Prefill compares links: the host lowercased without "www."
// and the path without a trailing slash. Query and fragment don't make a different link.
struct LinkURL {
    private static let schemes = ["https://", "http://"]
    private static let www = "www."

    let host: String
    let path: String

    init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let scheme = Self.schemes.first { trimmed.lowercased().hasPrefix($0) }
        let rest = trimmed.dropFirst(scheme?.count ?? 0)
        let end = rest.firstIndex { "/?#".contains($0) } ?? rest.endIndex
        let host = rest[..<end].lowercased()
        guard !host.isEmpty, !host.contains(where: { $0.isWhitespace || $0 == "@" || $0 == ":" }) else {
            return nil
        }
        let afterHost = rest[end...]
        let pathEnd = afterHost.firstIndex { "?#".contains($0) } ?? afterHost.endIndex
        var path = String(afterHost[..<pathEnd])
        while path.hasSuffix("/") { path.removeLast() }
        self.host = host.hasPrefix(Self.www) ? String(host.dropFirst(Self.www.count)) : host
        self.path = path
    }

    // The link as stored and suggested: as typed, with https:// in front when it had no scheme.
    static func full(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return schemes.contains(where: trimmed.lowercased().hasPrefix) ? trimmed : "https://" + trimmed
    }
}

extension LinkType {
    // For the app's add sheet: the link as it goes on the card, or nil when it isn't a web address.
    public static func cardText(_ raw: String) -> String? {
        ValueRules.isLink(raw) ? LinkURL.full(raw) : nil
    }
}
