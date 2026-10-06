import Foundation
import Testing
@testable import PrefillKit

// docs/message-examples.json is also read by web/src/messages.test.ts, so both sides
// agree on every field name. Simulator tests can read it because they run on the Mac's
// file system.
private let noAccess = CardWriteFailure.noAccess.reason

private let popupExample: PopupStateResponse = {
    let work = PopupValue(
        id: UUID(uuidString: "5E1D7C1A-8C1B-5F0E-9A6B-2C4D6E8F0A1B")!, caption: "work", text: "alex@work.example.org"
    )
    let home = PopupValue(
        id: UUID(uuidString: "0B3E5A7C-9D1F-5B2A-8C4E-6F8A0B2C4D6E")!, caption: "home", text: "alex.rivera@example.com"
    )
    let added = PopupValue(
        id: UUID(uuidString: "7A9C1E3B-5D7F-5A1C-8E2B-4D6F8A0C2E4A")!, caption: "email", text: "alex.new@example.net"
    )
    return PopupStateResponse(
        status: .ready, kinds: [PopupKind(kind: .email, values: [work, home], pinnedID: work.id)],
        recent: [PopupRecent(value: added, kind: .email, state: .saved)]
    )
}()

struct MessageContractTests {
    private static var examples: [String: [String: Any]] {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "docs/message-examples.json")
        let data = (try? Data(contentsOf: url)) ?? Data("{}".utf8)
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: [String: Any]] ?? [:]
    }

    private func example(_ group: String, _ name: String) -> Any? {
        Self.examples[group]?[name]
    }

    private func reencoded<T: Encodable>(_ value: T) throws -> NSDictionary {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
        return try #require(object as? NSDictionary)
    }

    @Test func theExamplesFileLoads() {
        #expect(Self.examples["requests"]?.count == 13)
        #expect(Self.examples["responses"]?.count == 11)
    }

    @Test(arguments: [
        "ping", "pageContext", "capture", "popupState", "pin", "unpin", "undoCapture", "muteSite", "linkSuggestions",
        "contactSuggestions", "customSuggestions", "answers", "picked"
    ])
    func requestExamplesRoundTripWithTheSameFieldNames(name: String) throws {
        let json = try #require(example("requests", name) as? NSDictionary)
        let request = try MessageCoding.request(from: json)
        #expect(try reencoded(request) == json)
    }

    @Test func pageContextDecodesToHintsPerKind() throws {
        let request = try MessageCoding.request(from: example("requests", "pageContext"))
        guard case .pageContext(let body) = request else {
            Issue.record("expected pageContext")
            return
        }
        #expect(body.host == "shop.example.net")
        #expect(body.hints == [.email: .work, .address: .shipping])
    }

    @Test func captureDecodesFieldsAndAddress() throws {
        let request = try MessageCoding.request(from: example("requests", "capture"))
        guard case .capture(let body) = request else {
            Issue.record("expected capture")
            return
        }
        #expect(body.hasPassword)
        #expect(body.fields.map(\.kind) == [.name, .email, .address])
        #expect(body.fields.last?.address == Alex.durant)
    }

    @Test func theCaptureExampleProducesTheCaptureResultExample() throws {
        guard case .capture(let request) = try MessageCoding.request(from: example("requests", "capture")) else {
            Issue.record("expected capture")
            return
        }
        let decisions = CaptureFilter(card: Alex.card, settings: Settings()).evaluate(request, at: .testNow)
        let json = try #require(example("responses", "captureResult") as? NSDictionary)
        let response = ExtensionResponse.capture(CaptureResponse(decisions: decisions))
        #expect(MessageCoding.jsonObject(response) as? NSDictionary == json)
    }

    @Test(arguments: [
        ("pong", ExtensionResponse.pong),
        ("pageContextResult", .pageContext(PageContextResponse(status: .saved))),
        ("pageContextFailed", .pageContext(PageContextResponse(status: .failed, reason: noAccess))),
        ("captureResult", .capture(CaptureResponse(saved: 1, review: 0, ignored: 1))),
        ("popupStateResult", .popupState(popupExample)),
        ("linkSuggestionsResult", .linkSuggestions(LinkSuggestionsResponse(links: [
            SuggestedLink(type: .github, url: "https://github.com/alexrivera", why: .pinned),
            SuggestedLink(type: .website, url: "https://alexrivera.dev")
        ]))),
        ("contactSuggestionsResult", .contactSuggestions(ContactSuggestionsResponse(
            emails: [
                SuggestedValue(value: "alex@work.example.org", why: .pinned, label: "work"),
                SuggestedValue(value: "alex.rivera@example.com", why: .used)
            ],
            addresses: [SuggestedAddress(address: Alex.durant, label: "home")],
            name: SuggestedName(given: "Alex", family: "Rivera")
        ))),
        ("customSuggestionsResult", .customSuggestions(CustomSuggestionsResponse(fields: [
            .init(values: [SuggestedValue(value: "UC Berkeley", label: "School")]),
            .init(values: [
                SuggestedValue(value: "Yes", why: .learned, label: "Work authorization", site: "example.io")
            ]),
            .init(values: [], guesses: ["EECS"])
        ]))),
        ("answersResult", .answers(AnswersResponse(saved: 2, updated: 1))),
        ("pickedResult", .picked(PickedResponse(remembered: true))),
        ("error", .error(reason: "unknown message"))
    ])
    func responsesEncodeToTheExamples(name: String, response: ExtensionResponse) throws {
        let json = try #require(example("responses", name) as? NSDictionary)
        #expect(MessageCoding.jsonObject(response) as? NSDictionary == json)
        let data = try JSONSerialization.data(withJSONObject: json)
        #expect(try JSONDecoder().decode(ExtensionResponse.self, from: data) == response)
    }

    @Test func everySharedValueMatchesTheExamplesList() {
        let enums = Self.examples["enums"] ?? [:]
        #expect(enums["fieldKind"] as? [String] == FieldKind.allCases.map(\.rawValue))
        #expect(enums["linkType"] as? [String] == LinkType.allCases.map(\.rawValue))
        #expect(enums["sectionHint"] as? [String] == SectionHint.allCases.map(\.rawValue))
        #expect(enums["syncStatus"] as? [String] == SyncStatus.allCases.map(\.rawValue))
        #expect(enums["popupStatus"] as? [String] == PopupStatus.allCases.map(\.rawValue))
        #expect(enums["recentState"] as? [String] == PopupRecentState.allCases.map(\.rawValue))
        #expect(enums["pickKind"] as? [String] == PickKind.allCases.map(\.rawValue))
        #expect(enums["why"] as? [String] == SuggestionWhy.allCases.map(\.rawValue))
    }

    // Mirrors the rejected requests in web/src/messages.test.ts.
    static let malformed: [(json: String?, failure: String)] = [
        (nil, "notJSON"),
        (#""ping""#, "notJSON"),
        ("{}", "keyNotFound"),
        (#"{"type": 1}"#, "typeMismatch"),
        (#"{"kind": "ping"}"#, "keyNotFound"),
        (#"{"type": "launch"}"#, "unknownType"),
        (#"{"type": "toString"}"#, "unknownType"),
        (#"{"type": "pageContext", "host": "example.net"}"#, "keyNotFound"),
        (#"{"type": "pageContext", "host": "example.net", "fields": [{"kind": "fax"}]}"#, "dataCorrupted"),
        (
            #"{"type": "pageContext", "host": "example.net", "fields": [{"kind": "email", "section": "school"}]}"#,
            "dataCorrupted"
        ),
        (#"{"type": "capture", "host": "example.net", "fields": []}"#, "keyNotFound"),
        (
            #"{"type": "capture", "host": "example.net", "hasPassword": false, "#
                + #""fields": [{"kind": "email", "value": 7}]}"#,
            "typeMismatch"
        )
    ]

    @Test(arguments: malformed)
    func malformedMessagesAreRejectedWithANamedFailure(json: String?, failure: String) throws {
        let message = try json.map { try JSONSerialization.jsonObject(with: Data($0.utf8), options: .fragmentsAllowed) }
        let error = #expect(throws: (any Error).self) { try MessageCoding.request(from: message) }
        #expect(error.map(MessageCoding.failureName) == failure)
    }
}
