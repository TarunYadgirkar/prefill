import Foundation

// The questions job applications keep asking. Prefill learns the person's answers to these
// from forms they submit, and the Custom tab offers them as a starter set.
public enum JobQuestion: String, Codable, Sendable, CaseIterable {
    case school, degree, major, gpa, graduation, authorization, sponsorship, heard

    public var label: String {
        switch self {
        case .school: "School"
        case .degree: "Degree"
        case .major: "Major"
        case .gpa: "GPA"
        case .graduation: "Graduation date"
        case .authorization: "Work authorization"
        case .sponsorship: "Sponsorship"
        case .heard: "How did you hear about us"
        }
    }

    // Other wordings of the question, as extra match words.
    var alsoMatches: String {
        switch self {
        case .school: "university, college"
        case .degree: ""
        case .major: "field of study, discipline"
        case .gpa: "grade point average"
        case .graduation: "graduation, grad date"
        case .authorization: "authorized to work, legally authorized, eligible to work"
        case .sponsorship: "sponsor, visa"
        case .heard: "hear about"
        }
    }

    // Nil when the answer breaks a custom field's rules, such as a line break.
    public func field(answer: String) -> CustomField? {
        try? CustomField.make(label: label, value: answer, alsoMatches: alsoMatches).get()
    }
}

// An answer Prefill saved from a form the person submitted.
public struct LearnedAnswer: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let host: String
    public let label: String
    public let value: String
    public let date: Date

    public init(id: UUID = UUID(), host: String, label: String, value: String, date: Date) {
        self.id = id
        self.host = host
        self.label = label
        self.value = value
        self.date = date
    }

    public func matches(_ field: CustomField) -> Bool {
        field.id == label.lowercased() && field.value == value
    }
}
