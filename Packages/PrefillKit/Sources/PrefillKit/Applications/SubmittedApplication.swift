import Foundation

// A job application the person sent, as the content script read it on a trusted submit:
// every question with what went in, and the names of the files uploaded. Sensitive fields are
// never in it. The extension queues it in ExtensionEvents and the
// app moves it into its own ApplicationArchive, which keeps every one.
public struct ApplicationRequest: Codable, Sendable, Hashable {
    public struct Field: Codable, Sendable, Hashable {
        public let question: String
        // An essay may run long and span lines.
        public let answer: String

        public init(question: String, answer: String) {
            self.question = question
            self.answer = answer
        }
    }

    public struct File: Codable, Sendable, Hashable {
        public let question: String
        public let name: String

        public init(question: String, name: String) {
            self.question = question
            self.name = name
        }
    }

    // One per page, so a second send from it (after the page turned an answer away) replaces
    // the first.
    public let id: UUID
    public let host: String
    // The page's path only: its query can carry tokens.
    public let path: String
    public let title: String
    public let fields: [Field]
    public let files: [File]

    public init(id: UUID = UUID(), host: String, path: String, title: String, fields: [Field], files: [File]) {
        self.id = id
        self.host = host
        self.path = path
        self.title = title
        self.fields = fields
        self.files = files
    }
}

public struct ApplicationResponse: Codable, Sendable, Hashable {
    public let saved: Bool

    public init(saved: Bool) {
        self.saved = saved
    }
}

public struct SubmittedApplication: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let date: Date
    public let host: String
    public let path: String
    public let title: String
    public let fields: [ApplicationRequest.Field]
    public let files: [ApplicationRequest.File]

    public init(date: Date, request: ApplicationRequest) {
        id = request.id
        self.date = date
        host = request.host
        path = request.path
        title = request.title
        fields = request.fields
        files = request.files
    }

    public var site: String { Normalizer.registrableDomain(host) }

    // A later step or send of this application: its answers replace earlier ones to the same
    // question and join the rest, in the order the questions were first asked. A question asked
    // twice (a second "Employer") is matched by its turn, so neither answer is lost.
    func adding(_ later: SubmittedApplication) -> SubmittedApplication {
        let earlier = Self.numbered(fields)
        let answers = Dictionary(Self.numbered(later.fields)) { _, last in last }
        let kept = earlier.map { answers[$0.0] ?? $0.1 }
        let asked = Set(earlier.map(\.0))
        let added = Self.numbered(later.fields).filter { !asked.contains($0.0) }.map(\.1)
        let names = Set(files.map(\.name))
        let request = ApplicationRequest(
            id: id, host: later.host, path: later.path, title: later.title,
            fields: kept + added, files: files + later.files.filter { !names.contains($0.name) }
        )
        return SubmittedApplication(date: later.date, request: request)
    }

    private struct Asked: Hashable {
        let question: String
        let turn: Int
    }

    private static func numbered(_ fields: [ApplicationRequest.Field]) -> [(Asked, ApplicationRequest.Field)] {
        var turns: [String: Int] = [:]
        return fields.map { field in
            let turn = turns[field.question, default: 0]
            turns[field.question] = turn + 1
            return (Asked(question: field.question, turn: turn), field)
        }
    }

    // Held to the limits of the message it came from, for one read from another device's file.
    var isValid: Bool {
        let request = ExtensionRequest.application(
            ApplicationRequest(id: id, host: host, path: path, title: title, fields: fields, files: files)
        )
        return request.isWithinLimits && request.isWellFormed
    }
}
