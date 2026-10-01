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
// them is not saved again.
public struct AppState: Codable, Sendable, Hashable {
    public static let maxRejected = 500

    public let values: [ContactValue]
    public let pins: [SitePin]
    public let settings: Settings
    public let cardLink: CardLink?
    public let rejectedValueIDs: [UUID]

    public init(
        values: [ContactValue] = [], pins: [SitePin] = [], settings: Settings = Settings(),
        cardLink: CardLink? = nil, rejectedValueIDs: [UUID] = []
    ) {
        self.values = values
        self.pins = pins
        self.settings = settings
        self.cardLink = cardLink
        self.rejectedValueIDs = rejectedValueIDs
    }

    public func rejecting(_ id: UUID) -> AppState {
        let kept = rejectedValueIDs.filter { $0 != id } + [id]
        return AppState(
            values: values, pins: pins, settings: settings, cardLink: cardLink,
            rejectedValueIDs: Array(kept.suffix(Self.maxRejected))
        )
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
