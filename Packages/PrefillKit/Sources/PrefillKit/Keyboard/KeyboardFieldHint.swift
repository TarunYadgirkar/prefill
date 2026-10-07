import Foundation

// What the focused field says it wants, read from its content type or keyboard type.
public enum KeyboardFieldHint: Sendable, Hashable {
    case email, phone, address, fullName, givenName, familyName, link

    func matches(_ value: KeyboardValue) -> Bool {
        switch self {
        case .email: value.kind == .email
        case .phone: value.kind == .phone
        case .address: value.kind == .address
        case .link: value.kind == .link
        case .fullName: value.kind == .name && value.label == KeyboardValue.fullNameLabel
        case .givenName: value.kind == .name && value.label == KeyboardValue.givenNameLabel
        case .familyName: value.kind == .name && value.label == KeyboardValue.familyNameLabel
        }
    }
}
