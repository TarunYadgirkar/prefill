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

    func rows(for field: FieldDescription, host: String) -> [AutofillRow] {
        script.rows(for: field, host: host, router: router)
    }

    static var bundledSource: String? {
        Bundle.main.url(forResource: "autofill", withExtension: "js")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }
}

// Whether Prefill shows its own list in every app. While it does, the relay answers the
// Chrome extension's suggestion requests with nothing, so a field never gets two lists.
enum AutofillMode {
    private static let active = Mutex(false)

    static var isActive: Bool {
        get { active.withLock { $0 } }
        set { active.withLock { $0 = newValue } }
    }

    static func standDown(_ request: ExtensionRequest) -> ExtensionResponse? {
        guard isActive else { return nil }
        return switch request {
        case .contactSuggestions: .contactSuggestions(ContactSuggestionsResponse())
        case .linkSuggestions: .linkSuggestions(LinkSuggestionsResponse(links: []))
        case .customSuggestions(let body):
            .customSuggestions(CustomSuggestionsResponse(fields: body.fields.map { _ in .init(values: []) }))
        default: nil
        }
    }
}
