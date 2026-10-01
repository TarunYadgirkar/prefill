import Foundation

public struct UsageEvent: Codable, Sendable, Hashable {
    public let valueID: UUID
    public let host: String
    public let date: Date

    public init(valueID: UUID, host: String, date: Date) {
        self.valueID = valueID
        self.host = host
        self.date = date
    }
}

public struct SitePin: Codable, Sendable, Hashable {
    public let host: String
    public let kind: ContactKind
    public let valueID: UUID

    public init(host: String, kind: ContactKind, valueID: UUID) {
        self.host = host
        self.kind = kind
        self.valueID = valueID
    }
}

public enum CaptureVerdict: String, Codable, Sendable {
    case saved, needsReview, duplicate, dismissed
}

public struct Capture: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let host: String
    public let value: ContactValue
    public let date: Date
    public let verdict: CaptureVerdict

    public init(id: UUID = UUID(), host: String, value: ContactValue, date: Date, verdict: CaptureVerdict) {
        self.id = id
        self.host = host
        self.value = value
        self.date = date
        self.verdict = verdict
    }

    public var kind: ContactKind { value.kind }
}
