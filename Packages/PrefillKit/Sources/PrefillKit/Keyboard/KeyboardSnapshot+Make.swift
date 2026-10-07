import Foundation

extension KeyboardSnapshot {
    // Name parts first, then contact values, links and answers, each kind most recently used
    // first and otherwise in the card's order, cut to maxValues.
    public static func make(memory: Memory, now: Date = .now) -> KeyboardSnapshot {
        let answers = memory.answers.compactMap { answer in
            value(for: answer).map { $0(memory.uses(of: answer).first?.date) }
        }
        let all = names(memory.name) + KeyboardValue.Kind.allCases.flatMap { kind in
            byRecentUse(answers.filter { $0.kind == kind })
        }
        var seen = Set<String>()
        let unique = all.filter { !$0.text.isEmpty && seen.insert($0.id).inserted }
        return KeyboardSnapshot(values: Array(unique.prefix(maxValues)), writtenAt: now)
    }

    static func byRecentUse(_ values: [KeyboardValue]) -> [KeyboardValue] {
        values.enumerated().sorted { lhs, rhs in
            switch (lhs.element.lastUsed, rhs.element.lastUsed) {
            case let (left?, right?) where left != right: left > right
            case (.some, nil): true
            case (nil, .some): false
            default: lhs.offset < rhs.offset
            }
        }.map(\.element)
    }

    private static func names(_ name: Memory.Name) -> [KeyboardValue] {
        let full = [name.given, name.family].filter { !$0.isEmpty }.joined(separator: " ")
        return [
            KeyboardValue(kind: .name, label: KeyboardValue.fullNameLabel, text: full),
            KeyboardValue(kind: .name, label: KeyboardValue.givenNameLabel, text: name.given),
            KeyboardValue(kind: .name, label: KeyboardValue.familyNameLabel, text: name.family)
        ]
    }

    private static func value(for answer: Answer) -> ((Date?) -> KeyboardValue)? {
        switch answer.question {
        case .custom(let label):
            return { KeyboardValue(kind: .custom, label: label, text: answer.text, lastUsed: $0) }
        case .kind(let kind):
            let text = answer.address?.oneLine ?? answer.text
            let caption = KeyboardCaption.of(answer.label, kind: kind)
            return { KeyboardValue(kind: KeyboardValue.Kind(kind), label: caption, text: text, lastUsed: $0) }
        }
    }
}

extension KeyboardValue.Kind {
    init(_ kind: ContactKind) {
        switch kind {
        case .email: self = .email
        case .phone: self = .phone
        case .address: self = .address
        case .link: self = .link
        }
    }
}

// Captions read as a person names the value: "Work email", "Mobile", "LinkedIn".
enum KeyboardCaption {
    private static let standalonePhones: Set<String> = ["mobile", "iphone", "main"]
    private static let nouns: [ContactKind: String] = [.email: "email", .phone: "phone", .address: "address"]

    static func of(_ label: String?, kind: ContactKind) -> String {
        guard let label, !label.isEmpty else { return kind == .link ? "Link" : capitalized(nouns[kind] ?? "") }
        let caption = LabelChoices.caption(label, kind: kind)
        if kind == .link { return linkCaption(caption) }
        if kind == .phone, standalonePhones.contains(caption.lowercased()) { return capitalized(caption) }
        return "\(capitalized(caption)) \(nouns[kind] ?? "")"
    }

    private static func linkCaption(_ caption: String) -> String {
        switch caption.lowercased() {
        case "homepage", "home page": "Website"
        case "other", "": "Link"
        default: capitalized(caption)
        }
    }

    private static func capitalized(_ text: String) -> String {
        guard let first = text.first, first.isLowercase else { return text }
        return first.uppercased() + text.dropFirst()
    }
}
