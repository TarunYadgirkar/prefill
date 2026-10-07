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

public struct KeyboardGroup: Hashable, Sendable, Identifiable {
    public let title: String
    public let values: [KeyboardValue]
    public var id: String { title }
}

extension KeyboardSnapshot {
    // "For this field" first when the field names a kind, then Contact, Links and Answers.
    // A value shows once, in the first group that has it.
    public func groups(for hint: KeyboardFieldHint?) -> [KeyboardGroup] {
        let matching = hint.map { hint in values.filter(hint.matches) } ?? []
        let shown = Set(matching.map(\.id))
        let rest = values.filter { !shown.contains($0.id) }
        let contact: Set<KeyboardValue.Kind> = [.name, .email, .phone, .address]
        let groups = [
            KeyboardGroup(title: String(localized: "For this field"), values: matching),
            KeyboardGroup(title: String(localized: "Contact"), values: rest.filter { contact.contains($0.kind) }),
            KeyboardGroup(title: String(localized: "Links"), values: rest.filter { $0.kind == .link }),
            KeyboardGroup(title: String(localized: "Answers"), values: rest.filter { $0.kind == .custom })
        ]
        return groups.filter { !$0.values.isEmpty }
    }
}
