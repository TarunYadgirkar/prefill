import Foundation

public struct Settings: Codable, Sendable, Hashable {
    public let matchEachSite: Bool
    public let saveNewInfo: Bool

    public init(matchEachSite: Bool = true, saveNewInfo: Bool = true) {
        self.matchEachSite = matchEachSite
        self.saveNewInfo = saveNewInfo
    }
}

// Written only by the app. `values` is in the person's manual order. `rejectedValueIDs`
// holds values the person dismissed or undid, oldest first, so a later form that repeats
// them is not saved again. `siteKinds` holds what the model made of sites the rules
// couldn't place, by registrable domain, and `insights` caches model answers.
// `mutedSites` are registrable domains where nothing is saved, and `foldedThrough` is the
// newest Safari event already folded in, so a later change in the app isn't undone by it.
public struct AppState: Codable, Sendable, Hashable {
    public static let maxRejected = 500
    public static let maxMutedSites = 200

    public let values: [ContactValue]
    public let pins: [SitePin]
    public let settings: Settings
    public let cardLink: CardLink?
    public let rejectedValueIDs: [UUID]
    public let siteKinds: [String: SiteKind]
    public let insights: [CachedInsight]
    public let mutedSites: [String]
    public let foldedThrough: Date?

    public init(
        values: [ContactValue] = [], pins: [SitePin] = [], settings: Settings = Settings(),
        cardLink: CardLink? = nil, rejectedValueIDs: [UUID] = [], siteKinds: [String: SiteKind] = [:],
        insights: [CachedInsight] = [], mutedSites: [String] = [], foldedThrough: Date? = nil
    ) {
        self.values = values
        self.pins = pins
        self.settings = settings
        self.cardLink = cardLink
        self.rejectedValueIDs = rejectedValueIDs
        self.siteKinds = siteKinds
        self.insights = insights
        self.mutedSites = mutedSites
        self.foldedThrough = foldedThrough
    }

    // State stored before site kinds, insights and muted sites existed still reads.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            values: try container.decode([ContactValue].self, forKey: .values),
            pins: try container.decode([SitePin].self, forKey: .pins),
            settings: try container.decode(Settings.self, forKey: .settings),
            cardLink: try container.decodeIfPresent(CardLink.self, forKey: .cardLink),
            rejectedValueIDs: try container.decode([UUID].self, forKey: .rejectedValueIDs),
            siteKinds: try container.decodeIfPresent([String: SiteKind].self, forKey: .siteKinds) ?? [:],
            insights: try container.decodeIfPresent([CachedInsight].self, forKey: .insights) ?? [],
            mutedSites: try container.decodeIfPresent([String].self, forKey: .mutedSites) ?? [],
            foldedThrough: try container.decodeIfPresent(Date.self, forKey: .foldedThrough)
        )
    }

    // A copy with the given fields replaced and everything else kept.
    func copy(
        values: [ContactValue]? = nil, pins: [SitePin]? = nil, settings: Settings? = nil,
        cardLink: CardLink?? = nil, rejectedValueIDs: [UUID]? = nil, siteKinds: [String: SiteKind]? = nil,
        insights: [CachedInsight]? = nil, mutedSites: [String]? = nil, foldedThrough: Date?? = nil
    ) -> AppState {
        AppState(
            values: values ?? self.values, pins: pins ?? self.pins, settings: settings ?? self.settings,
            cardLink: cardLink ?? self.cardLink, rejectedValueIDs: rejectedValueIDs ?? self.rejectedValueIDs,
            siteKinds: siteKinds ?? self.siteKinds, insights: insights ?? self.insights,
            mutedSites: mutedSites ?? self.mutedSites, foldedThrough: foldedThrough ?? self.foldedThrough
        )
    }

    public func rejecting(_ id: UUID) -> AppState {
        let kept = rejectedValueIDs.filter { $0 != id } + [id]
        return copy(rejectedValueIDs: Array(kept.suffix(Self.maxRejected)))
    }
}

