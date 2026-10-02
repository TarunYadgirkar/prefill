import Foundation

public enum IgnoreReason: String, Sendable, Hashable {
    case notContact, sensitive, someoneElse, partial, rejected, invalid
}

public enum CaptureDecision: Sendable, Hashable {
    case save(ContactValue)
    case review(ContactValue)
    case duplicate(UUID)
    case ignore(IgnoreReason)
}

public struct CaptureFilter: Sendable {
    private static let fullPhoneTokens: Set<String> = ["tel", "tel-national"]

    private let cardIDs: Set<UUID>
    private let rejected: Set<UUID>
    private let owner: OwnerName
    private let settings: Settings

    public init(card: CardRecord, settings: Settings, rejected: Set<UUID> = []) {
        self.cardIDs = Set(ContactKind.allCases.flatMap { card.entries($0) }.map {
            ContactValue(entry: $0, createdAt: .distantPast).id
        })
        self.rejected = rejected
        self.owner = OwnerName(givenName: card.givenName, familyName: card.familyName)
        self.settings = settings
    }

    public func evaluate(_ request: CaptureRequest, at date: Date) -> [CaptureDecision] {
        let parsed = request.fields.map { Self.parse($0, at: date) }
        let form = FormFacts(request: request, parsed: parsed, owner: owner)
        return request.fields.indices.map { index in
            Self.ignoreReason(request.fields[index], parsed: parsed[index]).map(CaptureDecision.ignore)
                ?? decide(index, form: form)
        }
    }

    public static func captures(from decisions: [CaptureDecision], host: String, at date: Date) -> [Capture] {
        let site = Normalizer.registrableDomain(host)
        return decisions.compactMap { decision in
            switch decision {
            case .save(let value): Capture(host: site, value: value, date: date, verdict: .saved)
            case .review(let value): Capture(host: site, value: value, date: date, verdict: .needsReview)
            case .duplicate, .ignore: nil
            }
        }
    }

    public static func usage(from decisions: [CaptureDecision], host: String, at date: Date) -> [UsageEvent] {
        let site = Normalizer.registrableDomain(host)
        return decisions.compactMap { decision in
            switch decision {
            case .save(let value): UsageEvent(valueID: value.id, host: site, date: date)
            case .duplicate(let id): UsageEvent(valueID: id, host: site, date: date)
            case .review, .ignore: nil
            }
        }
    }

    private func decide(_ index: Int, form: FormFacts) -> CaptureDecision {
        guard let value = form.parsed[index] else { return .ignore(.invalid) }
        if cardIDs.contains(value.id) { return .duplicate(value.id) }
        if rejected.contains(value.id) { return .ignore(.rejected) }
        if form.parsed[..<index].contains(where: { $0?.id == value.id }) { return .duplicate(value.id) }
        guard settings.saveNewInfo, !form.isContested(index) else { return .review(value) }
        let isTied = form.isCorroborated(except: index, cardIDs: cardIDs) || form.isTaggedInAccountForm(index)
        return isTied ? .save(value) : .review(value)
    }

    private static func ignoreReason(_ field: CapturedField, parsed: ContactValue?) -> IgnoreReason? {
        if field.kind == .name { return .notContact }
        let words = FieldWords(field)
        if words.isSensitive { return .sensitive }
        if words.isForSomeoneElse { return .someoneElse }
        if field.kind == .phone, words.isPartialPhone { return .partial }
        return parsed == nil ? .invalid : nil
    }

    private static func parse(_ field: CapturedField, at date: Date) -> ContactValue? {
        guard let payload = payload(field) else { return nil }
        let label = field.section.flatMap(LabelName.system(for:))
        return ContactValue(payload: payload, label: label, source: .captured, createdAt: date)
    }

    private static func payload(_ field: CapturedField) -> ContactPayload? {
        let text = (field.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        switch field.kind {
        case .email: return ValueRules.isEmail(text) ? .email(text) : nil
        case .phone: return ValueRules.isPhone(text, autocomplete: field.autocomplete) ? .phone(text) : nil
        case .address: return field.address.flatMap { ValueRules.isAddress($0) ? .address($0) : nil }
        case .name: return nil
        }
    }

    // Who the form is about. A name that isn't the card's means the phone and address
    // near it (same section, or no section to tell) may be someone else's, as in a gift
    // checkout, so they go to review. An email next to such a name goes to review only
    // when the person's own name isn't there too, since checkouts ask for the buyer's email.
    private struct FormFacts {
        let fields: [CapturedField]
        let parsed: [ContactValue?]
        let hasPassword: Bool
        let ownSections: [SectionHint?]
        let foreignSections: [SectionHint?]

        init(request: CaptureRequest, parsed: [ContactValue?], owner: OwnerName) {
            let names = request.fields.filter {
                owner.isKnown && $0.kind == .name && !Normalizer.fold($0.value ?? "").isEmpty
            }
            self.fields = request.fields
            self.parsed = parsed
            self.hasPassword = request.hasPassword
            self.ownSections = names.filter { owner.matches($0.value ?? "") }.map(\.section)
            self.foreignSections = names.filter { !owner.matches($0.value ?? "") }.map(\.section)
        }

        func isContested(_ index: Int) -> Bool {
            let field = fields[index]
            guard foreignSections.contains(where: { Self.overlaps($0, field.section) }) else { return false }
            guard field.kind == .email else { return true }
            return !ownSections.contains { Self.overlaps($0, field.section) }
        }

        func isCorroborated(except index: Int, cardIDs: Set<UUID>) -> Bool {
            !ownSections.isEmpty || parsed.indices.contains { other in
                other != index && parsed[other].map { cardIDs.contains($0.id) } == true
            }
        }

        func isTaggedInAccountForm(_ index: Int) -> Bool {
            let field = fields[index]
            let tokens = FieldWords.tokens(field.autocomplete)
            let isTagged = field.kind == .email ? tokens.contains("email") : !tokens.isDisjoint(with: fullPhoneTokens)
            return field.kind != .address && isTagged && (hasPassword || !ownSections.isEmpty)
        }

        private static func overlaps(_ lhs: SectionHint?, _ rhs: SectionHint?) -> Bool {
            lhs == nil || rhs == nil || lhs == rhs
        }
    }
}
