import Foundation

// Chrome's native messaging frame, also used between the native host and the Mac app: a
// 32-bit length in the machine's byte order (little-endian on every Mac Prefill runs on),
// then that many bytes of UTF-8 JSON.
public enum NativeFraming {
    public static let headerSize = 4
    // Chrome refuses a reply over 1 MB.
    public static let maxReply = 1024 * 1024
    public static let maxRequest = MessageLimits.bytes

    public static func frame(_ payload: Data) -> Data {
        var length = UInt32(payload.count).littleEndian
        return Data(bytes: &length, count: headerSize) + payload
    }

    // The body length a header announces, or nil when it is too short or over `max`.
    public static func bodyLength(_ header: Data, max: Int) -> Int? {
        guard header.count == headerSize else { return nil }
        let length = header.withUnsafeBytes { Int(UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))) }
        return length <= max ? length : nil
    }
}

extension MessageCoding {
    // What the native host passes on, and the app answers, for Chrome and Arc: a request a
    // page's content script sends there, which passed every check, rebuilt from its known
    // fields. Safari's sheet requests and pageContext (which reorders the card) are turned
    // away, so another extension that claims Prefill's ID can't read or rewrite the card.
    public static func validatedRequest(_ body: Data) throws -> Data {
        guard body.count <= MessageLimits.bytes else { throw MessageError.tooLarge }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: body)
        } catch {
            throw MessageError.notJSON
        }
        let request = try request(from: object)
        guard request.isBrowserPageRequest else { throw MessageError.unknownType }
        return try JSONEncoder().encode(request)
    }

    public static func replyData(_ response: ExtensionResponse) -> Data {
        (try? JSONEncoder().encode(response)) ?? Data(#"{"type":"error","reason":"encoding"}"#.utf8)
    }
}

extension ExtensionRequest {
    var isBrowserPageRequest: Bool {
        switch self {
        case .ping, .capture, .linkSuggestions, .contactSuggestions, .customSuggestions, .answers: true
        case .pageContext, .popupState, .pin, .unpin, .undoCapture, .muteSite: false
        }
    }
}
