import os

public enum MessageRouter {
    private static let log = PrefillLog.logger("messages")

    public static func route(_ message: Any?) -> ExtensionResponse {
        let request: ExtensionRequest
        do {
            request = try MessageCoding.request(from: message)
        } catch {
            log.error("unreadable message: \(MessageCoding.failureName(error), privacy: .public)")
            return .error(reason: "unknown message")
        }
        switch request {
        case .ping: return .pong
        case .pageContext, .capture: return .error(reason: "not handled yet")
        }
    }
}
