import Foundation
import Testing
@testable import PrefillKit

// Mirrors the size checks in web/src/messages.test.ts.
struct MessageLimitTests {
    private func capture(fields: [[String: Any]], host: String = "shop.example.net") -> [String: Any] {
        ["type": "capture", "host": host, "hasPassword": false, "submitted": true, "fields": fields]
    }

    private func failure(_ message: [String: Any]) -> String? {
        do {
            _ = try MessageCoding.request(from: message)
            return nil
        } catch {
            return MessageCoding.failureName(error)
        }
    }

    @Test func aCaptureAtTheLimitsIsRead() {
        let email: [String: Any] = [
            "kind": "email", "value": String(repeating: "a", count: 256), "label": String(repeating: "b", count: 100)
        ]
        #expect(failure(capture(fields: Array(repeating: email, count: 20))) == nil)
    }

    @Test(arguments: [
        ["kind": "email", "value": String(repeating: "a", count: 257)],
        ["kind": "email", "value": "a@b.c", "name": String(repeating: "n", count: 101)],
        ["kind": "email", "value": "a@b.c", "autocomplete": String(repeating: "x", count: 101)],
        [
            "kind": "address",
            "address": [
                "street": "1 Main St", "city": String(repeating: "c", count: 201), "state": "", "postalCode": "",
                "country": ""
            ]
        ]
    ] as [[String: any Sendable]])
    func anOversizeFieldIsTurnedAway(field: [String: any Sendable]) {
        #expect(failure(capture(fields: [field])) == "tooLarge")
    }

    @Test func tooManyFieldsAreTurnedAway() {
        let email: [String: Any] = ["kind": "email", "value": "a@b.c"]
        #expect(failure(capture(fields: Array(repeating: email, count: 21))) == "tooLarge")
        let page: [String: Any] = [
            "type": "pageContext", "host": "shop.example.net", "fields": Array(repeating: ["kind": "email"], count: 41)
        ]
        #expect(failure(page) == "tooLarge")
    }

    @Test func aLongHostOrAHugeMessageIsTurnedAway() {
        #expect(failure(capture(fields: [], host: String(repeating: "h", count: 254))) == "tooLarge")
        let huge: [String: Any] = ["type": "ping", "padding": String(repeating: "p", count: 70_000)]
        #expect(failure(huge) == "tooLarge")
    }
}
