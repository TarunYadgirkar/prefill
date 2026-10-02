import Foundation

// Wire format shared with web/src/messages.ts and described in docs/messages.md.
// Field names must stay identical on both sides; docs/message-examples.json is checked
// by tests in both languages.

public enum FieldKind: String, Codable, Sendable, CaseIterable {
    case email, phone, address, name

    public var contactKind: ContactKind? { ContactKind(rawValue: rawValue) }
}

public struct PageField: Codable, Sendable, Hashable {
    public let kind: FieldKind
    public let section: SectionHint?

    public init(kind: FieldKind, section: SectionHint?) {
        self.kind = kind
        self.section = section
    }
}

public struct PageContextRequest: Codable, Sendable, Hashable {
    public let host: String
    public let fields: [PageField]

    public init(host: String, fields: [PageField]) {
        self.host = host
        self.fields = fields
    }

    public var hints: [ContactKind: SectionHint] {
        SectionHint.firstPerKind(fields.map { ($0.kind, $0.section) })
    }
}

extension SectionHint {
    // One card order serves the whole page, so the first field of a kind sets its hint.
    static func firstPerKind(_ fields: [(FieldKind, SectionHint?)]) -> [ContactKind: SectionHint] {
        fields.reduce(into: [:]) { hints, field in
            guard let kind = field.0.contactKind, hints[kind] == nil, let section = field.1 else { return }
            hints[kind] = section
        }
    }
}

public enum SyncStatus: String, Codable, Sendable, CaseIterable {
    case unchanged, saved, failed, off, notSetUp
}

public struct PageContextResponse: Codable, Sendable, Hashable {
    public let status: SyncStatus
    public let reason: String?

    public init(status: SyncStatus, reason: String? = nil) {
        self.status = status
        self.reason = reason
    }

    public init(outcome: CardWriteOutcome) {
        switch outcome {
        case .unchanged: self.init(status: .unchanged)
        case .saved: self.init(status: .saved)
        case .failed(let failure): self.init(status: .failed, reason: failure.reason)
        }
    }
}

public struct CapturedField: Codable, Sendable, Hashable {
    public let kind: FieldKind
    public let value: String?
    public let address: PostalAddress?
    public let autocomplete: String?
    public let name: String?
    public let label: String?
    public let section: SectionHint?

    public init(
        kind: FieldKind, value: String?, address: PostalAddress?, autocomplete: String?,
        name: String?, label: String?, section: SectionHint?
    ) {
        self.kind = kind
        self.value = value
        self.address = address
        self.autocomplete = autocomplete
        self.name = name
        self.label = label
        self.section = section
    }
}

public struct CaptureRequest: Codable, Sendable, Hashable {
    public let host: String
    public let fields: [CapturedField]
    public let hasPassword: Bool
    // False when the page was only hidden, never submitted: such values are never saved
    // straight to the card.
    public let submitted: Bool

    public init(host: String, fields: [CapturedField], hasPassword: Bool, submitted: Bool = true) {
        self.host = host
        self.fields = fields
        self.hasPassword = hasPassword
        self.submitted = submitted
    }

    public var hints: [ContactKind: SectionHint] {
        SectionHint.firstPerKind(fields.map { ($0.kind, $0.section) })
    }
}

public struct CaptureResponse: Codable, Sendable, Hashable {
    public let saved: Int
    public let review: Int
    public let ignored: Int

    public init(saved: Int, review: Int, ignored: Int) {
        self.saved = saved
        self.review = review
        self.ignored = ignored
    }

    // Duplicates count toward none of the three: only their use on the site is recorded.
    public init(decisions: [CaptureDecision]) {
        self.init(
            saved: decisions.count { if case .save = $0 { true } else { false } },
            review: decisions.count { if case .review = $0 { true } else { false } },
            ignored: decisions.count { if case .ignore = $0 { true } else { false } }
        )
    }
}

public enum ExtensionRequest: Sendable, Hashable {
    case ping
    case pageContext(PageContextRequest)
    case capture(CaptureRequest)
}

