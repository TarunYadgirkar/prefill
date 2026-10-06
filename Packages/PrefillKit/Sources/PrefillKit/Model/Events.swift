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

// A value the person picked for a site from Safari. A nil `valueID` takes the pick back.
public struct PinEvent: Codable, Sendable, Hashable {
    public let host: String
    public let kind: ContactKind
    public let valueID: UUID?
    public let date: Date

    public init(host: String, kind: ContactKind, valueID: UUID?, date: Date) {
        self.host = host
        self.kind = kind
        self.valueID = valueID
        self.date = date
    }
}

// "Don't save on this site", turned on or off from Safari.
public struct MuteEvent: Codable, Sendable, Hashable {
    public let host: String
    public let isMuted: Bool
    public let date: Date

    public init(host: String, isMuted: Bool, date: Date) {
        self.host = host
        self.isMuted = isMuted
        self.date = date
    }
}

// A form question none of the custom field rules matched, kept for the app to ask the
// on-device model about. Only the field's words, never what the person typed.
public struct FormQuestion: Codable, Sendable, Hashable {
    public let host: String
    public let text: String
    public let date: Date

    public init(host: String, text: String, date: Date) {
        self.host = host
        self.text = text
        self.date = date
    }
}

// A custom answer the person picked from Prefill's list, kept by the question's words so
// the same question on any site offers it first.
public struct AnswerPick: Codable, Sendable, Hashable {
    public let words: String
    public let label: String
    public let date: Date

    public init(words: String, label: String, date: Date) {
        self.words = words
        self.label = label
        self.date = date
    }
}
