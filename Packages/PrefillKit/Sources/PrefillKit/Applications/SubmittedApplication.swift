import Foundation

// A job application the person sent, as the content script read it on a trusted submit:
// every question with what went in, and the names of the files uploaded. Sensitive fields and
// demographic questions are never in it. The extension queues it in ExtensionEvents and the
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

    // Held to the limits of the message it came from, for one read from another device's file.
    var isValid: Bool {
        let request = ExtensionRequest.application(
            ApplicationRequest(id: id, host: host, path: path, title: title, fields: fields, files: files)
        )
        return request.isWithinLimits && request.isWellFormed
    }
}
