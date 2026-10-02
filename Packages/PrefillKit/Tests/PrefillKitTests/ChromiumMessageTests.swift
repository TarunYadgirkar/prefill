import Foundation
import Testing
@testable import PrefillKit

struct ChromiumMessageTests {
    private let gateway = FakeGateway()

    private func route(_ message: [String: Any]) -> ExtensionResponse {
        let link = CardLink(
            contactIdentifier: Alex.card.identifier, containerIdentifier: nil, linkedIdentifiers: [],
            original: Alex.card, snapshotAt: .daysAgo(30)
        )
        let store = MemoryStore(AppState(values: Alex.allValues, cardLink: link))
        return MessageRouter(store: store, gateway: gateway, now: { .testNow }).route(message)
    }

    @Test func suggestionsFollowTheSiteWithoutWritingTheCard() {
        let reply = route([
            "type": "contactSuggestions", "host": "portal.example.org",
            "fields": [["kind": "email", "section": "work"], ["kind": "name"]]
        ])
        let expected = ContactSuggestionsResponse(
            emails: ["alex@work.example.org", "alex.rivera@example.com", "alex.school@example.edu"],
            name: SuggestedName(given: "Alex", family: "Rivera")
        )
        #expect(reply == .contactSuggestions(expected))
        #expect(gateway.saves.isEmpty)
    }

    @Test func framesCarryTheirLengthAndRefuseOversizedBodies() {
        let body = Data(#"{"type":"ping"}"#.utf8)
        let framed = NativeFraming.frame(body)
        #expect(NativeFraming.bodyLength(framed.prefix(4), max: 64) == body.count)
        #expect(NativeFraming.bodyLength(framed.prefix(4), max: 8) == nil)
    }

    @Test func theHostPassesOnOnlyKnownFields() throws {
        let raw = Data(#"{"type":"linkSuggestions","host":"boards.example.io","types":["github"],"extra":1}"#.utf8)
        let relayed = try JSONSerialization.jsonObject(with: MessageCoding.validatedRequest(raw)) as? NSDictionary
        #expect(relayed == ["type": "linkSuggestions", "host": "boards.example.io", "types": ["github"]])
        #expect(throws: MessageError.malformed) {
            try MessageCoding.validatedRequest(Data(#"{"type":"contactSuggestions","host":"A B","fields":[]}"#.utf8))
        }
        #expect(throws: MessageError.unknownType) {
            try MessageCoding.validatedRequest(Data(#"{"type":"popupState","host":"a.example","kinds":[]}"#.utf8))
        }
    }
}
