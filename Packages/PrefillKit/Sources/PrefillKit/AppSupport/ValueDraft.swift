import Foundation

// What the person typed for a new or edited value, checked the same way on the iPhone and
// the Mac before it goes on the card.
public struct ValueDraft: Sendable {
    public struct Problem: Error, Sendable {
        public let message: String
    }

    private static let minPhoneDigits = 7

    public init() {}

    // Filled in from a value already saved, for editing it.
    public init(_ payload: ContactPayload) {
        switch payload {
        case .email(let text): email = text
        case .phone(let text): phone = text
        case .link(let text): link = text
        case .address(let address):
            street = address.street
            city = address.city
            state = address.state
            postalCode = address.postalCode
            country = address.country
        }
    }

    public var email = ""
    public var phone = ""
    public var street = ""
    public var city = ""
    public var state = ""
    public var postalCode = ""
    public var country = ""
    public var link = ""

    public func payload(_ kind: ContactKind) -> Result<ContactPayload, Problem> {
        switch kind {
        case .email: emailPayload()
        case .phone: phonePayload()
        case .address: addressPayload()
        case .link: linkPayload()
        }
    }

    private func linkPayload() -> Result<ContactPayload, Problem> {
        guard let text = LinkType.cardText(link) else {
            return .failure(Problem(message: String(localized: "Enter a web address like github.com/yourname.")))
        }
        return .success(.link(text))
    }

    private func emailPayload() -> Result<ContactPayload, Problem> {
        let text = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = text.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."), !parts[1].hasSuffix(".") else {
            return .failure(Problem(message: String(localized: "Enter an email address like name@example.com.")))
        }
        return .success(.email(text))
    }

    private func phonePayload() -> Result<ContactPayload, Problem> {
        let text = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.filter(\.isNumber).count >= Self.minPhoneDigits else {
            return .failure(Problem(message: String(localized: "Enter a phone number with at least 7 digits.")))
        }
        return .success(.phone(text))
    }

    private func addressPayload() -> Result<ContactPayload, Problem> {
        let trim = { (text: String) in text.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !trim(street).isEmpty else {
            return .failure(Problem(message: String(localized: "Enter the street part of the address.")))
        }
        return .success(.address(PostalAddress(
            street: trim(street), city: trim(city), state: trim(state),
            postalCode: trim(postalCode), country: trim(country)
        )))
    }
}
