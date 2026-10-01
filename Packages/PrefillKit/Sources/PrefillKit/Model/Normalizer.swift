import Foundation

public enum Normalizer {
    private static let usNationalLength = 10
    private static let usZipLength = 5
    private static let twoPartSuffixes: Set<String> = [
        "co.uk", "org.uk", "ac.uk", "gov.uk", "me.uk", "ltd.uk", "plc.uk",
        "com.au", "net.au", "org.au", "edu.au", "gov.au",
        "co.nz", "org.nz", "co.jp", "ne.jp", "or.jp", "ac.jp",
        "co.in", "net.in", "org.in", "com.br", "com.mx", "com.cn", "com.hk", "com.sg",
        "co.za", "co.kr", "com.tw", "com.tr", "co.il"
    ]

    public static func key(for payload: ContactPayload) -> String {
        switch payload {
        case .email(let text): email(text)
        case .phone(let text): phone(text)
        case .address(let address): self.address(address)
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

    public static func fold(_ text: String) -> String {
        text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    public static func registrableDomain(_ host: String) -> String {
        let bare = host.lowercased()
            .split(separator: ":", maxSplits: 1).first.map(String.init) ?? ""
        let labels = bare.split(separator: ".").map(String.init)
        guard labels.count > 2, !isIPv4(labels) else { return labels.joined(separator: ".") }
        let lastTwo = labels.suffix(2).joined(separator: ".")
        let keep = twoPartSuffixes.contains(lastTwo) ? 3 : 2
        return labels.suffix(keep).joined(separator: ".")
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

    private static func isIPv4(_ labels: [String]) -> Bool {
        labels.count == 4 && labels.allSatisfy { UInt8($0) != nil }
    }
}
