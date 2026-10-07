import PrefillKit
import UIKit

// What the focused field tells a keyboard about itself: its content type, keyboard type and
// return key. Apps rarely set more, so most fields get no hint.
enum FieldTraits {
    private static let hints: [UITextContentType: KeyboardFieldHint] = [
        .emailAddress: .email, .telephoneNumber: .phone, .URL: .link,
        .name: .fullName, .givenName: .givenName, .familyName: .familyName,
        .fullStreetAddress: .address, .streetAddressLine1: .address
    ]
    private static let sensitive: Set<UITextContentType> = [
        .password, .newPassword, .oneTimeCode, .creditCardNumber, .creditCardSecurityCode
    ]

    static func hint(_ proxy: any UITextDocumentProxy) -> KeyboardFieldHint? {
        if let type = proxy.textContentType ?? nil, let hint = hints[type] { return hint }
        switch proxy.keyboardType ?? .default {
        case .emailAddress: return .email
        case .URL, .webSearch: return .link
        case .phonePad, .namePhonePad: return .phone
        default: return nil
        }
    }

    static func isSensitive(_ proxy: any UITextDocumentProxy) -> Bool {
        if proxy.isSecureTextEntry ?? false { return true }
        return (proxy.textContentType ?? nil).map(sensitive.contains) ?? false
    }

    static func returnLabel(_ type: UIReturnKeyType?) -> String {
        switch type ?? .default {
        case .go, .route: String(localized: "go")
        case .join: String(localized: "join")
        case .next: String(localized: "next")
        case .search, .google, .yahoo: String(localized: "search")
        case .send: String(localized: "send")
        case .done: String(localized: "done")
        case .emergencyCall: String(localized: "SOS")
        case .continue: String(localized: "continue")
        default: String(localized: "return")
        }
    }
}
