import AppIntents
import PrefillKit

nonisolated enum ValueKindOption: String, AppEnum {
    case email, phone, address

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Contact info"
    static let caseDisplayRepresentations: [ValueKindOption: DisplayRepresentation] = [
        .email: "email",
        .phone: "phone number",
        .address: "address"
    ]

    var kind: ContactKind {
        switch self {
        case .email: .email
        case .phone: .phone
        case .address: .address
        }
    }

    var spoken: String {
        switch self {
        case .email: String(localized: "email")
        case .phone: String(localized: "phone number")
        case .address: String(localized: "address")
        }
    }
}

// What the value is for, when the question says so ("my shipping address").
nonisolated enum PurposeOption: String, AppEnum {
    case home, work, shipping, billing

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Purpose"
    static let caseDisplayRepresentations: [PurposeOption: DisplayRepresentation] = [
        .home: "home",
        .work: "work",
        .shipping: "shipping",
        .billing: "billing"
    ]

    var hint: SectionHint {
        switch self {
        case .home: .home
        case .work: .work
        case .shipping: .shipping
        case .billing: .billing
        }
    }
}

// The labels a Focus can put first. The raw value is the folded label Settings.focusLabel holds.
nonisolated enum FocusLabelOption: String, AppEnum {
    case work, school, home

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Info"
    static let caseDisplayRepresentations: [FocusLabelOption: DisplayRepresentation] = [
        .work: "work",
        .school: "school",
        .home: "home"
    ]
}

// A site by its registrable domain, the way Prefill keeps pins and usage.
nonisolated struct SiteEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Site"
    static let defaultQuery = SiteQuery()

    let id: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(id)")
    }

    init(host: String) {
        id = Normalizer.registrableDomain(host)
    }
}

struct SiteQuery: EntityStringQuery {
    @Dependency var model: AppModel

    func entities(for identifiers: [SiteEntity.ID]) async throws -> [SiteEntity] {
        identifiers.map(SiteEntity.init(host:))
    }

    // Sites Prefill has seen, plus what the person typed when it looks like a web address.
    func entities(matching string: String) async throws -> [SiteEntity] {
        let seen = await hosts(matching: string)
        let typed = string.contains(".") ? [Normalizer.registrableDomain(string)] : []
        return (seen + typed.filter { !seen.contains($0) }).map(SiteEntity.init(host:))
    }

    func suggestedEntities() async throws -> [SiteEntity] {
        await hosts(matching: nil).map(SiteEntity.init(host:))
    }

    @MainActor private func hosts(matching text: String?) -> [String] {
        model.readStore()
        return model.siteHosts(matching: text)
    }
}

nonisolated enum IntentProblem: Error, CustomLocalizedStringResourceConvertible {
    case notSetUp
    case nothingOnCard(ValueKindOption)
    case valueGone
    case card(CardWriteFailure)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notSetUp: "Open Prefill and choose your contact card first."
        case .nothingOnCard(let kind): "Your contact card has no \(kind.spoken) yet. Add one in Prefill."
        case .valueGone: "That isn't on your contact card anymore. Open Prefill to see what's there."
        case .card(let failure): "\(failure.reason)"
        }
    }
}
