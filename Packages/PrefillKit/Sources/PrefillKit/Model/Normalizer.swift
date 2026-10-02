import Foundation

public enum Normalizer {
    private static let usNationalLength = 10
    private static let usZipLength = 5

    public static func key(for payload: ContactPayload) -> String {
        switch payload {
        case .email(let text): email(text)
        case .phone(let text): phone(text)
        case .address(let address): self.address(address)
        case .link(let text): link(text)
        }
    }

    public static func email(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public static func phone(_ raw: String, region: String = PhoneRegion.current) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.filter(\.isASCII).filter(\.isNumber)
        if trimmed.hasPrefix("+") { return "+" + digits }
        guard digits.count >= PhoneRegion.minNationalDigits, let code = PhoneRegion.callingCode(region) else {
            return digits
        }
        return code == PhoneRegion.nanpCode ? nanp(digits) : "+" + code + trunkStripped(digits)
    }

    // Street plus postal code only. Forms often leave out the country or state, or spell
    // them differently from the card ("US", "California"), and those must still match.
    public static func address(_ address: PostalAddress) -> String {
        let place = postalCode(address.postalCode)
        return street(address.street) + "\n" + (place.isEmpty ? fold(address.city) : place)
    }

    static func street(_ raw: String) -> String {
        raw.lowercased()
            .replacing("#", with: " # ")
            .split { !$0.isLetter && !$0.isNumber && $0 != "#" }
            .map { StreetWords.short[String($0)] ?? String($0) }
            .joined(separator: " ")
    }

    static func postalCode(_ raw: String) -> String {
        let compact = raw.lowercased().filter { !$0.isWhitespace }
        let zip = compact.prefix(usZipLength)
        let isUSZip = zip.count == usZipLength && zip.allSatisfy(\.isNumber)
            && (compact.count == usZipLength || compact.dropFirst(usZipLength).first == "-")
        return isUSZip ? String(zip) : compact
    }

    // Host and path only: no scheme, no "www.", a lowercase host and no trailing slash, so
    // "https://GitHub.com/alex/" and "github.com/alex" are the same link.
    public static func link(_ raw: String) -> String {
        guard let url = LinkURL(raw) else { return fold(raw) }
        return url.host + url.path
    }

    public static func fold(_ text: String) -> String {
        text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    public static func registrableDomain(_ host: String) -> String {
        PublicSuffix.registrableDomain(host)
    }

    public static func emailDomain(_ address: String) -> String? {
        let parts = email(address).split(separator: "@")
        guard parts.count == 2, let domain = parts.last else { return nil }
        return registrableDomain(String(domain))
    }

    private static func nanp(_ digits: String) -> String {
        if digits.count == usNationalLength { return "+1" + digits }
        if digits.count == usNationalLength + 1, digits.hasPrefix("1") { return "+" + digits }
        return digits
    }

    private static func trunkStripped(_ digits: String) -> String {
        digits.hasPrefix("0") ? String(digits.dropFirst()) : digits
    }
}
