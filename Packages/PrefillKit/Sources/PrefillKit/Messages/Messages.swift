import Foundation

// Wire format shared with web/src/messages.ts and described in docs/messages.md.
// Field names must stay identical on both sides; docs/message-examples.json is checked
// by tests in both languages.

public enum FieldKind: String, Codable, Sendable, CaseIterable {
    case email, phone, address, name, link

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

extension SectionHint {
    // The first field of a kind sets its hint for the page.
    static func firstPerKind(_ fields: [(FieldKind, SectionHint?)]) -> [ContactKind: SectionHint] {
        fields.reduce(into: [:]) { hints, field in
            guard let kind = field.0.contactKind, hints[kind] == nil, let section = field.1 else { return }
            hints[kind] = section
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
    // The person typed this value themselves, as opposed to the page filling it in.
    public let userTyped: Bool

    public init(
        kind: FieldKind, value: String?, address: PostalAddress?, autocomplete: String?,
        name: String?, label: String?, section: SectionHint?, userTyped: Bool
    ) {
        self.kind = kind
        self.value = value
        self.address = address
        self.autocomplete = autocomplete
        self.name = name
        self.label = label
        self.section = section
        self.userTyped = userTyped
    }
}

// `submit` is a form the person sent. `flush` is what they typed before the page was
// hidden, which is never saved straight to the card.
public enum CaptureTrigger: String, Codable, Sendable, CaseIterable {
    case submit, flush
}

public struct CaptureRequest: Codable, Sendable, Hashable {
    public let host: String
    public let fields: [CapturedField]
    public let hasPassword: Bool
    public let trigger: CaptureTrigger

    public init(host: String, fields: [CapturedField], hasPassword: Bool, trigger: CaptureTrigger = .submit) {
        self.host = host
        self.fields = fields
        self.hasPassword = hasPassword
        self.trigger = trigger
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
    case capture(CaptureRequest)
    case popupState(PopupStateRequest)
    case pin(PinRequest)
    case unpin(UnpinRequest)
    case undoCapture(UndoCaptureRequest)
    case muteSite(MuteSiteRequest)
    case linkSuggestions(LinkSuggestionsRequest)
    case contactSuggestions(ContactSuggestionsRequest)
    case customSuggestions(CustomSuggestionsRequest)
    case answers(AnswersRequest)
    case picked(PickedRequest)
    case application(ApplicationRequest)
}

public enum ExtensionResponse: Sendable, Hashable {
    case pong
    case capture(CaptureResponse)
    case popupState(PopupStateResponse)
    case linkSuggestions(LinkSuggestionsResponse)
    case contactSuggestions(ContactSuggestionsResponse)
    case customSuggestions(CustomSuggestionsResponse)
    case answers(AnswersResponse)
    case picked(PickedResponse)
    case application(ApplicationResponse)
    case error(reason: String)
}

private enum TypeKey: String, CodingKey {
    case type
}

private struct ErrorBody: Codable {
    let reason: String
}

private enum RequestType: String, Codable {
    case ping, capture, popupState, pin, unpin, undoCapture, muteSite, linkSuggestions
    case contactSuggestions, customSuggestions, answers, picked, application
}

private enum ResponseType: String, Codable {
    case pong, captureResult, popupStateResult, linkSuggestionsResult, error
    case contactSuggestionsResult, customSuggestionsResult, answersResult, pickedResult, applicationResult
}

extension ExtensionRequest: Codable {
    public init(from decoder: any Decoder) throws {
        let type = try decoder.container(keyedBy: TypeKey.self).decode(String.self, forKey: .type)
        switch RequestType(rawValue: type) {
        case .ping: self = .ping
        case .capture: self = .capture(try CaptureRequest(from: decoder))
        case .linkSuggestions: self = .linkSuggestions(try LinkSuggestionsRequest(from: decoder))
        case .contactSuggestions: self = .contactSuggestions(try ContactSuggestionsRequest(from: decoder))
        case .customSuggestions: self = .customSuggestions(try CustomSuggestionsRequest(from: decoder))
        case .some(let sheet): self = try Self.sheetRequest(sheet, from: decoder)
        case nil: throw MessageError.unknownType
        }
    }

    private static func sheetRequest(_ type: RequestType, from decoder: any Decoder) throws -> ExtensionRequest {
        switch type {
        case .popupState: .popupState(try PopupStateRequest(from: decoder))
        case .pin: .pin(try PinRequest(from: decoder))
        case .unpin: .unpin(try UnpinRequest(from: decoder))
        case .undoCapture: .undoCapture(try UndoCaptureRequest(from: decoder))
        case .muteSite: .muteSite(try MuteSiteRequest(from: decoder))
        case .answers: .answers(try AnswersRequest(from: decoder))
        case .picked: .picked(try PickedRequest(from: decoder))
        case .application: .application(try ApplicationRequest(from: decoder))
        case .ping, .capture, .linkSuggestions, .contactSuggestions, .customSuggestions:
            throw MessageError.unknownType
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
        case .capture: .capture
        case .popupState: .popupState
        case .pin: .pin
        case .unpin: .unpin
        case .undoCapture: .undoCapture
        case .muteSite: .muteSite
        case .linkSuggestions: .linkSuggestions
        case .contactSuggestions: .contactSuggestions
        case .customSuggestions: .customSuggestions
        case .answers: .answers
        case .picked: .picked
        case .application: .application
        }
    }

    private var body: (any Encodable)? {
        switch self {
        case .ping: nil
        case .capture(let body): body
        case .popupState(let body): body
        case .pin(let body): body
        case .unpin(let body): body
        case .undoCapture(let body): body
        case .muteSite(let body): body
        case .linkSuggestions(let body): body
        case .contactSuggestions(let body): body
        case .customSuggestions(let body): body
        case .answers(let body): body
        case .picked(let body): body
        case .application(let body): body
        }
    }
}

extension ExtensionResponse: Codable {
    public init(from decoder: any Decoder) throws {
        let type = try decoder.container(keyedBy: TypeKey.self).decode(String.self, forKey: .type)
        switch ResponseType(rawValue: type) {
        case .pong: self = .pong
        case .captureResult: self = .capture(try CaptureResponse(from: decoder))
        case .popupStateResult: self = .popupState(try PopupStateResponse(from: decoder))
        case .error: self = .error(reason: try ErrorBody(from: decoder).reason)
        case .some(let suggestions): self = try Self.suggestions(suggestions, from: decoder)
        case nil: throw MessageError.unknownType
        }
    }

    private static func suggestions(_ type: ResponseType, from decoder: any Decoder) throws -> ExtensionResponse {
        switch type {
        case .linkSuggestionsResult: .linkSuggestions(try LinkSuggestionsResponse(from: decoder))
        case .contactSuggestionsResult: .contactSuggestions(try ContactSuggestionsResponse(from: decoder))
        case .customSuggestionsResult: .customSuggestions(try CustomSuggestionsResponse(from: decoder))
        case .answersResult: .answers(try AnswersResponse(from: decoder))
        case .pickedResult: .picked(try PickedResponse(from: decoder))
        case .applicationResult: .application(try ApplicationResponse(from: decoder))
        case .pong, .captureResult, .popupStateResult, .error: throw MessageError.unknownType
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
        case .capture: .captureResult
        case .popupState: .popupStateResult
        case .linkSuggestions: .linkSuggestionsResult
        case .contactSuggestions: .contactSuggestionsResult
        case .customSuggestions: .customSuggestionsResult
        case .answers: .answersResult
        case .picked: .pickedResult
        case .application: .applicationResult
        case .error: .error
        }
    }

    private var body: (any Encodable)? {
        switch self {
        case .pong: nil
        case .capture(let body): body
        case .popupState(let body): body
        case .linkSuggestions(let body): body
        case .contactSuggestions(let body): body
        case .customSuggestions(let body): body
        case .answers(let body): body
        case .picked(let body): body
        case .application(let body): body
        case .error(let reason): ErrorBody(reason: reason)
        }
    }
}

public enum MessageError: String, Error, Sendable {
    case notJSON, unknownType, tooLarge, malformed
}

// SFExtensionMessageKey carries Foundation JSON objects (NSDictionary and friends).
public enum MessageCoding {
    public static func request(from message: Any?) throws -> ExtensionRequest {
        guard let message, JSONSerialization.isValidJSONObject(message) else { throw MessageError.notJSON }
        let data = try JSONSerialization.data(withJSONObject: message)
        guard data.count <= MessageLimits.bytes else { throw MessageError.tooLarge }
        let request = try JSONDecoder().decode(ExtensionRequest.self, from: data)
        guard request.isWithinLimits else { throw MessageError.tooLarge }
        guard request.isWellFormed else { throw MessageError.malformed }
        return request
    }

    // Names the kind of failure only. A decoding error's description can quote the value.
    public static func failureName(_ error: any Error) -> String {
        if let error = error as? MessageError { return error.rawValue }
        return switch error {
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
