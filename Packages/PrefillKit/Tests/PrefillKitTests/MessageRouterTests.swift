import Foundation
import PrefillKit
import Testing

struct MessageRouterTests {
    @Test func pingGetsPong() {
        #expect(MessageRouter.route(["type": "ping"]) == .pong)
    }

    @Test(arguments: [nil, "ping", ["type": 1], ["kind": "ping"]] as [(any Sendable)?])
    func anythingUnreadableGetsAnError(message: (any Sendable)?) {
        #expect(MessageRouter.route(message) == .error(reason: "unknown message"))
    }

    @Test func theReplyIsAFoundationObjectForSafari() {
        let reply = MessageCoding.jsonObject(MessageRouter.route(["type": "ping"]))
        #expect(reply as? [String: String] == ["type": "pong"])
    }
}
