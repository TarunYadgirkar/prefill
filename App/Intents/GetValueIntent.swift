import AppIntents
import PrefillKit

// "Which email do I use on netflix.com?" The answer shows on screen as Safari's bar and goes
// to Shortcuts as text; the spoken reply never reads the value aloud.
struct GetValueIntent: AppIntent {
    static let title: LocalizedStringResource = "Get contact info"
    static let description = IntentDescription(
        "Finds the email, phone number or address Safari suggests first, on one site or everywhere."
    )
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static let supportedModes: IntentModes = .background
    static let allowedExecutionTargets: IntentExecutionTargets = .main

    @Parameter(title: "Info", requestValueDialog: "Which do you want: email, phone number or address?")
    var kind: ValueKindOption

    @Parameter(title: "Site")
    var site: SiteEntity?

    @Parameter(title: "For")
    var purpose: PurposeOption?

    @Dependency var model: AppModel

    static var parameterSummary: some ParameterSummary {
        Summary("Get my \(\.$kind) for \(\.$site)") {
            \.$purpose
        }
    }

    init() {}

    init(kind: ValueKindOption, site: SiteEntity? = nil, purpose: PurposeOption? = nil) {
        self.kind = kind
        self.site = site
        self.purpose = purpose
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetIntent {
        await model.refreshForIntent()
        guard model.card != nil else { throw IntentProblem.notSetUp }
        let ranked = model.ranked(kind.kind, host: site?.id)
        guard let value = ValueLookup.answer(ranked, purpose: purpose?.hint) else {
            throw IntentProblem.nothingOnCard(kind)
        }
        return .result(
            value: value.display, dialog: dialog,
            snippetIntent: BarPreviewSnippet(kind: kind, site: site)
        )
    }

    private var dialog: IntentDialog {
        let kind = kind.spoken
        if let site { return "Here's the \(kind) you use on \(site.id)." }
        if let purpose { return "Here's your \(purpose.rawValue) \(kind)." }
        return "Here's the \(kind) Safari suggests first."
    }
}
