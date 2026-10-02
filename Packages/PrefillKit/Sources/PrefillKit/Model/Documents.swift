import Foundation

public struct Settings: Codable, Sendable, Hashable {
    public let matchEachSite: Bool
    public let saveNewInfo: Bool
    // The label a Focus filter asks Prefill to prefer everywhere, folded ("work"). Nil when
    // no Focus filter is on.
    public let focusLabel: String?

    public init(matchEachSite: Bool = true, saveNewInfo: Bool = true, focusLabel: String? = nil) {
        self.matchEachSite = matchEachSite
        self.saveNewInfo = saveNewInfo
        self.focusLabel = focusLabel
    }
}

// Written only by the app. `values` is in the person's manual order. `rejectedValueIDs`
// holds values the person dismissed or undid, oldest first, so a later form that repeats
// them is not saved again. `siteKinds` holds what the model made of sites the rules
// couldn't place, by registrable domain, and `insights` caches model answers.
public struct AppState: Codable, Sendable, Hashable {
    public static let maxRejected = 500

    public let values: [ContactValue]
    public let pins: [SitePin]
    public let settings: Settings
    public let cardLink: CardLink?
    public let rejectedValueIDs: [UUID]
    public let siteKinds: [String: SiteKind]
    public let insights: [CachedInsight]

    public init(
        values: [ContactValue] = [], pins: [SitePin] = [], settings: Settings = Settings(),
        cardLink: CardLink? = nil, rejectedValueIDs: [UUID] = [], siteKinds: [String: SiteKind] = [:],
        insights: [CachedInsight] = []
    ) {
        self.values = values
        self.pins = pins
        self.settings = settings
        self.cardLink = cardLink
        self.rejectedValueIDs = rejectedValueIDs
        self.siteKinds = siteKinds
        self.insights = insights
    }

    // State stored before site kinds and insights existed still reads.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            values: try container.decode([ContactValue].self, forKey: .values),
            pins: try container.decode([SitePin].self, forKey: .pins),
            settings: try container.decode(Settings.self, forKey: .settings),
            cardLink: try container.decodeIfPresent(CardLink.self, forKey: .cardLink),
            rejectedValueIDs: try container.decode([UUID].self, forKey: .rejectedValueIDs),
            siteKinds: try container.decodeIfPresent([String: SiteKind].self, forKey: .siteKinds) ?? [:],
            insights: try container.decodeIfPresent([CachedInsight].self, forKey: .insights) ?? []
        )
    }

    // A copy with the given fields replaced and everything else kept.
    func copy(
        values: [ContactValue]? = nil, pins: [SitePin]? = nil, settings: Settings? = nil,
        cardLink: CardLink?? = nil, rejectedValueIDs: [UUID]? = nil, siteKinds: [String: SiteKind]? = nil,
        insights: [CachedInsight]? = nil
    ) -> AppState {
        AppState(
            values: values ?? self.values, pins: pins ?? self.pins, settings: settings ?? self.settings,
            cardLink: cardLink ?? self.cardLink, rejectedValueIDs: rejectedValueIDs ?? self.rejectedValueIDs,
            siteKinds: siteKinds ?? self.siteKinds, insights: insights ?? self.insights
        )
    }

    public func rejecting(_ id: UUID) -> AppState {
        let kept = rejectedValueIDs.filter { $0 != id } + [id]
        return copy(rejectedValueIDs: Array(kept.suffix(Self.maxRejected)))
    }
}

// Written only by the extension, append-only. The caps keep the Keychain item small
// (about 120 bytes per usage event, 400 per capture, so well under 150 KB in total)
// while still covering months of form fills.
public struct ExtensionEvents: Codable, Sendable, Hashable {
    public static let maxUsage = 500
    public static let maxCaptures = 200

    public let usage: [UsageEvent]
    public let captures: [Capture]

    public init(usage: [UsageEvent] = [], captures: [Capture] = []) {
        self.usage = usage
        self.captures = captures
    }

    public func appending(usage newUsage: [UsageEvent], captures newCaptures: [Capture]) -> ExtensionEvents {
        ExtensionEvents(
            usage: Array((usage + newUsage).suffix(Self.maxUsage)),
            captures: Array((captures + newCaptures).suffix(Self.maxCaptures))
        )
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
