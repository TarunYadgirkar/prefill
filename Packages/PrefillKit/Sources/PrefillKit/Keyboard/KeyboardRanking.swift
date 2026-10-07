import Foundation

// What the keyboard knows about the focused field. iOS never tells a keyboard the field's
// label, so the order comes from what's typed, the field's traits and the person's picks.
public struct KeyboardContext: Sendable, Hashable {
    public var before: String
    public var hint: KeyboardFieldHint?
    public var recentPicks: [String]

    public init(before: String = "", hint: KeyboardFieldHint? = nil, recentPicks: [String] = []) {
        self.before = before
        self.hint = hint
        self.recentPicks = recentPicks
    }

    // How many characters a tap on the value replaces: the word being typed, when it led to
    // this value, as a QuickType suggestion replaces the word it completes.
    public func replacedLength(for value: KeyboardValue) -> Int {
        KeyboardTyped(before).replacedLength(for: value)
    }
}

extension KeyboardSnapshot {
    // Strongest signal first: what's typed, the field's traits, the keyboard's own recent
    // picks, the last use anywhere, then a fixed order. A value already in the field is left out.
    public func ranked(for context: KeyboardContext) -> [KeyboardValue] {
        let typed = KeyboardTyped(context.before)
        let fallback = KeyboardFallback(values)
        let recent = Dictionary(context.recentPicks.enumerated().map { ($1, $0) }, uniquingKeysWith: min)
        let keys = values.enumerated().filter { !typed.isAlreadyIn($0.element) }.map { offset, value in
            KeyboardRankKey(
                typed: typed.score(value),
                fitsField: context.hint?.matches(value) ?? false,
                recent: recent[value.id] ?? .max,
                lastUsed: value.lastUsed ?? .distantPast,
                fallback: fallback.rank(value),
                offset: offset
            )
        }
        return keys.sorted().map { values[$0.offset] }
    }
}

struct KeyboardRankKey: Comparable {
    let typed: Int
    let fitsField: Bool
    let recent: Int
    let lastUsed: Date
    let fallback: Int
    let offset: Int

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.typed != rhs.typed { return lhs.typed > rhs.typed }
        if lhs.fitsField != rhs.fitsField { return lhs.fitsField }
        if lhs.recent != rhs.recent { return lhs.recent < rhs.recent }
        if lhs.lastUsed != rhs.lastUsed { return lhs.lastUsed > rhs.lastUsed }
        if lhs.fallback != rhs.fallback { return lhs.fallback < rhs.fallback }
        return lhs.offset < rhs.offset
    }
}

// Name, primary email, phone, LinkedIn, GitHub, website, then answers, then everything else.
struct KeyboardFallback {
    private let primaryEmail: String?
    private let primaryPhone: String?

    init(_ values: [KeyboardValue]) {
        primaryEmail = values.first { $0.kind == .email }?.id
        primaryPhone = values.first { $0.kind == .phone }?.id
    }

    func rank(_ value: KeyboardValue) -> Int {
        if value.kind == .name, value.label == KeyboardValue.fullNameLabel { return 0 }
        if value.id == primaryEmail { return 1 }
        if value.id == primaryPhone { return 2 }
        if value.kind == .link, let site = Self.siteRank(value) { return site }
        return value.kind == .custom ? 6 : 7
    }

    private static func siteRank(_ value: KeyboardValue) -> Int? {
        let label = value.label.lowercased()
        let shown = value.shownText.lowercased()
        if label == "linkedin" || shown.contains("linkedin.com") { return 3 }
        if label == "github" || shown.hasPrefix("github.com") { return 4 }
        return label == "website" ? 5 : nil
    }
}

// The keyboard's own picks, most recent first, by value id. Kept in the keyboard's own
// defaults, which need no Full Access.
public struct KeyboardRecents: Sendable, Hashable {
    public static let maxCount = 30

    public let ids: [String]

    public init(ids: [String] = []) {
        self.ids = Array(ids.prefix(Self.maxCount))
    }

    public func picking(_ id: String) -> KeyboardRecents {
        KeyboardRecents(ids: [id] + ids.filter { $0 != id })
    }
}
