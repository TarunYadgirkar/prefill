import AppIntents
import PrefillKit

// Settings > Focus > Work > Add Filter > Prefill. While the Focus is on, values with the
// chosen label come first on every site the person hasn't pinned something on.
struct PreferInfoFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Prefer work info"
    static let description: IntentDescription = """
        Safari suggests your work email, phone number and address first while this Focus is on, \
        except on sites where you picked something else.
        """
    static let allowedExecutionTargets: IntentExecutionTargets = .main

    // No default: the system turns a Focus off by running the filter with its parameters
    // cleared, which puts the person's own order back.
    @Parameter(title: "Put first")
    var preferred: FocusLabelOption?

    @Dependency var model: AppModel

    var displayRepresentation: DisplayRepresentation {
        guard let preferred else { return DisplayRepresentation(title: "Prefer work info") }
        return DisplayRepresentation(title: "Prefer \(preferred.rawValue) info")
    }

    init() {}

    init(preferred: FocusLabelOption?) {
        self.preferred = preferred
    }

    static func suggestedFocusFilters(for context: FocusFilterSuggestionContext) async -> [PreferInfoFocusFilter] {
        [PreferInfoFocusFilter(preferred: .work)]
    }

    @MainActor func perform() async throws -> some IntentResult {
        await model.refreshForIntent()
        // The label is saved even when the card can't be read, so a Focus that ends
        // doesn't leave its values first on every site.
        let outcome = await model.setFocusLabel(preferred?.rawValue)
        guard model.card != nil else { throw IntentProblem.notSetUp }
        if case .failed(let failure) = outcome { throw IntentProblem.card(failure) }
        return .result()
    }
}
