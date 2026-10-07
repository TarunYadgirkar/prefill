import Foundation
import PrefillKit
import Synchronization

// Works out a field's rows off the main thread: the extension's rules in JavaScriptCore,
// then the same router that answers the extension, which reads the card.
actor AutofillWorker {
    private let script: AutofillScript
    private let router: MessageRouter

    init?(source: String, router: MessageRouter) {
        guard let script = try? AutofillScript(source: source) else { return nil }
        self.script = script
        self.router = router
    }

    private let intelligence = Intelligence()

    // A custom field with no matching answer gets the on-device model's guess, marked as one.
    // Only a labelled one-line field asks a question; a chat box or other text area doesn't.
    func rows(for field: FieldDescription, host: String) async -> [AutofillRow] {
        let rows = script.rows(for: field, host: host, router: router)
        guard rows.isEmpty, field.tag == .input, !field.label.isEmpty,
              let question = script.customQuestion(field) else { return rows }
        let saved = router.savedAnswers()
        guard !saved.isEmpty else { return rows }
        guard let label = await intelligence.answerLabel(question: question, labels: saved.map(\.label)),
              let answer = saved.first(where: { $0.label == label }) else { return rows }
        let pick = PickedRequest(host: "", kind: .custom, value: answer.value, question: question)
        return [AutofillRow(value: answer.value, detail: "Suggested", kind: "custom", pick: pick)]
    }

    func remember(_ row: AutofillRow, host: String) {
        AutofillScript.remember(row, host: host, router: router)
    }

    func fillValues(for fields: [FieldDescription], host: String) -> [Int: AutofillRow] {
        script.fillValues(for: fields, host: host, router: router)
    }

    static var bundledSource: String? {
        Bundle.main.url(forResource: "autofill", withExtension: "js")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }
}

// The browsers Prefill's extension is talking from. The extension sees the page itself
// (autocomplete, names, every option of a select) and fills the whole form, so in those
// browsers it gives every list and the Accessibility panel stays out. A browser counts until
// the process that ran the extension's host quits.
enum ExtensionPresence {
    private static let browsers = Mutex([String: pid_t]())

    static func saw(bundleID: String, pid: pid_t) {
        browsers.withLock { $0[bundleID.lowercased()] = pid }
    }

    static func isActive(in bundleID: String) -> Bool {
        browsers.withLock { known in
            guard let pid = known[bundleID.lowercased()] else { return false }
            if kill(pid, 0) == 0 || errno == EPERM { return true }
            known[bundleID.lowercased()] = nil
            return false
        }
    }
}
