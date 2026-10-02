import Contacts

// What kind of site a host is, as far as which of the person's values it wants.
public enum SiteKind: String, Codable, Sendable, CaseIterable {
    case work, school, personal, shopping, finance, government, unknown

    // The label (folded, as LabelName.of reads it) of the value this kind of site wants first.
    // Contacts has no shopping or finance label, and a custom one shows as raw text in
    // Safari's bar, so everything personal maps to home.
    var preferredLabel: String? {
        switch self {
        case .work: SuggestedLabel.work.rawValue
        case .school: SuggestedLabel.school.rawValue
        case .personal, .shopping, .finance, .government: SuggestedLabel.home.rawValue
        case .unknown: nil
        }
    }
}

// The labels Prefill suggests for a captured value: the system labels Safari's bar reads well.
public enum SuggestedLabel: String, Codable, Sendable, CaseIterable {
    case home, work, school

    public var contactsLabel: String {
        switch self {
        case .home: CNLabelHome
        case .work: CNLabelWork
        case .school: CNLabelSchool
        }
    }
}

// Where an answer came from: the on-device model, or Prefill's own rules.
public enum InsightSource: String, Codable, Sendable {
    case model, rules
}

public struct Insight<Result: Sendable & Hashable>: Sendable, Hashable {
    public let result: Result
    public let source: InsightSource

    public init(_ result: Result, source: InsightSource) {
        self.result = result
        self.source = source
    }
}
