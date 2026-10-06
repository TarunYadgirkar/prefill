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

// What the Custom tab offers a student to start from: the school is filled in, the rest
// are blank, and all of them can be edited before anything is saved.
public enum StudentStarter {
    public static let questions: [JobQuestion] = [.school, .degree, .major, .gpa, .graduation]
    public static let answers: [JobQuestion: String] = [.school: "University of California, Berkeley"]

    public static func example(_ question: JobQuestion) -> String {
        switch question {
        case .degree: "Bachelor of Science"
        case .major: "Computer Science"
        case .gpa: "3.8"
        case .graduation: "May 2028"
        default: ""
        }
    }

    // The questions still without a custom field.
    public static func missing(from fields: [CustomField]) -> [JobQuestion] {
        questions.filter { question in !fields.contains { $0.id == question.label.lowercased() } }
    }

    // A field for each answer that isn't blank and whose question has none yet, in the starter's order.
    public static func fields(for answers: [JobQuestion: String], adding fields: [CustomField]) -> [CustomField] {
        missing(from: fields).compactMap { question in
            let answer = (answers[question] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return answer.isEmpty ? nil : question.field(answer: answer)
        }
    }
}

// An answer Prefill saved from a form the person submitted.
public struct LearnedAnswer: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let host: String
    public let label: String
    public let value: String
    public let date: Date
    // The learned answer this one replaced, for Undo; nil for a new answer.
    public let previous: String?

    public init(id: UUID = UUID(), host: String, label: String, value: String, date: Date, previous: String? = nil) {
        self.id = id
        self.host = host
        self.label = label
        self.value = value
        self.date = date
        self.previous = previous
    }

    public func matches(_ field: CustomField) -> Bool {
        field.id == label.lowercased() && field.value == value
    }
}
