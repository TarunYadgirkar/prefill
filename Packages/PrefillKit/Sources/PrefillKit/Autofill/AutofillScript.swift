import Foundation
import JavaScriptCore

// Runs the extension's own field rules (web/src/mac/autofill.ts, built to
// web/dist-mac/autofill.js) in JavaScriptCore, so a field read through Accessibility gets
// the same answer it would get in the browser. The router then answers the request the
// rules ask for, exactly as it answers the extension.
public final class AutofillScript {
    public enum Failure: Error {
        case notLoaded
    }

    private let context: JSContext
    private let api: JSValue

    public init(source: String) throws(Failure) {
        guard let context = JSContext() else { throw .notLoaded }
        context.evaluateScript(source)
        guard let api = context.objectForKeyedSubscript("PrefillAutofill"), !api.isUndefined,
              context.exception == nil else { throw .notLoaded }
        self.context = context
        self.api = api
    }

    // The rows for a field on `host`: the page's host, or the app's bundle ID outside a browser.
    public func rows(for field: FieldDescription, host: String, router: MessageRouter) -> [AutofillRow] {
        guard let plan = plan(field), var request = plan["request"] as? [String: Any] else { return [] }
        request["host"] = host
        let reply = router.route(request)
        guard let planText = Self.json(plan), let replyData = try? JSONEncoder().encode(reply),
              let replyText = String(data: replyData, encoding: .utf8),
              let rowsText = call("rows", planText, replyText) else { return [] }
        return (try? JSONDecoder().decode([AutofillRow].self, from: Data(rowsText.utf8))) ?? []
    }

    // What the rules make of the field: its kind and the request to send, or nil for a
    // field Prefill leaves alone.
    func plan(_ field: FieldDescription) -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(field), let text = String(data: data, encoding: .utf8),
              let planText = call("plan", text),
              let plan = try? JSONSerialization.jsonObject(with: Data(planText.utf8)) as? [String: Any],
              plan["kind"] as? String != "none" else { return nil }
        return plan
    }

    private func call(_ name: String, _ arguments: String...) -> String? {
        let result = api.invokeMethod(name, withArguments: arguments)
        guard context.exception == nil, let result, result.isString else {
            context.exception = nil
            return nil
        }
        return result.toString()
    }

    private static func json(_ object: Any) -> String? {
        (try? JSONSerialization.data(withJSONObject: object)).flatMap { String(data: $0, encoding: .utf8) }
    }
}