public enum ExtensionResponse: Sendable, Hashable {
    case pong
    case pageContext(PageContextResponse)
    case capture(CaptureResponse)
    case error(reason: String)
}

private enum TypeKey: String, CodingKey {
    case type
}

private struct ErrorBody: Codable {
    let reason: String
}

private enum RequestType: String, Codable {
    case ping, pageContext, capture
}

private enum ResponseType: String, Codable {
    case pong, pageContextResult, captureResult, error
}

extension ExtensionRequest: Codable {
    public init(from decoder: any Decoder) throws {
        let type = try decoder.container(keyedBy: TypeKey.self).decode(String.self, forKey: .type)
        switch RequestType(rawValue: type) {
        case .ping: self = .ping
        case .pageContext: self = .pageContext(try PageContextRequest(from: decoder))
        case .capture: self = .capture(try CaptureRequest(from: decoder))
        case nil: throw MessageError.unknownType
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: TypeKey.self)
        try container.encode(type, forKey: .type)
        try body?.encode(to: encoder)
    }

    private var type: RequestType {
        switch self {
        case .ping: .ping
        case .pageContext: .pageContext
        case .capture: .capture
        }
    }

    private var body: (any Encodable)? {
        switch self {
        case .ping: nil
        case .pageContext(let body): body
        case .capture(let body): body
        }
    }
}

extension ExtensionResponse: Codable {
    public init(from decoder: any Decoder) throws {
        let type = try decoder.container(keyedBy: TypeKey.self).decode(String.self, forKey: .type)
        switch ResponseType(rawValue: type) {
        case .pong: self = .pong
        case .pageContextResult: self = .pageContext(try PageContextResponse(from: decoder))
        case .captureResult: self = .capture(try CaptureResponse(from: decoder))
        case .error: self = .error(reason: try ErrorBody(from: decoder).reason)
        case nil: throw MessageError.unknownType
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: TypeKey.self)
        try container.encode(type, forKey: .type)
        try body?.encode(to: encoder)
    }

    public var typeName: String { type.rawValue }

    private var type: ResponseType {
        switch self {
        case .pong: .pong
        case .pageContext: .pageContextResult
        case .capture: .captureResult
        case .error: .error
        }
    }

    private var body: (any Encodable)? {
        switch self {
        case .pong: nil
        case .pageContext(let body): body
        case .capture(let body): body
        case .error(let reason): ErrorBody(reason: reason)
        }
    }
}

public enum MessageError: Error, Sendable {
    case notJSON, unknownType, tooLarge
}

// SFExtensionMessageKey carries Foundation JSON objects (NSDictionary and friends).
public enum MessageCoding {
    public static func request(from message: Any?) throws -> ExtensionRequest {
        guard let message, JSONSerialization.isValidJSONObject(message) else { throw MessageError.notJSON }
        let data = try JSONSerialization.data(withJSONObject: message)
        guard data.count <= MessageLimits.bytes else { throw MessageError.tooLarge }
        let request = try JSONDecoder().decode(ExtensionRequest.self, from: data)
        guard request.isWithinLimits else { throw MessageError.tooLarge }
        return request
    }

    // Names the kind of failure only. A decoding error's description can quote the value.
    public static func failureName(_ error: any Error) -> String {
        switch error {
        case MessageError.notJSON: "notJSON"
        case MessageError.unknownType: "unknownType"
        case MessageError.tooLarge: "tooLarge"
        case DecodingError.typeMismatch: "typeMismatch"
        case DecodingError.valueNotFound: "valueNotFound"
        case DecodingError.keyNotFound: "keyNotFound"
        case DecodingError.dataCorrupted: "dataCorrupted"
        default: "other"
        }
    }

    public static func jsonObject(_ response: ExtensionResponse) -> Any {
        let data = (try? JSONEncoder().encode(response)) ?? Data(#"{"type":"error","reason":"encoding"}"#.utf8)
        return (try? JSONSerialization.jsonObject(with: data)) ?? [:]
    }
}