// Written only by the extension, append-only. The caps keep the Keychain item small
// (about 120 bytes per usage event, 400 per capture, so well under 150 KB in total)
// while still covering months of form fills. `saves` holds when captures went onto the
// card, for the hourly limit. `pins` and `mutes` are choices made in Safari's Prefill
// sheet, which the app folds into AppState.
public struct ExtensionEvents: Codable, Sendable, Hashable {
    public static let maxUsage = 500
    public static let maxCaptures = 200
    public static let maxSaves = 20
    public static let maxPins = 100
    public static let maxMutes = 100
    public static let maxAnswers = 40
    public static let maxQuestions = 40
    public static let maxAnswerPicks = 200

    public let usage: [UsageEvent]
    public let captures: [Capture]
    public let saves: [Date]
    public let pins: [PinEvent]
    public let mutes: [MuteEvent]
    public let answers: [LearnedAnswer]
    public let questions: [FormQuestion]
    public let answerPicks: [AnswerPick]
    // When the extension last reported a page with contact fields. Safari can't tell the app
    // whether All Websites is allowed, but the extension only runs on pages once it is.
    public let lastPageSeen: Date?

    public init(
        usage: [UsageEvent] = [], captures: [Capture] = [], saves: [Date] = [], pins: [PinEvent] = [],
        mutes: [MuteEvent] = [], answers: [LearnedAnswer] = [],
        questions: [FormQuestion] = [], answerPicks: [AnswerPick] = [], lastPageSeen: Date? = nil
    ) {
        self.usage = usage
        self.captures = captures
        self.saves = saves
        self.pins = pins
        self.mutes = mutes
        self.answers = answers
        self.questions = questions
        self.answerPicks = answerPicks
        self.lastPageSeen = lastPageSeen
    }

    // Documents written before `saves`, `pins`, `mutes` and `answers` existed still read. The
    // `cardWrites` that pages' card rewrites left in older documents are ignored.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usage = try container.decode([UsageEvent].self, forKey: .usage)
        captures = try container.decode([Capture].self, forKey: .captures)
        saves = try container.decodeIfPresent([Date].self, forKey: .saves) ?? []
        pins = try container.decodeIfPresent([PinEvent].self, forKey: .pins) ?? []
        mutes = try container.decodeIfPresent([MuteEvent].self, forKey: .mutes) ?? []
        answers = try container.decodeIfPresent([LearnedAnswer].self, forKey: .answers) ?? []
        questions = try container.decodeIfPresent([FormQuestion].self, forKey: .questions) ?? []
        answerPicks = try container.decodeIfPresent([AnswerPick].self, forKey: .answerPicks) ?? []
        lastPageSeen = try container.decodeIfPresent(Date.self, forKey: .lastPageSeen)
    }

    public func appending(_ new: ExtensionEvents) -> ExtensionEvents {
        ExtensionEvents(
            usage: Array((usage + new.usage).suffix(Self.maxUsage)),
            captures: Self.trimmed(captures + new.captures),
            saves: Array((saves + new.saves).suffix(Self.maxSaves)),
            pins: Array((pins + new.pins).suffix(Self.maxPins)),
            mutes: Array((mutes + new.mutes).suffix(Self.maxMutes)),
            answers: Array((answers + new.answers).suffix(Self.maxAnswers)),
            questions: Array((questions + new.questions).suffix(Self.maxQuestions)),
            answerPicks: Array((answerPicks + new.answerPicks).suffix(Self.maxAnswerPicks)),
            lastPageSeen: new.lastPageSeen ?? lastPageSeen
        )
    }

    // A page can file many values for review, so those go first, oldest first. Saved and
    // undone records go last: Undo reads them, and an undo counts only once the app folds it in.
    private static let evictionOrder: [Set<CaptureVerdict>] = [[.needsReview, .duplicate], [.dismissed], [.saved]]

    static func trimmed(_ captures: [Capture]) -> [Capture] {
        let excess = captures.count - maxCaptures
        guard excess > 0 else { return captures }
        let dropped = evictionOrder.reduce(into: [Int]()) { dropped, verdicts in
            let room = excess - dropped.count
            dropped += captures.indices.filter { verdicts.contains(captures[$0].verdict) }.prefix(room)
        }
        let droppedSet = Set(dropped)
        return captures.indices.filter { !droppedSet.contains($0) }.map { captures[$0] }
    }

    public func appending(
        usage newUsage: [UsageEvent], captures newCaptures: [Capture]
    ) -> ExtensionEvents {
        appending(ExtensionEvents(usage: newUsage, captures: newCaptures))
    }
}

enum DocumentCoder {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }
}
