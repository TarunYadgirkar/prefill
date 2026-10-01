import Foundation
import Testing
@testable import PrefillKit

// docs/message-examples.json is also read by web/src/messages.test.ts, so both sides
// agree on every field name. Simulator tests can read it because they run on the Mac's
// file system.
private let noAccess = CardWriteFailure.noAccess.reason

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
        #expect(Self.examples["requests"]?.count == 3)
        #expect(Self.examples["responses"]?.count == 5)
    }

    @Test(arguments: ["ping", "pageContext", "capture"])
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
        #expect(enums["sectionHint"] as? [String] == SectionHint.allCases.map(\.rawValue))
        #expect(enums["syncStatus"] as? [String] == SyncStatus.allCases.map(\.rawValue))
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
